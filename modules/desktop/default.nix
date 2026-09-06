# The shared desktop layer: a greeter, and the bits both compositors expect to
# find. The compositors themselves are one file each, so either can be dropped
# from ./: nothing here depends on which of them is installed.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./niri.nix
    ./hyprland.nix
  ];

  # greetd + tuigreet — a *terminal* greeter on tty1.
  #
  # Chosen over a graphical greeter on purpose: tuigreet needs no GL of its
  # own, so when a compositor fails to start you fall back to a working greeter
  # that can tell you so, rather than a black screen. Both compositors register
  # themselves via services.displayManager.sessionPackages; sessionData.desktops
  # is the directory those .desktop files are collected into, and pointing
  # tuigreet at it is what turns "two installed compositors" into "a session
  # picker at login".
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = lib.concatStringsSep " " [
        "${pkgs.tuigreet}/bin/tuigreet"
        "--time"
        "--remember" # last user
        "--remember-session" # and their last session
        "--sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions"
      ];
      user = "greeter";
    };
  };

  # Neither compositor ships a terminal, and both have default keybinds that
  # name a specific one. Installing both pairs means neither is dead on arrival
  # before we write any config of our own:
  #
  #   niri      Mod+T -> alacritty    Mod+D -> fuzzel
  #   Hyprland  Mod+Q -> kitty        Mod+R -> wofi
  environment.systemPackages = with pkgs; [
    alacritty
    fuzzel
    kitty
    wofi

    wayland-utils # wayland-info: what the compositor actually advertises
    wl-clipboard
  ];

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      dejavu_fonts
    ];
  };

  # Compositors need polkit for anything privileged (mounting, suspend).
  security.polkit.enable = true;
}
