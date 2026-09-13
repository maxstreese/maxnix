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
    # Pinned to hyprlang deliberately. Every Hyprland tutorial and rice is
    # written in it, and there is no deadline to move: flake.lock pins nixpkgs,
    # so 0.57 arrives only when you run `nix flake update`. As of this writing
    # nixpkgs-unstable still ships 0.56.2, so there is nothing to move *to*.
    #
    # ── Lua port: mapped, but blocked on one unknown ─────────────────────
    #
    # The API was reverse-engineered from a running Hyprland, since it is
    # undocumented. Two things make that awkward: `hyprctl eval` works *only*
    # when Hyprland is already running a Lua config (chicken and egg — switch
    # configType first), and it prints "ok" rather than the returned value, so
    # results have to be written out with io.open from inside the sandbox.
    #
    # Constructing a dispatcher is side-effect free — it returns an
    # HL.Dispatcher object rather than executing — so shapes can be probed
    # safely with pcall. A wrong shape returns nil instead of erroring.
    #
    #   hyprlang                     lua
    #   exec, X                      hl.dsp.exec_cmd("X")
    #   killactive,                  hl.dsp.window.close()
    #   exit,                        hl.dsp.exit()
    #   movefocus, l                 hl.dsp.focus({direction="l"})
    #   movewindow, l                hl.dsp.window.move({direction="l"})
    #   workspace, N                 hl.dsp.workspace.change_id({id=N})
    #   movetoworkspace, N           hl.dsp.window.move({workspace=N})
    #   fullscreen,                  hl.dsp.window.fullscreen()
    #   togglefloating,              hl.dsp.window.float()
    #   bindm … movewindow           hl.dsp.window.drag()
    #   bindm … resizewindow         hl.dsp.window.resize()
    #   bindl                        third arg: {locked = true}
    #   bind = $mod SHIFT, T, …      hl.bind("ALT + SHIFT + T", …)
    #
    # Note `hl.dsp.exec` does NOT exist — it is exec_cmd. Modifiers are joined
    # with " + " between *every* component: "ALT + SHIFT + T" registers,
    # "ALT SHIFT + T" silently does not.
    #
    # UNRESOLVED: the equivalent of `monitor = ,addreserved,64,0,0,0`, which
    # reserves the strip DankMaterialShell's bar occupies (see below). hl.monitor
    # exists but rejected every shape tried — a name/addreserved table, a
    # reserved list, and the raw hyprlang string. Without it the bar would be
    # covered by tiled windows, so the port is not worth finishing until that
    # is known. Revisit when 0.57 lands and the API is documented.
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

        # Shift, not Ctrl: GNOME claims Ctrl+Alt+Up/Down for
        # switch-to-workspace and swallows them before the guest sees them
        # (verified with wev; QEMU's input grab makes no difference). Shift
        # keeps the model consistent with ./niri.nix too — Alt+key focuses,
        # Alt+Shift+key moves.
        "$mod SHIFT, left, movewindow, l"
        "$mod SHIFT, right, movewindow, r"
        "$mod SHIFT, up, movewindow, u"
        "$mod SHIFT, down, movewindow, d"

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
        # Alt+S, not Alt+SPACE: GNOME claims Alt+space as its window menu.
        "$mod, S, exec, dms ipc spotlight toggle"
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
