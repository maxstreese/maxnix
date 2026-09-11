# The user layer.
#
# Home Manager runs the same module system as the rest of this repo, scoped to
# one user instead of the machine. It builds dotfiles into /nix/store and
# symlinks them into $HOME, so ~/.config files stop being things you edit and
# become build artifacts — the same trade NixOS makes for /etc.
#
# The split with the system layer: NixOS *enables* a thing (installs it,
# registers its session, wires portals); this layer *configures* it. Note that
# programs.niri exists in both namespaces and they are not the same option —
# see ./niri.nix.
{ lib, pkgs, ... }:
{
  imports = [
    ./dms.nix
    ./niri.nix
    ./hyprland.nix
  ];

  home.username = "max";
  home.homeDirectory = "/home/max";

  # Same rule as system.stateVersion, and a separate value: it pins the
  # defaults this config was written against. Set once, then leave alone.
  home.stateVersion = "26.11";

  # The terminal and launcher both compositor configs spawn.
  #
  # These were in environment.systemPackages until now — installed machine-wide
  # purely so the compositors' default keybinds would not dead-end. They are
  # user preferences, so this is where they belong.
  #
  # kitty and wofi are gone: they existed only because Hyprland's *default*
  # config named them. Now that both compositors are configured here, one
  # terminal and one launcher serve both, which is also one less thing to
  # keep consistent between them.
  home.packages = with pkgs; [
    alacritty
    fuzzel
    wl-clipboard

    # wev prints every Wayland key event its window receives, with the keysym.
    #
    # This is the debugger for a whole class of problem this setup keeps
    # producing, where nothing errors and a key simply does nothing:
    #
    #   - is the host compositor swallowing this key before the guest sees it?
    #     (GNOME claims Alt+Space, bare Super, Ctrl+Alt+Up/Down; and its
    #     workspace bindings are inert on a horizontal layout, so "nothing
    #     visibly happened" proves nothing without this)
    #   - what keysym does this physical key actually produce on the current
    #     layout? (bracketleft is AltGr+8 on de, slash is Shift+7 — binding the
    #     US names produced three dead binds)
    #
    # niri's own documentation points at wev for the second question. Run it,
    # focus its window, press the key, read the sym: field in the terminal.
    wev
  ];


  # Enabling both compositors' Home Manager modules collides here: niri's sets
  # xdg.portal.enable = true and Hyprland's sets it false, and the module
  # system has no way to pick.
  #
  # Neither is needed. Portals are already configured at the system level by
  # the NixOS modules (programs.niri wires xdg-desktop-portal-gnome,
  # programs.hyprland wires xdg-desktop-portal-hyprland), and that is the layer
  # that should own them — a portal backend is machine-wide infrastructure, not
  # a user preference. So this turns the user-level duplicate off outright.
  xdg.portal.enable = lib.mkForce false;

  programs.home-manager.enable = true;
}
