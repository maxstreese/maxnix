# DankMaterialShell — a Quickshell-based desktop shell.
#
# This fills the gap both compositors leave: niri and Hyprland draw windows and
# nothing else, so out of the box there is no bar, no launcher, no notification
# centre and no power menu. DMS provides all of it, built on Quickshell — which
# means running it is also a way to evaluate Quickshell as a platform before
# writing any QML ourselves.
#
# ── Why NOT inputs.dms.homeModules.niri ──────────────────────────────────────
#
# DMS ships a niri integration module and we deliberately do not use it, for
# two independent reasons:
#
#   1. It writes to `programs.niri.settings` and uses `config.lib.niri.actions`
#      — that is *niri-flake's* API. We use Home Manager's
#      wayland.windowManager.niri instead. Its own `includes.enable` option is
#      documented as "includes for niri-flake".
#   2. Two of its binds collide with ours: Mod+Comma with consume-or-expel
#      and Mod+V with toggle-window-floating.
#
# Nothing in it is hard to reproduce: every binding is `dms ipc <thing>
# <action>`. So the binds live in ./niri.nix and ./hyprland.nix, which also
# gets them into Hyprland — something the DMS module cannot do, since it only
# supports niri.
#
# The main module below is compositor-agnostic: it mentions neither compositor.
{
  inputs,
  osConfig,
  pkgs,
  ...
}:
let
  # ── Theming is live, and lives outside git ───────────────────────────────
  #
  # `programs.dank-material-shell.settings` exists and is deliberately unset
  # below, which is what makes theming instant: the module only generates
  # ~/.config/DankMaterialShell/settings.json when that option is non-empty,
  # so today the file is plain mutable state DMS owns and its settings UI can
  # write. Setting the option would put it in the store, and DMS would lose
  # the ability to save — the fast loop traded away for version control.
  #
  # These two keep both. Theme in the UI as now, then `dms-capture` to record
  # the result in the clone, where git sees it like any other change. Explicit
  # rather than a directory symlinked out of the store: DMS also writes
  # plugins/ and assorted state into that directory, and a capture step gets to
  # choose what is worth keeping instead of finding out afterwards.
  #
  # What is captured is the settings, not the palette: with
  # enableDynamicTheming the colours are generated from the wallpaper by
  # matugen, so the wallpaper and the choices around it are the inputs worth
  # keeping and the generated palette is not.
  stateDir = "home/max/dms-state";

  # settings.json  the main one, everything the settings UI writes
  # clsettings.json  clipboard
  # plugin_settings.json  per-plugin, and small
  #
  # plugins/ is excluded on purpose: that is third-party code DMS installs,
  # not configuration, and it does not belong in this repo.
  files = [
    "settings.json"
    "clsettings.json"
    "plugin_settings.json"
  ];

  # Literal shell, not Nix: the scripts expand MAXNIX_FLAKE at runtime and fall
  # back to the declared path, matching `rebuild` in ../../hosts/maxnix/vm.nix.
  clone = "\${MAXNIX_FLAKE:-${osConfig.maxnix.dev.clonePath}}";

  capture = pkgs.writeShellApplication {
    name = "dms-capture";
    runtimeInputs = [ pkgs.git ];
    text = ''
      clone="${clone}"
      src="$HOME/.config/DankMaterialShell"
      dest="$clone/${stateDir}"

      if [ ! -d "$src" ]; then
        echo "dms-capture: nothing at $src — has DMS ever run?" >&2
        exit 1
      fi
      if [ ! -e "$clone/flake.nix" ]; then
        echo "dms-capture: no flake.nix at $clone" >&2
        echo "set MAXNIX_FLAKE to where the clone is" >&2
        exit 1
      fi

      mkdir -p "$dest"
      for f in ${toString files}; do
        if [ -f "$src/$f" ]; then
          cp -L -- "$src/$f" "$dest/$f"
          echo "captured $f"
        fi
      done

      # Custom themes, if any were made. Replaced wholesale rather than
      # merged, so deleting one in the UI is also captured.
      if [ -d "$src/themes" ]; then
        rm -rf "$dest/themes"
        cp -rL -- "$src/themes" "$dest/themes"
        echo "captured themes/"
      fi

      echo
      git -C "$clone" status --short -- "${stateDir}"
      echo "review, then commit ${stateDir} as usual" >&2
    '';
  };

  restore = pkgs.writeShellApplication {
    name = "dms-restore";
    text = ''
      clone="${clone}"
      src="$clone/${stateDir}"
      dest="$HOME/.config/DankMaterialShell"

      if [ ! -d "$src" ]; then
        echo "dms-restore: nothing captured yet at $src" >&2
        exit 1
      fi

      mkdir -p "$dest"
      for f in ${toString files}; do
        if [ -f "$src/$f" ]; then
          cp -- "$src/$f" "$dest/$f"
          echo "restored $f"
        fi
      done
      if [ -d "$src/themes" ]; then
        rm -rf "$dest/themes"
        cp -r -- "$src/themes" "$dest/themes"
        echo "restored themes/"
      fi

      # DMS reads these at startup and writes them back on change, so a
      # restore into a running shell would be overwritten by the next save.
      # Restart it if it is up; say so rather than doing it silently.
      if systemctl --user is-active --quiet dms; then
        echo "restarting dms to pick them up" >&2
        systemctl --user restart dms
      fi
    '';
  };
in
{
  imports = [ inputs.dms.homeModules.dank-material-shell ];

  home.packages = [
    capture
    restore
  ];

  programs.dank-material-shell = {
    enable = true;

    # Start DMS from the session target rather than a spawn-at-startup line in
    # each compositor's config. Upstream warns not to enable both systemd
    # startup and niri.enableSpawn — you get two shells. We use neither spawn
    # mechanism, so there is nothing to collide.
    systemd.enable = true;

    # Material You palette generation from the wallpaper. This is DMS's
    # signature feature and the main reason to look at it at all; it pulls in
    # matugen.
    enableDynamicTheming = true;

    # The CPU/memory/network widgets in the bar.
    enableSystemMonitoring = true;

    # Off for now — each pulls a package for something the VM cannot
    # exercise. All three become relevant on metal (ROAD TO METAL):
    #   enableVPN             glib + networkmanager, no VPN here
    #   enableAudioWavelength cava, and guest audio is not wired up
    #   enableCalendarEvents  khal, no calendar
  };
}
