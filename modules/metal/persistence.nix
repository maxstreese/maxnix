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
# of this host's modules. Discovered by getting it wrong with the TPM option
# first, which then lived in a file of its own for the same reason.
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
#   /var/log        already its own btrfs subvolume (./disk-layout.nix),
#                   so it survives a root rollback without any help.
#                   Listing it as well would mean two mechanisms managing
#                   one path.
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
# the stricter requirement of a plain attrset.
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

        # `twingate setup` writes to both of these, and the daemon needs both:
        # the network name in /etc/twingate, the account in /var/lib/twingate
        # (<uuid>/auth.json, cert.pem, key.pem, device_id). Until 2026-11-27
        # only the first was here, and the first reboot after setup showed
        # what that is worth: the daemon exits with "there is no default
        # account, please run `twingate setup` first" and the unit ends in
        # start-limit-hit. 0711 is the mode the daemon gives the directory
        # itself.
        "/etc/twingate"
        {
          directory = "/var/lib/twingate";
          mode = "0711";
        }

        # Secure Boot keys. Not reproducible: losing them means re-enrolling
        # from firmware setup mode. See maxnix.boot.secureBoot in ./disk.nix.
        "/var/lib/sbctl"

        # Fleet's node key, from enrolling with IT's server. Losing it makes
        # every boot a fresh enrollment, i.e. a new host in their console. An
        # empty directory until maxnix.fleet is enabled; see ./fleet.nix.
        "/var/lib/orbit"

        # restic's cache of the repository's index and snapshots. Rebuildable,
        # but from Google Drive: without this, the first backup after every
        # boot downloads all of that metadata again. Excluded from the backup
        # itself; see ./backup.nix.
        "/var/cache/restic-backups-maxnix"

        # systemd's record of when each timer last ran. Persistent=true
        # catches up a missed run from it after boot — the backup's and the
        # GC's, ./backup.nix and ../base/default.nix. Without it every boot
        # starts with no record, systemd treats the timer as never run and
        # waits for the next scheduled time, so a laptop that was off at
        # midnight never backs up, and nothing says so.
        "/var/lib/systemd/timers"

        # NetworkManager's connections, Wi-Fi passwords included, as joined in
        # DMS's widget or with nmcli (../../hosts/t14s/configuration.nix). Root-only, as
        # NetworkManager keeps them.
        {
          directory = "/etc/NetworkManager/system-connections";
          mode = "0700";
        }
        # And its own state: whether Wi-Fi is switched on, when each network
        # was last used, and the secret key behind stable private IPv6
        # addresses, which would otherwise change at every boot.
        {
          directory = "/var/lib/NetworkManager";
          mode = "0700";
        }

        # The laptop services' state (../../hosts/t14s/laptop.nix, and Bluetooth from the
        # hardware report). Paired devices and their keys, root-only: without
        # it every headset is a stranger after a reboot.
        {
          directory = "/var/lib/bluetooth";
          mode = "0700";
        }
        # A firmware update staged for the next boot, and the history of
        # applied ones: the reboot that applies a UEFI update is exactly the
        # one that would otherwise forget it.
        "/var/lib/fwupd"
        # The power profile last chosen, so it is still chosen after a reboot.
        "/var/lib/power-profiles-daemon"
        # Battery charge history, which UPower's history graphs are made of.
        "/var/lib/upower"

        # The system that ran last, which the generation log compares the
        # running one against (../base/generation-log.nix). Without it the
        # first run after every boot would have nothing to compare with, and
        # an update that needed a reboot would go unrecorded.
        "/var/lib/generation-log"

        # Failed logins, counted by pam_faillock (../base/login-limits.nix). On the
        # wiped root, a reboot would reset the count and with it the lockout.
        {
          directory = "/var/lib/faillock";
          mode = "0700";
        }

        # The observability stack's history (../base/observability): months of
        # metrics and logs that cannot be rebuilt. Excluded from the backup
        # (./backup.nix).
        #
        # With their owners stated. preservation otherwise creates the
        # directory root:root 0755 and bind-mounts it in place, and Loki — the
        # one without a systemd StateDirectory to fix ownership — failed on
        # the first boot with "mkdir /var/lib/loki/rules: permission denied"
        # (2026-10-09). tests/observability.nix leaves this file out, and the
        # desktop suite, which has it, never asked about Loki; it does now.
        # Only where the user exists, so the disk test, which builds its
        # system from this file without the rest of the machine, still
        # evaluates.
      ]
      ++
        lib.concatMap
          (
            { directory, user }:
            lib.optional (config.users.users ? ${user}) {
              inherit directory user;
              group = user;
              mode = "0700";
            }
          )
          [
            {
              directory = "/var/lib/prometheus2";
              user = "prometheus";
            }
            {
              directory = "/var/lib/loki";
              user = "loki";
            }
            {
              directory = "/var/lib/grafana";
              user = "grafana";
            }
          ]
      ++ [
        # Alloy and Tempo run with DynamicUser, so their state is under
        # /var/lib/private, which systemd insists stays 0700, and systemd
        # itself chowns it to the dynamic user at every start. Alloy's holds
        # the journal read position: without it, every boot re-reads the last
        # 12 hours of journal into Loki.
        {
          directory = "/var/lib/private/alloy";
          configureParent = true;
          parent.mode = "0700";
        }
        # Tempo's traces and WAL, same arrangement.
        {
          directory = "/var/lib/private/tempo";
          configureParent = true;
          parent.mode = "0700";
        }
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
    description = "Set the old root aside and start from the blank snapshot";
    wantedBy = [ "initrd.target" ];
    after = [ "systemd-cryptsetup@crypted.service" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    # The old root is moved aside, not deleted, and kept for 30 days
    # (2026-11-16). The list above is the risk in this design: a path left
    # off it is state that silently disappears at the next boot, and no
    # generation brings it back, because it was never in the store. With
    # the old roots kept, such a file can still be copied out and the path
    # added:
    #
    #   mount -o subvol=/ /dev/mapper/crypted /mnt && ls /mnt/old_roots
    #
    # They are named by the time of the boot that retired them and aged by
    # their mtime, which the `touch` sets to that same moment. A clock that
    # is wrong at boot (an empty RTC battery says 1970) makes every age
    # negative, so nothing is deleted. They hold whatever the root held,
    # /tmp included, and are in no backup: nothing mounts them.
    #
    # Nested subvolumes go first, each time: btrfs refuses to delete a
    # subvolume that contains others.
    script = ''
      mkdir -p /btrfs_tmp
      mount -t btrfs -o subvol=/ /dev/mapper/crypted /btrfs_tmp

      delete_subvolume() {
        btrfs subvolume list -o "$1" | cut -f9- -d' ' | while read -r sub; do
          if [ -d "/btrfs_tmp/$sub" ]; then
            delete_subvolume "/btrfs_tmp/$sub"
          fi
        done
        btrfs subvolume delete "$1"
      }

      mkdir -p /btrfs_tmp/old_roots
      if [ -e /btrfs_tmp/root ]; then
        stamp=$(date -u +%Y-%m-%dT%H%M%SZ)
        name=$stamp
        n=0
        while [ -e "/btrfs_tmp/old_roots/$name" ]; do
          n=$((n + 1))
          name="$stamp-$n"
        done
        mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$name"
        touch "/btrfs_tmp/old_roots/$name"
      fi

      now=$(date +%s)
      for old in /btrfs_tmp/old_roots/*; do
        [ -e "$old" ] || continue
        age=$((now - $(stat -c %Y "$old")))
        if [ "$age" -gt $((30 * 24 * 3600)) ]; then
          delete_subvolume "$old"
        fi
      done

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
