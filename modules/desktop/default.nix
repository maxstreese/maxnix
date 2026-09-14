# The shared desktop layer: a greeter, and the bits both compositors expect to
# find. The compositors themselves are one file each and nothing here depends
# on which of them is installed. Both are meant to stay — the split is so each
# one's enablement is self-contained, not so one can be dropped later.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./greeter.nix
    ./niri.nix
    ./hyprland.nix
  ];

  # The login screen lives in ./greeter.nix. It used to be configured here as
  # tuigreet; see that file for what changed and how to go back.

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

      # For DankMaterialShell. Its Nix modules handle no fonts at all —
      # checked, there is not a single font reference in them — and a Material
      # shell without Material Symbols draws every icon as an empty box. Inter
      # is the typeface the design language assumes.
      material-symbols
      inter
    ];
  };

  # Compositors need polkit for anything privileged (mounting, suspend).
  security.polkit.enable = true;
}
