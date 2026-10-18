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
    ./quickshell.nix
    ./niri.nix
    ./firefox.nix
    ./ghostty.nix
    ./apps.nix
    ./dev.nix
    ./git.nix
    ./ssh.nix
    ./shell.nix
    ./harlequin.nix
  ];

  home.username = "max";
  home.homeDirectory = "/home/max";

  # Same rule as system.stateVersion, and a separate value: it pins the
  # defaults this config was written against. Set once, then leave alone.
  home.stateVersion = "26.11";

  # The launcher the niri config spawns, and the clipboard tools. The
  # terminal it spawns is in ./ghostty.nix; everything else installed for this
  # user is in ./dev.nix, ./apps.nix or ./git.nix.
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

  programs.home-manager.enable = true;
}
