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

  options.maxnix.boot.secureBoot = lib.mkEnableOption ''
    Secure Boot via lanzaboote, replacing systemd-boot.

    OFF until the machine exists and its keys are enrolled, because turning
    it on before that produces a system that cannot install itself: the
    bootloader it wants to write is signed with keys that are not there yet.

    The order on install day is fixed and cannot be shortened:

      1. install with this off, so systemd-boot writes a working ESP
      2. boot, then `sudo sbctl create-keys` (or lanzaboote's
         boot.lanzaboote.generateKeys.enable) to make /var/lib/sbctl
      3. put the firmware into Setup Mode and enrol — `sbctl enroll-keys`
      4. set this true, rebuild, reboot
      5. turn Secure Boot on in the firmware and check `bootctl status`

    Steps 3 and 5 are firmware menus on a specific machine, so nothing here
    can do them, and nothing here can test them either
  '';

  config = lib.mkMerge [
    (import ./disk-layout.nix { inherit (config.maxnix.disk) passwordFile; })

    # TPM unlock. Its own file because ../../tests/disk.nix needs the same
    # attrset — see the note there.
    (import ./luks-tpm.nix)

    {
      boot.loader.efi.canTouchEfiVariables = true;

      # Both must be mounted before anything writes to them.
      fileSystems."/persist".neededForBoot = true;
      fileSystems."/var/log".neededForBoot = true;
    }

    # systemd-boot, until Secure Boot replaces it. lanzaboote is a drop-in
    # replacement for it specifically, which is why the ESP was sized for
    # Unified Kernel Images from the start.
    (lib.mkIf (!config.maxnix.boot.secureBoot) {
      boot.loader.systemd-boot.enable = true;
    })

    (lib.mkIf config.maxnix.boot.secureBoot {
      # mkForce because the branch above is a plain definition, and both are
      # evaluated — the module system has to be told which one wins rather
      # than being left to merge two contradictory values.
      boot.loader.systemd-boot.enable = lib.mkForce false;
      boot.lanzaboote = {
        enable = true;
        # Where sbctl keeps the keys. Note for when impermanence lands: this
        # is state, it is not reproducible, and losing it means re-enrolling
        # from firmware setup mode — so it has to be on /persist.
        pkiBundle = "/var/lib/sbctl";
      };
    })
  ];
}
