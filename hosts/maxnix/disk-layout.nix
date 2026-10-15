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
#                 the key its harness writes; install-maxnix (../../flake.nix)
#                 points it at the passphrase it read from 1Password.
#   device        overridable for the same reason: install-maxnix takes a
#                 --disk, which its test points at a virtual disk. The
#                 default is still a plain string, for the reason above.
{
  passwordFile ? null,
  # The ThinkPad's one M.2 slot, by PCI path. Stable across reboots in a way
  # /dev/nvme0n1 is not guaranteed to be, and unlike /dev/disk/by-id/… it
  # names the slot rather than the drive, so no serial number lands in this
  # public repo (the same reason ./facter.json is stripped of them). With a
  # single slot that loses nothing: a replacement drive sits at the same
  # path. Only disko reads it, on install day — the installed system finds
  # its partitions by label (disk-main-ESP, disk-main-luks).
  device ? "/dev/disk/by-path/pci-0000:01:00.0-nvme-1",
  # disko's CLI calls this with arguments of its own (diskoFile, …).
  ...
}:
{
  disko.devices.disk.main = {
    inherit device;
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
            # install time and at every boot, and is the one password typed
            # before the session (no TPM unlock; ./disk.nix).
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];

              # Snapshot /root while it is still empty, and keep it read-only.
              #
              # This is what "a clean root" means for the rest of this
              # machine's life: the rollback in ../persistence.nix restores
              # this exact snapshot on every boot. Taken here, at format time,
              # because it is the only moment the subvolume is genuinely
              # empty — snapshotting later would bake whatever had
              # accumulated into the baseline and quietly defeat the point.
              #
              # On the btrfs content rather than the subvolume: disko's
              # generic hooks are attached to content types, and its btrfs
              # subvolume submodule does not include them. $device is the
              # hook variable disko exports for this content.
              postCreateHook = ''
                MNTPOINT=$(mktemp -d)
                mount "$device" "$MNTPOINT" -o subvol=/
                trap 'umount "$MNTPOINT"; rm -rf "$MNTPOINT"' EXIT

                # Only if absent, because disko's formatting has to be
                # idempotent: its own test harness runs disko-format a second
                # time and asserts it succeeds, and nixos-anywhere re-runs it
                # in repair mode. An unconditional snapshot fails there with
                # "already exists" — which is how this was first written.
                #
                # Skipping when it exists is also the correct semantics: the
                # first snapshot, taken when /root was empty, is the one that
                # should define a clean root forever. Re-taking it later would
                # silently promote an accumulated root to the new baseline.
                if ! btrfs subvolume show "$MNTPOINT/root-blank" >/dev/null 2>&1; then
                  btrfs subvolume snapshot -r "$MNTPOINT/root" "$MNTPOINT/root-blank"
                fi
              '';
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
