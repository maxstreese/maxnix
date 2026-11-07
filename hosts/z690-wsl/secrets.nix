# Secrets for the WSL host, the same way as the ThinkPad's
# (../t14s/secrets.nix has the full account: files, keys, adding a secret).
#
# One file, ./secrets.yaml, encrypted to admin and this host's own key
# (../../.sops.yaml), and to nothing of the ThinkPad's: this guest is the
# weaker place, reachable as root from Windows (`wsl -u root`), so its key
# opens nothing else and its login password is not metal's (decided
# 2026-11-07, README "Decisions, and why").
#
# The key follows the ThinkPad's rule: generated once, kept in 1Password,
# restored onto the guest, never generated here:
#
#   nix run .#z690-wsl-restore-key
#
# which also checks that what landed is the z690-wsl key in .sops.yaml.
# Unlike metal's, its place is on the plain root: WSL keeps the root, and
# the whole distribution is one VHDX file on Windows' disk.
#
# ── The login password ──────────────────────────────────────────────────
#
# What 1Password's "unlock with system authentication" asks for, through
# polkit and the agent in ./default.nix. Stored as a yescrypt hash, set with
#
#   nix run .#secret-set -- --host z690-wsl login-password \
#     op://uxobupcysqhat566ymgikx46fm/2eyd5at2rb5lhnmg535epqjxzq/password
#
# Behind a switch (maxnix.loginPassword.fromSops, in ./default.nix), on only
# once the key is on the guest and the hash is in the file: declared earlier,
# sops-nix fails to decrypt at activation and max's password would be
# locked. With it, users are immutable, as on metal, so the declared hash
# wins at every activation and `passwd` does not last. sudo still asks for
# nothing (NixOS-WSL's default), and root gets no password: `wsl -u root`
# from Windows needs none, so one would guard nothing.
{ config, lib, ... }:
{
  options.maxnix.loginPassword.fromSops = lib.mkEnableOption ''
    max's password from the `login-password` hash in ./secrets.yaml. Off
    until the host's key is restored and the hash is set
  '';

  config = lib.mkMerge [
    {
      sops = {
        defaultSopsFile = ./secrets.yaml;
        age.keyFile = "/var/lib/sops-nix/age.key";

        # Only the key above, not sshd's host keys, as on the ThinkPad.
        age.sshKeyPaths = [ ];
        gnupg.sshKeyPaths = [ ];
      };
    }

    (lib.mkIf config.maxnix.loginPassword.fromSops {
      # Before the users are set up, into /run/secrets-for-users.
      sops.secrets.login-password.neededForUsers = true;

      users.mutableUsers = false;
      users.users.max.hashedPasswordFile = config.sops.secrets.login-password.path;
    })
  ];
}
