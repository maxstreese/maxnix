# Hyprland configuration.
#
# As with niri, NixOS installs Hyprland and registers its session; this module
# only generates config. package and portalPackage are null so nothing is
# installed twice (the module's own docs say to null them when the NixOS module
# provides Hyprland).
{ lib, osConfig, ... }:
let
  # The bindings shared with ./niri.nix, rendered into Hyprland's syntax.
  # ./binds.nix explains why they live in one place; this turns each entry
  # into "MODS, KEY, exec, COMMAND".
  #
  # mods = [] renders an empty modifier field, which is exactly the leading
  # comma Hyprland wants for an unmodified key: ", XF86AudioMute, exec, …".
  hyprMods = {
    mod = "$mod";
    shift = "SHIFT";
    alt = "ALT";
    ctrl = "CTRL";
  };
  renderBind =
    b:
    let
      mods = lib.concatStringsSep " " (map (m: hyprMods.${m}) b.mods);
      # uwsm for long-lived apps only; see the note at the bind list below.
      prefix = lib.optionalString (b.uwsm or false) "uwsm app -- ";
      # Empty arguments are dropped, which is not cosmetic. niri's `spawn` is
      # an argv list, so an empty string there is a real sixth argument and
      # the brightness binds pass one. Hyprland's `exec` is a shell string
      # where no such argument can be expressed — the hand-written config
      # never had it — so joining naively appended a trailing space and
      # changed the command. Filtering keeps each compositor doing exactly
      # what it did before.
      words = lib.filter (w: w != "") b.spawn;
    in
    "${mods}, ${b.key}, exec, ${prefix}${lib.concatStringsSep " " words}";

  shared = lib.partition (b: b.locked or false) (import ./binds.nix);
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;

    # Hyprland runs under UWSM (see modules/desktop/hyprland.nix), which owns
    # graphical-session.target. Home Manager's default is to inject exec-once
    # lines that import variables into systemd and start its own
    # hyprland-session.target bound to the same graphical-session.target —
    # two managers of one target. Upstream says pick one; UWSM is the one.
    systemd.enable = false;

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
    #   bind = $mod SHIFT, T, …      hl.bind("SUPER + SHIFT + T", …)
    #
    # Note `hl.dsp.exec` does NOT exist — it is exec_cmd. Modifiers are joined
    # with " + " between *every* component: "SUPER + SHIFT + T" registers,
    # "SUPER SHIFT + T" silently does not.
    #
    # UNRESOLVED: the equivalent of `monitor = ,addreserved,64,0,0,0`, which
    # reserves the strip DankMaterialShell's bar occupies (see below). hl.monitor
    # exists but rejected every shape tried — a name/addreserved table, a
    # reserved list, and the raw hyprlang string. Without it the bar would be
    # covered by tiled windows, so the port is not worth finishing until that
    # is known. Revisit when 0.57 lands and the API is documented.
    configType = "hyprlang";

    settings = {
      # Super, as upstream. It reaches the guest only while the host has
      # released its overlay key — see the note in ./niri.nix and
      # scripts/vm-keys.
      "$mod" = "SUPER";

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

      # Animations are Hyprland's signature, and also the thing most likely to
      # expose virgl's limits. Left at defaults: if they stutter in the VM,
      # that should be attributable to virgl rather than to our tuning.

      bind = [
        # `uwsm app --` asks systemd to start the program as its own unit in
        # the session's app slice, rather than as a child of Hyprland inside
        # the compositor's cgroup. Upstream: "Running applications as child
        # processes inside compositor's unit is discouraged." Own unit means
        # own lifetime (a compositor crash does not take the terminal with
        # it), own resource accounting, and orderly shutdown on logout. niri
        # does the equivalent on its own for every `spawn`; Hyprland needs
        # the prefix. The `dms ipc` binds below are short-lived commands to
        # an already-running service, so they do not need it.
        "$mod, Q, killactive,"
        "$mod SHIFT, E, exit,"

        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"

        # Same model as ./niri.nix: Mod+key focuses, Mod+Ctrl+key moves.
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

      ]
      # The terminal, the launcher and every DMS binding, from ./binds.nix.
      # They are identical to niri's by construction now rather than by
      # somebody remembering to edit both files.
      ++ map renderBind shared.wrong;

      # bindl = active even when the session is locked, which is what the
      # media keys want.
      bindl = map renderBind shared.right;

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
    };
  };
}
