# How this machine boots, and where its filesystems come from.
#
# This is the one part of a NixOS install that is traditionally NOT code: you
# partition by hand with an installer, then `nixos-generate-config` writes a
# hardware-configuration.nix describing what you did. disko turns that round —
# the layout below is the source of truth, and both the installer (which
# formats) and the running system (which mounts) read it.
#
# NOTHING HERE APPLIES IN THE VM. `nixos-rebuild build-vm` and every test node
# import qemu-vm.nix, which overrides fileSystems with mkVMOverride and hands
# the guest its own virtual disks. That is why this file can describe hardware
# that does not exist yet without breaking anything that runs today; see
# ../../modules/vm/qemu-guest.nix for the two settings that make that true.
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
# device is a placeholder. The real one is a /dev/disk/by-id/… path, which is
# a fact about a machine that has not been chosen yet — `nixos-facter` on the
# target produces it (road to metal, README). Everything here evaluates and
# builds with the placeholder; only an actual install would fail, loudly, at
# the point of writing to a disk that is not there.
#
# No swap. Hibernation wants a swapfile at least the size of RAM, and RAM is
# another fact about the unchosen machine. A swapfile on btrfs is a file, so
# adding it later costs nothing — unlike the partition layout around it.
{ lib, ... }:
{
  # systemd-boot rather than GRUB: lanzaboote, which is how Secure Boot gets
  # done on NixOS, requires it and is a drop-in replacement afterwards.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  disko.devices.disk.main = {
    # ROAD TO METAL. Replace with the target's /dev/disk/by-id/… path, which
    # is stable across reboots and enclosure changes in a way /dev/sdX is not.
    device = lib.mkDefault "/dev/disk/by-id/PLACEHOLDER-run-nixos-facter";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          # 1G rather than the conventional 512M: a Unified Kernel Image
          # carries the kernel, initrd and cmdline in one signed file, and
          # several generations of those do not fit in 512M. Sizing it now
          # avoids a reinstall when lanzaboote lands.
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            # The ESP holds boot material and is world-readable by default;
            # umask=0077 keeps it to root.
            mountOptions = [ "umask=0077" ];
          };
        };

        luks = {
          size = "100%";
          content = {
            type = "luks";
            name = "crypted";
            settings = {
              # TRIM through the encryption layer. It leaks which blocks are
              # in use, which is the accepted trade on an SSD that would
              # otherwise degrade; revisit if the threat model ever involves
              # someone holding the disk.
              allowDiscards = true;
            };
            # No keyFile and no passwordFile: the passphrase is typed, at
            # install time and at every boot. TPM-backed unlock replaces the
            # typing later (lanzaboote + systemd-cryptenroll) and is layered
            # on top of exactly this — it does not change the layout.
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                # Split so that impermanence can wipe one of them without
                # touching the others. Until that lands this is simply a
                # conventional layout that costs nothing.
                "/root" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "/home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                # The store is the large one and compresses well. It is also
                # the subvolume that must NEVER be rolled back: a wiped store
                # with an intact bootloader is an unbootable machine.
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                # Exists now, unused now. This is where declared state goes
                # once the root is ephemeral, and creating it up front means
                # that change is a config edit rather than a repartition.
                "/persist" = {
                  mountpoint = "/persist";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                # Kept out of the root subvolume for the same reason: logs
                # from before a rollback are exactly what you want to read
                # after one.
                "/log" = {
                  mountpoint = "/var/log";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };

  # /persist and /var/log must be mounted before anything writes to them.
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;
}
