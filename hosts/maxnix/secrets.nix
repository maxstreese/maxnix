# Secrets, as encrypted files in this repository.
#
# Values live encrypted in ./secrets.yaml. At activation the machine decrypts
# them into /run/secrets, a tmpfs, with the owner and mode declared per
# secret. Configuration then references the *path*, never the value — a
# value written into a Nix option would be copied into the world-readable
# store:
#
#   maxnix.backup.passwordFile = config.sops.secrets.restic-password.path;
#
# The file is public along with the rest of the repo. That is sound only
# because it is encrypted, and why the keys below are post-quantum.
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
# Keep the value in 1Password too, then pipe it in so it never reaches an
# argument list, an editor's swap file or the screen. Inside `nix develop`,
# which provides sops, jq and the admin key:
#
#   op read "op://<vault>/<item>/<field>" | jq -R . \
#     | sops set --value-stdin hosts/maxnix/secrets.yaml '["<name>"]'
#
# `jq -R .` because --value-stdin wants JSON, not the raw value ("Value for
# --set is not valid JSON"): it turns the line into a JSON string, and drops
# the newline `op read` ends with, which would otherwise end up in the
# secret. For a multi-line value, `jq -Rs .` instead — that one keeps it.
#
# Fleet's two are `fleet-url` and `fleet-enroll-secret`.
#
# and declare it below, next to whatever consumes it.
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
in
{
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
