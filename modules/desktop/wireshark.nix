# Wireshark, with packet capture as a normal user.
#
# A NixOS module rather than a user package, for the same reason as Steam and
# the screen recorder: capturing needs raw access to a network interface,
# and only the system can hand that out. The module installs dumpcap, the
# small program that does the capturing, as a wrapper with cap_net_raw and
# cap_net_admin that only the `wireshark` group may run. The window itself
# then runs unprivileged, which is how upstream wants it: its dissectors
# parse whatever is on the wire and are no place for root.
# pkgs.wireshark in home.packages would install a Wireshark that opens
# saved captures and can record nothing.
#
# In the desktop role and not ../gui: what is worth capturing is the
# ThinkPad's own Wi-Fi and VPN traffic. Under WSL the network is Windows'
# to capture.
{ pkgs, ... }:
{
  programs.wireshark = {
    enable = true;
    # The module's default is wireshark-cli: tshark, and no window.
    package = pkgs.wireshark;
  };

  users.users.max.extraGroups = [ "wireshark" ];
}
