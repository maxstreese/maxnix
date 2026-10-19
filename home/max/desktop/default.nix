# The user layer's desktop half: niri's config, DankMaterialShell and
# Quickshell, the terminal, Firefox and the desktop applications. Imported by
# the desktop role (../../../modules/desktop/default.nix), on top of ../core.
{ lib, pkgs, ... }:
{
  imports = [
    ./dms.nix
    ./quickshell.nix
    ./niri.nix
    ./firefox.nix
    ./ghostty.nix
    ./apps.nix
    ./onepassword.nix
  ];

  # The launcher the niri config spawns, and the clipboard tools. The
  # terminal it spawns is in ./ghostty.nix; everything else installed for this
  # user is in ./apps.nix or ../core.
  #
  # These were in environment.systemPackages until now — installed machine-wide
  # purely so the compositors' default keybinds would not dead-end. They are
  # user preferences, so this is where they belong.
  #
  # kitty and wofi are gone: they existed only because Hyprland's *default*
  # config named them, back when Hyprland ran next to niri.
  home.packages = with pkgs; [
    fuzzel
    wl-clipboard

    # wev prints every Wayland key event its window receives, with the keysym.
    #
    # This is the debugger for a whole class of problem this setup keeps
    # producing, where nothing errors and a key simply does nothing:
    #
    #   - is the host compositor swallowing this key before the guest sees it?
    #     (bare Super never arrives unless scripts/vm-keys has released it,
    #     and "nothing visibly happened" proves nothing without this)
    #   - what keysym does this physical key actually produce on the current
    #     layout? (bracketleft is AltGr+8 on de, slash is Shift+7 — binding the
    #     US names produced three dead binds)
    #
    # niri's own documentation points at wev for the second question. Run it,
    # focus its window, press the key, read the sym: field in the terminal.
    wev
  ];

  # niri's Home Manager module sets xdg.portal.enable = true, a user-level
  # copy of what is already configured at the system level: programs.niri
  # wires xdg-desktop-portal-gnome there, and that is the layer that should
  # own it — a portal backend is machine-wide infrastructure, not a user
  # preference. So this turns the user-level duplicate off outright. Forced
  # since the days Hyprland's module set the same option to false and the
  # module system could not pick; kept forced so the system layer stays the
  # only owner whatever a module defaults to.
  xdg.portal.enable = lib.mkForce false;
}
