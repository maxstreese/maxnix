# What survives a wipe of the root.
#
# Step 1 of impermanence: the bind mounts, without the wipe. /persist/<path>
# is mounted over <path>, so state written there physically lives on the
# /persist subvolume — but the root is still an ordinary subvolume, so nothing
# is destroyed yet and a mistake here costs nothing.
#
# That ordering is the point. Once the root is rolled back on every boot, an
# omission from this list is data that silently disappears, and the feedback
# loop is a reboot. Getting the list right while errors are harmless is
# cheaper than getting it right afterwards.
#
# A plain attrset, not a module function, so ../../tests/disk.nix can hand the
# identical thing to makeDiskoTest as extraSystemConfig — that harness builds
# its installed system from the layout plus its own defaults and imports none
# of this host's modules. Same reason ./luks-tpm.nix exists; discovered by
# getting it wrong there first.
#
# ── Why preservation and not impermanence ────────────────────────────────
#
# Both are nix-community modules for this. impermanence is the established
# one; preservation is newer and explicitly not a drop-in replacement.
#
# preservation generates systemd mount units and tmpfiles rules, so the work
# happens declaratively through systemd, where impermanence runs logic at boot
# to move files into place. This repo has already rejected one imperative shim
# on those grounds (the .bashrc session-variable hack), and the same reasoning
# applies to something on the boot path. The usual counter — impermanence's
# home-manager integration — does not apply here: /home is its own subvolume
# and is never wiped.
#
# ── What is NOT here, and why ────────────────────────────────────────────
#
#   /var/log        already its own btrfs subvolume (../../hosts/maxnix/
#                   disk-layout.nix), so it survives a root rollback without
#                   any help. Listing it as well would mean two mechanisms
#                   managing one path.
#   /home           same.
#   /etc/ssh/…      host keys would belong here, but services.openssh.enable
#                   is false on metal — only the VM runs sshd. Add them with
#                   sshd, and note sops-nix decrypts with the host key, so
#                   that ordering matters when secrets land.
#
# ── Step 2: the root is now wiped on every boot ──────────────────────────
#
# The service below restores /root from the read-only /root-blank snapshot
# taken at format time (see ./disk-layout.nix) before the root is mounted. So
# anything not in the lists here, and not on the /nix, /home or /var/log
# subvolumes, is gone at the next boot.
#
# A module function rather than a plain attrset now, because it needs pkgs for
# btrfs-progs in the initrd. That is still shareable with the disk test: this
# goes into extraSystemConfig's `imports`, and the module system calls module
# functions there like anywhere else. Only makeDiskoTest's `disko-config` has
# the stricter requirement that forced ./luks-tpm.nix to stay an attrset.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  preservation = {
    enable = true;
    preserveAt."/persist" = {
      files = [
        # Journald's identity, and what systemd keys ConditionFirstBoot on.
        # inInitrd because it is read before the ordinary mounts happen.
        {
          file = "/etc/machine-id";
          inInitrd = true;
        }
      ];
      directories = [
        # The uid/gid allocation map. Losing this can renumber users
        # underneath their own files, which is the worst failure on this list
        # and the least obvious.
        "/var/lib/nixos"

        # `twingate setup` writes the network name here — the machine config
        # already documents that losing it means running setup again.
        "/etc/twingate"

        # Secure Boot keys. Not reproducible: losing them means re-enrolling
        # from firmware setup mode. See maxnix.boot.secureBoot in ./disk.nix.
        "/var/lib/sbctl"
      ];
    };
  };

  # /persist has to be mounted before anything reads from it — including the
  # initrd, for machine-id above.
  #
  # Lives here rather than in ./disk.nix so the test gets it too: declaring it
  # there would leave the test's /persist mounted too late and the failure
  # would look like a preservation bug.
  fileSystems."/persist".neededForBoot = true;

  # Roll the root back to its blank snapshot, before it is mounted.
  #
  # Ordering is the whole correctness argument. It has to run after
  # systemd-cryptsetup has opened /dev/mapper/crypted, or there is nothing to
  # mount, and before sysroot.mount, or it would be deleting a subvolume that
  # is already in use as the root. DefaultDependencies=no keeps systemd from
  # adding the ordinary ordering that would place it far too late.
  #
  # Nested subvolumes are deleted first: btrfs refuses to delete a subvolume
  # that contains others, and anything creating them inside / later (docker,
  # systemd-nspawn) would otherwise turn every boot into a failed rollback and
  # a root that quietly stopped being ephemeral.
  # Only where the root actually is the btrfs subvolume this rolls back.
  #
  # Every VM path — build-vm and all three test nodes — takes its root from
  # qemu-vm.nix, which is ext4 on a scratch image. Declared unconditionally,
  # the service ran there too and failed on every single boot with
  # "mount: /btrfs_tmp: unknown filesystem type 'btrfs'". The suites still
  # passed, because a failed oneshot does not block initrd.target — which is
  # the part worth pausing on: this unit fails *open*. A rollback that stops
  # working leaves a machine that boots normally and is quietly no longer
  # ephemeral, so a permanently-red unit in the VMs would have been training
  # to ignore exactly the signal that matters on metal.
  boot.initrd.systemd.services.rollback-root = lib.mkIf (config.fileSystems."/".fsType == "btrfs") {
    description = "Roll the root subvolume back to its blank snapshot";
    wantedBy = [ "initrd.target" ];
    after = [ "systemd-cryptsetup@crypted.service" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /btrfs_tmp
      mount -t btrfs -o subvol=/ /dev/mapper/crypted /btrfs_tmp

      btrfs subvolume list -o /btrfs_tmp/root | cut -f9 -d' ' | while read -r sub; do
        btrfs subvolume delete "/btrfs_tmp/$sub"
      done
      btrfs subvolume delete /btrfs_tmp/root
      btrfs subvolume snapshot /btrfs_tmp/root-blank /btrfs_tmp/root

      umount /btrfs_tmp
    '';
  };

  # btrfs is not otherwise in the initrd's PATH; without this the service
  # above fails and the root silently stops being ephemeral.
  boot.initrd.systemd.extraBin.btrfs = "${pkgs.btrfs-progs}/bin/btrfs";

  # With machine-id bind-mounted from /persist it is no longer the tmpfs
  # systemd expects to commit on first boot, and that unit fails noisily
  # without doing anything useful. Upstream's own example suppresses it.
  systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];
}
