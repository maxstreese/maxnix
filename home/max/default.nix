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
