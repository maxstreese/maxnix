# Secrets, as encrypted files in this repository.
#
# Values live encrypted in two files. At activation the machine decrypts
# them into /run/secrets, a tmpfs, with the owner and mode declared per
# secret. Configuration then references the *path*, never the value — a
# value written into a Nix option would be copied into the world-readable
# store:
#
#   maxnix.backup.passwordFile = config.sops.secrets.restic-password.path;
#
# The files are public along with the rest of the repo. That is sound only
# because they are encrypted, and why the keys below are post-quantum.
#
# ── Two files: shared, and metal's own ───────────────────────────────────
#
#   ./secrets.yaml        admin, vm, metal: what both machines use — Fleet,
#                         Harlequin, the Drive client and token, the VM's
#                         restic password
#   ./secrets-metal.yaml  admin, metal: what the VM must not read — the
#                         login password and metal's restic password
#
# The VM's key lives in a disk image on the Ubuntu host; until 2026-10-15
# one file held everything, so that key also opened metal's login password
# and the password to metal's backups. Which file a secret is in is set per
# secret below (sopsFile), and `nix run .#secret-set` reads it from there.
# The Drive token stays shared: both repositories are reached through one
# OAuth client, and drive.file grants that client every file it made, so a
# second token would see the same folders. What keeps metal's snapshots out
# of the VM's reach is the restic password, which encrypts them.
#
# Moving a secret between files does not take it out of git history, where
# the old file stays decryptable by every key it named. A moved secret
# whose old value matters gets a new one as it moves; the login password
# kept its own (2026-10-15), being a yescrypt hash of a long random password.
#
# ── Keys: three, each kept in 1Password ──────────────────────────────────
#
# sops encrypts the file once under a random data key, then wraps that data
# key separately to every public key in ../../.sops.yaml. Any one private
# key opens its own copy, so the keys need no relation to each other:
#
#   admin  a person editing secrets. Never on disk: sops fetches it from
#          1Password per run, via SOPS_AGE_KEY_CMD, set by the flake's dev shell.
#   vm     the build-vm guest. Restored onto its /home disk (./vm.nix).
#   metal  this machine on hardware. Restored onto /persist on install day.
#
# The machine keys are generated once, stored in 1Password and *restored*,
# not generated on the machine (sops.age.generateKey stays false). A wiped
# or reinstalled machine gets its old key back, so .sops.yaml never changes
# and no `sops updatekeys` is needed. Restoring the VM's, from a terminal
# 1Password can prompt in — never through a tool whose output is logged:
#
#   nix run .#vm-restore-key
#
# which also checks that what landed is the `vm` key in .sops.yaml.
#
# On metal the same file goes in with nixos-anywhere's --extra-files, so it
# is on /persist before first boot and the first activation already decrypts.
#
# ── Adding a secret ──────────────────────────────────────────────────────
#
# Declare it below, next to whatever consumes it, and keep the value in
# 1Password. Then, from the repo root and your own terminal, where 1Password
# can prompt:
#
#   nix run .#secret-set -- <name> "op://<vault>/<item>/<field>"
#
# It refuses names not declared here, writes nothing if 1Password returns
# nothing, and reads back what it wrote. The value goes through pipes only,
# never an argument list, an editor's swap file or the screen. Under it is
# what used to be typed by hand, `op read | jq -R . | sops set
# --value-stdin` — --value-stdin wants JSON, not the raw value — with the
# newline `op read` ends with dropped. See ../../flake.nix.
#
# The login password goes in as a hash, never as the password itself: the
# machine needs nothing more to check a login. secret-set hashes it with
# yescrypt by itself, for every secret declared neededForUsers, so the same
# command does it:
#
#   nix run .#secret-set -- login-password "op://<vault>/<item>/password"
#
# Fleet's two are `fleet-url` and `fleet-enroll-secret`. The backup's come
# from 1Password items `nix run .#backup` reads too, one restic password per
# machine:
#
#   restic-password             MaxNix Backup Restic Repository Password VM     password
#   restic-password-metal       MaxNix Backup Restic Repository Password Metal  password
#   rclone-drive-client-id      MaxNix Backup Google OAuth Client  client_id
#   rclone-drive-client-secret  MaxNix Backup Google OAuth Client  client_secret
#   rclone-drive-token          MaxNix Backup Google OAuth Client  token
#
# ── What can never live here ─────────────────────────────────────────────
#
# The LUKS passphrase. The machine key sits on the disk that passphrase
# unlocks, so the secret would be needed before the thing holding it exists.
# That is why ./disk.nix takes a typed passphrase and ./luks-tpm.nix layers
# TPM unlock on top rather than a keyfile.
{ config, lib, ... }:
let
  harlequin = config.maxnix.harlequin.profiles;
  backup = config.maxnix.backup;

  # The Drive secrets only for an rclone: repository; a local one, as in
  # checks.metal-boots, needs the password alone.
  backupDrive =
    backup.enable && backup.repository != null && lib.hasPrefix "rclone:" backup.repository;

  metal = config.maxnix.secrets.metal;
  fromMetal = {
    inherit (metal) sopsFile;
  };
  # Each machine's restic password under a name of its own, so the name
  # alone says which file it is in, for secret-set and for a reader.
  resticPassword = if metal.enable then "restic-password-metal" else "restic-password";
in
{
  options.maxnix.loginPassword.fromSops = lib.mkEnableOption ''
    max's and root's password from the `login-password` hash in metal's
    sops file. On for the machine (./configuration.nix); off on every VM,
    which has no metal key (../../modules/vm/qemu-guest.nix)
  '';

  options.maxnix.secrets.metal = {
    enable = lib.mkEnableOption ''
      the secrets only metal may read, from its own sops file: its restic
      password instead of the VM's. On for the machine
      (./configuration.nix); off on every VM (../../modules/vm/qemu-guest.nix)
    '';
    sopsFile = lib.mkOption {
      type = lib.types.path;
      default = ./secrets-metal.yaml;
      description = ''
        The file metal's own secrets are in: login-password and
        restic-password-metal. Encrypted to admin and metal only
        (../../.sops.yaml). A test points it at a fixture.
      '';
    };
  };

  options.maxnix.harlequin.profiles.enable = lib.mkEnableOption ''
    Harlequin's connection profiles, rendered from sops into
    ~/.config/harlequin/config.toml (see home/max/harlequin.nix)
  '';

  config = {
    sops = {
      defaultSopsFile = ./secrets.yaml;

      # Metal's path; ./vm.nix points the VM at its /home disk instead. On
      # /persist because the root is wiped every boot (./persistence.nix).
      age.keyFile = "/persist/sops/age.key";

      # Only the key above. sops-nix otherwise adds the machine's SSH host keys
      # as decryption keys whenever sshd is enabled — which it is in the VM —
      # and those are on the disposable root and were never recipients.
      age.sshKeyPaths = [ ];
      gnupg.sshKeyPaths = [ ];
    };

    # Consumers. Each secret is declared only when the thing using it is on:
    # sops-nix does nothing at all while sops.secrets is empty, which keeps the
    # test machines — they import this file but hold no key — from trying and
    # failing to decrypt.
    #
    # Fleet takes two: the enroll secret, and the server's URL, which is kept
    # out of the public repo as well. Orbit wants the URL as an environment
    # variable, so a template renders it into an env file under
    # /run/secrets/rendered, root-only like the rest.
    sops.secrets = lib.mkMerge [
      (lib.mkIf config.maxnix.fleet.enable {
        fleet-enroll-secret = { };
        fleet-url = { };
      })
      (lib.mkIf harlequin.enable {
        trino-host = { };
        trino-user = { };
      })
      (lib.mkIf backup.enable {
        ${resticPassword} = if metal.enable then fromMetal else { };
      })
      # Decrypted before the users are set up, into /run/secrets-for-users,
      # which is what neededForUsers is for: /run/secrets comes later.
      (lib.mkIf config.maxnix.loginPassword.fromSops {
        login-password = fromMetal // {
          neededForUsers = true;
        };
      })
      (lib.mkIf backupDrive {
        rclone-drive-client-id = { };
        rclone-drive-client-secret = { };
        rclone-drive-token = { };
      })
    ];
    sops.templates."orbit.env" = lib.mkIf config.maxnix.fleet.enable {
      content = "ORBIT_FLEET_URL=${config.sops.placeholder.fleet-url}\n";
    };
    # Per attribute, not `maxnix.fleet = mkIf …`: conditioning the whole
    # attrset on its own `enable` would make the option depend on itself.
    maxnix.fleet.enrollSecretPath = lib.mkIf config.maxnix.fleet.enable config.sops.secrets.fleet-enroll-secret.path;
    maxnix.fleet.urlEnvironmentFile =
      lib.mkIf config.maxnix.fleet.enable
        config.sops.templates."orbit.env".path;

    # The backup's rclone.conf. Its shape is public, its three values are
    # not, so a template like the ones above rather than one opaque secret
    # holding the whole file. The remote name is the `gdrive` in the default
    # maxnix.backup.repository. Root-owned, which is who the restic unit runs
    # as.
    #
    # rclone writes refreshed access tokens back into its config file. Here
    # that lands in the rendered copy and is replaced at the next activation.
    # Harmless for a token stored whole, as `rclone authorize` prints it — but
    # one stored without its access_token is rewritten as an empty token on
    # first use, refresh_token included, and every run after that fails with
    # "no refresh token" until the next activation. See the `backup` app in
    # ../../flake.nix, which refuses such a token.
    sops.templates."rclone.conf" = lib.mkIf backupDrive {
      content = ''
        [gdrive]
        type = drive
        scope = drive.file
        client_id = ${config.sops.placeholder.rclone-drive-client-id}
        client_secret = ${config.sops.placeholder.rclone-drive-client-secret}
        token = ${config.sops.placeholder.rclone-drive-token}
      '';
    };
    maxnix.backup.passwordFile = lib.mkIf backup.enable config.sops.secrets.${resticPassword}.path;

    # The login password, for max and root alike. Root keeps one so the
    # emergency shell still opens when a boot goes wrong; a locked root would
    # leave only the installer. With users.mutableUsers = false
    # (./configuration.nix) the hash is applied at every activation, so a
    # `passwd` lasts until the next one — the price of a password that a
    # wiped root cannot reset (README, "Decisions, and why").
    users.users = lib.mkIf config.maxnix.loginPassword.fromSops {
      max.hashedPasswordFile = config.sops.secrets.login-password.path;
      root.hashedPasswordFile = config.sops.secrets.login-password.path;
    };
    maxnix.backup.rcloneConfigFile = lib.mkIf backupDrive config.sops.templates."rclone.conf".path;

    # Harlequin's profiles. The file's shape is public; which systems it points
    # at is not, so host and user come from sops like Fleet's URL. Rendered
    # owned by max, since harlequin and hsql read it as that user;
    # home/max/harlequin.nix links it into ~/.config. Passwords never go here:
    # a profile that needs one names an environment variable
    # (password = "${TRINO_PASSWORD}"), filled by `op run` at launch.
    #
    # port is explicit because the adapter always passes one (8080 by
    # default), and an explicit port beats the 443 the https:// in the host
    # would otherwise imply.
    sops.templates."harlequin.toml" = lib.mkIf harlequin.enable {
      owner = "max";
      content = ''
        [profiles.trino]
        adapter = "trino"
        host = "${config.sops.placeholder.trino-host}"
        port = "443"
        user = "${config.sops.placeholder.trino-user}"
      '';
    };
  };
}
