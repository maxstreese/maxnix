# Where the working clone is, and whether generated config should point at it.
#
# Everything else in this repo builds config into /nix/store and symlinks it
# into $HOME, which is the right trade for a machine and the wrong one for a
# design loop: the store is read-only, so changing a colour means `rebuild`,
# and ~30 s per keystroke is not a loop. These two options are the exception,
# scoped as narrowly as possible.
{ lib, ... }:
{
  options.maxnix.dev = {
    clonePath = lib.mkOption {
      type = lib.types.str;
      default = "/home/max/Repositories/github.com/maxstreese/maxnix";
      description = ''
        Absolute path to the working clone inside this machine.

        The guest keeps its own clone rather than sharing the host's (see
        ./vm.nix), and two things need to agree on where it is: `rebuild`,
        which builds from it, and liveConfig below, which points generated
        config at it. Declared once here so they cannot disagree.

        Runtime overrides still win where it makes sense — the shell tools
        read MAXNIX_FLAKE first and fall back to this.
      '';
    };

    liveConfig = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Point generated Quickshell config at the clone instead of copying it
        into the store, so edits take effect on save.

        Quickshell watches the files it loaded and reloads on change —
        `watchFiles` defaults to true, and quickshell-core.qmltypes carries
        the `onReload`/`ReloadPopup` machinery to match. Aimed at a store
        path that machinery is inert, because store files never change. This
        is what stops preventing it.

        Off by default, and deliberately so: it makes the running system
        depend on a mutable path that may not exist. On a fresh install,
        before the clone is made, the symlink would simply dangle. It is
        turned on for the VM in ./vm.nix, which is where development happens
        and where the clone is guaranteed by the workflow.

        What it costs: nothing can check the live content. The suites build
        `hostModules`, never the VM variant, so they keep testing the store
        copy — which is also what metal gets. Until a design is promoted back
        into the store, "it is in git" and "it is what the machine will boot"
        are two different claims.
      '';
    };
  };
}
