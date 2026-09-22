# The partition layout, as data.
#
# Split out of ./disk.nix so that exactly one description of the disk exists
# and two different consumers can read it:
#
#   ./disk.nix        the NixOS module, which turns it into fileSystems and
#                     initrd LUKS entries for the real machine
#   ../../tests/disk.nix  disko's makeDiskoTest, which formats a virtual disk
#                     from it and boots the result
#
# It has to be a plain function rather than a NixOS module because that is
# what makeDiskoTest accepts: it calls its `disko-config` with `{ lib }` only,
# so anything needing `config` cannot be handed to it. Testing a *copy* of the
# layout was the alternative, and a copy that drifts from the original is
# precisely the failure this repo keeps finding.
#
# Two consequences of being test-visible, both load-bearing:
#
#   device        is a plain string, NOT lib.mkDefault. makeDiskoTest strips
#                 every attribute whose name starts with `_`, which includes
#                 the `_type` marker of an override — a mkDefault here
#                 survives as a shapeless attrset and the layout silently
#                 stops meaning what it says. The value is a placeholder
#                 anyway, and the test substitutes /dev/vda for it.
#   passwordFile  disko needs a passphrase non-interactively to *create* the
#                 LUKS volume. null (the default, and what the real machine
#                 uses) means it is typed at the prompt. The test points it at
#                 the key its harness writes; `nixos-anywhere
#                 --disk-encryption-keys` uses the same hook on install day.
{
  passwordFile ? null,
}:
{
  disko.devices.disk.main = {
    # ROAD TO METAL. Replace with the target's /dev/disk/by-id/… path, which
    # is stable across reboots and enclosure changes in a way /dev/sdX is not.
    device = "/dev/disk/by-id/PLACEHOLDER-run-nixos-facter";
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
            inherit passwordFile;
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
}
