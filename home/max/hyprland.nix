# Hyprland configuration.
#
# As with niri, NixOS installs Hyprland and registers its session; this module
# only generates config. package and portalPackage are null so nothing is
# installed twice (the module's own docs say to null them when the NixOS module
# provides Hyprland).
{ osConfig, ... }:
{
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;

    # ── hyprlang, not lua ────────────────────────────────────────────────
    #
    # Hyprland 0.56 moved to a Lua config and generates ~/.config/hypr/
    # hyprland.lua when none exists — which is why its dispatcher API changed
    # under us earlier (`hyprctl dispatch exec kitty` now fails; dispatchers
    # live at hl.dsp.<namespace>.<action>()). Home Manager supports both via
    # configType, and at our stateVersion it would default to "lua".
    #
    # Pinned to hyprlang anyway, deliberately: essentially every Hyprland
    # tutorial, wiki page and rice you will read while evaluating is written in
    # hyprlang, and the Lua API is new enough that its dispatcher names are
    # hard to discover. Matching the ecosystem's documentation is worth more
    # during an evaluation than being on the newer format. Revisit if you keep
    # Hyprland.
    configType = "hyprlang";

    settings = {
      # Alt rather than Super, for the same reason as niri: GNOME's overlay-key
      # is Super_L and it consumes the key before the guest sees it.
      "$mod" = "ALT";
      "$terminal" = "alacritty";
      "$menu" = "fuzzel";

      # Hyprland ignores XKB_DEFAULT_LAYOUT.
      #
      # The variable *is* in its environment — verified — but Hyprland's own
      # input:kb_layout defaults to "us", so it always passes a non-empty
      # layout to libxkbcommon and the environment default is never consulted.
      # niri, which leaves the field empty, picks up "de" from the environment
      # without any of this.
      #
      # Derived from the system setting rather than repeated, so the layout
      # stays defined in exactly one place (hosts/maxnix/configuration.nix).
      # osConfig is the NixOS config, available because Home Manager runs here
      # as a NixOS module.
      input.kb_layout = osConfig.environment.sessionVariables.XKB_DEFAULT_LAYOUT;

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
      };

      decoration.rounding = 8;

      # Reserve the top strip for DankMaterialShell's bar.
      #
      # `hyprctl layers` shows the bar as a top-level layer surface
      # (namespace dms:bar, 1920x64) but it reserves no exclusive zone, so
      # tiled windows are placed straight over it. niri does not need this
      # because DMS generates ~/.config/niri/dms/layout.kdl for it; for
      # Hyprland it writes only colors.lua, leaving the layout to us.
      #
      # 64 is the bar height DMS actually reports. If you restyle the bar,
      # this needs to follow.
      monitor = ",addreserved,64,0,0,0";

      # Animations are the thing worth judging Hyprland on, and also the thing
      # most likely to expose virgl's limits. Left at defaults so the
      # comparison with niri is about the compositors, not about our tuning.

      bind = [
        "$mod, T, exec, $terminal"
        "$mod, D, exec, $menu"
        "$mod, Q, killactive,"
        "$mod SHIFT, E, exit,"

        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"

        "$mod CTRL, left, movewindow, l"
        "$mod CTRL, right, movewindow, r"
        "$mod CTRL, up, movewindow, u"
        "$mod CTRL, down, movewindow, d"

        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"

        "$mod, F, fullscreen,"
        "$mod, V, togglefloating,"

        # DankMaterialShell — deliberately the same key combinations as
        # ./niri.nix, so switching compositors during the evaluation does not
        # also mean relearning the shell.
        "$mod, SPACE, exec, dms ipc spotlight toggle"
        "$mod, N, exec, dms ipc notifications toggle"
        "$mod SHIFT, comma, exec, dms ipc settings toggle"
        "$mod, P, exec, dms ipc notepad toggle"
        "$mod, X, exec, dms ipc powermenu toggle"
        "$mod, C, exec, dms ipc clipboard toggle"
        "$mod, M, exec, dms ipc processlist toggle"
        "$mod SHIFT, N, exec, dms ipc night toggle"
        "$mod SHIFT, L, exec, dms ipc lock lock"
      ];

      # bindl = active even when the session is locked, which is what the
      # media keys want.
      bindl = [
        ", XF86AudioRaiseVolume, exec, dms ipc audio increment 3"
        ", XF86AudioLowerVolume, exec, dms ipc audio decrement 3"
        ", XF86AudioMute, exec, dms ipc audio mute"
        ", XF86AudioMicMute, exec, dms ipc audio micmute"
        ", XF86MonBrightnessUp, exec, dms ipc brightness increment 5"
        ", XF86MonBrightnessDown, exec, dms ipc brightness decrement 5"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
    };
  };
}
