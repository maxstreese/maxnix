# Backups.
#
# Impermanence made this question answerable. Before it, "what is worth
# backing up" meant auditing a root filesystem full of state nobody declared.
# Now the machine states it outright:
#
#   /nix        reproducible from the flake; never back it up
#   /           wiped every boot by definition
#   /var/log    useful to read, worthless to restore
#   /persist    every piece of system state that survives, because something
#               in ./persistence.nix says it should
#   /home       the actual work
#
# So the backup set is /persist and /home, and it is that short precisely
# because the rest of the machine is reproducible or deliberately disposable.
#
# ── restic rather than borg ──────────────────────────────────────────────
#
# Both are deduplicating and both have a NixOS module with timers and
# pruning. restic speaks S3, B2, SFTP and anything rclone reaches, where borg
# needs a borg-aware endpoint (a server running borg, BorgBase, rsync.net).
# Since the destination is not chosen yet, the one that can point almost
# anywhere is the safer default — and awscli2 is already installed here, so S3
# is a plausible landing place.
#
# The destination was settled afterwards, and constrained rather than chosen:
# Google Drive is the only one the employer permits on this machine (learned
# 2026-09-23), so the default repository is a Drive folder over rclone.
#
# ── Off until enabled on a machine holding the secrets ───────────────────
#
# The Drive credentials and the repository password come from sops
# (./secrets.nix), which declares them only once this is enabled. So this is
# disabled by default, switched on per machine, and asserts rather than
# silently doing nothing when half-configured.
#
# On the password specifically: it must NOT live only on this machine. A
# restic repository is encrypted with it, so a disk failure that takes
# /persist would take both the data and the only key to its backups. That is
# the argument for putting it in the repo under sops-nix rather than dropping
# a file on /persist — the one secret this configuration genuinely needs, and
# the reason item 15 follows this one rather than preceding it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.maxnix.backup;

  # An `rclone:` repository needs a binary and a token that a local path does
  # not, so several things below turn on this.
  isRclone = cfg.repository != null && lib.hasPrefix "rclone:" cfg.repository;
in
{
  options.maxnix.backup = {
    enable = lib.mkEnableOption "nightly restic backups of /persist and /home";

    repository = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      # The `gdrive` remote is the one ./secrets.nix renders into
      # rclone.conf, and `nix run .#backup` reads this same value, so the
      # machine and the restore path cannot point at different folders.
      default = "rclone:gdrive:maxnix-backup";
      description = ''
        The restic repository to write to. Any restic backend: a path, an
        sftp: URL, s3:, b2:, rclone:.
      '';
    };

    rcloneConfigFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to an rclone configuration file, for an `rclone:` repository.

        Required for Google Drive, which is the only destination permitted on
        a company machine. The file holds an OAuth refresh token, so it is a
        long-lived credential and belongs with the repository password rather
        than on disk beside it.

        ./secrets.nix renders it from three sops values and sets this; the
        values come from the 1Password item `nix run .#backup` reads:

          1. An OAuth client of our own, in the company Workspace's Google
             Cloud project `maxstreese-laptop-backup`: Desktop type, Internal
             audience (no verification, no 7-day token expiry), scope
             drive.file. rclone's shared credentials are rate-limited and
             being retired during 2026.
          2. A token for it, from `nix run .#backup -- authorize` on a machine
             with a browser, saved as the item's `token` field.
          3. The client id, secret and token piped into sops (./secrets.nix).

        Note what this does NOT replace: restic still encrypts everything
        client-side with maxnix.backup.passwordFile before anything is
        uploaded. Drive is storage, not trust.
      '';
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        File holding the repository password, read by the backup service as
        root. A path on the machine, never the password itself — putting it in
        a Nix option would copy it into the world-readable store.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.repository != null;
        message = "maxnix.backup.enable needs maxnix.backup.repository.";
      }
      {
        assertion = cfg.passwordFile != null;
        message = "maxnix.backup.enable needs maxnix.backup.passwordFile.";
      }
      {
        # Without the config file rclone has no token and the backup fails at
        # the first upload, nightly, in a unit nobody is watching.
        assertion = !(isRclone && cfg.rcloneConfigFile == null);
        message = "an rclone: repository needs maxnix.backup.rcloneConfigFile.";
      }
    ];

    # rclone is NOT on the unit's PATH by default: the nixpkgs module sets
    # `path = [ config.programs.ssh.package ]` and nothing else, while
    # restic's rclone backend shells out to the `rclone` binary. Without this
    # the job fails at the first upload. Checked in the module source rather
    # than discovered at 03:00 by a timer.
    systemd.services.restic-backups-maxnix.path = lib.mkIf isRclone [ pkgs.rclone ];

    # backup-now: the nightly backup, started by hand and watched until it
    # ends. Starting the unit rather than calling restic is the point — the
    # same paths, excludes, secrets and pruning as the timer's run, and
    # systemd will not start a second one beside a run already going.
    #
    # The unit is a oneshot, so `systemctl start` returns only once it has
    # finished, with its result as the exit status; the journal is followed
    # meanwhile. Ctrl-C stops the watching, not the backup. For everything
    # else — snapshots, restore, mount — there is `sudo restic-maxnix`, the
    # nixpkgs module's wrapper with the unit's environment.
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "backup-now";
        runtimeInputs = [
          pkgs.coreutils
          config.systemd.package
        ];
        text = ''
          unit=restic-backups-maxnix.service

          # Root for systemctl start and for reading the unit's journal. The
          # setuid sudo, not one from the store.
          if [ "$(id -u)" -ne 0 ]; then
            exec ${config.security.wrapperDir}/sudo "$(readlink -f "$0")" "$@"
          fi

          echo "starting $unit; Ctrl-C stops watching, not the backup" >&2
          journalctl --follow --lines=0 --output=cat --unit="$unit" &
          follow=$!
          trap 'kill "$follow" 2>/dev/null || true' EXIT

          status=0
          systemctl start "$unit" || status=$?
          # Let the last lines through before the follower is stopped.
          sleep 1

          if [ "$status" -eq 0 ]; then
            echo "backup finished" >&2
          else
            echo "backup FAILED; the whole run: journalctl -u $unit -n 200" >&2
          fi
          exit "$status"
        '';
      })
    ];

    services.restic.backups.maxnix = {
      inherit (cfg) repository passwordFile rcloneConfigFile;

      # Drive accepts 750 GB of uploads per user per day, and the first
      # backup can be larger. Past the limit rclone would otherwise retry for
      # hours; this makes the run fail instead, and restic picks up from its
      # saved progress the next night.
      rcloneOptions = lib.mkIf isRclone { drive-stop-on-upload-limit = true; };

      # Creates the repository on first run, so a fresh machine needs no
      # manual `restic init` step.
      initialize = true;

      paths = [
        "/persist"
        "/home"
      ];

      exclude = [
        # Caches: large, and by definition rebuildable. restic's own is
        # preserved on /persist (./persistence.nix) and would otherwise be
        # backed up into the repository it caches.
        "/home/*/.cache"
        "/persist/var/cache/restic-backups-maxnix"
        "/home/*/.local/share/Trash"

        # Steam. Tens of gigabytes of game data that Valve will happily send
        # again, and the single biggest thing on this machine — see the 12.5
        # GiB closure note in the README for the scale of what is already
        # here without it.
        "/home/*/.local/share/Steam"

        # Rootless Docker's images, layers and volumes (./containers.nix).
        # Gigabytes, and every image is a pull away. A named volume holding
        # something irreplaceable is the one thing this loses — keep such data
        # in a bind mount under a backed-up path instead.
        "/home/*/.local/share/docker"

        # Build output and dependency trees, all reproducible from a lockfile
        # that IS backed up.
        "**/node_modules"
        "**/.direnv"
        "**/target/debug"
      ];

      timerConfig = {
        OnCalendar = "daily";
        # Without this a laptop that was asleep at the scheduled time simply
        # skips the backup — the same trap as the GC timer in
        # ./configuration.nix, and the same fix.
        Persistent = true;
        RandomizedDelaySec = "30min";
      };

      # Keep enough to recover from a mistake noticed late, without keeping
      # every snapshot forever.
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
        "--keep-yearly 3"
      ];
    };
  };
}
