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
# Commit signing with an SSH key from the vault is one step further
# (gpg.format = ssh, gpg.ssh.program = op-ssh-sign, which the app package
# ships). Not wired: it needs the public key of a specific vault item.
{ ... }:
{
  programs.ssh = {
    enable = true;
    # Home Manager's legacy defaults would otherwise be written out and warn
    # about their own deprecation. We want a minimal config: this one line.
    enableDefaultConfig = false;
    settings."*".IdentityAgent = "~/.1password/agent.sock";
  };

  programs.bash = {
    enable = true;
    initExtra = ''
      command -v op >/dev/null && source <(op completion bash)
    '';
  };
}
