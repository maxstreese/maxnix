# Shared test-script prelude: screenshotting the guest over VNC.
#
# The driver's own machine.screenshot() cannot be used here. It goes through
# QEMU's screendump, which fails with "Error: no surface" whenever the guest
# renders through GL, because a GL scanout is a dmabuf rather than a
# CPU-readable surface. VNC's readback path handles it fine, which is why
# modules/vm/qemu-guest.nix runs a loopback VNC server.
#
# Same reason enableOCR is left off in these tests: get_screen_text() and
# wait_for_text() are built on screendump too.
{ hostPkgs }:
''
  import subprocess
  from pathlib import Path

  VNCDOTOOL = "${hostPkgs.vncdotool}/bin/vncdotool"
  MAGICK = "${hostPkgs.imagemagick}/bin/magick"
  VNC_ADDR = "localhost::5909"


  def vnc_capture(machine, name):
      """Screenshot the guest over VNC into the driver's output directory."""
      path = Path(machine.out_dir) / (name + ".png")
      subprocess.run(
          [VNCDOTOOL, "-s", VNC_ADDR, "capture", str(path)],
          check=True,
          timeout=120,
      )
      machine.log(f"captured {path} ({path.stat().st_size} bytes)")
      return path


  def unique_colours(path):
      """How many distinct colours the image contains.

      File size is not a usable proxy for "something was drawn". An empty
      Hyprland workspace is solid black at 1920x1080 and still produces a 6 KB
      PNG — comfortably past any size threshold, while showing nothing. Counting
      colours distinguishes "rendered a blank desktop" from "rendered a desktop
      with a window on it".
      """
      out = subprocess.run(
          [MAGICK, "identify", "-format", "%k", str(path)],
          check=True,
          capture_output=True,
          text=True,
          timeout=60,
      )
      return int(out.stdout.strip())
''
