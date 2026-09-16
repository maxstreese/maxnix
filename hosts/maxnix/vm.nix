# How this host runs under `nixos-rebuild build-vm`.
#
# The virtual hardware lives in ../../modules/vm/qemu-guest.nix so the test
# node can share it; this file holds only what is specific to launching the VM
# by hand from a shell.
#
# Everything under virtualisation.vmVariant applies solely to the second
# evaluation that produces run-maxnix-vm. The base machine never sees it, and
# these become QEMU flags on the Ubuntu host — which is why the host needs
# nothing but a Nix daemon and /dev/kvm.
{ ... }:
{
  virtualisation.vmVariant =
    { config, pkgs, ... }:
    let
      # ── The fast loop ────────────────────────────────────────────────────
      #
      # Rebuild this machine from the repo shared at /mnt/maxnix and activate
      # it live, without rebooting. Measured at ~35s, against 1.5-3 minutes for
      # rebuilding on the host plus a reboot and a fresh login.
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
      # file needs `git add` on the host before rebuild can see it.
      rebuild = pkgs.writeShellApplication {
        name = "rebuild";
        text = ''
          flake="''${MAXNIX_FLAKE:-/mnt/maxnix}"

          if [ ! -e "$flake/flake.nix" ]; then
            echo "no flake.nix at $flake" >&2
            echo "the repo is shared there by hosts/maxnix/vm.nix;" >&2
            echo "set MAXNIX_FLAKE to point somewhere else" >&2
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

      virtualisation = {
        # Default is "./${hostname}.qcow2", i.e. wherever you happened to cd.
        # Pinned so a forgotten image in another directory cannot silently
        # supply stale state. If you change a password and it does not take,
        # this file is why: delete it and the VM is recreated from scratch —
        # which also wipes every login made inside it (1Password, Firefox, …);
        # see the README's open point on login state.
        diskImage = "./.vm/maxnix.qcow2";

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

        # The repo itself, mounted inside the VM at /mnt/maxnix. It is what
        # `rebuild` above builds from, and it lets you edit Quickshell QML on
        # the host and see it in the guest without a rebuild at all.
        #
        # $PWD does NOT work here. The generated runner does `cd "$TMPDIR"`
        # before this string is expanded, so $PWD would silently share an empty
        # temp directory. (diskImage above escapes this only because the runner
        # resolves it to an absolute path *before* that cd.)
        #
        # $OLDPWD is what the launch directory becomes after that single cd. If
        # a future nixpkgs adds a second cd to the runner this breaks silently,
        # so MAXNIX_REPO is the explicit escape hatch:
        #   MAXNIX_REPO=/path/to/repo ./result/bin/run-maxnix-vm
        sharedDirectories.maxnix = {
          source = ''"''${MAXNIX_REPO:-$OLDPWD}"'';
          target = "/mnt/maxnix";

          # `writable` replaced `securityModel` when nixpkgs moved shared
          # directories from 9p to virtiofs; the old option no longer exists
          # and setting it fails evaluation. true keeps the previous rw
          # behaviour. Nothing in the guest writes here — `rebuild` only
          # reads the flake — so false would be a small hardening, deferred
          # so a version bump does not also change behaviour.
          writable = true;
        };
      };
    };
}
