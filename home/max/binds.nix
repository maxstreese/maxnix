# The bindings both compositors share, written once.
#
# niri and Hyprland are both permanent here, and switching between them is a
# logout and a session pick — which only works if muscle memory transfers. So
# the command bindings were identical in both files by hand: seventeen of
# them, same keys, same commands, in two syntaxes. A bind added to one had to
# be added to the other by eye, and nothing caught it when that failed.
#
# This is the list. ./niri.nix and ./hyprland.nix each render it into their own
# shape, so the two cannot drift.
#
# ── What is NOT here ─────────────────────────────────────────────────────
#
# Window management. `focus-column-left`, `maximize-column`,
# `consume-or-expel-window-left` and the rest are niri's scrolling-layout
# model and have no Hyprland equivalent worth pretending to. Those stay in
# ./niri.nix, where they belong to one compositor honestly rather than being
# forced into a shared shape.
#
# The split is exactly "does this run a command": everything here spawns
# something, which is why it is portable at all.
#
# ── Why the fields are shaped like this ──────────────────────────────────
#
#   mods    neutral names, mapped per compositor. niri writes Mod+Shift+…,
#           Hyprland writes `$mod SHIFT, …` — same meaning, different spelling,
#           and keeping the neutral form means neither spelling leaks here.
#   key     an XKB keysym, which both accept, so it needs no translation.
#   locked  works while the session is locked. niri expresses this as
#           _props.allow-when-locked; Hyprland as an option on the bind.
#           One flag, two renderings.
#   repeat  fires again while the key is held. Required, not optional, and
#           that is the point: the two compositors default it the opposite
#           way — niri true (niri-config/src/binds.rs, `let mut repeat =
#           true`), Hyprland false (LuaBindingsToplevel.cpp, absent means
#           false) — so leaving it unsaid meant every shared binding behaved
#           differently depending on which session you had logged into, for
#           as long as this list has existed. Naming it here is the only way
#           the list can honestly claim the two cannot drift.
#
#           The rule is: repeat a step, never a spawn or a toggle. Volume and
#           brightness are increments and want it; holding Mod+T should not
#           open a terminal eleven times (niri repeats at 25/s after 600ms),
#           and holding mute should not flap it on and off. Upstream
#           Hyprland's own example sets repeating on mute, and niri's default
#           does the same; both are wrong about it, so both are overridden.
#   title   shown in niri's hotkey overlay. Hyprland has no equivalent and
#           drops it, which is why it is optional rather than required.
#   uwsm    Hyprland launches long-lived apps through `uwsm app --` so they
#           land in their own systemd scope rather than inside the
#           compositor's; niri does not need it. See ./hyprland.nix.
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
    uwsm = true;
  }
  {
    mods = [ "mod" ];
    key = "D";
    repeat = false;
    title = "Run an Application";
    spawn = [ "fuzzel" ];
    uwsm = true;
  }

  # DankMaterialShell. Every one of these is a short-lived `dms ipc` call that
  # talks to the already-running shell, so none of them wants uwsm.
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
