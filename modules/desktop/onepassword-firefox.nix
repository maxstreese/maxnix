# 1Password's browser half: letting Firefox's extension reach the app.
#
# The app itself is in ../gui/onepassword.nix, which every host with a GUI
# imports. This part stays with the desktop role because Firefox does
# (../../home/max/desktop/firefox.nix); on a host without Firefox there is no
# browser to allow.
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
{ ... }:
{
  environment.etc."1password/custom_allowed_browsers" = {
    text = ''
      .firefox-wrapped
    '';
    mode = "0755";
  };
}
