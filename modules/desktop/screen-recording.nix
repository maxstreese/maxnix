# gpu-screen-recorder, the preferred recording backend of DMS's Quick Capture
# plugin (see home/max/dms.nix). Hardware encoding through NVENC or VA-API, and
# the only backend there that records audio and can pause.
#
# A NixOS module rather than a user package, for the same reason as Steam:
# capturing a KMS framebuffer without a portal prompt each time needs
# gsr-kms-server with cap_sys_admin, and only the system can hand out that
# wrapper. pkgs.gpu-screen-recorder in home.packages would install a recorder
# that has to ask every time.
#
# ── Metal only ───────────────────────────────────────────────────────────
#
# mkDefault, because ../vm/qemu-guest.nix turns it off for every VM — the
# build-vm guest and every test node alike — since a virtio GPU has no encoder
# to drive. So the bare machine (`checks.metal`, the install) has it and
# nothing virtual does. wf-recorder in home/max/dms.nix covers the VM.
{ lib, ... }:
{
  programs.gpu-screen-recorder.enable = lib.mkDefault true;
}
