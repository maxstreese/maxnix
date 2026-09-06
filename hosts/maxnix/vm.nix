# VM-only settings.
#
# Everything under `virtualisation.vmVariant` applies solely to the second
# evaluation that produces run-maxnix-vm. The base machine never sees it.
#
# These become QEMU command-line flags on the Ubuntu host — which is why the
# host needs nothing but a Nix daemon and /dev/kvm.
{ ... }:
{
  virtualisation.vmVariant.virtualisation = {
    cores = 4;
    memorySize = 8192; # MiB — of your 30 GiB
    diskSize = 16384; # MiB — a ceiling; the qcow2 grows into it

    # Default is "./${hostname}.qcow2", i.e. wherever you happened to cd.
    # Pinned so a forgotten image in another directory cannot silently supply
    # stale state. If you change the password above and it does not take, this
    # file is why: delete it and the VM is recreated from scratch.
    diskImage = "./.vm/maxnix.qcow2";

    # Headless on purpose. `-nographic` puts the guest console in this very
    # terminal over an emulated serial port — no QEMU window, no GPU, no
    # display backend, nothing that can fail interestingly yet.
    # Graphics and virtio-gpu arrive in step 2, as an isolated change.
    #
    # Exit the VM with: Ctrl-a x
    graphics = false;
  };
}
