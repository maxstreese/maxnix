# 1Password — the credential bridge for this machine.
#
# ── Why it is here at all ─────────────────────────────────────────────────
#
# This machine is meant to become the daily driver, and a daily driver has to
# log in to things: Google, Claude, Spotify, GitHub. The rule for this repo is that no
# credential ever appears in it — not in Nix, not in git, not in the store.
# 1Password is how the two are reconciled: the repo installs and enables it,
# you sign in once inside the guest, and from then on the browser extension,
# the SSH agent and the `op` CLI hand credentials to whatever asks. The vault
# is the source of truth; the guest's disk holds only the app's local state.
#
# Nothing below knows an account, a secret key or a password.
#
# ── What the pieces are ───────────────────────────────────────────────────
#
#   programs._1password-gui   the desktop app. Also the thing the browser
#                             extension talks to, via 1Password-BrowserSupport,
#                             which the module installs as a setgid wrapper.
#   programs._1password       the `op` CLI. With "Integrate with 1Password CLI"
#                             turned on in the app, `op read op://…` unlocks
#                             through the app instead of asking for a password.
#   polkitPolicyOwners        who may use "unlock with system authentication".
#                             The package bakes a polkit policy for exactly
#                             these users; without it the app can only unlock
#                             with the account password.
#
# ── The NixOS wrinkle: allowed browsers ──────────────────────────────────
#
# BrowserSupport only answers browsers whose *executable name* it recognises.
# nixpkgs' Firefox is a shell wrapper that execs `.firefox-wrapped` (a symlink
# to lib/firefox/firefox), and 1Password sees that name, not "firefox". The
# escape hatch 1Password provides is /etc/1password/custom_allowed_browsers,
# one name per line; it insists the file be root-owned and not writable by
# others, hence the explicit mode. Forget this and the extension silently
# never connects to the app.
#
# ── Unfree ────────────────────────────────────────────────────────────────
#
# Both packages carry a proprietary licence and nixpkgs refuses them unless
# told otherwise. `allowUnfreePackages` is a list matched against pname, and
# the NixOS module system concatenates it across modules — so each module
# that needs an unfree package names it here, next to the reason, rather
# than one central blanket `allowUnfree = true`. A new unfree dependency
# sneaking in still fails evaluation, loudly.
{ config, ... }:
{
  nixpkgs.config.allowUnfreePackages = [
    "1password"
    "1password-cli"
  ];

  programs._1password.enable = true;

  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ config.users.users.max.name ];
  };

  environment.etc."1password/custom_allowed_browsers" = {
    text = ''
      .firefox-wrapped
    '';
    mode = "0755";
  };
}
