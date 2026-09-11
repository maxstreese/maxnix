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
# The Home Manager option sits under wayland.windowManager, matching Hyprland —
# so despite both being "niri config", the two never collide.
{ osConfig, pkgs, ... }:
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
      # ── Why Alt and not Super ──────────────────────────────────────────
      #
      # This VM runs inside a GNOME session whose `overlay-key` is Super_L, and
      # GNOME consumes that before any client sees it — so Super-based binds
      # are unreliable no matter what QEMU's input grab does. niri has no
      # `mod-key` option (checked against 26.04), so the remap means writing
      # the binds out rather than flipping a setting.
      #
      # This is the same fix upstream applies in nixos/tests/sway.nix
      # (`sed s/Mod4/Mod1/`). Translate Super→Alt when reading niri docs.
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
      # So Mod+BracketLeft/Right became Alt+Comma/Period (comma and period are
      # at base level on both layouts), and Mod+Shift+Slash became Alt+Shift+7
      # — which is the same physical key combination that types "/" on a German
      # keyboard, and still resolves on US since 7 is unshifted there too.
      #
      # Rule of thumb for anything added here: letters, digits, arrows and
      # function keys are portable across layouts; punctuation is not. Check
      # with `xkbcli compile-keymap --layout de` before trusting a key name
      # taken from documentation.
      binds = {
        "Alt+T" = {
          _props.hotkey-overlay-title = "Open a Terminal";
          spawn = [ "alacritty" ];
        };
        "Alt+D" = {
          _props.hotkey-overlay-title = "Run an Application";
          spawn = [ "fuzzel" ];
        };
        "Alt+Q".close-window = { };

        # Focus: columns left/right, windows within a column up/down.
        "Alt+Left".focus-column-left = { };
        "Alt+Right".focus-column-right = { };
        "Alt+Up".focus-window-up = { };
        "Alt+Down".focus-window-down = { };

        # Move the focused column along the scrollable strip.
        "Alt+Ctrl+Left".move-column-left = { };
        "Alt+Ctrl+Right".move-column-right = { };

        # Workspaces are vertical in niri; the strip scrolls horizontally.
        "Alt+Page_Down".focus-workspace-down = { };
        "Alt+Page_Up".focus-workspace-up = { };
        "Alt+Ctrl+Page_Down".move-column-to-workspace-down = { };
        "Alt+Ctrl+Page_Up".move-column-to-workspace-up = { };

        # Sizing, and the two floating/tiling escape hatches.
        "Alt+R".switch-preset-column-width = { };
        "Alt+F".maximize-column = { };
        "Alt+Comma".consume-or-expel-window-left = { };
        "Alt+Period".consume-or-expel-window-right = { };
        "Alt+V".toggle-window-floating = { };
        "Alt+Shift+V".switch-focus-between-floating-and-tiling = { };

        "Alt+O".toggle-overview = { };

        # ── DankMaterialShell ──────────────────────────────────────────────
        #
        # Reproduced from inputs.dms.homeModules.niri, which we cannot import
        # (see ./dms.nix). Upstream spells these Mod+…; ours are Alt+… and
        # three moved to avoid colliding with binds above:
        #
        #   upstream        here              collided with
        #   Mod+Comma       Alt+Shift+Comma   Alt+Comma  consume-or-expel-left
        #   Mod+V           Alt+C             Alt+V      toggle-window-floating
        #   Super+Alt+L     Alt+Shift+L       (Alt+Alt is not expressible)
        #   Mod+Alt+N       Alt+Shift+N       (same)
        "Alt+Space" = {
          _props.hotkey-overlay-title = "Toggle Application Launcher";
          spawn = [ "dms" "ipc" "spotlight" "toggle" ];
        };
        "Alt+N" = {
          _props.hotkey-overlay-title = "Toggle Notification Center";
          spawn = [ "dms" "ipc" "notifications" "toggle" ];
        };
        "Alt+Shift+Comma" = {
          _props.hotkey-overlay-title = "Toggle Settings";
          spawn = [ "dms" "ipc" "settings" "toggle" ];
        };
        "Alt+P" = {
          _props.hotkey-overlay-title = "Toggle Notepad";
          spawn = [ "dms" "ipc" "notepad" "toggle" ];
        };
        "Alt+X" = {
          _props.hotkey-overlay-title = "Toggle Power Menu";
          spawn = [ "dms" "ipc" "powermenu" "toggle" ];
        };
        "Alt+C" = {
          _props.hotkey-overlay-title = "Toggle Clipboard Manager";
          spawn = [ "dms" "ipc" "clipboard" "toggle" ];
        };
        "Alt+M" = {
          _props.hotkey-overlay-title = "Toggle Process List";
          spawn = [ "dms" "ipc" "processlist" "toggle" ];
        };
        "Alt+Shift+N" = {
          _props.hotkey-overlay-title = "Toggle Night Mode";
          spawn = [ "dms" "ipc" "night" "toggle" ];
        };
        "Alt+Shift+L" = {
          _props.hotkey-overlay-title = "Lock the Screen";
          spawn = [ "dms" "ipc" "lock" "lock" ];
        };

        # Media and brightness keys. Portable across layouts, and allowed
        # while the screen is locked.
        "XF86AudioRaiseVolume" = {
          _props.allow-when-locked = true;
          spawn = [ "dms" "ipc" "audio" "increment" "3" ];
        };
        "XF86AudioLowerVolume" = {
          _props.allow-when-locked = true;
          spawn = [ "dms" "ipc" "audio" "decrement" "3" ];
        };
        "XF86AudioMute" = {
          _props.allow-when-locked = true;
          spawn = [ "dms" "ipc" "audio" "mute" ];
        };
        "XF86AudioMicMute" = {
          _props.allow-when-locked = true;
          spawn = [ "dms" "ipc" "audio" "micmute" ];
        };
        "XF86MonBrightnessUp" = {
          _props.allow-when-locked = true;
          spawn = [ "dms" "ipc" "brightness" "increment" "5" "" ];
        };
        "XF86MonBrightnessDown" = {
          _props.allow-when-locked = true;
          spawn = [ "dms" "ipc" "brightness" "decrement" "5" "" ];
        };
        "Print".screenshot = { };
        "Alt+Shift+7".show-hotkey-overlay = { };
        "Alt+Shift+E".quit = { };
      };

      # Stated explicitly, even though niri would pick this up from
      # XKB_DEFAULT_LAYOUT on its own — it leaves the field empty, so
      # libxkbcommon falls back to the environment.
      #
      # Relying on that absence is fragile: it would break silently the day
      # niri adopts a default (exactly as Hyprland has, with kb_layout = "us"),
      # or the day this Home Manager module starts emitting one. Both
      # compositors now state the layout, and both read it from the same place,
      # so neither depends on an upstream default staying absent.
      input.keyboard.xkb.layout =
        osConfig.environment.sessionVariables.XKB_DEFAULT_LAYOUT;

      # Client-side decorations off: niri draws its own focus ring, and CSD
      # title bars waste a row in a tiling layout.
      prefer-no-csd = { };
    };
  };
}
