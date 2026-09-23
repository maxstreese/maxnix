# Hyprland configuration.
#
# As with niri, NixOS installs Hyprland and registers its session; this module
# only generates config. package and portalPackage are null so nothing is
# installed twice (the module's own docs say to null them when the NixOS module
# provides Hyprland).
{ lib, osConfig, ... }:
let
  inherit (lib.generators) mkLuaInline;
  toLua = lib.generators.toLua { };

  # ── How this renders ─────────────────────────────────────────────────────
  #
  # Home Manager turns `settings.<name>` into `hl.<name>(...)`, one call per
  # element when the value is a list. Three shapes matter here:
  #
  #   { a = 1; }                      hl.name({ a = 1 })
  #   { _args = [ x y ]; }            hl.name(x, y)
  #   mkLuaInline "hl.dsp.exit()"     emitted as Lua, not as a quoted string
  #
  # Binds need all three: two or three positional arguments, the second of
  # which is a live Lua call rather than a value. Hence `_args` everywhere
  # below and mkLuaInline around every dispatcher.
  #
  # Commands go through toLua rather than into the string by hand, so quoting
  # is the generator's problem and not a thing to get right seventeen times.

  hyprMods = {
    mod = "SUPER";
    shift = "SHIFT";
    alt = "ALT";
    ctrl = "CTRL";
  };

  # "SUPER + SHIFT + T". The separator goes between *every* component,
  # including between the last modifier and the key: "SUPER SHIFT + T" is
  # accepted and then never fires.
  keys = mods: key: lib.concatStringsSep " + " (map (m: hyprMods.${m}) mods ++ [ key ]);

  mkBind = args: { _args = args; };

  # A bind that runs a dispatcher, with no options.
  dispatch =
    mods: key: expr:
    mkBind [
      (keys mods key)
      (mkLuaInline expr)
    ];

  # The four arrow keys, whose keysym happens to be spelled the same as the
  # direction the dispatchers take — so one list drives both halves.
  directions = [
    "left"
    "right"
    "up"
    "down"
  ];

  workspaces = [
    1
    2
    3
    4
  ];

  # ── The shared bindings, rendered ────────────────────────────────────────
  #
  # ./binds.nix explains why they live in one place. Only the rendering is
  # Hyprland's; the list itself is compositor-neutral and niri reads the same
  # one.
  renderBind =
    b:
    let
      # uwsm for long-lived apps only; see the note at the bind list below.
      prefix = lib.optionalString (b.uwsm or false) "uwsm app -- ";
      # Empty arguments are dropped, which is not cosmetic. niri's `spawn` is
      # an argv list, so an empty string there is a real sixth argument and
      # the brightness binds pass one. exec_cmd takes a shell string where no
      # such argument can be expressed — the hand-written config never had it
      # — so joining naively appended a trailing space and changed the
      # command. Filtering keeps each compositor doing exactly what it did
      # before.
      words = lib.filter (w: w != "") b.spawn;
      cmd = prefix + lib.concatStringsSep " " words;
    in
    mkBind (
      [
        (keys b.mods b.key)
        (mkLuaInline "hl.dsp.exec_cmd(${toLua cmd})")
      ]
      # `locked` is the shared flag for "works while the session is locked",
      # which was a separate `bindl` list under hyprlang and is an options
      # table here.
      #
      # repeating is new, and deliberate. Under hyprlang these were plain
      # `bindl`, which does not repeat, so holding volume-down stepped once.
      # niri has repeated every bind by default since 0.1.8, so the two
      # compositors have disagreed on this the whole time despite sharing the
      # list. Upstream's own example sets `{ locked = true, repeating = true }`
      # on exactly these six keys; taking it closes the gap in niri's
      # direction.
      ++ lib.optional (b.locked or false) {
        locked = true;
        repeating = true;
      }
    );

  # ── Window management ────────────────────────────────────────────────────
  #
  # Not shared, and not shareable: niri's scrolling layout has no honest
  # Hyprland equivalent, so these stay here. See ./binds.nix.
  windowBinds = [
    (dispatch [ "mod" ] "Q" "hl.dsp.window.close()")
    (dispatch [ "mod" "shift" ] "E" "hl.dsp.exit()")
    (dispatch [ "mod" ] "F" "hl.dsp.window.fullscreen()")
    (dispatch [ "mod" ] "V" ''hl.dsp.window.float({ action = "toggle" })'')
  ]
  ++ map (d: dispatch [ "mod" ] d "hl.dsp.focus({ direction = ${toLua d} })") directions
  # Same model as ./niri.nix: Mod+key focuses, Mod+Ctrl+key moves.
  ++ map (d: dispatch [ "mod" "ctrl" ] d "hl.dsp.window.move({ direction = ${toLua d} })") directions
  ++ lib.concatMap (n: [
    (dispatch [ "mod" ] (toString n) "hl.dsp.focus({ workspace = ${toString n} })")
    (dispatch [ "mod" "shift" ] (toString n) "hl.dsp.window.move({ workspace = ${toString n} })")
  ]) workspaces
  ++ [
    # Was `bindm` under hyprlang; now an option on an ordinary bind.
    # Was `bindm` under hyprlang. There is no option to carry that flag
    # across, and there must not be: hl.bind's option table has no `mouse`
    # field at all (LuaBindingsToplevel.cpp reads repeating, locked, release,
    # non_consuming, auto_consuming, transparent, ignore_mods, dont_inhibit,
    # long_press, submap_universal, click, drag, device — and stops), and
    # KeybindManager.cpp dispatches `k->mouse ? "mouse" : k->handler`, so a
    # bind carrying it would be routed to the legacy mouse dispatcher instead
    # of to the Lua closure and would not work at all.
    #
    # Nothing is lost. onMouseEvent synthesises the key name "mouse:272" and
    # runs it through ordinary bind matching, so a plain bind on that key is
    # how a Lua config expresses this, and `hyprctl binds` correctly reporting
    # `bind` rather than `bindm` is the expected outcome.
    #
    # Upstream's own shipped example passes `{ mouse = true }` on exactly
    # these two binds. It is a no-op there, and copying it was measured to do
    # nothing here. `{ drag = true }` is not the replacement either: it sets
    # release, so the bind would fire on button-up.
    (mkBind [
      (keys [ "mod" ] "mouse:272")
      (mkLuaInline "hl.dsp.window.drag()")
    ])
    (mkBind [
      (keys [ "mod" ] "mouse:273")
      (mkLuaInline "hl.dsp.window.resize()")
    ])
  ];
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

    # ── lua, not hyprlang ────────────────────────────────────────────────
    #
    # Hyprland 0.55 moved to a Lua config; hyprlang was to be "supported for
    # 1 - 2 releases starting from 0.55" and then dropped. We pin 0.56.2, so
    # the runway was one release and this is not an optional modernisation.
    #
    # Redundant, strictly: the module derives this from home.stateVersion, and
    # 26.11 is past the 26.05 cutoff, so "lua" is already the default. Written
    # out anyway — the point of this repo is that what runs is what is
    # specified, and a compositor changing config language underneath us on a
    # stateVersion comparison is exactly the kind of surprise that is worth
    # one line to prevent.
    configType = "lua";

    settings = {
      config = {
        # Hyprland ignores XKB_DEFAULT_LAYOUT.
        #
        # The variable *is* in its environment — verified — but Hyprland's own
        # input:kb_layout defaults to "us", so it always passes a non-empty
        # layout to libxkbcommon and the environment default is never
        # consulted. niri, which leaves the field empty, picks up "de" from
        # the environment without any of this.
        #
        # Derived from the system setting rather than repeated, so the layout
        # stays defined in exactly one place (hosts/maxnix/configuration.nix).
        # osConfig is the NixOS config, available because Home Manager runs
        # here as a NixOS module.
        input.kb_layout = osConfig.environment.sessionVariables.XKB_DEFAULT_LAYOUT;

        general = {
          gaps_in = 5;
          gaps_out = 10;
          border_size = 2;
        };

        decoration.rounding = 8;

        # Animations are Hyprland's signature, and also the thing most likely
        # to expose virgl's limits. Left at defaults: if they stutter in the
        # VM, that should be attributable to virgl rather than to our tuning.
      };

      # Reserve the top strip for DankMaterialShell's bar.
      #
      # `hyprctl layers` shows the bar as a top-level layer surface
      # (namespace dms:bar, 1920x64) but it reserves no exclusive zone, so
      # tiled windows are placed straight over it. niri does not need this
      # because DMS generates ~/.config/niri/dms/layout.kdl for it; for
      # Hyprland it writes only colors.lua, leaving the layout to us.
      #
      # This was `monitor = ,addreserved,64,0,0,0` and was the one thing
      # blocking the move to Lua, because the replacement could not be found
      # by guessing at shapes. It is a typed field, and the package says so:
      # $out/share/hypr/stubs/hl.meta.lua declares
      #   ---@field reserved_area? integer|HL.CssGap
      #   ---@alias HL.CssGap integer|{top?,right?,bottom?,left?}
      # An empty `output` means "every monitor", as the hyprlang leading comma
      # did. 64 is the bar height DMS actually reports; if you restyle the bar,
      # this needs to follow.
      monitor = {
        output = "";
        reserved_area.top = 64;
      };

      # One list now. hyprlang needed three (bind/bindl/bindm) because the
      # flags were part of the directive name; here they are an options table,
      # so locked and mouse binds are ordinary binds that carry an argument.
      #
      # On uwsm: `uwsm app --` asks systemd to start the program as its own
      # unit in the session's app slice, rather than as a child of Hyprland
      # inside the compositor's cgroup. Upstream: "Running applications as
      # child processes inside compositor's unit is discouraged." Own unit
      # means own lifetime (a compositor crash does not take the terminal with
      # it), own resource accounting, and orderly shutdown on logout. niri
      # does the equivalent on its own for every `spawn`; Hyprland needs the
      # prefix. The `dms ipc` binds are short-lived commands to an
      # already-running service, so they do not need it.
      bind = windowBinds ++ map renderBind (import ./binds.nix);
    };
  };
}
