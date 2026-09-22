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

  # With machine-id bind-mounted from /persist it is no longer the tmpfs
  # systemd expects to commit on first boot, and that unit fails noisily
  # without doing anything useful. Upstream's own example suppresses it.
  systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];
}
