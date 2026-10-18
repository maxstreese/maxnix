# niri configuration.
#
# Two modules, two namespaces, two jobs:
#
#   NixOS  programs.niri.enable                installs niri, registers the
#                                              .desktop session so greetd can
#                                              offer it, wires xdg-portals and
#                                              polkit. Must be system-level:
#                                              greetd reads that session list
#                                              before any user logs in.
#   here   wayland.windowManager.niri.settings generates
#                                              ~/.config/niri/config.kdl.
#
# The Home Manager option sits under wayland.windowManager, so despite both
# being "niri config", the two never collide.
{
  osConfig,
  pkgs,
  ...
}:
let
  # ── Binds that run a command ─────────────────────────────────────────────
  #
  # `repeat` is written out on every one of them, even where it matches niri's
  # default, which is `true` (niri-config/src/binds.rs, `let mut repeat =
  # true`). The rule is: repeat a step, never a spawn or a toggle. Holding
  # Mod+T should not open a terminal eleven times (niri repeats at 25/s after
  # 600ms), and holding mute should not flap it on and off — niri's own default
  # config repeats on mute. Volume and brightness are increments and want it.
  # The helpers below are that rule: what they spawn decides whether it may
  # repeat, so no bind can leave it to the default.
  #
  # These lived in a compositor-neutral list, home/max/binds.nix, while niri
  # and Hyprland both rendered it; Hyprland defaulted repeat to false, which
  # is how the field came to be stated at all. Folded in here on 2026-10-18,
  # right after Hyprland went, with config.kdl byte-identical.
  #
  # spawn is argv, so an empty string is a real argument rather than
  # whitespace (the brightness binds pass one).

  # Runs a command, shown in the hotkey overlay under `title`. Never repeats.
  command = title: argv: {
    _props = {
      hotkey-overlay-title = title;
      repeat = false;
    };
    spawn = argv;
  };

  # A DankMaterialShell action: a short-lived `dms ipc` call that talks to the
  # already-running shell.
  dms =
    title: words:
    command title (
      [
        "dms"
        "ipc"
      ]
      ++ words
    );

  # Media and brightness keys: no overlay title, and allowed while locked —
  # turning the volume down should not require logging in first. A step
  # repeats while held, a toggle does not.
  step = argv: {
    _props = {
      allow-when-locked = true;
      repeat = true;
    };
    spawn = argv;
  };
  lockedToggle = argv: {
    _props = {
      allow-when-locked = true;
      repeat = false;
    };
    spawn = argv;
  };
in
{
  wayland.windowManager.niri = {
    enable = true;

    # package would ideally be null here, since the NixOS module already
    # installs niri — but checkConfig asserts on a non-null package (it needs a
    # niri binary to validate against). Build-time validation is worth more
    # than avoiding a duplicate profile entry, and the cost is zero bytes: this
    # is the same store path the system layer installs.
    package = pkgs.niri;

    # Validate at build time by running niri against the generated config, so a
    # typo fails the build instead of dropping you into a broken session.
    checkConfig = true;

    # The NixOS module already defines a systemd user service for niri. Leaving
    # this on would define a second one.
    systemd.enable = false;

    settings = {
      # ── Mod is Super, as upstream ──────────────────────────────────────
      #
      # For as long as this runs as a VM inside a GNOME session, Super has a
      # catch: GNOME's `overlay-key` is Super_L. While QEMU holds the keyboard
      # grab, Mutter inhibits its own shortcuts for that window — but the bare
      # overlay key is the one thing it still handles itself, and the grab is
      # only honoured once GNOME has been told to allow it. scripts/vm-keys
      # arranges both for the duration of a run, and its header explains the
      # mechanism:
      #
      #   scripts/vm-keys run -- nix run .#vm
      #
      # Without it, Super-based binds are dead in the guest. This used to be
      # worked around with Alt as the modifier; the binds are now upstream's,
      # which is also what the eventual metal install wants — none of this
      # applies once there is no host compositor in the way.
      #
      # ── Only bind keys that exist at the UNSHIFTED level of the layout ──
      #
      # niri resolves binds against the base keysym of a physical key, not the
      # character you would type: "binding shifted keys requires spelling out
      # Shift and the unshifted version of the key, according to your XKB
      # layout". Getting this wrong produces a bind that is configured, shown
      # in the hotkey overlay, and completely dead.
      #
      # niri's own defaults are US-centric, and three of them do not survive
      # the move to `de`:
      #
      #   key    us base level        de base level      de needs
      #   [      bracketleft          8                  AltGr+8
      #   ]      bracketright         9                  AltGr+9
      #   /      slash                7                  Shift+7
      #
      # So Mod+BracketLeft/Right became Mod+Comma/Period (comma and period are
      # at base level on both layouts), and Mod+Shift+Slash became Mod+Shift+7
      # — which is the same physical key combination that types "/" on a German
      # keyboard, and still resolves on US since 7 is unshifted there too.
      #
      # Rule of thumb for anything added here: letters, digits, arrows and
      # function keys are portable across layouts; punctuation is not. Check
      # with `xkbcli compile-keymap --layout de` before trusting a key name
      # taken from documentation.
      binds = {
        "Mod+Q".close-window = { };

        # Focus: columns left/right, windows within a column up/down.
        "Mod+Left".focus-column-left = { };
        "Mod+Right".focus-column-right = { };
        "Mod+Up".focus-window-up = { };
        "Mod+Down".focus-window-down = { };

        # Move the focused column along the scrollable strip. Upstream's
        # scheme: Mod+key focuses, Mod+Ctrl+key moves.
        "Mod+Ctrl+Left".move-column-left = { };
        "Mod+Ctrl+Right".move-column-right = { };

        # Workspaces are vertical in niri; the strip scrolls horizontally.
        "Mod+Page_Down".focus-workspace-down = { };
        "Mod+Page_Up".focus-workspace-up = { };
        "Mod+Ctrl+Page_Down".move-column-to-workspace-down = { };
        "Mod+Ctrl+Page_Up".move-column-to-workspace-up = { };

        # Sizing, and the two floating/tiling escape hatches.
        "Mod+R".switch-preset-column-width = { };
        "Mod+F".maximize-column = { };
        "Mod+Comma".consume-or-expel-window-left = { };
        "Mod+Period".consume-or-expel-window-right = { };
        "Mod+V".toggle-window-floating = { };
        "Mod+Shift+V".switch-focus-between-floating-and-tiling = { };

        "Mod+O".toggle-overview = { };

        "Mod+Shift+7".show-hotkey-overlay = { };
        "Mod+Shift+E".quit = { };

        "Mod+T" = command "Open a Terminal" [
          "ghostty"
          "+new-window"
        ];
        "Mod+D" = command "Run an Application" [ "fuzzel" ];

        # ── DankMaterialShell ──────────────────────────────────────────────
        #
        # Reproduced from inputs.dms.homeModules.niri, which we cannot import
        # (see ./dms.nix). Upstream's keys, except two that collide with
        # binds above:
        #
        #   upstream        here              collided with
        #   Mod+Comma       Mod+Shift+Comma   Mod+Comma  consume-or-expel-left
        #   Mod+V           Mod+C             Mod+V      toggle-window-floating
        "Mod+Space" = dms "Toggle Application Launcher" [
          "spotlight"
          "toggle"
        ];
        # The bar. Auto-hide rather than hiding outright: windows get the full
        # screen either way, but an auto-hidden bar still slides in at the top
        # edge, so the clock and tray are a mouse move away instead of a
        # keypress. Mod+Shift+B slides it in and out from the keyboard; DMS
        # ignores that one (BAR_AUTO_HIDE_DISABLED) unless auto-hide is on.
        # Both save to DMS's settings.json, so the state survives a restart.
        "Mod+B" = dms "Toggle Bar Auto-Hide" [
          "bar"
          "toggleAutoHide"
          "index"
          "0"
        ];
        "Mod+Shift+B" = dms "Reveal or Tuck the Bar" [
          "bar"
          "toggleReveal"
          "index"
          "0"
        ];
        "Mod+N" = dms "Toggle Notification Center" [
          "notifications"
          "toggle"
        ];
        "Mod+Shift+Comma" = dms "Toggle Settings" [
          "settings"
          "toggle"
        ];
        "Mod+P" = dms "Toggle Notepad" [
          "notepad"
          "toggle"
        ];
        "Mod+X" = dms "Toggle Power Menu" [
          "powermenu"
          "toggle"
        ];
        "Mod+C" = dms "Toggle Clipboard Manager" [
          "clipboard"
          "toggle"
        ];
        "Mod+M" = dms "Toggle Process List" [
          "processlist"
          "toggle"
        ];
        "Mod+Alt+N" = dms "Toggle Night Mode" [
          "night"
          "toggle"
        ];
        "Mod+Alt+L" = dms "Lock the Screen" [
          "lock"
          "lock"
        ];

        # Screen capture, through the Quick Capture plugin (./dms.nix). This
        # replaces niri's built-in Print screenshot. Print is a named keysym
        # on no layer of any layout, so it holds on `de` as everywhere. Alt is
        # avoided on purpose: Alt+Print is Sys_Req.
        #
        # `edit` opens the annotator after capturing; `float` would pin the
        # image on screen instead.
        "Print" = dms "Capture a Region" [
          "call"
          "quickCapture"
          "screenshot"
          "region"
          "edit"
        ];
        "Shift+Print" = dms "Capture the Screen" [
          "call"
          "quickCapture"
          "screenshot"
          "full"
          "edit"
        ];
        # A toggle: the first press starts a region recording, the next stops
        # it. gpu-screen-recorder on metal, wf-recorder in the VM; see
        # ./dms.nix.
        "Mod+Print" = dms "Start or Stop Recording a Region" [
          "call"
          "quickCapture"
          "recordToggle"
          "region"
        ];

        # ── Media and brightness ───────────────────────────────────────────
        "XF86AudioRaiseVolume" = step [
          "dms"
          "ipc"
          "audio"
          "increment"
          "3"
        ];
        "XF86AudioLowerVolume" = step [
          "dms"
          "ipc"
          "audio"
          "decrement"
          "3"
        ];
        "XF86AudioMute" = lockedToggle [
          "dms"
          "ipc"
          "audio"
          "mute"
        ];
        "XF86AudioMicMute" = lockedToggle [
          "dms"
          "ipc"
          "audio"
          "micmute"
        ];
        "XF86MonBrightnessUp" = step [
          "dms"
          "ipc"
          "brightness"
          "increment"
          "5"
          ""
        ];
        "XF86MonBrightnessDown" = step [
          "dms"
          "ipc"
          "brightness"
          "decrement"
          "5"
          ""
        ];
      };

      # Stated explicitly, even though niri would pick this up from
      # XKB_DEFAULT_LAYOUT on its own — it leaves the field empty, so
      # libxkbcommon falls back to the environment.
      #
      # Relying on that absence is fragile: it would break silently the day
      # niri adopts a default (exactly as Hyprland had, with kb_layout = "us"),
      # or the day this Home Manager module starts emitting one. Read from the
      # one place the layout is defined, so it does not depend on an upstream
      # default staying absent.
      input.keyboard.xkb.layout = osConfig.environment.sessionVariables.XKB_DEFAULT_LAYOUT;

      # Client-side decorations off: niri draws its own focus ring, and CSD
      # title bars waste a row in a tiling layout.
      prefer-no-csd = { };
    };
  };
}
