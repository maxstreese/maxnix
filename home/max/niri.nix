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
{ pkgs, ... }:
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
        "Alt+BracketLeft".consume-or-expel-window-left = { };
        "Alt+BracketRight".consume-or-expel-window-right = { };
        "Alt+V".toggle-window-floating = { };
        "Alt+Shift+V".switch-focus-between-floating-and-tiling = { };

        "Alt+O".toggle-overview = { };
        "Print".screenshot = { };
        "Alt+Shift+Slash".show-hotkey-overlay = { };
        "Alt+Shift+E".quit = { };
      };

      # Client-side decorations off: niri draws its own focus ring, and CSD
      # title bars waste a row in a tiling layout.
      prefer-no-csd = { };
    };
  };
}
