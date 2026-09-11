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
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
    };
  };
}
