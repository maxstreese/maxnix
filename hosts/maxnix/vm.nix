# How this host runs under `nixos-rebuild build-vm`.
#
# The virtual hardware lives in ../../modules/vm/qemu-guest.nix so the test
# node can share it; this file holds only what is specific to launching the VM
# by hand from a shell.
#
# The guest has no view of the host filesystem. It used to have the repo
# mounted at /mnt/maxnix (9p, then virtiofs, then 9p again), and that share
# was both the fast loop and a hole in the VM boundary. Dropped 2026-09-18:
# the guest keeps its own clone like any other machine, git is the sync, and
# the host reaches in over ssh — `nix run .#vm-deploy` builds here and
# activates there, which is the standard NixOS remote-deploy model and the
# same one the metal install will use.
#
# Everything under virtualisation.vmVariant applies solely to the second
# evaluation that produces run-maxnix-vm. The base machine never sees it, and
# these become QEMU flags on the Ubuntu host — which is why the host needs
# nothing but a Nix daemon and /dev/kvm.
{ ... }:
{
  virtualisation.vmVariant =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostPkgs = config.virtualisation.host.pkgs;

      # ── A second disk for /home ─────────────────────────────────────────
      #
      # Everything you sign in to — 1Password, Firefox, Spotify, Claude Code —
      # keeps its state under /home. Deleting the root image is the documented
      # reset, so /home gets its own image that survives it. Delete
      # .vm/home.qcow2 only when you mean to start over with every login.
      #
      # qemu-vm.nix creates only the root image itself, and its own
      # emptyDiskImages live in a per-run temp directory, so this image has to
      # be created here. The runner has no pre-start hook, but the drive's
      # `file` string is expanded by the shell at launch — so it can be a
      # command substitution that creates the image on first use and prints
      # its path. One caveat: by the time it runs the runner has done
      # `cd "$TMPDIR"`, so the default path is anchored to $OLDPWD, the launch
      # directory. If a future nixpkgs adds a second cd to the runner this
      # breaks silently, which is what MAXNIX_HOME_IMAGE is for.
      #
      # MAXNIX_HOME_IMAGE overrides the location, which is how tests keep
      # their hands off the real one.
      #
      # The qcow2 is sparse: 32G is a ceiling, not an allocation.
      homeImage = hostPkgs.writeShellScript "maxnix-home-image" ''
        img="''${MAXNIX_HOME_IMAGE:-.vm/home.qcow2}"
        # Relative paths mean "relative to where the VM was launched", not to
        # the runner's temp directory, which is the cwd by the time this runs.
        case "$img" in /*) ;; *) img="$OLDPWD/$img" ;; esac
        if [ ! -e "$img" ]; then
          mkdir -p "$(dirname "$img")"
          ${config.virtualisation.qemu.package}/bin/qemu-img create -q -f qcow2 "$img" 32G >&2
          echo "created home disk image $img" >&2
        fi
        readlink -f "$img"
      '';

      # ── The fast loop ────────────────────────────────────────────────────
      #
      # Rebuild this machine from a clone of the repo inside the guest and
      # activate it live, without rebooting. Measured at ~30s. This is the
      # inside-the-VM loop: edit in the clone (or let Claude Code do it),
      # `rebuild`, look. The clone lives on the /home disk, so it survives a
      # root-image reset, and it syncs with the host through git like any two
      # machines would. From the host, `nix run .#vm-deploy` is the equivalent.
      #
      # Two things this wraps that are easy to get wrong by hand:
      #
      #   - The attribute is the *vmVariant's* toplevel, not the bare
      #     nixosConfigurations entry. The base config has no fileSystems and
      #     no bootloader — qemu-vm.nix supplies both, and it exists only
      #     inside the variant. Targeting the obvious attribute fails with
      #     "The 'fileSystems' option does not specify your root file system."
      #   - `switch-to-configuration test`, not `switch`: test activates now
      #     without touching the bootloader or the default boot entry, which is
      #     right for a VM whose disk image you throw away.
      #
      # Inherited from flakes: they only see git-tracked files, so a brand new
      # file needs `git add` before rebuild can see it.
      rebuild = pkgs.writeShellApplication {
        name = "rebuild";
        text = ''
          flake="''${MAXNIX_FLAKE:-$HOME/Repositories/github.com/maxstreese/maxnix}"

          if [ ! -e "$flake/flake.nix" ]; then
            echo "no flake.nix at $flake" >&2
            echo "clone the repo there (git clone <remote> \"$flake\")," >&2
            echo "or set MAXNIX_FLAKE to where it is" >&2
            exit 1
          fi

          attr="nixosConfigurations.${config.networking.hostName}.config.virtualisation.vmVariant.system.build.toplevel"

          echo "building from $flake ..." >&2
          out=$(nix build --no-link --print-out-paths "$flake#$attr")

          echo "activating $out" >&2
          sudo "$out/bin/switch-to-configuration" test
        '';
      };
    in
    {
      imports = [ ../../modules/vm/qemu-guest.nix ];

      environment.systemPackages = [ rebuild ];

      # ── SSH into the running VM ──────────────────────────────────────────
      #
      # The host-side way to drive the VM you are actually using: run
      # `rebuild`, poke the compositors and DMS over their IPC, take a
      # screenshot with grim and copy it out, read the journal — without a
      # fresh boot through the test driver each time. `nix run .#vm-ssh -- …`
      # (flake.nix) wraps the connection.
      #
      # Password authentication, deliberately: the password is plaintext in
      # this repo by decision, so a key would add ceremony without adding
      # secrecy. The port is bound to the host's loopback only (below), so
      # nothing on the network can reach it.
      #
      # VM-only. Whether the real host runs sshd is a separate decision, so
      # this lives here rather than in configuration.nix.
      services.openssh = {
        enable = true;
        settings.PasswordAuthentication = true;
      };

      # `nix run .#vm-deploy` pushes a closure built on the host into the
      # guest with `nix copy` over that ssh connection. Host-built paths carry
      # no signature the guest knows, and only a trusted user may import
      # unsigned paths. VM-only, like sshd: on metal the deploy story is a
      # separate decision.
      nix.settings.trusted-users = [ "max" ];

      virtualisation = {
        # Default is "./${hostname}.qcow2", i.e. wherever you happened to cd.
        # Pinned so a forgotten image in another directory cannot silently
        # supply stale state. If you change a password and it does not take,
        # this file is why: delete it and the VM is recreated from scratch.
        # /home is on its own image (see homeImage above), so that reset
        # keeps every login made inside the VM.
        diskImage = "./.vm/maxnix.qcow2";

        # The /home disk. `serial` gives it a stable name under
        # /dev/disk/by-id, which is what the mount below refers to. mkAfter
        # keeps it behind the module's root drive, so root stays /dev/vda.
        qemu.drives = lib.mkAfter [
          {
            name = "home";
            file = ''"$(${homeImage})"'';
            driveExtraOpts = {
              cache = "writeback";
              werror = "report";
            };
            deviceExtraOpts.serial = "home";
          }
        ];

        # Formatted on first boot (autoFormat), mounted from the initrd
        # (neededForBoot). The latter matters: NixOS creates /home/max during
        # activation, which runs *before* systemd mounts anything. Mounted
        # late, the fresh filesystem would hide that directory and the first
        # login would land in an empty, root-owned /home.
        fileSystems."/home" = {
          # The generated fstab shows the derived mount options twice.
          # qemu-vm.nix copies virtualisation.fileSystems into fileSystems
          # through the same submodule type, which appends
          # x-systemd.makefs / x-initrd.mount a second time. Upstream quirk,
          # harmless; not worth working around.
          device = "/dev/disk/by-id/virtio-home";
          fsType = "ext4";
          autoFormat = true;
          neededForBoot = true;
        };

        qemu.options = [
          # A real window. The test node overrides this with egl-headless.
          #
          # grab-on-hover: grab the keyboard whenever the pointer is over the
          # window, instead of only after Ctrl+Alt+G. The grab is what makes
          # GTK ask Mutter to inhibit the host's shortcuts, so with it Alt+Tab,
          # Super+1 and the rest go to the guest as soon as you point at it,
          # and back to the host when you point away. It only works once the
          # host has granted the request — scripts/vm-keys handles that, and
          # explains the whole chain. Drop the flag if you would rather grab
          # explicitly.
          #
          # Override at runtime without rebuilding:
          #   QEMU_OPTS="-display egl-headless" ./result/bin/run-maxnix-vm
          "-display gtk,gl=on,show-cursor=on,grab-on-hover=on"
        ];

        # Host loopback 2222 → guest 22, for the sshd above. QEMU's user-mode
        # networking does the forwarding; the guest sees an ordinary inbound
        # connection.
        forwardPorts = [
          {
            from = "host";
            host.address = "127.0.0.1";
            host.port = 2222;
            guest.port = 22;
          }
        ];

      };
    };
}
