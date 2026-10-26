{
  description = "maxnix — a NixOS machine running niri with Quickshell; staged as a VM until it becomes the host";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # DankMaterialShell — a Quickshell-based desktop shell. Not in nixpkgs;
    # "stable" is upstream's release branch (drop the suffix for master).
    # Since 2.0 (2026-10-20) it is Dux Labs' dux-shell; AvengeMedia's URLs
    # still redirect, but upstream asks packagers to move.
    dms = {
      url = "github:duxlabs-dev/dux-shell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # DMS plugins by hthienloc, one directory per plugin; home/max/desktop/dms.nix
    # picks the ones it wants by subpath. Not a flake, just source. Quick
    # Capture moved here from its own repo, hthienloc/dms-quick-capture,
    # which was archived on 2026-09-19.
    dms-plugins-hthienloc = {
      url = "github:hthienloc/dms-plugins";
      flake = false;
    };

    # Dank Greeter — the graphical login screen matching DMS. It lives in its
    # own repo; the DMS flake's nixosModules.greeter is now only a deprecation
    # warning pointing here. Renamed dux-greeter with DMS 2.0; the input keeps
    # its old name, which nothing outside this file would gain from changing.
    dank-greeter = {
      url = "github:duxlabs-dev/dux-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      # Without this you evaluate two different nixpkgs, which bloats the
      # closure and lets the user layer drift from the system layer.
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets that live encrypted in this repo. Imported but unconfigured;
    # see hosts/t14s/secrets.nix for what it is waiting on.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # A prebuilt file->package index, so `,` and nix-locate work without
    # anyone building a database first. See home/max/core/dev.nix.
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative state: bind-mounts what must survive a wiped root.
    # See modules/metal/persistence.nix.
    #
    # No `inputs.nixpkgs.follows` here, unlike every other input: preservation
    # declares no inputs at all — it is a module and nothing else — so the
    # override would name something that does not exist and Nix warns about it
    # on every evaluation.
    preservation.url = "github:nix-community/preservation";

    # Secure Boot: signs a Unified Kernel Image and replaces systemd-boot.
    # Off unless maxnix.boot.secureBoot is set; see modules/metal/disk.nix.
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NixOS as a WSL distribution, for hosts/z690-wsl on the Windows desktop
    # (docs/desktop-pc.md): the module that makes a NixOS system boot under
    # WSL, and the tarball builder for `wsl --import`.
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
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
    # manual; see modules/metal/disk.nix.
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

      # The roles a host is composed from (modules/*), each with the external
      # modules it builds on. A role imports modules that define options;
      # which of them are switched on is mostly the host's business.
      roles = {
        base = [
          ./modules/base
          inputs.sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager

          # The user layer needs flake inputs of its own (home/max/desktop/dms.nix
          # imports one), and Home Manager modules do not see them by default.
          { home-manager.extraSpecialArgs = { inherit inputs; }; }
        ];
        desktop = [
          ./modules/desktop
          inputs.dank-greeter.nixosModules.default
        ];
        metal = [
          ./modules/metal
          inputs.disko.nixosModules.disko
          inputs.preservation.nixosModules.preservation
          inputs.lanzaboote.nixosModules.lanzaboote
        ];
        # Running as a WSL distribution: the platform in place of metal.
        wsl = [ inputs.nixos-wsl.nixosModules.default ];
      };

      # A host's modules: the roles it names, in that order, then its own
      # directory.
      mkHost = names: dir: lib.concatMap (n: roles.${n}) names ++ [ dir ];

      # One machine, one source of truth: the ThinkPad, as its roles and
      # hosts/t14s.
      #
      # Evaluated normally this describes the system that is meant to end up
      # installed on metal.
      # Evaluated again with nixos/modules/virtualisation/qemu-vm.nix layered on
      # top — which every NixOS config can do, via `virtualisation.vmVariant` —
      # it also yields run-maxnix-vm, a script that runs on *this* Ubuntu host.
      # Being a VM is a variant of the machine, not a second description of it.
      #
      # Shared verbatim by the build-vm configuration below and by the desktop
      # suites' nodes, so those tests can never drift from the real machine.
      # It also has to be shared whole: the base role *sets* home-manager
      # options, which only exist once home-manager's NixOS module is imported
      # — so a node importing the one without the other fails to evaluate.
      hostModules = mkHost [
        "base"
        "desktop"
        "metal"
      ] ./hosts/t14s;

      t14s = lib.nixosSystem {
        inherit system;
        modules = hostModules ++ [ ./hosts/t14s/vm.nix ];
      };

      # NixOS under WSL on the Windows desktop; see hosts/z690-wsl.
      z690Wsl = lib.nixosSystem {
        inherit system;
        modules = mkHost [
          "base"
          "wsl"
        ] ./hosts/z690-wsl;
      };

      # The installer USB and its script (hosts/installer). The key it must
      # find is read off .sops.yaml, as vm-restore-key reads the VM's, so the
      # two cannot disagree.
      metalRecipient =
        let
          lines = lib.splitString "\n" (builtins.readFile ./.sops.yaml);
          hits = lib.concatMap (
            l:
            let
              m = builtins.match "  - &metal (age1[a-z0-9]+)" l;
            in
            lib.optional (m != null) (builtins.head m)
          ) lines;
        in
        assert lib.assertMsg (builtins.length hits == 1) ".sops.yaml must name exactly one &metal key";
        builtins.head hits;
      # The repo as the installer carries it: what git tracks, which is all a
      # build from git ever sees. A build from the working tree (`path:.`)
      # would otherwise copy everything .gitignore keeps out — .vm/ above
      # all, the dev VM's disk images, 8 GB with the VM's sops key on them,
      # which a first image built that way carried onto the stick
      # (2026-10-15). Filtered here so how the image is built cannot matter.
      repoSource = builtins.path {
        name = "maxnix-source";
        path = inputs.self;
        filter =
          path: _type:
          let
            rel = lib.removePrefix "${toString inputs.self}/" (toString path);
          in
          !(
            builtins.elem rel [
              ".vm"
              ".direnv"
              ".git"
            ]
            || lib.hasPrefix "result" rel && !(lib.hasInfix "/" rel)
          );
      };

      # install-maxnix for one disk, with disko's partitioning script for
      # that disk built here, from the pinned nixpkgs, through disko's own
      # module (system.build.destroyFormatMount, what its test harness runs).
      # Nothing is evaluated or built on the installer. The passphrase file is
      # where the script puts it, in a tmpfs.
      mkInstallMaxnix =
        disk:
        let
          workDir = "/run/install-maxnix";
          layout = lib.nixosSystem {
            inherit system;
            modules = [
              inputs.disko.nixosModules.disko
              (import ./modules/metal/disk-layout.nix {
                device = disk;
                passwordFile = "${workDir}/luks.key";
              })
            ];
          };
        in
        import ./hosts/installer/install-maxnix.nix {
          inherit
            pkgs
            disk
            workDir
            metalRecipient
            ;
          diskoScript = lib.getExe layout.config.system.build.destroyFormatMount;
          flake = repoSource;
        };
      installMaxnix =
        mkInstallMaxnix
          (import ./modules/metal/disk-layout.nix { }).disko.devices.disk.main.device;
      installer = lib.nixosSystem {
        inherit system;
        modules = [ ./hosts/installer ];
        specialArgs = {
          inherit installMaxnix;
          flake = repoSource;
          disko = inputs.disko.packages.${system}.disko;
        };
      };

      # Integration tests over that same machine definition: tests/desktop.nix
      # for the machine and its greeter, tests/niri.nix for the session.
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

        niri = pkgs.testers.runNixOSTest (import ./tests/niri.nix { inherit hostModules gpu; });
      };

      # The two instantiations. `tests` keeps its old meaning — the full,
      # GPU-requiring suites — so the runners and app names below are
      # unchanged.
      tests = mkTests true;

      # disko, with its test harness patched for nixpkgs without the scripted
      # initrd (gone 2026-10): makeDiskoTest still reads the removed
      # boot.initrd.systemd.enable to decide how /tmp/secret.key reaches the
      # initrd, and reading a removed option throws. The patch keeps the
      # systemd branch. Only testLib is swapped; the module and everything
      # the metal toplevel takes from disko stay the input's. Remove with
      # docs/blocked.toml `disko-testlib-systemd-initrd`.
      diskoForTests =
        let
          # Importing from this is import-from-derivation: a local build of a
          # few seconds during evaluation, nothing fetched.
          patched = pkgs.applyPatches {
            name = "disko-tests-systemd-initrd";
            src = inputs.disko;
            patches = [ ./tests/disko-tests-systemd-initrd.patch ];
          };
          # As disko's flake.nix calls it, from our nixpkgs (disko follows it).
          patchedLib = import "${patched}/lib" {
            inherit lib;
            makeTest = import "${nixpkgs}/nixos/tests/make-test-python.nix";
            eval-config = import "${nixpkgs}/nixos/lib/eval-config.nix";
            qemu-common = import "${nixpkgs}/nixos/lib/qemu-common.nix";
          };
        in
        inputs.disko
        // {
          lib = inputs.disko.lib // {
            inherit (patchedLib) testLib;
          };
        };

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
      # This is the configuration hosts/t14s/configuration.nix claims to
      # describe, and until modules/metal/disk.nix existed it could not even be
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
        metal = t14s.config.system.build.toplevel;

        # The WSL host, built. There is no booting a WSL distribution in a
        # NixOS test — it needs Windows' WSL to start it — so building it is
        # what CI can honestly say about it; the boot is checked on the
        # desktop.
        z690-wsl = z690Wsl.config.system.build.toplevel;

        # How the machine lets people in, read off the files it would install
        # rather than the options behind them. The VM suites cannot answer
        # this for metal: every VM keeps passwordless sudo
        # (modules/vm/qemu-guest.nix). tests/desktop.nix has the lockout's
        # behaviour; this has metal's sudoers, and the lockout's place in each
        # of its stacks (modules/base/login-limits.nix):
        #
        #   preauth   before the first line that can say yes (fingerprint or
        #             password, `sufficient`), so a locked account stays locked
        #   authfail  after the last password check and before pam_deny, so a
        #             failure is counted rather than skipped
        #   account   pam_faillock, to clear the count after a success
        metal-auth =
          let
            etc = t14s.config.environment.etc;
            stacks = [
              "login"
              "sudo"
              "su"
              "polkit-1"
              "dankshell"
            ];
            # Autologin after the LUKS passphrase (modules/desktop/greeter.nix):
            # on metal, and nowhere a passphrase did not come first — the VM
            # stands for every node without LUKS.
            autologin =
              cfg:
              let
                s = cfg.services.greetd.settings;
              in
              if s ? initial_session then s.initial_session.user else null;
            vmCfg = t14s.config.virtualisation.vmVariant;
          in
          assert lib.assertMsg (
            autologin t14s.config == "max"
          ) "metal does not log max in after the passphrase";
          assert lib.assertMsg (
            t14s.config.boot.initrd.luks.devices ? crypted
          ) "metal has no LUKS volume to unlock";
          assert lib.assertMsg (
            autologin vmCfg == null
          ) "the VM, which has no passphrase at boot, logs in by itself";
          pkgs.runCommand "metal-auth" { } ''
            set -eu
            wheel=$(grep '^%wheel' ${etc.sudoers.source})
            case "$wheel" in
              *NOPASSWD*) echo "metal's sudo lets wheel in without a password: $wheel" >&2; exit 1 ;;
            esac

            for s in ${lib.concatStringsSep " " stacks}; do
              f=${builtins.dirOf etc."pam.d/login".source}/$s
              n() { grep -n -E "$1" "$f" | head -1 | cut -d: -f1; }
              last() { grep -n -E "$1" "$f" | tail -1 | cut -d: -f1; }
              pre=$(n '^auth +required +[^ ]*pam_faillock\.so .*\bpreauth\b')
              fail=$(n '^auth +\[default=die\] +[^ ]*pam_faillock\.so .*\bauthfail\b')
              yes=$(n '^auth +sufficient +[^ ]*pam_(unix|fprintd)\.so')
              unix=$(last '^auth +sufficient +[^ ]*pam_unix\.so')
              deny=$(n '^auth +required +[^ ]*pam_deny\.so')
              acct=$(n '^account +required +[^ ]*pam_faillock\.so')
              # Each with the config file: without conf=, pam_faillock reads
              # its defaults from the store (modules/base/login-limits.nix).
              [ "$(grep -c 'pam_faillock\.so .*conf=/etc/security/faillock\.conf' "$f")" = 3 ] \
                || { echo "$s: a pam_faillock line without conf=" >&2; exit 1; }
              for v in pre fail yes unix deny acct; do
                [ -n "$(eval echo \$$v)" ] || { echo "$s: no $v line" >&2; cat "$f" >&2; exit 1; }
              done
              [ "$pre" -lt "$yes" ] || { echo "$s: preauth after the first sufficient line" >&2; exit 1; }
              [ "$unix" -lt "$fail" ] && [ "$fail" -lt "$deny" ] \
                || { echo "$s: authfail not between pam_unix and pam_deny" >&2; exit 1; }
            done
            touch $out
          '';

        # And that the layout it describes actually partitions, formats and
        # boots. See ./tests/disk.nix for why that is a separate claim.
        metal-boots = import ./tests/disk.nix {
          inherit pkgs;
          inherit (inputs) preservation;
          disko = diskoForTests;
        };

        # install-maxnix, the installer USB's script (hosts/installer): its
        # refusals, then partitioning a virtual disk and placing the sops
        # key, which the booted result must decrypt with. See
        # ./tests/install.nix for what it leaves to install day.
        metal-install = import ./tests/install.nix {
          inherit pkgs mkInstallMaxnix;
          inherit (inputs) preservation sops-nix;
          disko = diskoForTests;
        };

        # The installer USB's system builds: the image is this plus a
        # squashfs, which is left to `nix build .#installer-iso`.
        installer = installer.config.system.build.toplevel;

        # The Fleet agent, switched on against a server that is not there.
        # See ./tests/fleet.nix for what that does and does not prove.
        fleet = pkgs.testers.runNixOSTest ./tests/fleet.nix;

        # Rootless Docker running a Docker Hub image, and a second machine
        # checking its published port is behind the firewall.
        containers = pkgs.testers.runNixOSTest ./tests/containers.nix;

        # The observability stack collecting, storing and serving, and nothing
        # of it reachable from a second machine with the firewall off.
        observability = pkgs.testers.runNixOSTest ./tests/observability.nix;

        # sops-nix decrypting a post-quantum age key at activation, the way
        # the real keys in .sops.yaml will be used.
        secrets = pkgs.testers.runNixOSTest (import ./tests/secrets.nix { inherit (inputs) sops-nix; });
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
          exec ${lib.getExe t14s.config.system.build.vm} "$@"
        '';
      };

      # nix run .#installer-vm [-- --headless] [-- --no-stick] [-- --fresh]
      #
      # Install day, rehearsed in QEMU: the installer image (packages.
      # installer-iso, unchanged) plugged in as a USB stick, UEFI firmware
      # without Secure Boot, and an empty NVMe disk where install-maxnix
      # expects the ThinkPad's — behind a PCIe root port, so it is
      # /dev/disk/by-path/pci-0000:01:00.0-nvme-1 here too. Then the README's
      # checklist from step 5 on, by hand, `nixos-install` included: the one
      # step checks.metal-install leaves out, and 1Password's sign-in on a
      # device it has not seen, which nothing else here can try.
      #
      #   --headless  no window; VNC on 127.0.0.1:5909, as vm-headless
      #   --no-stick  the stick pulled, as for step 9: boots the disk
      #   --offline   no network card. For booting what was installed with
      #               metal's real key: online it is metal to the world —
      #               it would enroll in Fleet as metal and back up into
      #               metal's Drive repository
      #   --fresh     a new, empty disk and firmware settings
      #
      # The disk is a sparse 64 GiB image in .vm/, growing to about the
      # machine's closure once installed. What lands on it is the real
      # machine — LUKS, and metal's key on /persist if that is what was
      # given — so the image is deleted with --fresh or by hand once done.
      #
      # A GL-capable GPU, as the dev VM has (modules/vm/qemu-guest.nix, whose
      # Mesa-wrapped QEMU this reuses): niri has no software renderer, so on
      # QEMU's plain VGA the installed system came up, logged in by itself,
      # and then showed nothing but niri-session's last console line
      # (2026-10-16). The installer's console needs none of it.
      #
      # No QEMU keymap (-k): the window passes the keyboard's scancodes
      # through, so the installer's German layout applies as on the
      # ThinkPad. Measured 2026-10-15 that `-k de` makes it worse for
      # scripted typing: vncdotool sends keysyms without Shift, and `/`
      # arrived as `7`. Scripted, type `loadkeys us` first, then anything.
      installerVm = pkgs.writeShellApplication {
        name = "installer-vm";
        runtimeInputs = [
          pkgs.qemu_kvm
          pkgs.coreutils
        ];
        text = ''
          dir=.vm
          disk=$dir/installer-disk.qcow2
          vars=$dir/installer-efivars.fd
          display=(-display "gtk,gl=on")
          stick=1
          net=(-netdev "user,id=net" -device "virtio-net-pci,netdev=net")
          for arg in "$@"; do
            case "$arg" in
              --headless) display=(-display egl-headless -vnc 127.0.0.1:9) ;;
              --no-stick) stick=0 ;;
              --offline) net=(-nic none) ;;
              --fresh) rm -f "$disk" "$vars" ;;
              *) echo "usage: nix run .#installer-vm -- [--headless] [--no-stick] [--offline] [--fresh]" >&2; exit 2 ;;
            esac
          done
          [ -e flake.nix ] || { echo "run this from the repo root; the disk goes in ./$dir" >&2; exit 1; }
          mkdir -p "$dir"
          [ -e "$disk" ] || qemu-img create -q -f qcow2 "$disk" 64G
          [ -e "$vars" ] || install -m 644 ${pkgs.OVMF.fd}/FV/OVMF_VARS.fd "$vars"

          usb=()
          if [ "$stick" = 1 ]; then
            iso=$(echo ${installer.config.system.build.isoImage}/iso/*.iso)
            usb=(
              -device "qemu-xhci,id=xhci"
              -drive "if=none,id=stick,format=raw,readonly=on,file=$iso"
              -device "usb-storage,bus=xhci.0,drive=stick,bootindex=0"
            )
          fi

          echo "installer-vm: disk $disk, stick $([ "$stick" = 1 ] && echo in || echo out), network ''${net[0]}" >&2
          exec ${t14s.config.virtualisation.vmVariant.virtualisation.qemu.package}/bin/qemu-system-x86_64 \
            -machine q35,accel=kvm -cpu host -smp 4 -m 8192 \
            -device virtio-vga-gl,xres=1920,yres=1080 \
            -drive if=pflash,format=raw,readonly=on,file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd \
            -drive "if=pflash,format=raw,file=$vars" \
            -device pcie-root-port,id=rp1,bus=pcie.0,chassis=1,addr=0x1c \
            -drive "if=none,id=nvme,format=qcow2,file=$disk" \
            -device nvme,serial=maxnix-install,drive=nvme,bus=rp1,bootindex=1 \
            "''${usb[@]}" \
            "''${net[@]}" \
            "''${display[@]}"
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
          NIX_DISK_IMAGE="$scratch/test.qcow2"           MAXNIX_HOME_IMAGE="$scratch/home.qcow2"             timeout 8 ${lib.getExe t14s.config.system.build.vm} > "$scratch/qemu.log" 2>&1
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
      # Goes through the loopback port forward in hosts/t14s/vm.nix, logs in
      # with the (plaintext, by decision) VM password, and ignores host keys —
      # every root-image reset mints a new one, and this is loopback to a
      # machine you own. -F /dev/null skips the host's /etc/ssh/ssh_config,
      # which is Ubuntu's and names options this Nix-built ssh does not know.
      #
      # Named `ssh` and put first on PATH on purpose: `nix copy` and friends
      # exec whatever `ssh` they find, so this is how vm-deploy's copies get
      # their port and password without any of those tools knowing.
      vmSshShim = pkgs.writeShellScriptBin "ssh" ''
        exec ${lib.getExe pkgs.sshpass} -p ${lib.escapeShellArg t14s.config.virtualisation.vmVariant.users.users.max.initialPassword} \
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
      #   nix run .#vm-ssh -- dms screenshot all --stdout --no-clipboard > shot.png
      #   nix run .#vm-ssh -- journalctl --user -u dms -n 50
      #
      # An ssh login is not part of the graphical session, so on its own it has
      # none of the variables that point at it: no WAYLAND_DISPLAY, no
      # NIRI_SOCKET. `niri msg` then fails, anything Wayland cannot find the
      # compositor, and the screenshot example above used to be `grim -`,
      # which had both problems (grim is not even installed) and so printed
      # nothing (found 2026-10-08). niri already exports exactly these into
      # the systemd user manager, so the session's own values are imported
      # from there rather than guessed from socket names.
      # With no session (greeter only) the grep finds nothing and the command
      # runs as before.
      #
      # ssh joins its arguments into one string for the remote shell anyway,
      # so prefixing that string with the import changes nothing about how a
      # command is quoted. The remote shell is bash, so `eval` also handles the
      # $'…' quoting systemd uses for values with special characters.
      vmSsh = pkgs.writeShellApplication {
        name = "vm-ssh";
        runtimeInputs = [ vmSshShim ];
        text = ''
          # shellcheck disable=SC2016  # expanded in the guest, not here
          session='set -a; eval "$(systemctl --user show-environment 2>/dev/null | grep -E "^(WAYLAND_DISPLAY|DISPLAY|NIRI_SOCKET)=")"; set +a'
          if [ $# -eq 0 ]; then
            # A command suppresses ssh's automatic tty, so ask for one back.
            exec ssh -t max@127.0.0.1 "$session; exec \"\$SHELL\" -l"
          fi
          exec ssh max@127.0.0.1 "$session; $*"
        '';
      };

      # nix run .#vm-restore-key
      #
      # Put the VM's sops key back after a full reset (.vm/home.qcow2 deleted),
      # or onto a fresh VM. The key is kept in 1Password and restored, never
      # generated in the guest — see hosts/t14s/secrets.nix for why.
      #
      # It goes from `op read` straight through the ssh pipe into a root-only
      # file; nothing prints it and nothing on the host writes it down. Run it
      # from your own terminal, where 1Password can prompt. `op` is the host's,
      # not the flake's: it talks to the 1Password app, which is the host's.
      #
      # Then it checks rather than trusts: the guest derives the public half of
      # what landed and compares it with `vm` in .sops.yaml. age is copied in
      # for that, with the guest half above, the way vm-deploy copies its
      # closure — so a VM that predates this still works.
      vmRestoreKey =
        let
          # Where the VM decrypts from, read off its own config so the two
          # cannot disagree.
          key = t14s.config.virtualisation.vmVariant.sops.age.keyFile;

          # The guest half. Lands in /run (tmpfs) first and replaces the key
          # only if something arrived: if `op read` fails — prompt denied,
          # 1Password locked — the pipe still closes, and writing straight to
          # the key would swap a working key for an empty file.
          install = pkgs.writeShellScript "install-sops-key" ''
            set -eu
            umask 077
            t=$(mktemp -p /run)
            trap 'rm -f "$t"' EXIT
            cat > "$t"
            [ -s "$t" ] || { echo "nothing received; ${key} left as it was" >&2; exit 1; }
            install -D -m 600 -o root -g root "$t" ${key}
          '';
        in
        pkgs.writeShellApplication {
          name = "vm-restore-key";
          runtimeInputs = [
            vmSshShim
            pkgs.nix
            pkgs.gnused
          ];
          text = ''
            want=$(sed -n 's/^  - &vm //p' ${./.sops.yaml})
            [ -n "$want" ] || { echo "no vm key in .sops.yaml" >&2; exit 1; }

            nix copy --no-check-sigs --to ssh://max@127.0.0.1 ${install} ${pkgs.age}

            echo "reading the VM key from 1Password..." >&2
            op read --account my.1password.com op://uxobupcysqhat566ymgikx46fm/yzia6np7dypeudlivpgqi5jwuu/notesPlain \
              | ssh max@127.0.0.1 'sudo ${install}'

            got=$(ssh max@127.0.0.1 'sudo ${pkgs.age}/bin/age-keygen -y ${key}')
            if [ "$got" = "$want" ]; then
              echo "restored: ${key} matches vm in .sops.yaml" >&2
            else
              echo "MISMATCH: ${key} is not the vm key in .sops.yaml" >&2
              exit 1
            fi
          '';
        };

      # The admin key's command, shared by the dev shell and secret-set so the
      # two cannot drift apart. See the dev shell for why a command.
      sopsAgeKeyCmd = "op read --account my.1password.com op://uxobupcysqhat566ymgikx46fm/fsgcalkkn3guvyu6uf3blufipa/notesPlain";

      # nix run .#secret-set -- <name> <op-reference>
      #
      # Put one value from 1Password into hosts/t14s/secrets.yaml, or
      # secrets-metal.yaml for metal's own, from the repo root and your own
      # terminal, where 1Password can prompt:
      #
      #   nix run .#secret-set -- restic-password "op://<vault>/<item>/password"
      #
      # What the hand-written `op read | jq -R . | sops set` in
      # hosts/t14s/secrets.nix did, with its gaps closed:
      #
      #   - Only names the machine declares, metal or VM, read off their
      #     configs: a typo would otherwise sit in the file, unused, while the
      #     declared secret stayed missing.
      #   - Nothing written unless 1Password returned something. A plain pipe
      #     carries on after a failed `op read` — prompt denied, 1Password
      #     locked — the hazard vm-restore-key guards against too.
      #   - Secrets decrypted for the users (neededForUsers) are login
      #     passwords, stored as hashes; for those it hashes with yescrypt
      #     itself, so a password can never land there in plaintext.
      #   - Checked, not trusted: it decrypts what it wrote and compares.
      #
      # The value lives in shell variables and pipes, never in a file or an
      # argument list, and is never printed; for a hash, the first seven
      # characters ($y$j9T$) are, as proof of the kind. Trailing newlines are
      # dropped, as `op read` adds one; a multi-line value keeps its inner
      # ones. `op` is the host's, like vm-restore-key's.
      secretSet =
        let
          # Name → the file it lives in, read off the secret's sopsFile, so a
          # secret moved between hosts/t14s/secrets.yaml and
          # secrets-metal.yaml is written where the machine looks for it.
          # Both machines' declarations: metal's names and the VM's are not
          # the same set. A name the two read from different files has no
          # one answer, and stops the build.
          filesOf =
            cfg: lib.mapAttrs (_: s: "hosts/t14s/${baseNameOf (toString s.sopsFile)}") cfg.sops.secrets;
          metalFiles = filesOf t14s.config;
          vmFiles = filesOf t14s.config.virtualisation.vmVariant;
          clashes = lib.filter (n: metalFiles ? ${n} && metalFiles.${n} != vmFiles.${n}) (
            builtins.attrNames vmFiles
          );
          files =
            assert lib.assertMsg (
              clashes == [ ]
            ) "secret-set: metal and the VM read ${toString clashes} from different files";
            vmFiles // metalFiles;
          declared = builtins.attrNames files;
          hashed = builtins.attrNames (lib.filterAttrs (_: s: s.neededForUsers) t14s.config.sops.secrets);
        in
        pkgs.writeShellApplication {
          name = "secret-set";
          runtimeInputs = [
            pkgs.sops
            pkgs.jq
            pkgs.mkpasswd
          ];
          text = ''
            export SOPS_AGE_KEY_CMD=${lib.escapeShellArg sopsAgeKeyCmd}
            declared=${lib.escapeShellArg (lib.concatStringsSep " " declared)}
            hashed=${lib.escapeShellArg (lib.concatStringsSep " " hashed)}

            if [ $# -ne 2 ]; then
              echo "usage: secret-set <name> <op-reference>" >&2
              echo "names: $declared" >&2
              exit 2
            fi
            name=$1 ref=$2

            case " $declared " in
              *" $name "*) ;;
              *)
                echo "$name is not a secret the machine declares; declare it in hosts/t14s/secrets.nix first" >&2
                exit 1
                ;;
            esac
            case "$name" in
              ${lib.concatStrings (lib.mapAttrsToList (n: f: "${n}) file=${f} ;;\n  ") files)}
            esac
            [ -f "$file" ] || { echo "no $file here; run this from the repo root" >&2; exit 1; }

            echo "reading $name from 1Password..." >&2
            value=$(op read --account my.1password.com "$ref")
            [ -n "$value" ] || { echo "1Password returned nothing; $file left as it was" >&2; exit 1; }

            case " $hashed " in
              *" $name "*)
                value=$(printf '%s' "$value" | mkpasswd -m yescrypt --stdin)
                shown="a yescrypt hash, ''${value:0:7}…"
                ;;
              *) shown="the value from 1Password" ;;
            esac

            printf '%s' "$value" | jq -Rs . | sops set --value-stdin "$file" "[\"$name\"]"

            [ "$(sops decrypt --extract "[\"$name\"]" "$file")" = "$value" ] \
              || { echo "MISMATCH: $name in $file is not what was written" >&2; exit 1; }
            echo "set $name to $shown, and read back to match" >&2
          '';
        };

      # nix run .#backup -- <command>
      #
      # Runs a command against the backup's Google Drive with credentials from
      # 1Password, from any machine that has `op` signed in:
      #
      #   nix run .#backup -- rclone about gdrive:
      #   nix run .#backup -- rclone lsd gdrive:
      #   nix run .#backup -- restic snapshots
      #   nix run .#backup -- restic restore latest --target /tmp/r --include /home/max/x
      #
      # restic gets the repository and its password the same way, and its
      # rclone backend starts the rclone below with this environment, so the
      # gdrive: remote reaches it unchanged.
      #
      # For testing the OAuth client now, and for the day this machine's disk
      # is gone along with its sops key: 1Password is then the only copy left,
      # so this is the restore path, not a convenience.
      #
      # The remote is defined entirely by environment variables holding op://
      # references, which `op run` resolves into the command's environment
      # only, masking them in its output. Nothing secret reaches an argument
      # list or shell history. The one leak would be rclone saving a refreshed
      # token, refresh token included, into its config file — so that is
      # pointed at a fresh file in $XDG_RUNTIME_DIR (tmpfs) and removed on
      # exit, rather than ~/.config/rclone/rclone.conf.
      #
      # `op` is the host's, as for vm-restore-key, and always with --account:
      # without it `op` reads the default account, finds no such vault, and a
      # hand-written `rclone authorize drive "$(op read …)" …` then runs with
      # empty arguments.
      #
      # ── nix run .#backup -- authorize ────────────────────────────────────
      #
      # Fills the token field, once, or again after the grant is revoked.
      # Guarded because of how that went the first time: rclone authorize
      # given an empty client id does not fail, it silently falls back to
      # rclone's own client, and the token it prints is refused later with
      # `unauthorized_client` — the client that redeems a refresh token must
      # be the one that issued it. Here the id and secret reach rclone as
      # RCLONE_DRIVE_* variables rather than arguments, so they are not in ps
      # either, and an empty one stops the run. The scope comes the same way:
      # rclone's default is full `drive`, not the `drive.file` the consent
      # screen grants.
      #
      # The consent screen should name this project's app, not rclone. Save
      # the JSON it prints as the item's `token` field exactly as printed.
      # Do not strip the expired access_token: rclone 1.75 rewrites a token
      # whose access_token is empty or missing back into its config file as
      # an empty one, refresh_token gone — reproduced, and how the VM's first
      # backup failed (2026-10-02). Every command below therefore checks the
      # field's shape before running.
      backup =
        let
          item = "op://uxobupcysqhat566ymgikx46fm/vzuc267xgjsigg4luhczyeml6q";
          # One restic password per repository, as in hosts/t14s/secrets.nix:
          # the VM's key must not open metal's snapshots.
          resticPasswordVm = "op://uxobupcysqhat566ymgikx46fm/3mgylwhm4eziob5ka5v2vv4o24/password";
          resticPasswordMetal = "op://uxobupcysqhat566ymgikx46fm/remrafourzg634zb6a33fn2hoa/password";
          vmRepository = t14s.config.virtualisation.vmVariant.maxnix.backup.repository;

          # Runs inside `op run`, after the references are resolved.
          authorize = pkgs.writeShellScript "backup-authorize" ''
            set -eu
            if [ -z "$RCLONE_DRIVE_CLIENT_ID" ] || [ -z "$RCLONE_DRIVE_CLIENT_SECRET" ]; then
              echo "client id or secret empty in 1Password; not falling back to rclone's client" >&2
              exit 1
            fi
            exec ${lib.getExe pkgs.rclone} authorize drive
          '';

          # Likewise inside `op run`: refuse a token rclone would destroy (see
          # above), then run the command. Prints field names only.
          checked = pkgs.writeShellScript "backup-checked" ''
            set -eu
            if ! printf '%s' "$RCLONE_CONFIG_GDRIVE_TOKEN" \
              | ${lib.getExe pkgs.jq} -e '(.access_token // "") != "" and (.refresh_token // "") != ""' >/dev/null 2>&1; then
              echo "the token field needs both access_token and refresh_token, as rclone authorize printed it;" >&2
              echo "it has: $(printf '%s' "$RCLONE_CONFIG_GDRIVE_TOKEN" | ${lib.getExe pkgs.jq} -c keys 2>/dev/null || echo 'no valid JSON')" >&2
              echo "fix: nix run .#backup -- authorize, and save its output unchanged" >&2
              exit 1
            fi
            exec "$@"
          '';
        in
        pkgs.writeShellApplication {
          name = "backup";
          runtimeInputs = [
            pkgs.rclone
            pkgs.restic
          ];
          text = ''
            if [ $# -eq 0 ]; then
              echo "usage: nix run .#backup -- <command>   e.g. rclone about gdrive:" >&2
              echo "       nix run .#backup -- authorize" >&2
              exit 2
            fi

            umask 077
            conf=$(mktemp -p "''${XDG_RUNTIME_DIR:?needs a tmpfs XDG_RUNTIME_DIR}" rclone.XXXXXX.conf)
            trap 'rm -f "$conf"' EXIT

            # Backend-wide, so `authorize` and the gdrive: remote share them.
            export RCLONE_CONFIG="$conf"
            export RCLONE_DRIVE_SCOPE=drive.file
            export RCLONE_DRIVE_CLIENT_ID="${item}/client_id"
            export RCLONE_DRIVE_CLIENT_SECRET="${item}/client_secret"

            if [ "$1" = authorize ]; then
              op run --account my.1password.com -- ${authorize}
              exit
            fi

            # Only here: before the first authorize the token field does not
            # exist, and `op run` refuses a reference it cannot resolve.
            export RCLONE_CONFIG_GDRIVE_TYPE=drive
            export RCLONE_CONFIG_GDRIVE_TOKEN="${item}/token"
            # The machine's own setting, so the two cannot drift apart, unless
            # overridden: RESTIC_REPOSITORY=rclone:gdrive:maxnix-backup-vm for
            # the VM's (hosts/t14s/vm.nix), which also picks the VM's
            # password.
            export RESTIC_REPOSITORY="''${RESTIC_REPOSITORY:-${t14s.config.maxnix.backup.repository}}"
            if [ "$RESTIC_REPOSITORY" = ${lib.escapeShellArg vmRepository} ]; then
              export RESTIC_PASSWORD="${resticPasswordVm}"
            else
              export RESTIC_PASSWORD="${resticPasswordMetal}"
            fi

            op run --account my.1password.com -- ${checked} "$@"
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
      # because max is a trusted user there (hosts/t14s/vm.nix). The copy is
      # over loopback and only sends what the guest does not already have.
      #
      # The toplevel is interpolated into the script, so `nix run .#vm-deploy`
      # builds it as a dependency — no nested nix invocation, and what gets
      # deployed is exactly what this evaluation of the flake describes.
      vmDeploy =
        let
          toplevel = t14s.config.virtualisation.vmVariant.system.build.toplevel;
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

            # The same diff the in-guest `rebuild` prints, run in the guest
            # because that is where both systems are: the new one has just
            # been copied there, and the current one was never here. See the
            # note at `rebuild` in hosts/t14s/vm.nix for why this is the
            # artifact worth having.
            echo >&2
            ssh max@127.0.0.1 nvd diff /run/current-system ${toplevel} >&2 || true
            echo >&2

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
      #   always   `nix flake check` — formatting, lint, the metal stage, and
      #            the two desktop suites without their screen assertions. Sandboxed, so
      #            results are cached: a second run of an unchanged tree is
      #            nearly free.
      #   with a   the same two suites with every subtest, through the
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
            # modules/metal/disk.nix gave the metal configuration a root
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
            echo "-- the installable systems build --" >&2
            nix build --print-build-logs ${checkArgs metalChecks}

            echo >&2
            echo "-- vm suites, portable tier --" >&2
            # --max-jobs 1 because these guests are the whole desktop machine,
            # 8192 MiB each: in parallel they may grow to 16 GiB, all a GitHub
            # runner has (install-nix-action sets max-jobs = auto there).
            # A guest keeps every page it touches, page cache included, so
            # the ceiling is what bounds it, not a typical run. Measured on
            # the host, 2026-10-12, peaks were desktop 2.8 GiB, niri 3.0
            # (and 3.6 for hyprland, a suite since removed). Stated here
            # rather than left to whatever nix.conf says — the divergence
            # this runner exists to prevent.
            #
            # The metal stage above runs in parallel, on less margin: its
            # ceilings add up to 17 GiB (observability's 4096 + 4096 + 1024,
            # two 1024s each for metal-boots, metal-install and containers,
            # one each for secrets and fleet), over a runner's 16, but its
            # measured peaks only to about 9.4 GiB (2026-10-12), observability
            # 5.3 of that, before metal-install — unmeasured, and built like
            # metal-boots, which peaked at 1.5. Kept parallel for that; if a
            # runner ever runs out there, it gets this flag too.
            nix build --max-jobs 1 --print-build-logs ${checkArgs portableVmTests}

            if [ "$have_gpu" = no ]; then
              echo >&2
              echo "SKIPPED, no render node — these need a GPU:" >&2
              echo "  desktop:  the guest has a GPU with working virgl" >&2
              echo "  desktop:  the greeter renders" >&2
              echo "  niri:     drives the virtual display" >&2
              echo "  niri:     starts the DankMaterialShell service" >&2
              echo "  niri:     renders a client window" >&2
              echo "  niri:     the session renders a rich screen" >&2
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

          # Editing hosts/t14s/secrets.yaml, and reading a key's public
          # half with `age-keygen -y`. Pinned here so the sops that writes
          # the file is the flake's, not whatever the host has.
          pkgs.sops
          pkgs.age

          # The login password's hash, for the `login-password` secret
          # (hosts/t14s/secrets.nix): `mkpasswd -m yescrypt --stdin`.
          pkgs.mkpasswd

          # `rclone authorize "drive" <id> <secret>` for the backup's Google
          # Drive token (modules/metal/backup.nix). From the flake's nixpkgs so
          # it matches the rclone the backup unit runs; mismatched versions
          # produce token format errors.
          pkgs.rclone
        ];

        # sops gets the admin key from 1Password on each run rather than from
        # a file: the command's output is the key, and 1Password prompts
        # before handing it over. Here rather than in .envrc so `nix develop`
        # sets it too, on a machine without direnv. See hosts/t14s/secrets.nix.
        #
        # A command, not `op run` with SOPS_AGE_KEY: that would put the key in
        # sops's environment, and `sops edit` passes its environment on to the
        # editor and everything the editor starts. Through a pipe the key only
        # ever reaches sops. Opaque ids rather than names, so the public repo
        # says as little as possible about the vault.
        env.SOPS_AGE_KEY_CMD = sopsAgeKeyCmd;
      };

      # nix run .#install -- root@<target>
      #
      # Install this flake onto a machine, over SSH, from here.
      #
      # NOT how the ThinkPad gets installed: that is the installer USB
      # (packages.installer-iso, hosts/installer), decided 2026-10-15 — this
      # needs a second machine with Nix, and the laptop on a cable, since the
      # kexec'd installer knows no Wi-Fi. Kept for a machine where both hold.
      #
      # It kexecs the target into a NixOS installer (so the target can be
      # running any Linux — including the Ubuntu this repo is developed on),
      # runs disko against modules/metal/disk-layout.nix to partition and
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
      # 1. modules/metal/disk-layout.nix names the ThinkPad's M.2 slot
      #    (/dev/disk/by-path/…). Check it against `ls -l /dev/disk/by-path`
      #    on the target before running this; on another machine it is wrong.
      # 2. The layout is encrypted and takes no passphrase from the config
      #    (maxnix.disk.passwordFile is null), so supply one for the
      #    formatting step:
      #
      #      nix run .#install -- \
      #        --disk-encryption-keys /tmp/secret.key \
      #          <(op read --no-newline "op://<vault>/<item>/password") \
      #        root@<target>
      #
      #    and set maxnix.disk.passwordFile = "/tmp/secret.key" so disko
      #    knows where to look. The *installed* machine still prompts at every
      #    boot, because nothing lands in settings.keyFile — which is the
      #    behaviour checks.metal-boots demonstrates.
      # 3. The machine's sops key has to be on /persist before the first
      #    boot: --extra-files with a directory holding persist/sops/age.key.
      #    install-maxnix does this step, and checks the key, on the USB path.
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
          exec nixos-anywhere --flake "${inputs.self}#t14s" "$@"
        '';
      };

      # nix run .#closure-diff -- <base-rev>
      #
      # Which packages change on metal between <base-rev> and the working
      # tree: both toplevels built, then `nvd diff`, the same report the
      # rebuild paths print before activating. Run from the repo root; a
      # branch name, tag or commit works as <base-rev>.
      #
      # What .github/workflows/closure-diff.yml posts on Renovate's lock file
      # maintenance PR, whose own description says only "All locks
      # refreshed": Renovate cannot say more, since inputs that follow a
      # branch have no version to report (researched 2026-10-16; the nix
      # manager leaves them to lock file maintenance, which is never grouped
      # and has no setting for its PR body). A list of changed inputs would
      # only trade hashes for commit dates; what a lock refresh means is
      # which packages change, and only a build of both sides shows that.
      #
      # Tried 2026-10-16 on a copy with `nix flake update` run, a week of
      # nixpkgs: 47 version changes (kernel, Firefox, Nix, …), 2 removals,
      # 173 s and about 7 GB with the base already built. A runner builds
      # both sides from nothing, so expect two metal closures' worth.
      #
      # Metal rather than the VM, as the real machine; Home Manager is a
      # NixOS module here, so the user's packages are in its closure too.
      # nvd is the flake's own, like everything the app runs except nix.
      closureDiff = pkgs.writeShellApplication {
        name = "closure-diff";
        runtimeInputs = [
          pkgs.nvd
          pkgs.git
        ];
        text = ''
          if [ $# -ne 1 ]; then
            echo "usage: nix run .#closure-diff -- <base-rev>" >&2
            exit 2
          fi
          [ -e flake.nix ] || { echo "run this from the repo root" >&2; exit 1; }
          rev=$(git rev-parse --verify "$1^{commit}")
          attr=nixosConfigurations.t14s.config.system.build.toplevel
          out=$(mktemp -d)
          trap 'rm -rf "$out"' EXIT

          echo "building metal at $rev..." >&2
          nix build --out-link "$out/base" "git+file://$PWD?rev=$rev#$attr"
          echo "building metal from the working tree..." >&2
          nix build --out-link "$out/head" ".#$attr"
          # From inside, so nvd's header names the sides, not a temp dir.
          cd "$out"
          nvd diff base head
        '';
      };

      # nix run .#blocked — which workarounds in docs/blocked.toml are still
      # waiting on a third party. The checker is ./tools/blocked.py; the list
      # format is described at the top of the TOML.
      #
      # Two layers because writePython3Bin pins the interpreter and runs
      # flake8 over the script at build time, but sets no PATH, and the
      # checks call out to gh, git and bash. writeShellApplication supplies
      # that. nix itself is deliberately not among them: the `nix` checks
      # should evaluate with the Nix you are running, the same one CI pins.
      #
      # Not a `check`, and not part of `ci`: most of its checks need the
      # network, which the build sandbox does not have, and a pull request
      # should not fail because something upstream moved.
      blockedPy = pkgs.writers.writePython3Bin "blocked-py" { } (builtins.readFile ./tools/blocked.py);
      blocked = pkgs.writeShellApplication {
        name = "blocked";
        runtimeInputs = [
          pkgs.gh
          pkgs.git
          pkgs.bash
        ];
        text = ''exec ${lib.getExe blockedPy} "$@"'';
      };

      # nix run .#blocked-report — what .github/workflows/blocked.yml runs:
      # the checker's JSON turned into issues, one per entry that has become
      # doable, so GitHub's own notifications say so. ./tools/blocked-report.py
      # describes the issue lifecycle. `--dry-run` prints what it would do on
      # GitHub and changes nothing, which is the way to run it by hand.
      blockedReportPy = pkgs.writers.writePython3Bin "blocked-report-py" { } (
        builtins.readFile ./tools/blocked-report.py
      );
      blockedReport = pkgs.writeShellApplication {
        name = "blocked-report";
        runtimeInputs = [
          blocked
          pkgs.gh
        ];
        text = ''exec ${lib.getExe blockedReportPy} "$@"'';
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
            # auto-discovers renovate.jsonc and checks it as a repository
            # config, where an explicit path makes it fall back to the laxer
            # global schema.
            echo "== renovate-config-validator ==" >&2
            renovate-config-validator
            touch "$out"
          '';

      # statix looks for statix.toml in the directory it is run from, which is
      # why this cds into the source instead of passing paths. That file lists
      # the two lints this repo switches off, and why.
    in
    {
      nixosConfigurations.t14s = t14s;
      nixosConfigurations.z690-wsl = z690Wsl;
      nixosConfigurations.installer = installer;

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
        vm = t14s.config.system.build.vm;
        default = t14s.config.system.build.vm;

        # The script that writes nixos.wsl, the file `wsl --import` takes.
        # NixOS-WSL's own builder, run as root since it assembles a root
        # filesystem: `sudo nix run .#z690-wsl-tarball`, then copy nixos.wsl to
        # Windows.
        z690-wsl-tarball = z690Wsl.config.system.build.tarballBuilder;

        # The installer USB; see hosts/installer for writing it to a stick.
        installer-iso = installer.config.system.build.isoImage;

        # Exposed so `nix build .#ci` checks the runner itself without
        # running it — writeShellApplication puts shellcheck in its build, so
        # this is how a typo in that script is caught before CI hits it.
        ci = ciRunner;
      };

      # Everything that runs on any machine: the static checks, the metal
      # stage and the VM suites minus their screen assertions. `nix flake check` is
      # therefore meaningful here and on a GPU-less runner alike.
      #
      # The GPU suites are deliberately absent. They are not hidden — they are
      # `nix run .#test-desktop|test-niri`, and `nix run .#ci`
      # runs them automatically wherever a render node exists. Keeping them
      # out of `checks` is what lets `nix flake check` be a command that
      # passes everywhere rather than one you have to qualify.
      checks.${system} = portableChecks;

      # nix run .#test-desktop | .#test-niri
      #
      # Both bind the same VNC port, so run them one at a time.
      apps.${system} = {
        vm-headless = {
          type = "app";
          program = lib.getExe vmHeadless;
        };
        installer-vm = {
          type = "app";
          program = lib.getExe installerVm;
        };
        test-vm-starts = {
          type = "app";
          program = lib.getExe vmStarts;
        };
        vm-ssh = {
          type = "app";
          program = lib.getExe vmSsh;
        };
        vm-restore-key = {
          type = "app";
          program = lib.getExe vmRestoreKey;
        };
        vm-deploy = {
          type = "app";
          program = lib.getExe vmDeploy;
        };
        backup = {
          type = "app";
          program = lib.getExe backup;
        };
        secret-set = {
          type = "app";
          program = lib.getExe secretSet;
        };
        ci = {
          type = "app";
          program = lib.getExe ciRunner;
        };
        install = {
          type = "app";
          program = lib.getExe installRunner;
        };
        blocked = {
          type = "app";
          program = lib.getExe blocked;
        };
        closure-diff = {
          type = "app";
          program = lib.getExe closureDiff;
        };
        blocked-report = {
          type = "app";
          program = lib.getExe blockedReport;
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
