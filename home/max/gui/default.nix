# The user layer's GUI half: what graphical apps need from the user's side,
# with no assumption about the compositor. Imported by the GUI layer
# (../../../modules/gui/default.nix), which both the desktop role and
# z690-wsl bring in, on top of ../core.
{ ... }:
{
  imports = [
    ./onepassword.nix
    ./herdr.nix
  ];
}
