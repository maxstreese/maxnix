# DankMaterialShell — a Quickshell-based desktop shell.
#
# This fills the gap both compositors leave: niri and Hyprland draw windows and
# nothing else, so out of the box there is no bar, no launcher, no notification
# centre and no power menu. DMS provides all of it, built on Quickshell — which
# means running it is also a way to evaluate Quickshell as a platform before
# writing any QML ourselves.
#
# ── Why NOT inputs.dms.homeModules.niri ──────────────────────────────────────
#
# DMS ships a niri integration module and we deliberately do not use it, for
# two independent reasons:
#
#   1. It writes to `programs.niri.settings` and uses `config.lib.niri.actions`
#      — that is *niri-flake's* API. We use Home Manager's
#      wayland.windowManager.niri instead. Its own `includes.enable` option is
#      documented as "includes for niri-flake".
#   2. Two of its binds collide with ours: Mod+Comma with consume-or-expel
#      and Mod+V with toggle-window-floating.
#
# Nothing in it is hard to reproduce: every binding is `dms ipc <thing>
# <action>`. So the binds live in ./niri.nix and ./hyprland.nix, which also
# gets them into Hyprland — something the DMS module cannot do, since it only
# supports niri.
#
# The main module below is compositor-agnostic: it mentions neither compositor.
{ inputs, ... }:
{
  imports = [ inputs.dms.homeModules.dank-material-shell ];

  programs.dank-material-shell = {
    enable = true;

    # Start DMS from the session target rather than a spawn-at-startup line in
    # each compositor's config. Upstream warns not to enable both systemd
    # startup and niri.enableSpawn — you get two shells. We use neither spawn
    # mechanism, so there is nothing to collide.
    systemd.enable = true;

    # Material You palette generation from the wallpaper. This is DMS's
    # signature feature and the main reason to look at it at all; it pulls in
    # matugen.
    enableDynamicTheming = true;

    # The CPU/memory/network widgets in the bar.
    enableSystemMonitoring = true;

    # Off for now — each pulls a package for something the VM cannot
    # exercise. All three become relevant on metal (ROAD TO METAL):
    #   enableVPN             glib + networkmanager, no VPN here
    #   enableAudioWavelength cava, and guest audio is not wired up
    #   enableCalendarEvents  khal, no calendar
  };
}
