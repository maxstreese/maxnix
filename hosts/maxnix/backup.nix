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
# ── Off until two things exist ───────────────────────────────────────────
#
# A repository to write to, and a password to encrypt with. Neither can be
# invented here, so this is disabled by default and asserts rather than
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
  ...
}:
let
  cfg = config.maxnix.backup;
in
{
  options.maxnix.backup = {
    enable = lib.mkEnableOption "nightly restic backups of /persist and /home";

    repository = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "s3:s3.eu-central-1.amazonaws.com/maxnix-backups";
      description = ''
        The restic repository to write to. Any restic backend: a path, an
        sftp: URL, s3:, b2:, rclone:.
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
    ];

    services.restic.backups.maxnix = {
      inherit (cfg) repository passwordFile;

      # Creates the repository on first run, so a fresh machine needs no
      # manual `restic init` step.
      initialize = true;

      paths = [
        "/persist"
        "/home"
      ];

      exclude = [
        # Caches: large, and by definition rebuildable.
        "/home/*/.cache"
        "/home/*/.local/share/Trash"

        # Steam. Tens of gigabytes of game data that Valve will happily send
        # again, and the single biggest thing on this machine — see the 12.5
        # GiB closure note in the README for the scale of what is already
        # here without it.
        "/home/*/.local/share/Steam"

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
