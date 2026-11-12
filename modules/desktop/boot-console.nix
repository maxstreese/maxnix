# The boot console: bootvine's live tree of systemd's pending units in place
# of the scrolling kernel and systemd lines, from the initrd through to the
# greeter, and again at shutdown. On metal it also draws the prompt for the
# LUKS passphrase, the one screen every power-on stops at.
#
# The module comes with the desktop role (../../flake.nix, where the input is
# pinned and why), not base: WSL has no boot console to draw on.
#
# Not Plymouth: that hides the boot behind a splash, and this repo would
# rather see what the machine is doing. If bootvine misbehaves, an older
# generation boots without it.
{ ... }:
{
  services.bootvine.enable = true;
}
