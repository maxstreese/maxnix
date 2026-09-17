# Daily-driver applications that need an account.
#
# Nothing here carries a credential. Each signs in once through Firefox with
# the 1Password extension (see ./firefox.nix and
# ../../modules/desktop/onepassword.nix) and keeps its own session state on
# the guest disk from then on.
#
# Both packages are unfree. Home Manager cannot declare that itself here —
# with useGlobalPkgs it borrows the system's nixpkgs config — so the
# allow-list entries live next to the home-manager block in
# hosts/maxnix/configuration.nix.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # Spotify's Linux client is Chromium-based. It runs natively on Wayland
    # when NIXOS_OZONE_WL=1 is in the environment, which the desktop layer
    # sets; without it, it falls back to XWayland. First start: "Log in with
    # browser" hands the login to Firefox. State lands in ~/.config/spotify.
    spotify

    # Claude Code, the `claude` CLI. First run: `claude` opens the browser
    # for OAuth against the same Claude account as the web app. The resulting
    # token is kept in ~/.claude, since Linux gets no keychain integration.
    # An API key via `op read` works too, if that is ever preferred.
    claude-code
  ];
}
