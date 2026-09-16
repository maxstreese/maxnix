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
      # ── Mod is Super, as upstream ──────────────────────────────────────
      #
      # This VM runs inside a GNOME session whose `overlay-key` is Super_L.
      # While QEMU holds the keyboard grab, Mutter inhibits its own shortcuts
      # for that window — but the bare overlay key is the one thing it still
      # handles itself, and the grab is only honoured once GNOME has been
      # told to allow it. scripts/vm-keys arranges both for the duration of a
      # run, and its header explains the mechanism:
      #
      #   scripts/vm-keys run -- nix run .#vm
      #
      # Without it, Super-based binds are dead in the guest. This used to be
      # worked around with Alt as the modifier; the binds are now upstream's.
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
        "Mod+T" = {
          _props.hotkey-overlay-title = "Open a Terminal";
          spawn = [ "alacritty" ];
        };
        "Mod+D" = {
          _props.hotkey-overlay-title = "Run an Application";
          spawn = [ "fuzzel" ];
        };
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

        # ── DankMaterialShell ──────────────────────────────────────────────
        #
        # Reproduced from inputs.dms.homeModules.niri, which we cannot import
        # (see ./dms.nix). Upstream's keys, except two that collide with
        # binds above:
        #
        #   upstream        here              collided with
        #   Mod+Comma       Mod+Shift+Comma   Mod+Comma  consume-or-expel-left
        #   Mod+V           Mod+C             Mod+V      toggle-window-floating
        "Mod+Space" = {
          _props.hotkey-overlay-title = "Toggle Application Launcher";
          spawn = [ "dms" "ipc" "spotlight" "toggle" ];
        };
        "Mod+N" = {
          _props.hotkey-overlay-title = "Toggle Notification Center";
          spawn = [ "dms" "ipc" "notifications" "toggle" ];
        };
        "Mod+Shift+Comma" = {
          _props.hotkey-overlay-title = "Toggle Settings";
          spawn = [ "dms" "ipc" "settings" "toggle" ];
        };
        "Mod+P" = {
          _props.hotkey-overlay-title = "Toggle Notepad";
          spawn = [ "dms" "ipc" "notepad" "toggle" ];
        };
        "Mod+X" = {
          _props.hotkey-overlay-title = "Toggle Power Menu";
          spawn = [ "dms" "ipc" "powermenu" "toggle" ];
        };
        "Mod+C" = {
          _props.hotkey-overlay-title = "Toggle Clipboard Manager";
          spawn = [ "dms" "ipc" "clipboard" "toggle" ];
        };
        "Mod+M" = {
          _props.hotkey-overlay-title = "Toggle Process List";
          spawn = [ "dms" "ipc" "processlist" "toggle" ];
        };
        "Mod+Alt+N" = {
          _props.hotkey-overlay-title = "Toggle Night Mode";
          spawn = [ "dms" "ipc" "night" "toggle" ];
        };
        "Mod+Alt+L" = {
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
        "Mod+Shift+7".show-hotkey-overlay = { };
        "Mod+Shift+E".quit = { };
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
