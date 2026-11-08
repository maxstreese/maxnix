# Foreign binaries run here, on purpose.
#
# A binary built for a generic Linux names /lib64/ld-linux-x86-64.so.2 as its
# loader and expects its libraries in FHS paths. NixOS has neither, so such a
# binary dies before main() with a misleading "No such file or directory".
# nix-ld puts a shim at that path (environment.ldso) which hands over to the
# store's glibc loader and adds the libraries listed below. On x86-64 the
# library path reaches only the loaded program, not its children, so
# correctly built Nix programs started from it are unaffected.
#
# This reverses part of an earlier decision (README "Decisions, and why").
# For my own projects the answer is still a flake per project, and uv for
# marimo is still pointed at a Nix Python (../../home/max/core/dev.nix). What
# changed is the work repos: they pin their toolchains in mise.toml, mise
# downloads upstream builds, and those repos are not mine to convert to
# flakes. The cost is that an undeclared binary no longer fails loudly; it
# runs, outside anything Nix can see, roll back or collect.
#
# In base rather than desktop because the work repos are used under WSL too,
# where VS Code's remote server needs the same shim.
{ pkgs, ... }:
{
  programs.nix-ld = {
    enable = true;

    # Added to the module's own defaults (zlib, zstd, libstdc++, curl,
    # openssl, xz, systemd, …), which it sets as a list and so merges with
    # this one. Each entry is here because a named tool failed without it;
    # nothing is added on speculation.
    libraries = with pkgs; [
      # Playwright's Chromium and headless shell (a work repo's component
      # and e2e tests; `pnpm exec playwright install chromium`). Found
      # 2026-10-22 with `ld.so --list` against both binaries, then cut down
      # by dropping each package and keeping it only if a library went
      # missing: libdrm comes in through libgbm, and atk now ships inside
      # at-spi2-core. --list sees link-time dependencies only; whatever
      # Chromium dlopens is covered by running the tests themselves.
      glib
      nss
      nspr
      dbus
      at-spi2-core
      cups
      expat
      libxcb
      libxkbcommon
      libx11
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libgbm
      pango
      cairo
      alsa-lib

      # build123d's OpenCascade bindings (cadquery-ocp, the -novtk wheel) in
      # ~/repos/github.com/maxstreese/cad, a mise + uv repo. `import
      # build123d` failed with "libGL.so.1: cannot open shared object file"
      # (2026-11-08, z690-wsl): OCP.cpython-313-x86_64-linux-gnu.so and its
      # bundled libTKOpenGl link it, and ldd over every .so in that venv
      # found it the only library missing. With it, the repo's builds
      # (`mise run build curtain-rail`, `… door-handles`) succeed. Linked,
      # not used to draw: nothing renders, the viewer is a browser tab.
      # libglvnd's libGL, which hands any real GL call to the driver in
      # /run/opengl-driver.
      libGL
    ];
  };
}
