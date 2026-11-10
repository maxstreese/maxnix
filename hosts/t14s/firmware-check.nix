# Asks fwupd whether firmware updates exist and, if so, says so with a desktop
# notification. It reports and nothing more: installing is `fwupdmgr update`
# and a reboot, by hand (./laptop.nix has why and the timer that runs this).
#
# A package function so the test can build it around stand-ins for fwupdmgr
# and notify-send (tests/niri.nix): the VM has no firmware devices and no way
# to the LVFS, and what can go wrong here is reading fwupdmgr's answers.
{
  writeShellApplication,
  fwupd,
  libnotify,
  jq,
}:
writeShellApplication {
  name = "firmware-check";
  runtimeInputs = [
    fwupd
    libnotify
    jq
  ];
  text = ''
    # New metadata from the LVFS. Exit 2 is fwupdmgr's "nothing to do" (the
    # metadata is recent enough); anything else, offline included, is not a
    # reason to stop: get-updates below then answers from what was fetched
    # last time.
    status=0
    fwupdmgr refresh >/dev/null || status=$?
    if [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; then
      echo "fwupdmgr refresh failed ($status), going on with the metadata there is" >&2
    fi

    # Exit 2 again means no device has an update. --no-unreported-check keeps
    # it from asking whether to upload the report of an earlier update, which
    # nobody is there to answer.
    status=0
    updates=$(fwupdmgr get-updates --json --no-unreported-check) || status=$?
    if [ "$status" -eq 2 ]; then
      echo "no firmware updates"
      exit 0
    elif [ "$status" -ne 0 ]; then
      echo "fwupdmgr get-updates failed ($status)" >&2
      exit "$status"
    fi

    # One line per device, installed version to newest (fwupd lists releases
    # newest first; seen on a ThinkPad with fwupd 2.0, 2026-11-10).
    summary=$(jq -r '
      .Devices[]?
      | select((.Releases // []) | length > 0)
      | "\(.Name): \(.Version) → \(.Releases[0].Version)"
    ' <<<"$updates")
    if [ -z "$summary" ]; then
      echo "no firmware updates"
      exit 0
    fi
    echo "$summary"

    # Critical, so it stays until dismissed. Retried for five minutes: a
    # timer that fires as the session starts can be ahead of the shell that
    # shows notifications, and one that is missed is not repeated for a week.
    for _ in $(seq 10); do
      if notify-send --urgency=critical --app-name="Firmware" \
        "Firmware updates available" \
        "$summary"$'\n\n'"Install with: fwupdmgr update"; then
        exit 0
      fi
      sleep 30
    done
    echo "could not show the notification" >&2
    exit 1
  '';
}
