{
  description = "maxnix — a NixOS machine running niri and Hyprland with Quickshell; staged as a VM until it becomes the host";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # DankMaterialShell — a Quickshell-based desktop shell. Not in nixpkgs;
    # "stable" is upstream's release branch (drop the suffix for master).
    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Dank Greeter — the graphical login screen matching DMS. It lives in its
    # own repo; the DMS flake's nixosModules.greeter is now only a deprecation
    # warning pointing here.
    dank-greeter = {
      url = "github:AvengeMedia/dank-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      # Without this you evaluate two different nixpkgs, which bloats the
      # closure and lets the user layer drift from the system layer.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Drives `nix fmt` and the formatting check. Config in ./treefmt.nix.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
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
      # Evaluated normally this describes the system that is meant to end up
      # installed on metal.
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
        inputs.dank-greeter.nixosModules.default

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
      # test body is shared — see tests/compositor.nix. `session` is the
      # desktop entry the greeter would offer; the test runs its real Exec.
      tests = {
        desktop = pkgs.testers.runNixOSTest (import ./tests/desktop.nix { inherit hostModules; });

        niri = pkgs.testers.runNixOSTest (
          import ./tests/compositor.nix {
            inherit hostModules;
            name = "niri";
            session = "niri";
            # ghostty opens its window from its D-Bus-activated service, so
            # even a client the test starts by hand lands in that unit.
            launch = "ghostty +new-window";
            appUnit = "app-com.mitchellh.ghostty.service";
            ipcReady = "ls /run/user/1000/niri.wayland-*.sock";
            outputs = "NIRI_SOCKET=$(ls /run/user/1000/niri.wayland-*.sock | head -1) niri msg outputs";
            layout = "NIRI_SOCKET=$(ls /run/user/1000/niri.wayland-*.sock | head -1) niri msg keyboard-layouts";
          }
        );

        hyprland = pkgs.testers.runNixOSTest (
          import ./tests/compositor.nix {
            inherit hostModules;
            name = "hyprland";
            # The UWSM-managed entry, not the plain one: that is the session
            # meant to be used, see modules/desktop/hyprland.nix.
            session = "hyprland-uwsm";
            # Launch the way the binds do, and expect the window in ghostty's
            # own unit rather than inside the compositor's.
            launch = "uwsm app -- ghostty +new-window";
            appUnit = "app-com.mitchellh.ghostty.service";
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

      # nix run .#test-vm-starts
      #
      # Asserts that the command a human actually types starts.
      #
      # Every other check overrides -display to egl-headless, so the
      # `gtk,gl=on` path that `nix run .#vm` uses is exercised by nothing. That
      # is exactly how commit 5231c9a shipped: -vnc landed in the shared
      # qemu-guest module, QEMU refuses `-display gtk,gl=on` together with -vnc
      # ("Display vnc is incompatible with the GL context"), and build-vm was
      # broken for a whole commit while all three test suites stayed green.
      #
      # The trick is that QEMU validates flag compatibility at startup and
      # exits immediately when they conflict, so "still alive after a few
      # seconds" is a sufficient signal — and `timeout` reports that as exit
      # 124. Any other exit code means QEMU bailed, and the log says why.
      #
      # Deliberately shallow: it proves the runner starts, nothing about
      # booting or rendering. That depth is already covered by the three
      # nixosTest checks, which cannot reach this path.
      vmStarts = pkgs.writeShellApplication {
        name = "test-vm-starts";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          if [ -z "''${DISPLAY:-}" ] && [ -z "''${WAYLAND_DISPLAY:-}" ]; then
            echo "no graphical session found." >&2
            echo "this test exercises -display gtk, which needs one; it cannot run headless." >&2
            exit 2
          fi

          scratch=$(mktemp -d)
          trap 'rm -rf "$scratch"' EXIT

          echo "starting the real runner for 8s — a window will appear" >&2

          # Scratch disks, so a test run never disturbs the VM state in ./.vm
          # or depends on where it was invoked from.
          set +e
          NIX_DISK_IMAGE="$scratch/test.qcow2"           MAXNIX_HOME_IMAGE="$scratch/home.qcow2"             timeout 8 ${lib.getExe maxnix.config.system.build.vm} > "$scratch/qemu.log" 2>&1
          rc=$?
          set -e

          if [ "$rc" -eq 124 ]; then
            echo "ok: the runner started with its real flags and stayed up" >&2
          else
            echo "FAIL: the runner exited with status $rc rather than being killed by timeout" >&2
            echo "--- qemu output ---" >&2
            cat "$scratch/qemu.log" >&2
            exit 1
          fi
        '';
      };

      # An `ssh` that reaches the VM.
      #
      # Goes through the loopback port forward in hosts/maxnix/vm.nix, logs in
      # with the (plaintext, by decision) VM password, and ignores host keys —
      # every root-image reset mints a new one, and this is loopback to a
      # machine you own. -F /dev/null skips the host's /etc/ssh/ssh_config,
      # which is Ubuntu's and names options this Nix-built ssh does not know.
      #
      # Named `ssh` and put first on PATH on purpose: `nix copy` and friends
      # exec whatever `ssh` they find, so this is how vm-deploy's copies get
      # their port and password without any of those tools knowing.
      vmSshShim = pkgs.writeShellScriptBin "ssh" ''
        exec ${lib.getExe pkgs.sshpass} -p ${lib.escapeShellArg maxnix.config.users.users.max.initialPassword} \
          ${pkgs.openssh}/bin/ssh \
            -p 2222 \
            -F /dev/null \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            "$@"
      '';

      # nix run .#vm-ssh -- <command…>
      #
      # Run a command in the running VM, or open a shell with no arguments.
      # The host-side way to look at and poke the machine you are using:
      #   nix run .#vm-ssh -- niri msg outputs
      #   nix run .#vm-ssh -- 'grim -' > shot.png       # screenshot, copied out
      #   nix run .#vm-ssh -- journalctl --user -u dms -n 50
      vmSsh = pkgs.writeShellApplication {
        name = "vm-ssh";
        runtimeInputs = [ vmSshShim ];
        text = ''
          exec ssh max@127.0.0.1 "$@"
        '';
      };

      # nix run .#vm-deploy
      #
      # Build this machine here and activate it in the running VM, without a
      # reboot and without the guest ever seeing the repo. This is the
      # standard NixOS remote-deploy shape — build on one machine, `nix copy`
      # the closure, run switch-to-configuration on the other — done by hand
      # rather than via nixos-rebuild --target-host, so the two ssh hops are
      # explicit and the shim above covers both.
      #
      # `test`, not `switch`, for the same reason as the in-guest `rebuild`:
      # activate now, leave the bootloader alone, the disk is disposable.
      #
      # --no-check-sigs: the host's paths are unsigned; the guest accepts them
      # because max is a trusted user there (hosts/maxnix/vm.nix). The copy is
      # over loopback and only sends what the guest does not already have.
      #
      # The toplevel is interpolated into the script, so `nix run .#vm-deploy`
      # builds it as a dependency — no nested nix invocation, and what gets
      # deployed is exactly what this evaluation of the flake describes.
      vmDeploy =
        let
          toplevel = maxnix.config.virtualisation.vmVariant.system.build.toplevel;
        in
        pkgs.writeShellApplication {
          name = "vm-deploy";
          runtimeInputs = [
            vmSshShim
            pkgs.nix
          ];
          text = ''
            echo "copying ${toplevel} into the VM..." >&2
            nix copy --no-check-sigs --to ssh://max@127.0.0.1 ${toplevel}

            echo "activating" >&2
            ssh max@127.0.0.1 sudo ${toplevel}/bin/switch-to-configuration test
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

      # `nix fmt`, and the check that asserts the tree is already formatted.
      # ./treefmt.nix documents what runs and what is deliberately left out.
      treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

      # statix and deadnix, report-only.
      #
      # Kept out of treefmt on purpose. treefmt-nix can run both, but only in
      # their --fix modes, which would make `nix fmt` a command that deletes
      # code: deadnix's fix is to remove an unused function argument. Pointing
      # something out and rewriting it are different acts, so the formatter
      # only reformats and this only reports.
      #
      # statix looks for statix.toml in the directory it is run from, which is
      # why this cds into the source instead of passing paths. That file lists
      # the two lints this repo switches off, and why.
      lintCheck =
        pkgs.runCommand "maxnix-lint"
          {
            nativeBuildInputs = [
              pkgs.statix
              pkgs.deadnix
            ];
          }
          ''
            cd ${inputs.self}
            echo "== statix ==" >&2
            statix check .
            echo "== deadnix ==" >&2
            deadnix --fail .
            touch "$out"
          '';
    in
    {
      nixosConfigurations.maxnix = maxnix;

      # nix fmt
      formatter.${system} = treefmtEval.config.build.wrapper;

      # nix run .#vm      — or just `nix run .`
      #
      # No wrapper needed: qemu-vm.nix already sets
      #   meta.mainProgram = "run-${config.system.name}-vm"
      # on this derivation, which is exactly what `nix run` resolves.
      #
      # Run it from the repo root. `nix run .#vm` requires flake.nix in the
      # current directory anyway (Nix does not search upward), and that matches
      # what the VM needs: both disk images are relative to the launch
      # directory. Invoking it by absolute path from elsewhere would work, and
      # would scatter .vm/*.qcow2 wherever you happened to be.
      #
      # Unlike `nix build`, `nix run` leaves no `result` symlink and therefore
      # no GC root, so a garbage collection can force a rebuild. Use
      # `nix build .#vm` when you want the closure pinned.
      packages.${system} = {
        vm = maxnix.config.system.build.vm;
        default = maxnix.config.system.build.vm;
      };

      # The three nixosTests, plus the two static checks. Only the latter two
      # can run under `nix flake check`: a sandboxed build reaches neither
      # /dev/kvm nor /dev/dri, which is why the VM tests have their own
      # runners instead (testRunner, above).
      checks.${system} = tests // {
        formatting = treefmtEval.config.build.check inputs.self;
        lint = lintCheck;
      };

      # nix run .#test-desktop | .#test-niri | .#test-hyprland
      #
      # All three bind the same VNC port, so run them one at a time.
      apps.${system} = {
        vm-headless = {
          type = "app";
          program = lib.getExe vmHeadless;
        };
        test-vm-starts = {
          type = "app";
          program = lib.getExe vmStarts;
        };
        vm-ssh = {
          type = "app";
          program = lib.getExe vmSsh;
        };
        vm-deploy = {
          type = "app";
          program = lib.getExe vmDeploy;
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
