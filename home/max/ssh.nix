# SSH and `op`, both answered by the 1Password app.
#
# ── SSH agent ─────────────────────────────────────────────────────────────
#
# The desktop app can act as an SSH agent: keys live in the vault, the agent
# serves them, and every use is an unlock or a confirmation in the app. No
# key file ever lands on this disk. The app exposes the agent as a Unix
# socket at ~/.1password/agent.sock once "Use the SSH agent" is switched on
# in Settings → Developer — a one-time click, not something Nix can do.
#
# IdentityAgent in ssh_config rather than SSH_AUTH_SOCK in the environment:
# ssh honours it regardless of how the shell or the compositor session was
# started, and it does not fight gnome-keyring, whose own agent socket may
# or may not end up in SSH_AUTH_SOCK depending on the session. Git goes
# through ssh, so it inherits this for free.
#
# ── op, the CLI ───────────────────────────────────────────────────────────
#
# Installed system-wide by modules/desktop/onepassword.nix. With "Integrate
# with 1Password CLI" switched on in the same Developer settings, `op` unlocks
# through the app instead of prompting for the account password, and
#   op read "op://Vault/Item/field"
#   op run --env-file=.env -- some-command
# become the way to hand a secret to anything CLI-shaped without writing it
# down. Shell completion is the only declarative part.
#
# Commit signing uses the same agent and is configured in ./git.nix.
#
# ── Which keys the agent offers ──────────────────────────────────────────
#
# agent.toml selects them. Without it the agent offers every key in every
# vault of every signed-in account, and servers cap authentication attempts,
# so that stops scaling once the vault fills up. Entries are offered in the
# order written, so the auth key comes first.
#
# `account` matters here and is easy to miss: a business account gives each
# member a Private vault too, so a bare `vault = "Private"` is ambiguous
# across two signed-in accounts. Naming the sign-in address settles it, and
# a work key later is a third entry pointing at the other account.
#
# What agent.toml cannot do is choose a key per host — every listed key is
# offered to every server. If that ever matters, ssh_config does it, with an
# IdentityFile naming the public key plus IdentitiesOnly. Not done here: with
# two keys there is nothing to gain, and a wrong guess breaks authentication.
{ ... }:
{
  programs.ssh = {
    enable = true;
    # Home Manager's legacy defaults would otherwise be written out and warn
    # about their own deprecation. We want a minimal config: this one line.
    enableDefaultConfig = false;
    settings."*".IdentityAgent = "~/.1password/agent.sock";
  };

  # The auth key, for reference; the agent serves it and nothing here needs
  # to name it:
  #   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINwdtUM7OJgowEZ1bP8EDspvnvKJucZhmqkibDZ1srpz
  xdg.configFile."1Password/ssh/agent.toml".text = ''
    [[ssh-keys]]
    item = "GitHub SSH Auth (maxstreese)"
    vault = "Private"
    account = "my.1password.com"

    [[ssh-keys]]
    item = "Git Signing (max@streese.com)"
    vault = "Private"
    account = "my.1password.com"
  '';

  programs.bash = {
    enable = true;
    initExtra = ''
      command -v op >/dev/null && source <(op completion bash)
    '';
  };
}
