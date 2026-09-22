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

    # Secure Boot: signs a Unified Kernel Image and replaces systemd-boot.
    # Off unless maxnix.boot.secureBoot is set; see hosts/maxnix/disk.nix.
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Installs this flake onto a machine over SSH. Pinned like everything
    # else, so install day runs a known version rather than whatever is
    # current; see the `install` app below.
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko";
    };

    # Declarative disk partitioning. The one install step that was still
    # manual; see hosts/maxnix/disk.nix.
    disko = {
      url = "github:nix-community/disko";
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
        ./hosts/maxnix/disk.nix
        inputs.disko.nixosModules.disko
        inputs.lanzaboote.nixosModules.lanzaboote
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
      #
      # Each is built twice, from one definition, differing only in `gpu`:
      #
      #   gpu = true    every subtest, including the four that look at the
      #                 screen. Needs a real GPU, so it needs this machine and
      #                 the interactive driver (see testRunner).
      #   gpu = false   the same machine and the same assertions minus those
      #                 four. Runs anywhere — a sandboxed `nix build` here, or
      #                 a GitHub runner that has KVM and no /dev/dri.
      #
      # Only the portable set goes in `checks`, so `nix flake check` passes on
      # any machine. The full set is what `nix run .#test-*` and `nix run .#ci`
      # reach for when a GPU is actually present. Both are declared here, so
      # nothing is hidden behind a flag you cannot see.
      mkTests = gpu: {
        desktop = pkgs.testers.runNixOSTest (import ./tests/desktop.nix { inherit hostModules gpu; });

        niri = pkgs.testers.runNixOSTest (
          import ./tests/compositor.nix {
            inherit hostModules gpu;
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
            inherit hostModules gpu;
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

      # The two instantiations. `tests` keeps its old meaning — the full,
      # GPU-requiring suites — so the runners and app names below are
      # unchanged.
      tests = mkTests true;

      # Everything that runs on any machine. Named once here so the `checks`
      # Everything that runs on any machine, in three groups because `ci`
      # builds them in that order, cheapest first. A formatting typo should
      # not be discovered after a 12.5 GiB download. The split lives here and
      # not in the workflow, so CI stays one command and never has to know
      # what a tier is.
      #
      # `checks` is their union, so the groups cannot drift from what CI
      # actually runs.
      staticChecks = {
        formatting = treefmtEval.config.build.check inputs.self;
        lint = lintCheck;
      };

      # The machine as it would be installed, built.
      #
      # This is the configuration hosts/maxnix/configuration.nix claims to
      # describe, and until hosts/maxnix/disk.nix existed it could not even be
      # evaluated — it failed on having no root filesystem and no bootloader.
      # Nothing built it, so nothing checked it: `packages.vm` builds the
      # vmVariant's toplevel and the suites build a third variant again, all
      # of which get their disks from qemu-vm.nix and therefore prove nothing
      # about the metal path.
      #
      # Cheap to add now that it evaluates: its closure is very nearly the
      # same as the one the VM suites already realise, so on a warm store this
      # is a few seconds, and it is ordered before them so a metal-only
      # breakage is reported before anything boots.
      #
      # It catches a build, not a boot. Whether the layout in disk.nix would
      # actually partition, format and come up is a different question, and
      # the answer to it is a disko VM test.
      metalChecks = {
        metal = maxnix.config.system.build.toplevel;

        # And that the layout it describes actually partitions, formats and
        # boots. See ./tests/disk.nix for why that is a separate claim.
        metal-boots = import ./tests/disk.nix {
          inherit pkgs;
          inherit (inputs) disko;
        };
      };

      portableVmTests = mkTests false;
      portableChecks = portableVmTests // staticChecks // metalChecks;

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

      # nix run .#ci
      #
      # The single entry point, and the same command in CI as on this desk.
      #
      # The premise: anything CI runs must be runnable locally, with one
      # command, and nothing may differ between the two except facts about the
      # hardware. So this does not branch on "am I in CI" — there is no such
      # flag. It probes for a usable GPU and says what it found, and the only
      # difference between a local run and a runner's is which line that probe
      # prints and which suites follow it.
      #
      # Two tiers, both declared in this flake:
      #
      #   always   `nix flake check` — formatting, lint, and the three VM
      #            suites without their screen assertions. Sandboxed, so
      #            results are cached: a second run of an unchanged tree is
      #            nearly free.
      #   with a   the same three suites with every subtest, through the
      #   GPU      interactive driver. Not sandboxed, because the Nix sandbox
      #            does not mount /sys and Mesa cannot identify a render node
      #            without it — eglInitialize fails even with the device
      #            world-readable. Measured 2026-09-21.
      # `.#checks.<system>.<name>` for every name in an attrset, as one
      # space-separated argument list. Both tiers are spelled from the same
      # attrsets `checks` exposes, so neither can name a check that is not
      # there or miss one that is.
      checkArgs =
        set: lib.concatMapStringsSep " " (n: ".#checks.${system}.${n}") (builtins.attrNames set);

      ciRunner =
        let
          gpuSuites = lib.mapAttrsToList (name: test: {
            inherit name;
            runner = testRunner name test;
          }) tests;
        in
        pkgs.writeShellApplication {
          name = "ci";
          runtimeInputs = [ pkgs.nix ];
          text = ''
            echo "== maxnix ci ==" >&2

            # The probe. A render node that exists but cannot be opened is the
            # same as no render node, so this opens it rather than stat-ing
            # it — that distinction is exactly what bit this host before the
            # device was made world-readable.
            if [ -e /dev/dri/renderD128 ] && (: <>/dev/dri/renderD128) 2>/dev/null; then
              have_gpu=yes
            else
              have_gpu=no
            fi
            echo "gpu: $have_gpu (/dev/dri/renderD128)" >&2

            # Builds the checks by name rather than running `nix flake check`.
            #
            # `nix flake check` does now pass — it validates
            # `nixosConfigurations` too, and that only started working when
            # hosts/maxnix/disk.nix gave the metal configuration a root
            # filesystem and a bootloader. So this is no longer a workaround
            # for a broken flake, and `nix flake check --max-jobs 1` would be
            # a correct one-line replacement.
            #
            # It is still not used, for one reason: it builds in dependency
            # order, not cheapest-first. A formatting typo would be reported
            # after the VM suites rather than in the second before them. The
            # ordering below is the whole value this script adds over that
            # one-liner.

            echo >&2
            echo "-- static checks --" >&2
            nix build --print-build-logs ${checkArgs staticChecks}

            echo >&2
            echo "-- the metal system builds --" >&2
            nix build --print-build-logs ${checkArgs metalChecks}

            echo >&2
            echo "-- vm suites, portable tier --" >&2
            # --max-jobs 1 because each guest is 8192 MiB and there are three
            # of them: in parallel that is 24 GB, and a GitHub runner has 16.
            # This host carries max-jobs = 1 in nix.conf, which is why it
            # never bit locally — and leaning on a local setting for
            # correctness in CI is precisely the divergence this runner
            # exists to prevent, so it is stated rather than assumed.
            nix build --max-jobs 1 --print-build-logs ${checkArgs portableVmTests}

            if [ "$have_gpu" = no ]; then
              echo >&2
              echo "SKIPPED, no render node — these need a GPU:" >&2
              echo "  desktop:  the guest has a GPU with working virgl" >&2
              echo "  desktop:  the greeter renders" >&2
              echo "  niri/hyprland: drives the virtual display" >&2
              echo "  niri/hyprland: starts the DankMaterialShell service" >&2
              echo "  niri/hyprland: renders a client window" >&2
              echo "  niri/hyprland: the session renders a rich screen" >&2
              echo >&2
              echo "ok (portable tier only)" >&2
              exit 0
            fi

            ${lib.concatMapStringsSep "\n" (s: ''
              echo >&2
              echo "-- ${s.name} (full suite) --" >&2
              ${lib.getExe s.runner}
            '') gpuSuites}

            echo >&2
            echo "ok (everything)" >&2
          '';
        };

      # nix develop
      #
      # What you need on PATH to work *on* this repo. Nothing here is needed
      # to build the machine, and nothing here duplicates an app: the entry
      # points stay `nix run .#ci | .#vm | .#vm-ssh | .#vm-deploy | .#test-*`,
      # which are pinned by the flake and cannot drift from what CI runs.
      #
      # This exists so "what tools does this repo assume" has a declared
      # answer rather than being whatever the host happens to have installed
      # — the same reason everything else here is declared.
      devShell = pkgs.mkShellNoCC {
        name = "maxnix";
        packages = [
          # The very thing `nix fmt` runs. Having it directly is for the
          # narrower jobs the flake output cannot express: formatting or
          # checking one file rather than the tree.
          treefmtEval.config.build.wrapper

          # The `lint` check only ever reports, deliberately (see
          # ../treefmt.nix), so fixing is a thing you do on purpose:
          # `statix fix` and `deadnix --edit`. Both read the repo's own
          # statix.toml when run from the root.
          pkgs.statix
          pkgs.deadnix

          # The `lint` check runs these over .github/; they are here for
          # editing a workflow or the Renovate config.
          pkgs.actionlint
          pkgs.renovate

          # Looking at a running VM from the host. `nix run .#vm-headless`
          # prints a vncdotool line to capture its screen; imagemagick is how
          # you count colours the way tests/vnc.nix does, which is what
          # recalibrating one of those thresholds by hand needs.
          pkgs.vncdotool
          pkgs.imagemagick

          # `nix eval --json … | jq` is how most of this config gets
          # inspected — which module set an option, what a node's QEMU line
          # ended up being.
          pkgs.jq
        ];
      };

      # nix run .#install -- root@<target>
      #
      # Install this flake onto a machine, over SSH, from here.
      #
      # It kexecs the target into a NixOS installer (so the target can be
      # running any Linux — including the Ubuntu this repo is developed on),
      # runs disko against hosts/maxnix/disk-layout.nix to partition and
      # format, then installs and reboots. That is the same sequence
      # checks.metal-boots exercises against a virtual disk; this is the one
      # that writes to a real one.
      #
      # Wrapped rather than left to `nix run github:...` for the usual reason
      # apps exist here: the flake reference and the host attribute are part
      # of the invocation, and install day is a bad time to be reconstructing
      # them from memory. The input is pinned, so it also runs a known
      # version rather than whatever is current that morning.
      #
      # ── Before running this ───────────────────────────────────────────
      #
      # THIS DESTROYS THE TARGET'S DISK. Everything on it.
      #
      # 1. hosts/maxnix/disk-layout.nix still names a placeholder device.
      #    Replace it with the target's /dev/disk/by-id/… path first, or
      #    disko will refuse to find it.
      # 2. The layout is encrypted and takes no passphrase from the config
      #    (maxnix.disk.passwordFile is null), so supply one for the
      #    formatting step:
      #
      #      nix run .#install -- \
      #        --disk-encryption-keys /tmp/secret.key <(pass maxnix/luks) \
      #        root@<target>
      #
      #    and set maxnix.disk.passwordFile = "/tmp/secret.key" so disko
      #    knows where to look. The *installed* machine still prompts at every
      #    boot, because nothing lands in settings.keyFile — which is the
      #    behaviour checks.metal-boots demonstrates.
      # 3. Worth knowing: --generate-hardware-config nixos-facter <path> runs
      #    nixos-facter on the target and writes the report back here, which
      #    is the same report hardware.facter.reportPath wants. It removes the
      #    separate installer-USB trip described in
      #    hosts/maxnix/configuration.nix.
      #
      # Everything after `--` is passed straight through, so any flag in
      # `nix run .#install -- --help` is available.
      #
      # ── No `install-vm-test` app, deliberately ───────────────────────
      #
      # nixos-anywhere has a --vm-test flag that rehearses the install
      # against a throwaway VM, and it looked like the obvious companion to
      # this. Two reasons it is not here.
      #
      # It is redundant: checks.metal-boots already formats, installs and
      # boots this exact layout, from the same disk-layout.nix, on every CI
      # run.
      #
      # And it does not work on a layout like this one. --vm-test builds its
      # own disko-destroy-format-mount script (a different derivation from
      # the system.build.diskoScript this flake uses, which builds fine) and
      # that harness injects `export password=disko` in three places. disko
      # runs shellcheck over its generated scripts, and the injection trips
      # SC2030/SC2031 — "password was modified in a subshell" — so the build
      # fails before any VM starts. Measured 2026-09-22; it is an upstream
      # defect in the test harness, not a problem with this configuration.
      installRunner = pkgs.writeShellApplication {
        name = "install";
        runtimeInputs = [ inputs.nixos-anywhere.packages.${system}.default ];
        text = ''
          if [ "$#" -eq 0 ]; then
            echo "usage: nix run .#install -- [flags] root@<target>" >&2
            echo "this DESTROYS the target's disk; see flake.nix for the" >&2
            echo "two things to do first (device path, encryption key)." >&2
            exit 2
          fi
          exec nixos-anywhere --flake "${inputs.self}#maxnix" "$@"
        '';
      };

      # One-step runner for a test's interactive driver.
      #
      # This is how the GPU tier runs, and it has to be: a sandboxed build
      # cannot do GL at all. Not for want of permission — the Nix sandbox does
      # not mount /sys, so Mesa cannot resolve a render node's driver and
      # eglInitialize fails even with the device world readable. Exposing /sys
      # would be a far larger hole than exposing the device.
      #
      # KVM is a different story and no longer a blocker: /dev/kvm is mode
      # 0666 on this host, which a sandboxed build can use. Group membership
      # would not have worked — the sandbox denies setgroups, so only the
      # `other` bits are reachable from inside a build.
      #
      # The interactive driver runs as you, outside the sandbox, where both
      # devices are simply available. Wrapping it here puts that knowledge in
      # the entry point instead of a comment nobody rereads.
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
              pkgs.actionlint
              pkgs.renovate
            ];
          }
          ''
            cd ${inputs.self}
            echo "== statix ==" >&2
            statix check .
            echo "== deadnix ==" >&2
            deadnix --fail .
            # The workflow is the one tracked file that is neither Nix nor
            # covered by anything else, and its failure mode is a push that
            # dies on the runner. actionlint also runs shellcheck over every
            # `run:` block.
            #
            # Given an explicit path because actionlint otherwise discovers
            # workflows by walking up to a .git, and the store copy has none.
            echo "== actionlint ==" >&2
            actionlint .github/workflows/*.yml
            # Renovate is configured here but runs as a GitHub App, so a
            # mistake in its config surfaces as "the bot quietly does nothing"
            # rather than as a failure anyone sees. Validating it locally is
            # the only feedback loop there is. No argument: the validator
            # auto-discovers .github/renovate.json5 and checks it as a
            # repository config, where an explicit path makes it fall back to
            # the laxer global schema.
            echo "== renovate-config-validator ==" >&2
            renovate-config-validator
            touch "$out"
          '';
    in
    {
      nixosConfigurations.maxnix = maxnix;

      # nix fmt
      formatter.${system} = treefmtEval.config.build.wrapper;

      # nix develop
      devShells.${system}.default = devShell;

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

        # Exposed so `nix build .#ci` checks the runner itself without
        # running it — writeShellApplication puts shellcheck in its build, so
        # this is how a typo in that script is caught before CI hits it.
        ci = ciRunner;
      };

      # Everything that runs on any machine: the two static checks and the
      # three VM suites minus their screen assertions. `nix flake check` is
      # therefore meaningful here and on a GPU-less runner alike.
      #
      # The GPU suites are deliberately absent. They are not hidden — they are
      # `nix run .#test-desktop|test-niri|test-hyprland`, and `nix run .#ci`
      # runs them automatically wherever a render node exists. Keeping them
      # out of `checks` is what lets `nix flake check` be a command that
      # passes everywhere rather than one you have to qualify.
      checks.${system} = portableChecks;

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
        ci = {
          type = "app";
          program = lib.getExe ciRunner;
        };
        install = {
          type = "app";
          program = lib.getExe installRunner;
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
