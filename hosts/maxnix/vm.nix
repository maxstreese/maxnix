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
  virtualisation.vmVariant = {
    imports = [ ../../modules/vm/qemu-guest.nix ];

    virtualisation = {
      # Default is "./${hostname}.qcow2", i.e. wherever you happened to cd.
      # Pinned so a forgotten image in another directory cannot silently supply
      # stale state. If you change a password and it does not take, this file
      # is why: delete it and the VM is recreated from scratch.
      diskImage = "./.vm/maxnix.qcow2";

      qemu.options = [
        # A real window. The test node overrides this with egl-headless.
        #
        # Override at runtime without rebuilding:
        #   QEMU_OPTS="-display egl-headless" ./result/bin/run-maxnix-vm
        "-display gtk,gl=on,show-cursor=on"
      ];

      # The repo itself, mounted inside the VM at /mnt/maxnix. Lets you edit
      # Quickshell QML on the host and see it in the guest without a rebuild.
      #
      # $PWD does NOT work here. The generated runner does `cd "$TMPDIR"`
      # before this string is expanded, so $PWD would silently share an empty
      # temp directory. (diskImage above escapes this only because the runner
      # resolves it to an absolute path *before* that cd.)
      #
      # $OLDPWD is what the launch directory becomes after that single cd. If a
      # future nixpkgs adds a second cd to the runner this breaks silently, so
      # MAXNIX_REPO is the explicit escape hatch:
      #   MAXNIX_REPO=/path/to/repo ./result/bin/run-maxnix-vm
      sharedDirectories.maxnix = {
        source = ''"''${MAXNIX_REPO:-$OLDPWD}"'';
        target = "/mnt/maxnix";
        securityModel = "none";
      };
    };
  };
}
