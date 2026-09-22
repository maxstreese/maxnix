# How this machine boots, and where its filesystems come from.
#
# The layout itself is ./disk-layout.nix — plain data, so that the test in
# ../../tests/disk.nix can format a virtual disk from the very same
# description rather than from a copy of it. This file is the NixOS half:
# it declares the bootloader, hands the layout to disko, and states which
# mounts the boot depends on.
#
# This is the one part of a NixOS install that is traditionally NOT code: you
# partition by hand with an installer, then `nixos-generate-config` writes a
# hardware-configuration.nix describing what you did. disko turns that round —
# the layout is the source of truth, and both the installer (which formats)
# and the running system (which mounts) read it.
#
# NOTHING HERE APPLIES IN THE VM. `nixos-rebuild build-vm` and every test node
# import qemu-vm.nix, which overrides fileSystems and boot.initrd.luks.devices
# with mkVMOverride and hands the guest its own virtual disks. That is why
# this file can describe hardware that does not exist yet without breaking
# anything that runs today — verified, not assumed: the test nodes evaluate to
# an empty luks set and their own filesystems.
#
# ── Why this shape ────────────────────────────────────────────────────────
#
# LUKS2 + btrfs subvolumes rather than a plain ext4 root, because two things
# already on the road to metal both require it:
#
#   Secure Boot with TPM unlock  needs the root to be encrypted at all, or
#                                there is nothing for the TPM to release.
#   Impermanence                 is implemented by rolling a subvolume back to
#                                a blank snapshot on boot. ext4 cannot do that.
#
# Doing it later would mean reinstalling, so it is done now.
#
# ── What is deliberately missing ──────────────────────────────────────────
#
# The device is a placeholder. The real one is a /dev/disk/by-id/… path, which
# is a fact about a machine that has not been chosen yet — `nixos-facter` on
# the target produces it (road to metal, README). Everything here evaluates
# and builds with the placeholder; only an actual install would fail, loudly,
# at the point of writing to a disk that is not there.
#
# No swap. Hibernation wants a swapfile at least the size of RAM, and RAM is
# another fact about the unchosen machine. A swapfile on btrfs is a file, so
# adding it later costs nothing — unlike the partition layout around it.
{ config, lib, ... }:
{
  options.maxnix.disk.passwordFile = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "/tmp/secret.key";
    description = ''
      File holding the LUKS passphrase, used when *creating* the volume.

      null, the default and what the real machine uses, means disko prompts
      and the passphrase is typed — at install time, and at every boot until
      TPM unlock replaces the typing.

      It exists because disko cannot create an encrypted volume without a
      passphrase from somewhere, and two callers need to supply one without
      a human present: the disk test, and `nixos-anywhere
      --disk-encryption-keys` on install day.
    '';
  };

  config = lib.mkMerge [
    (import ./disk-layout.nix { inherit (config.maxnix.disk) passwordFile; })

    {
      # systemd-boot rather than GRUB: lanzaboote, which is how Secure Boot
      # gets done on NixOS, requires it and is a drop-in replacement after.
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # Both must be mounted before anything writes to them.
      fileSystems."/persist".neededForBoot = true;
      fileSystems."/var/log".neededForBoot = true;
    }
  ];
}
