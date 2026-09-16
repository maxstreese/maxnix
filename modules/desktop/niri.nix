# niri — scrollable-tiling Wayland compositor.
#
# The nixpkgs module handles the whole supporting cast: the session .desktop
# entry, the systemd user service, xdg-desktop-portal-gnome, gnome-keyring.
{ ... }:
{
  programs.niri = {
    enable = true;

    # Upstream pulls in Nautilus purely to back the portal's file chooser.
    # That is a lot of GNOME for one dialog; the GTK file chooser serves. Flip
    # to true if a file picker misbehaves.
    useNautilus = false;
  };
}
