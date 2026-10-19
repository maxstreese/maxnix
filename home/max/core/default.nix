# The user layer, the part every machine gets: shell, git, the dev
# tools, Harlequin and Claude Code. Imported by the base role
# (../../../modules/base/default.nix); the desktop half is ../desktop.
#
# Home Manager runs the same module system as the rest of this repo, scoped to
# one user instead of the machine. It builds dotfiles into /nix/store and
# symlinks them into $HOME, so ~/.config files stop being things you edit and
# become build artifacts — the same trade NixOS makes for /etc.
#
# The split with the system layer: NixOS *enables* a thing (installs it,
# registers its session, wires portals); this layer *configures* it. Note that
# programs.niri exists in both namespaces and they are not the same option —
# see ../desktop/niri.nix.
{ ... }:
{
  imports = [
    ./shell.nix
    ./git.nix
    ./dev.nix
    ./harlequin.nix
    ./claude.nix
  ];

  home.username = "max";
  home.homeDirectory = "/home/max";

  # Same rule as system.stateVersion, and a separate value: it pins the
  # defaults this config was written against. Set once, then leave alone.
  home.stateVersion = "26.11";

  programs.home-manager.enable = true;
}
