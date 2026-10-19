# What a laptop runs beside the desktop: real-time audio, battery and power
# profiles, firmware updates — and the state of each that must survive the
# wiped root. Bluetooth itself needs nothing here: nixpkgs' facter modules
# turn it on from the hardware report (./facter.json), which found the
# T14s's controller.
#
# On every VM too. DMS's battery and power widgets read these over D-Bus, and
# in the VM they then find a service with nothing to report rather than none
# at all — which is also what tests/desktop.nix checks. Bluetooth stays
# metal-only: the VMs have no controller and no hardware report.
{ ... }:
{
  # Real-time scheduling for PipeWire. Without it every session's PipeWire
  # logs "mod.rt: RTKit error: org.freedesktop.DBus.Error.ServiceUnknown" and
  # runs audio at normal priority — harmless in a VM, crackles on a laptop
  # under load.
  security.rtkit.enable = true;

  # Battery state, for DMS's battery widget (Quickshell's UPower service).
  services.upower.enable = true;

  # Power profiles — power saver, balanced, performance — for DMS's power
  # widget, which reads org.freedesktop.UPower.PowerProfiles: the interface
  # power-profiles-daemon provides. Not TLP, which conflicts with it and
  # which DMS does not talk to. Which driver it uses on this Ryzen —
  # amd-pstate's energy preference or the ACPI platform profile — shows only
  # on the hardware: `powerprofilesctl`. Decided 2026-10-14.
  services.power-profiles-daemon.enable = true;

  # Firmware updates from the LVFS, where Lenovo publishes ThinkPad firmware;
  # which of this machine's is there shows on the hardware, with
  # `fwupdmgr refresh` and `fwupdmgr get-updates`. A UEFI update is staged, applied at the next
  # boot, and recorded in /var/lib/fwupd, which is why that is preserved
  # (../../modules/metal/persistence.nix) — on the wiped root, fwupd would forget it had one
  # pending across exactly the reboot that applies it.
  services.fwupd.enable = true;
}
