# Everything this host takes from Windows, in one place.
#
# The rule (README, "Decisions, and why", decided 2026-11-07): the guest is
# self-contained by default, and always for credentials and dev tooling. It
# may use an interface Windows or WSL itself guarantees, never software or
# settings installed by hand on the Windows side, and each such use is
# declared here so it stays visible, named and removable. 1Password is the
# case that fell on the other side: its Windows CLI and agent are installed
# and switched on by hand, so the app runs in the guest instead
# (./default.nix, ../../modules/gui).
#
# What is taken, and why each passes:
#
#   WSLg        the display. Every GUI app here draws through it (the
#               1Password service in ./default.nix uses its X server).
#               Ships with WSL.
#   GPU driver  /usr/lib/wsl/lib, below. Ships with the Windows NVIDIA
#               driver, which the hardware needs anyway.
#   URLs        opened in the default Windows browser, below. Uses only
#               rundll32.exe, part of every Windows install, and nothing
#               about which browser it is.
#
# Only the URL opener goes through interop, Windows binaries launched from
# the guest; WSLg and the GPU driver are Linux-side (a socket, and libraries
# that talk to /dev/dxg). Interop stays on (decided 2026-11-07, README
# "Decisions, and why"): turning it off (wsl.wslConf.interop.enabled = false)
# would close the path by which anything in the guest can run code as max on
# Windows, but Windows Terminal and the Windows browser stay in daily use
# either way, and it would take the URL opener with it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  windows = "${config.wsl.wslConf.automount.root}/c/Windows";

  # rundll32's FileProtocolHandler hands the URL to Windows' own handler for
  # its scheme, the default browser for http(s). Preferred over the other
  # common way, `explorer.exe <url>`: explorer exits 1 even on success, and
  # cmd.exe's `start` mangles URLs with `&` in them.
  #
  # URLs only, deliberately. This is registered for http/https alone, so
  # xdg-open never routes a local file here; the check keeps anything else
  # that calls BROWSER from handing Windows a path or a command line.
  open-in-windows = pkgs.writeShellApplication {
    name = "open-in-windows";
    text = ''
      if [ "$#" -ne 1 ]; then
        echo "usage: open-in-windows <http(s) URL>" >&2
        exit 2
      fi
      case "$1" in
        http://* | https://*) ;;
        *)
          echo "open-in-windows: only http(s) URLs, not: $1" >&2
          exit 2
          ;;
      esac
      rundll32=${lib.escapeShellArg "${windows}/System32/rundll32.exe"}
      if [ ! -x "$rundll32" ]; then
        echo "open-in-windows: $rundll32 not found; is C: mounted and interop on?" >&2
        exit 1
      fi
      exec "$rundll32" url.dll,FileProtocolHandler "$1"
    '';
  };
in
{
  # The GPU reaches WSL by paravirtualisation, not passthrough: the Windows
  # NVIDIA driver puts its user-space half (libcuda, libd3d12, nvidia-smi)
  # under /usr/lib/wsl/lib, and no Linux NVIDIA driver is installed. This
  # links those into hardware.graphics, i.e. /run/opengl-driver/lib, where
  # Nix-built CUDA and Mesa programs look. Wanted for GPU compute from Java
  # (TornadoVM's PTX backend) on the RTX 3080 Ti; docs/desktop-pc.md
  # section 3. Linked and present in the guest (2026-11-07).
  wsl.useWindowsDriver = true;

  # Nothing finds those libraries by itself, though. Mesa's Vulkan driver
  # for WSL (dzn) and its d3d12 GL driver load libd3d12.so by name at run
  # time, and the driver's own binaries (nvidia-smi) are generic-Linux ELFs
  # going through nix-ld; neither searches /run/opengl-driver/lib or
  # /usr/lib/wsl/lib. Found 2026-11-07: Vulkan saw only llvmpipe, so
  # herdr-desktop drew on the CPU, and nvidia-smi could not find
  # libnvidia-ml.so. With /usr/lib/wsl/lib on the library path, vulkaninfo
  # lists "Microsoft Direct3D12 (NVIDIA GeForce RTX 3080 Ti)" and nvidia-smi
  # runs. Ubuntu under WSL gets the same from /etc/ld.so.conf.d/ld.wsl.conf,
  # which Nix's glibc does not read; LD_LIBRARY_PATH is the equivalent, and
  # nix-ld adds its own path to it, so one variable serves both. The
  # directory holds the Windows driver's libraries only (libd3d12, libdxcore,
  # libcuda, NVIDIA's own), not Mesa's, so it shadows nothing a program
  # brings itself. Also the path a JDK or TornadoVM finds libcuda by.
  environment.sessionVariables.LD_LIBRARY_PATH = [ "/usr/lib/wsl/lib" ];

  # Links open in the browser already on the Windows desktop, rather than a
  # second one under WSLg with its own sign-ins (docs/desktop-pc.md,
  # section 3). Two routes in, both to the same script: BROWSER, which gh,
  # Claude Code and most CLI tools read, and xdg-open's handler for
  # http(s), which GUI apps such as 1Password go through. Without either,
  # `gh auth login` and Claude Code's sign-in found no browser at all
  # (first boot, 2026-11-07). Both routes confirmed in the guest the same
  # day: `xdg-open https://github.com` and `gh auth login` open the Windows
  # browser.
  home-manager.users.max = {
    home.packages = [
      open-in-windows
      pkgs.xdg-utils
    ];

    home.sessionVariables.BROWSER = "open-in-windows";

    xdg.desktopEntries.open-in-windows = {
      name = "Open in Windows";
      comment = "Open a web link in the default Windows browser";
      exec = "open-in-windows %u";
      mimeType = [
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ];
      noDisplay = true;
    };

    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "x-scheme-handler/http" = "open-in-windows.desktop";
        "x-scheme-handler/https" = "open-in-windows.desktop";
      };
    };
  };
}
