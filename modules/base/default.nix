# The base role: what is true of the user and the system on every machine
# this repo describes, whatever its hardware or whether it has a desktop.
#
# A host imports this together with the other roles it needs (flake.nix);
# what is only true of one machine stays in hosts/<name>. The modules imported
# here define options and switch nothing on by themselves unless their own
# comments say so; this file sets what is on everywhere.
{ pkgs, ... }:
{
  imports = [
    ./containers.nix
    ./dev.nix
    ./login-limits.nix
    ./observability
  ];

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  # ── Keyboard layout, in two independent places ───────────────────────────
  #
  # These are not the same mechanism and neither implies the other:
  #
  #   console.keyMap       the Linux virtual console — the TTY, and therefore
  #                        the greeter. Applied by loadkeys via
  #                        /etc/vconsole.conf.
  #   XKB_DEFAULT_LAYOUT   Wayland sessions. Compositors receive raw evdev
  #                        keycodes and map them through libxkbcommon, which
  #                        reads this variable. They never consult the console
  #                        keymap. Without it you get libxkbcommon's built-in
  #                        default, "us" — so the greeter was German and the
  #                        session was American.
  #
  # services.xserver.xkb.layout deliberately does NOT appear here. It is the
  # conventional NixOS spelling and it would do nothing: XKB_DEFAULT_LAYOUT
  # appears nowhere in the NixOS module tree, and programs.niri does not read
  # services.xserver.xkb. Setting it alone evaluates
  # fine and leaves you on "us".
  #
  # This reaches the compositor because sessionVariables are written to
  # /etc/pam/environment, which pam_env applies in greetd's PAM session.
  #
  # It is a *default*, and only compositors that leave the layout unset will
  # consult it. niri does, and reports "German"; Hyprland, while it ran here,
  # did not (its kb_layout defaults to "us"). home/max/niri.nix states the
  # layout anyway, reading it back from this option, so the layout is still
  # defined in exactly one place.
  #
  # Add XKB_DEFAULT_VARIANT / _OPTIONS here too if you ever want e.g.
  # nodeadkeys — your host currently sets neither.
  console.keyMap = "de";
  environment.sessionVariables.XKB_DEFAULT_LAYOUT = "de";

  users.users.max = {
    isNormalUser = true;
    description = "Max";
    extraGroups = [ "wheel" ];
  };

  # No console autologin, deliberately (decided 2026-09-17). The text
  # consoles on Ctrl+Alt+F2…F6 keep their password prompt, and that is the
  # rescue path if the graphical greeter ever fails to draw: it needs working
  # GL, a TTY does not (see ../../modules/desktop/greeter.nix). Autologin
  # would have made the lock screen decorative — anyone at the keyboard, two
  # keystrokes, the whole session; and in the VMs, whose sudo asks for no
  # password (../../modules/vm/qemu-guest.nix), a root shell too.

  # The machine needs flakes so it can rebuild itself from a clone of this
  # repo. In the VM, `rebuild` (../../hosts/maxnix/vm.nix) activates the result without a
  # reboot; on metal it is plain nixos-rebuild.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Keeping the store from growing without bound.
  #
  # Nix never overwrites: every rebuild writes new store paths and leaves the
  # old ones alone. What keeps them alive is the system profile, which retains
  # every generation you have activated — that retention is exactly what makes
  # `nixos-rebuild --rollback` and the boot menu work. So the store grows with
  # every rebuild and nothing shrinks it unless asked.
  #
  # The measurements this is sized against: one system closure here is 12.5
  # GiB, and the Ubuntu host's hand-managed store had reached 60 GB by the
  # time this was written.
  # Monday 09:00 rather than the small hours, on purpose.
  #
  # Both timers are Persistent (the NixOS default, and it is what you want):
  # systemd records the last run, so a trigger missed while the machine was
  # off fires shortly after the next boot instead of being skipped — given
  # that the record survives the root wipe, which is why ../metal/persistence.nix
  # preserves /var/lib/systemd/timers. The
  # consequence is that scheduling this for 03:15 on a Sunday — which looks
  # considerate — means a machine that sleeps at night never runs it *then*
  # and instead runs it at Monday's first boot, with no jitter
  # (randomizedDelaySec defaults to "0" for the collector), i.e. the moment
  # you open the lid.
  #
  # Picking an hour the machine is plausibly already awake makes the timer
  # fire when it says it will. The cost is that it runs during working hours;
  # the collection is mostly I/O and the optimiser is deferred 90 minutes so
  # the two never overlap.
  nix.gc = {
    automatic = true;
    dates = "Mon 09:00";
    # Without this the collection only removes what nothing points at —
    # build leftovers and old nix-shell inputs — and never touches a
    # generation, which is where the space actually is. This deletes
    # generations older than 30 days *first*, un-rooting their closures so
    # they become collectable.
    #
    # 30 days is a deliberate trade, not a default: those generations are
    # what you roll back *to*, and on a machine changed as often and as
    # experimentally as this one, that history is the safety net. A month of
    # it costs little on a real disk.
    options = "--delete-older-than 30d";
  };

  # Deduplicates the store by replacing byte-identical files across different
  # paths with hardlinks; typically reclaims 25-35%.
  #
  # Scheduled 90 minutes after the collection above, on purpose: running it
  # afterwards means it only hardlinks paths that survived, instead of doing
  # that work for paths about to be deleted. This one already carries 30
  # minutes of jitter by default (randomizedDelaySec = "1800").
  #
  # The alternative is nix.settings.auto-optimise-store, which does the same
  # deduplication inline as each path is added. That spreads the cost across
  # every build rather than concentrating it in one timer; this way round the
  # cost is predictable and off-peak.
  nix.optimise = {
    automatic = true;
    dates = [ "Mon 10:30" ];
  };

  # Environment for the *user* layer that can only be set here.
  #
  # marimo checks PyPI on startup and nags when it is behind, which on a
  # Nix-installed package is advice that cannot be followed: the store path
  # is immutable and the version is whatever the pinned nixpkgs carries.
  # ../../home/max/dev.nix explains the lag.
  #
  # This looks like it belongs in the user layer, and Home Manager's
  # home.sessionVariables is the obvious option — but that option means
  # exactly what it says, "set at login", and lands in a file only
  # ~/.profile sources. A terminal window is an interactive shell, and under
  # Wayland nothing sources a profile, so the variable would be set where
  # nobody looks. Measured in the guest: present under `bash -l`, absent
  # under `bash -i`, absent from the systemd user environment.
  #
  # sessionVariables here goes through /etc/pam/environment instead, which
  # pam_env applies to the whole session — including the systemd *user*
  # manager, and therefore every app it starts, ghostty among them. Verified
  # the same way XKB_DEFAULT_LAYOUT was, which travels this exact route.
  environment.sessionVariables.MARIMO_SKIP_UPDATE_CHECK = "1";

  # Home Manager as a NixOS module, so one `nix build` rebuilds the machine and
  # the user layer together into a single generation — no separate
  # `home-manager switch`. Which user layer a machine gets is the host's choice
  # (hosts/maxnix/configuration.nix); the layer itself lives in ../../home/max.
  home-manager = {
    # Use the system's pkgs and nixpkgs config rather than a second instance.
    useGlobalPkgs = true;
    # Install user packages into the system profile instead of
    # ~/.nix-profile, which keeps them inside the generation.
    useUserPackages = true;

    # niri had already written a real ~/.config/niri/config.kdl (and
    # Hyprland its own config, back when it ran here) inside this VM's disk
    # image. Home Manager refuses to clobber existing regular files,
    # so without this the very first activation fails with a confusing error.
    # With it, they are renamed aside — which is also a neat demonstration of
    # the imperative state this whole layer exists to replace.
    backupFileExtension = "hm-bak";
  };

  environment.systemPackages = with pkgs; [
    git
    htop
    vim

    # Diffs two system generations by store path: what was added, removed or
    # version-bumped. Both rebuild paths print one before activating, and it
    # is on PATH so a generation can be compared against any other after the
    # fact — `nvd diff /run/booted-system /run/current-system` being the one
    # worth knowing, which says what has changed since this boot.
    nvd

    # The machine as SQL tables: processes, packages, mounts, users, open
    # sockets. `sudo osqueryi`, since many tables need root. It is also what
    # the employer's Fleet asks its questions with (../metal/fleet.nix), so e.g.
    # `select * from disk_encryption;` answers the LUKS check the way Fleet
    # will — on metal only, as every VM path has an unencrypted root. The
    # agent brings its own copy; this one is for asking by hand.
    osquery
  ];

  # The machine observing itself: metrics, logs, Grafana, and Claude Code's
  # telemetry. See ./observability. Needs no secret, so on everywhere,
  # metal and every test node alike.
  maxnix.observability.enable = true;
}
