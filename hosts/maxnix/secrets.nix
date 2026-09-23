# Secrets, as encrypted files in this repository.
#
# The sops-nix module is imported here and declares nothing. That is not an
# oversight: `sops.secrets` defaults to {} and the module gates all of its
# work behind `lib.mkIf (cfg.secrets != { })`, so an import with no secrets
# is genuinely inert — verified, not assumed, by building the metal system
# with it in place.
#
# What it buys today is small and worth being honest about: the input is
# pinned and Renovate now tracks it, and the first real secret is an edit to
# this file rather than a research task. What it does not buy is any working
# secret, because none can exist yet.
#
# ── How it works, when it does ───────────────────────────────────────────
#
# Values live encrypted in a YAML file committed here. At activation the host
# decrypts them into /run/secrets, a tmpfs, with the owner and mode declared
# per secret. Configuration then references the *path*, never the value:
#
#   maxnix.backup.passwordFile = config.sops.secrets.restic-password.path;
#
# which is the whole point — a value written into a Nix option would be
# copied into the world-readable store.
#
# ── The two customers, both certain, neither obtainable yet ──────────────
#
#   restic-password   encrypts the backup repository. It must not live only
#                     on /persist: one disk failure would take the data and
#                     the only key to its backups together.
#   rclone.conf       the Google Drive OAuth refresh token. Blocked on an
#                     OAuth client ID, which a managed Workspace account may
#                     refuse outright — see ./backup.nix.
#
# ── What it is waiting on ────────────────────────────────────────────────
#
# A decryption key, and this is the one secret sops cannot manage for itself.
#
# The convention is to decrypt with the host's SSH key, which does not exist
# here: services.openssh.enable is false on metal, only the VM runs sshd. So
# this machine needs a dedicated age key, generated once and never committed:
#
#   mkdir -p /persist/sops && age-keygen -o /persist/sops/age.key
#   age-keygen -y /persist/sops/age.key        # the public half, for .sops.yaml
#
# /persist because it must survive the root wipe, and because it has to exist
# before the secrets it decrypts are needed.
#
# Then, in this file:
#
#   sops.age.keyFile = "/persist/sops/age.key";
#   sops.defaultSopsFile = ./secrets.yaml;
#   sops.secrets.restic-password = { };
#
# plus a .sops.yaml at the repo root naming the public half as a recipient,
# and `sops secrets.yaml` to write the value.
#
# ── What can never live here ─────────────────────────────────────────────
#
# The LUKS passphrase. The age key would sit on the disk that passphrase
# unlocks, so the secret would be needed before the thing holding it exists.
# That is why ./disk.nix takes a typed passphrase and item 13 layers TPM
# unlock on top rather than a keyfile.
{ ... }:
{
  # Deliberately empty. See above.
}
