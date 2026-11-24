# What Claude Desktop's Cowork needs from the machine to run commands
# locally: QEMU, UEFI firmware and virtiofsd, at the paths the app looks for
# them.
#
# Cowork itself runs in Anthropic's cloud and reaches this machine through
# the app (../../home/max/desktop/claude-desktop.nix); that part needs
# nothing. What it does on the machine, it does in a small virtual machine
# the app starts, with only the folders handed to it. Without that VM a
# session has no shell here: it can read and write files in a connected
# folder and cannot move, delete or run anything (first session,
# 2026-11-24). The app's log gave the reason, in
# ~/.config/Claude/logs/cowork_vm_node.log:
#
#   [startVM] VM not supported (linux/x64, virtualization_tools_missing)
#
# The app decides that from three fixed paths, read out of its code
# (6.28899.6), and nothing else: not PATH, no setting, no variable.
#
#   /usr/bin/qemu-system-x86_64
#   /usr/share/OVMF/OVMF_CODE_4M.fd or OVMF_CODE.fd, and beside it the same
#     name with VARS for CODE
#   /usr/libexec/virtiofsd or /usr/bin/virtiofsd (the one it ships in its
#     resources is used on Ubuntu 22 only)
#
# Those are Debian's, the one layout Anthropic supports, so they are what
# this provides: symlinks into the store, made by systemd-tmpfiles at boot
# and at every switch. Files under /usr on a NixOS machine are not how
# things are done here. The alternative is rewriting the paths inside the
# app's minified JavaScript and repacking its archive, which the first
# community flake for this app did, with regular expressions over code that
# changes every two days; its builds have failed since August. A release
# cannot move Debian's paths without breaking Anthropic's own users.
#
# Nothing else is needed. The app also wants /dev/kvm and /dev/vhost-vsock
# readable and writable; both are 0666 here as NixOS comes (looked at in the
# guest), so max is in no extra group. The helper that starts QEMU and the
# image it boots first are in the package. With the links in place a session
# in the dev VM got its shell (2026-11-24), the app's VM nested in ours.
#
# A NixOS module and not part of the package: /usr belongs to the system.
# Desktop role, as the app is.
{ pkgs, ... }:
{
  systemd.tmpfiles.rules = [
    "L+ /usr/bin/qemu-system-x86_64 - - - - ${pkgs.qemu_kvm}/bin/qemu-system-x86_64"
    "L+ /usr/share/OVMF/OVMF_CODE.fd - - - - ${pkgs.OVMF.fd}/FV/OVMF_CODE.fd"
    "L+ /usr/share/OVMF/OVMF_VARS.fd - - - - ${pkgs.OVMF.fd}/FV/OVMF_VARS.fd"
    "L+ /usr/libexec/virtiofsd - - - - ${pkgs.virtiofsd}/bin/virtiofsd"
  ];
}
