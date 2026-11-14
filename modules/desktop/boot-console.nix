# The boot console: bootvine's live tree of systemd's pending units in place
# of the scrolling kernel and systemd lines, from the initrd through to the
# greeter, and again at shutdown. On metal it also draws the prompt for the
# LUKS passphrase, the one screen every power-on stops at.
#
# In the desktop role, not base: WSL has no boot console to draw on.
#
# Package and module are nixpkgs' own. Until 2026-11-14 both came from
# bootvine's flake, pinned to its v0.1.3 tag, because nixpkgs had neither;
# then nixpkgs gained them and the two modules declared the same option, which
# stopped the lock refresh. So its version now moves with nixpkgs like every
# other program that runs as root here, and a bump shows in the closure diff
# on the lock PR.
#
# Not Plymouth: that hides the boot behind a splash, and this repo would
# rather see what the machine is doing. If bootvine misbehaves, an older
# generation boots without it.
{ ... }:
{
  services.bootvine.enable = true;
}
