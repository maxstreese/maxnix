# Hyprland — dynamic-tiling Wayland compositor.
{ ... }:
{
  programs.hyprland = {
    enable = true;

    # Hyprland's own portal (xdg-desktop-portal-hyprland) is wired up by the
    # module. XWayland is on by default and worth keeping: it is the difference
    # between "X11 apps work" and a confusing class of missing windows.
    xwayland.enable = true;

    # withUWSM launches Hyprland under the Universal Wayland Session Manager,
    # which upstream recommends. Left off for now: it changes how the session
    # and its systemd targets start, and step 3 is about getting a compositor
    # on screen with as few moving parts as possible. Worth revisiting once
    # Quickshell needs graphical-session.target to behave.
    withUWSM = false;
  };
}
