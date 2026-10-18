# The bindings that run a command, as data.
#
# Written when niri and Hyprland both ran here and each rendered this
# one list, so the seventeen command bindings could not drift between them.
# Hyprland went on 2026-10-18 (README, "Decisions, and why"); ./niri.nix is
# now the only renderer. Whether the list should stay separate from niri's
# own binds is an open point there.
#
# ── What is NOT here ─────────────────────────────────────────────────────
#
# Window management. `focus-column-left`, `maximize-column`,
# `consume-or-expel-window-left` and the rest are niri actions rather than
# commands, and live in ./niri.nix. The split is exactly "does this run a
# command": everything here spawns something.
#
# ── Why the fields are shaped like this ──────────────────────────────────
#
#   mods    neutral names (mod, shift, alt, ctrl), spelled by ./niri.nix.
#   key     an XKB keysym at the unshifted level of the `de` layout: niri
#           resolves binds against that level, see ./niri.nix.
#   locked  works while the session is locked; niri's allow-when-locked.
#   repeat  fires again while the key is held. Required, not optional:
#           niri defaults it to true (niri-config/src/binds.rs, `let mut
#           repeat = true`), so leaving it unsaid makes every spawn repeat.
#           The field exists because Hyprland, while it was here, defaulted
#           the other way, and the shared list behaved differently per
#           session until it was named.
#
#           The rule is: repeat a step, never a spawn or a toggle. Volume and
#           brightness are increments and want it; holding Mod+T should not
#           open a terminal eleven times (niri repeats at 25/s after 600ms),
#           and holding mute should not flap it on and off. niri's default
#           repeats on mute, so it is overridden.
#   title   shown in niri's hotkey overlay. Optional: the media keys have
#           none and stay out of the overlay.
[
  {
    mods = [ "mod" ];
    key = "T";
    repeat = false;
    title = "Open a Terminal";
    spawn = [
      "ghostty"
      "+new-window"
    ];
  }
  {
    mods = [ "mod" ];
    key = "D";
    repeat = false;
    title = "Run an Application";
    spawn = [ "fuzzel" ];
  }

  # DankMaterialShell. Every one of these is a short-lived `dms ipc` call that
  # talks to the already-running shell.
  {
    mods = [ "mod" ];
    key = "Space";
    repeat = false;
    title = "Toggle Application Launcher";
    spawn = [
      "dms"
      "ipc"
      "spotlight"
      "toggle"
    ];
  }
  # The bar. Auto-hide rather than hiding outright: windows get the full
  # screen either way, but an auto-hidden bar still slides in at the top
  # edge, so the clock and tray are a mouse move away instead of a keypress.
  # Mod+Shift+B slides it in and out from the keyboard; DMS ignores that one
  # (BAR_AUTO_HIDE_DISABLED) unless auto-hide is on. Both save to DMS's
  # settings.json, so the state survives a restart.
  {
    mods = [ "mod" ];
    key = "B";
    repeat = false;
    title = "Toggle Bar Auto-Hide";
    spawn = [
      "dms"
      "ipc"
      "bar"
      "toggleAutoHide"
      "index"
      "0"
    ];
  }
  {
    mods = [
      "mod"
      "shift"
    ];
    key = "B";
    repeat = false;
    title = "Reveal or Tuck the Bar";
    spawn = [
      "dms"
      "ipc"
      "bar"
      "toggleReveal"
      "index"
      "0"
    ];
  }
  {
    mods = [ "mod" ];
    key = "N";
    repeat = false;
    title = "Toggle Notification Center";
    spawn = [
      "dms"
      "ipc"
      "notifications"
      "toggle"
    ];
  }
  {
    mods = [
      "mod"
      "shift"
    ];
    key = "Comma";
    repeat = false;
    title = "Toggle Settings";
    spawn = [
      "dms"
      "ipc"
      "settings"
      "toggle"
    ];
  }
  {
    mods = [ "mod" ];
    key = "P";
    repeat = false;
    title = "Toggle Notepad";
    spawn = [
      "dms"
      "ipc"
      "notepad"
      "toggle"
    ];
  }
  {
    mods = [ "mod" ];
    key = "X";
    repeat = false;
    title = "Toggle Power Menu";
    spawn = [
      "dms"
      "ipc"
      "powermenu"
      "toggle"
    ];
  }
  {
    mods = [ "mod" ];
    key = "C";
    repeat = false;
    title = "Toggle Clipboard Manager";
    spawn = [
      "dms"
      "ipc"
      "clipboard"
      "toggle"
    ];
  }
  {
    mods = [ "mod" ];
    key = "M";
    repeat = false;
    title = "Toggle Process List";
    spawn = [
      "dms"
      "ipc"
      "processlist"
      "toggle"
    ];
  }
  {
    mods = [
      "mod"
      "alt"
    ];
    key = "N";
    repeat = false;
    title = "Toggle Night Mode";
    spawn = [
      "dms"
      "ipc"
      "night"
      "toggle"
    ];
  }
  {
    mods = [
      "mod"
      "alt"
    ];
    key = "L";
    repeat = false;
    title = "Lock the Screen";
    spawn = [
      "dms"
      "ipc"
      "lock"
      "lock"
    ];
  }

  # Screen capture, through the Quick Capture plugin (./dms.nix). This
  # replaces niri's built-in Print screenshot. Print is a named keysym on no
  # layer of any layout, so it holds on `de` as everywhere.
  # Alt is avoided on purpose: Alt+Print is Sys_Req.
  #
  # `edit` opens the annotator after capturing; `float` would pin the image on
  # screen instead.
  {
    mods = [ ];
    key = "Print";
    repeat = false;
    title = "Capture a Region";
    spawn = [
      "dms"
      "ipc"
      "call"
      "quickCapture"
      "screenshot"
      "region"
      "edit"
    ];
  }
  {
    mods = [ "shift" ];
    key = "Print";
    repeat = false;
    title = "Capture the Screen";
    spawn = [
      "dms"
      "ipc"
      "call"
      "quickCapture"
      "screenshot"
      "full"
      "edit"
    ];
  }
  # A toggle: the first press starts a region recording, the next stops it.
  # gpu-screen-recorder on metal, wf-recorder in the VM; see ./dms.nix.
  {
    mods = [ "mod" ];
    key = "Print";
    repeat = false;
    title = "Start or Stop Recording a Region";
    spawn = [
      "dms"
      "ipc"
      "call"
      "quickCapture"
      "recordToggle"
      "region"
    ];
  }

  # Media and brightness. No modifier, and allowed while locked — turning the
  # volume down should not require logging in first.
  {
    mods = [ ];
    key = "XF86AudioRaiseVolume";
    repeat = true;
    locked = true;
    spawn = [
      "dms"
      "ipc"
      "audio"
      "increment"
      "3"
    ];
  }
  {
    mods = [ ];
    key = "XF86AudioLowerVolume";
    repeat = true;
    locked = true;
    spawn = [
      "dms"
      "ipc"
      "audio"
      "decrement"
      "3"
    ];
  }
  {
    mods = [ ];
    key = "XF86AudioMute";
    repeat = false;
    locked = true;
    spawn = [
      "dms"
      "ipc"
      "audio"
      "mute"
    ];
  }
  {
    mods = [ ];
    key = "XF86AudioMicMute";
    repeat = false;
    locked = true;
    spawn = [
      "dms"
      "ipc"
      "audio"
      "micmute"
    ];
  }
  {
    mods = [ ];
    key = "XF86MonBrightnessUp";
    repeat = true;
    locked = true;
    spawn = [
      "dms"
      "ipc"
      "brightness"
      "increment"
      "5"
      ""
    ];
  }
  {
    mods = [ ];
    key = "XF86MonBrightnessDown";
    repeat = true;
    locked = true;
    spawn = [
      "dms"
      "ipc"
      "brightness"
      "decrement"
      "5"
      ""
    ];
  }
]
