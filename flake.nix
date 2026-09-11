{
  description = "maxnix — a NixOS VM for evaluating niri, Hyprland and Quickshell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # DankMaterialShell — a Quickshell-based desktop shell. Not in nixpkgs;
    # "stable" is upstream's release branch (drop the suffix for master).
    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      # Without this you evaluate two different nixpkgs, which bloats the
      # closure and lets the user layer drift from the system layer.
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (nixpkgs) lib;

      # One machine, one source of truth.
      #
      # Evaluated normally this describes a system you could install on metal.
      # Evaluated again with nixos/modules/virtualisation/qemu-vm.nix layered on
      # top — which every NixOS config can do, via `virtualisation.vmVariant` —
      # it also yields run-maxnix-vm, a script that runs on *this* Ubuntu host.
      # Being a VM is a variant of the machine, not a second description of it.
      # Everything that defines the machine, independent of how it is run.
      #
      # Shared verbatim by the build-vm configuration below and by every test
      # node, so a test can never drift from the real machine. It also has to
      # be shared: hosts/maxnix/configuration.nix *sets* home-manager options,
      # which only exist once home-manager's NixOS module is imported — so a
      # test node importing the former without the latter fails to evaluate.
      hostModules = [
        ./hosts/maxnix/configuration.nix
        ./modules/desktop
        home-manager.nixosModules.home-manager

        # The user layer needs flake inputs of its own (home/max/dms.nix
        # imports one), and Home Manager modules do not see them by default.
        { home-manager.extraSpecialArgs = { inherit inputs; }; }
      ];

      maxnix = lib.nixosSystem {
        inherit system;
        modules = hostModules ++ [ ./hosts/maxnix/vm.nix ];
      };

      # Integration tests over that same machine definition. The two compositor
      # tests differ only in how you ask a compositor what it is doing, so the
      # test body is shared — see tests/compositor.nix.
      tests = {
        desktop = pkgs.testers.runNixOSTest (import ./tests/desktop.nix { inherit hostModules; });

        niri = pkgs.testers.runNixOSTest (
          import ./tests/compositor.nix {
            inherit hostModules;
            name = "niri";
            session = "niri-session";
            ipcReady = "ls /run/user/1000/niri.wayland-*.sock";
            outputs = "NIRI_SOCKET=$(ls /run/user/1000/niri.wayland-*.sock | head -1) niri msg outputs";
            layout = "NIRI_SOCKET=$(ls /run/user/1000/niri.wayland-*.sock | head -1) niri msg keyboard-layouts";
          }
        );

        hyprland = pkgs.testers.runNixOSTest (
          import ./tests/compositor.nix {
            inherit hostModules;
            name = "hyprland";
            # What the session .desktop entry actually execs, rather than the
            # bare Hyprland binary, so this covers the real launch path.
            session = "start-hyprland";
            # Wait for the *command* socket, not just the instance directory.
            # The directory and .socket2.sock (events) appear well before
            # .socket.sock, so watching the directory races and hyprctl then
            # fails with "Couldn't connect ... (4)".
            ipcReady = "ls /run/user/1000/hypr/*/.socket.sock";
            # XDG_RUNTIME_DIR is required even with the instance signature:
            # hyprctl resolves its socket relative to it, and the driver's
            # backdoor is a bare root shell that has none.
            outputs = "XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1) hyprctl monitors";
            layout = "XDG_RUNTIME_DIR=/run/user/1000 HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1) hyprctl devices";
          }
        );
      };

      # nix run .#vm-headless
      #
      # The same VM, but rendering off-screen with a loopback VNC server
      # instead of a window — which is the only way to capture the screen while
      # GL is on. Only one thing may own QEMU's GL context, so a gtk window and
      # -vnc cannot coexist: `-display gtk,gl=on -vnc ...` makes QEMU refuse to
      # start ("Display vnc is incompatible with the GL context").
      #
      # Nothing appears on your desktop. Interact with it over VNC, or use it
      # purely to let something else look at the screen:
      #   nix run nixpkgs#vncdotool -- -s localhost::5909 capture /tmp/shot.png
      #   nix run nixpkgs#vncdotool -- -s localhost::5909 key super-t
      vmHeadless = pkgs.writeShellApplication {
        name = "vm-headless";
        text = ''
          echo "maxnix starting headless - VNC on 127.0.0.1:5909 (display :9)" >&2
          echo "capture:  nix run nixpkgs#vncdotool -- -s localhost::5909 capture /tmp/shot.png" >&2
          # Prepended, so a QEMU_OPTS already in the environment still wins.
          export QEMU_OPTS="-display egl-headless -vnc 127.0.0.1:9 ''${QEMU_OPTS:-}"
          exec ${lib.getExe maxnix.config.system.build.vm} "$@"
        '';
      };

      # One-step runner for a test's interactive driver.
      #
      # `nix build .#checks.<system>.<name>` cannot work on this host: a
      # sandboxed build can open neither /dev/kvm nor /dev/dri, because both are
      # crw-rw---- root:kvm / root:render and the only grant is an ACL for the
      # human user, which does not apply to the nixbld build users. So a
      # sandboxed run gets no GPU (niri cannot render at all) and silently falls
      # back to TCG for want of KVM.
      #
      # The interactive driver runs as you, outside the sandbox, where those
      # ACLs apply. Wrapping it here puts that knowledge in the entry point
      # instead of a comment nobody rereads.
      testRunner =
        name: test:
        pkgs.writeShellApplication {
          name = "test-${name}";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            out=$(mktemp -d -t "maxnix-test-${name}-XXXXXX")
            echo "screenshots and logs -> $out" >&2
            cd "$out"
            # --no-interactive runs the test script. To get a REPL against a
            # live VM instead, pass --interactive through; the later flag wins:
            #   nix run .#test-${name} -- --interactive
            exec ${test.driverInteractive}/bin/nixos-test-driver \
              --no-interactive -o "$out" "$@"
          '';
        };
    in
    {
      nixosConfigurations.maxnix = maxnix;

      # nix run .#vm      — or just `nix run .`
      #
      # No wrapper needed: qemu-vm.nix already sets
      #   meta.mainProgram = "run-${config.system.name}-vm"
      # on this derivation, which is exactly what `nix run` resolves.
      #
      # Run it from the repo root. `nix run .#vm` requires flake.nix in the
      # current directory anyway (Nix does not search upward), and that matches
      # what the VM needs: virtualisation.diskImage and the 9p share are both
      # relative to the launch directory. Invoking it by absolute path from
      # elsewhere would work, and would scatter .vm/maxnix.qcow2 wherever you
      # happened to be.
      #
      # Unlike `nix build`, `nix run` leaves no `result` symlink and therefore
      # no GC root, so a garbage collection can force a rebuild. Use
      # `nix build .#vm` when you want the closure pinned.
      packages.${system} = {
        vm = maxnix.config.system.build.vm;
        default = maxnix.config.system.build.vm;
      };

      checks.${system} = tests;

      # nix run .#test-desktop | .#test-niri | .#test-hyprland
      #
      # All three bind the same VNC port, so run them one at a time.
      apps.${system} = {
        vm-headless = {
          type = "app";
          program = lib.getExe vmHeadless;
        };
      }
      // lib.mapAttrs' (name: test: {
        name = "test-${name}";
        value = {
          type = "app";
          program = lib.getExe (testRunner name test);
        };
      }) tests;
    };
}
