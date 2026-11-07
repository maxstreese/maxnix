# Desktop applications, most of which need an account.
#
# Nothing here carries a credential. Each signs in once through Firefox with
# the 1Password extension (see ./firefox.nix and
# ../../../modules/desktop/onepassword.nix) and keeps its own session state on
# the guest disk from then on.
#
# Spotify, Slack and Discord are unfree. Home Manager cannot declare that
# itself here — with useGlobalPkgs it borrows the system's nixpkgs config — so
# the allow-list entries live in ../../../modules/desktop/default.nix, next to
# where this layer is imported. Claude Code moved to ../core/claude.nix.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # Spotify's Linux client is Chromium-based. It runs natively on Wayland
    # when NIXOS_OZONE_WL=1 is in the environment, which the desktop layer
    # sets; without it, it falls back to XWayland. First start: "Log in with
    # browser" hands the login to Firefox. State lands in ~/.config/spotify.
    spotify

    # Slack. Electron, so it follows NIXOS_OZONE_WL onto Wayland like the
    # others. Sign-in is the usual workspace URL and email link, handled in
    # Firefox; the session then lives in ~/.config/Slack.
    slack

    # Discord, also Electron. Home Manager has a programs.discord module,
    # unused on purpose: all it adds is writing settings.json, and Discord
    # rewrites that file itself — the same fight the greeter's colour file
    # lost. The package alone is what is wanted.
    discord

    # No account needed for these two; they sit here as the other desktop
    # applications.
    obs-studio
    gimp
  ];
}
