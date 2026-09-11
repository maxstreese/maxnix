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
        "--asterisks"
        "--greeting maxnix"

        # The greeter always showed "F12 Power" but nothing happened, because
        # tuigreet has no shutdown/reboot commands unless you give it some.
        #
        # Absolute paths to the binaries rather than "systemctl poweroff":
        # greetd takes `command` as one string and splits it, so an argument
        # containing a space is a quoting problem waiting to happen.
        "--power-shutdown ${pkgs.systemd}/bin/poweroff"
        "--power-reboot ${pkgs.systemd}/bin/reboot"

        "--sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions"
      ];
      user = "greeter";
    };
  };

  # Terminals and launchers used to live here, installed machine-wide purely so
  # the compositors' *default* keybinds would not dead-end. Both compositors
  # are now configured in home/max, so those are user packages and moved there
  # — which also let kitty and wofi go entirely.
  #
  # What stays is diagnostics: tools you want available before or without a
  # user session.
  environment.systemPackages = with pkgs; [
    wayland-utils # wayland-info: what the compositor actually advertises
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
