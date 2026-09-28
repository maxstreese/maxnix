# Our own Quickshell config — the scratchpad, not the desktop.
#
# DankMaterialShell is the shell this machine actually runs (../max/dms.nix),
# and it is a Quickshell program. Writing our own was the original reason
# Quickshell was on the list; this is where that starts, with DMS still doing
# the real work and this running only when asked.
#
# The module is already enabled and the package already installed — DMS's home
# module sets `programs.quickshell.enable` and `package` for its own sake. What
# it does not set is a config: `configs` is empty, `activeConfig` is null and
# `systemd.enable` is false. So adding a config here places files and starts
# nothing.
{
  config,
  osConfig,
  pkgs,
  ...
}:
let
  dev = osConfig.maxnix.dev;
  configDir = "${dev.clonePath}/home/max/quickshell";
in
{
  programs.quickshell.configs.maxnix =
    if dev.liveConfig then
      # The whole point of the option: a store path that is *itself* a symlink
      # to the clone, so ~/.config/quickshell/maxnix resolves to files you can
      # edit and Quickshell's watcher has something that can change.
      config.lib.file.mkOutOfStoreSymlink configDir
    else
      # The normal path, and the only one metal or a test ever sees: the
      # directory copied into the store, immutable like every other generated
      # config here.
      ./quickshell;

  # `qs-dev` — run the scratchpad against the clone, whatever liveConfig says.
  #
  # Deliberately independent of that option. `--path` (QS_CONFIG_PATH) takes a
  # directory directly, so this does not care how ~/.config/quickshell/maxnix
  # was wired and cannot be quietly running a store copy while you edit a file
  # that nothing reads — which is exactly the confusion the option could
  # otherwise create.
  #
  # MAXNIX_FLAKE first, matching `rebuild` in ../../hosts/maxnix/vm.nix, so a
  # clone in an unusual place needs no rebuild to work with.
  home.packages = [
    (pkgs.writeShellApplication {
      name = "qs-dev";
      runtimeInputs = [ config.programs.quickshell.package ];
      text = ''
        dir="''${MAXNIX_FLAKE:-${dev.clonePath}}/home/max/quickshell"
        if [ ! -f "$dir/shell.qml" ]; then
          echo "qs-dev: no shell.qml under $dir" >&2
          echo "set MAXNIX_FLAKE if the clone is somewhere else" >&2
          exit 1
        fi
        echo "running $dir — edit and save to reload" >&2
        exec quickshell --path "$dir" "$@"
      '';
    })
  ];

  # Not asserted anywhere, so worth saying: nothing validates the QML. There is
  # no equivalent of `niri validate` or Hyprland's --verify-config — quickshell
  # needs a Wayland session to load a config at all, so a syntax error surfaces
  # when you run it and not before. The store copy is at least built, which
  # catches a missing file; it does not catch a broken one.
}
