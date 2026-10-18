# The metal role: what a machine installed on real hardware needs and a VM or
# a WSL guest does not — the LUKS/btrfs disk and its bootloader, the root
# wiped at every boot and what survives it, backups of what survives, and the
# employer's device management.
#
# Every VM is a variant of a metal host (qemu-vm.nix replaces the disk and
# bootloader), so it inherits this role and switches parts of it back off;
# see ../vm/qemu-guest.nix. The external modules these build on (disko,
# preservation, lanzaboote) are imported next to this role in flake.nix.
{ ... }:
{
  imports = [
    ./disk.nix
    ./persistence.nix
    ./backup.nix
    ./fleet.nix
  ];
}
