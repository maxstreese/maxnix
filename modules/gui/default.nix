# The GUI layer: graphical apps that need a display but not niri. Imported by
# the desktop role (../desktop/default.nix) and by hosts whose display comes
# from elsewhere, today z690-wsl, where WSLg draws Linux windows into
# Windows' own (docs/desktop-pc.md, section 3).
#
# Split out of the desktop role 2026-11-06 so the WSL host can have
# 1Password, its SSH agent and commit signing from the same modules as the
# ThinkPad, rather than a bridge to the Windows app that would rest on
# software installed by hand outside the repo. What lives here must not
# assume niri, DMS or a greeter; anything that does belongs in ../desktop.
{ ... }:
{
  imports = [
    ./onepassword.nix
  ];

  # The user layer's GUI half, alongside ../../home/max/core from base.
  home-manager.users.max.imports = [ ../../home/max/gui ];
}
