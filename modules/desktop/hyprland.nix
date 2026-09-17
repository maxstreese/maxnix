# Hyprland — dynamic-tiling Wayland compositor, run under UWSM.
#
# UWSM (Universal Wayland Session Manager) wraps the compositor in systemd
# user units, so graphical-session.target, xdg-desktop-autostart.target and
# friends are managed properly. Lock, suspend, portals and DankMaterialShell
# all lean on that, and niri already provides it through its own module; this
# gives Hyprland the same footing. Upstream recommends it.
#
# The nixpkgs package ships two login sessions and the greeter offers both:
#
#   Hyprland                  start-hyprland directly, no session manager
#   Hyprland (uwsm-managed)   uwsm start … hyprland.desktop
#
# Pick the second. Trimming the list to one entry is possible but costs a
# wrapper around the package; two entries were judged the cheaper price.
#
# The Home Manager side has to know about this: its module injects exec-once
# lines that start its own hyprland-session.target, which would fight UWSM
# over graphical-session.target. See home/max/hyprland.nix.
{ ... }:
{
  programs.hyprland = {
    enable = true;
    withUWSM = true;

    # Hyprland's own portal (xdg-desktop-portal-hyprland) is wired up by the
    # module. XWayland is on by default and worth keeping: it is the difference
    # between "X11 apps work" and a confusing class of missing windows.
    xwayland.enable = true;
  };
}
