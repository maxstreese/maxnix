# herdr's desktop app: persistent terminals and coding agents in a window.
# The CLI is in ../core/dev.nix, everywhere; this half needs a display, so it
# lives in the GUI layer, which the ThinkPad's desktop and the WSL host both
# import. Free, so no allow-list entry.
#
# Under WSLg (2026-11-07, docs/desktop-pc.md section 3) it draws on the GPU
# once the Windows driver is on the library path (../../../hosts/z690-wsl/windows.nix),
# clipboard works both ways with Windows apps, scaling is sharp, and links
# open in the Windows browser. On first start it turns on linger for max and
# runs herdr-core as transient `hc-serve-*` user units that outlive the
# window.
{ pkgs, ... }:
{
  home.packages = [ pkgs.herdr-desktop ];
}
