# Claude Desktop, Anthropic's desktop app: Chat and Code, and the host for
# trying local MCP servers and MCP Apps against the real client.
#
# From Anthropic's own .deb, repacked here (2026-11-23). The Linux build is a
# beta that Anthropic ships for Debian and Ubuntu only, through an apt
# repository; nixpkgs does not carry it (three pull requests open, the newest
# NixOS/nixpkgs#587988; docs/blocked.toml watches for it). What the .deb holds
# is an ordinary Electron application, so the recipe is the one nixpkgs uses
# for Slack: unpack, point the binaries at the store, wrap.
#
# Not a flake input, although two community flakes package the same .deb. The
# first looked at had been stuck for eight weeks at a version four majors old,
# its update job failing since August. The second was current, and its recipe
# is what this one started from (github:tomsch/claude-desktop-nix, MIT). But
# a recipe taken as an input can change in any way at each lock refresh, by
# one author, unreviewed, and the closure diff on the lock PR shows only the
# version: this is the wrapper that starts an app holding the Claude login, as
# max. Kept here, a bump changes two values in ./claude-desktop.json, and the
# bytes are Anthropic's, by hash, from Anthropic's server. The same footing as
# ../core/aoe.nix, and the same price: when a release needs a library this
# does not name, the fix is made here. autoPatchelfHook fails the build when
# that happens, so it shows in CI and not at the first start.
#
# What differs from that recipe:
#
#   - Chromium's sandbox is on. It passed --no-sandbox, reasoning that the
#     setuid helper cannot work from the Nix store. True of the helper, which
#     is why it is deleted below; but Chromium prefers the user-namespace
#     sandbox anyway, which is also what Anthropic's package arranges on
#     Ubuntu (its postinst writes an AppArmor profile "so Chromium's namespace
#     sandbox works"). NixOS allows unprivileged user namespaces as it comes.
#     Checked in the guest: the renderers sit in their own user, PID and
#     network namespaces under seccomp (README "Findings worth keeping").
#   - Libraries are found through the binaries' RUNPATH, not LD_LIBRARY_PATH.
#     The app starts other programs (Claude Code, local MCP servers through
#     npx or uvx), and a variable in its environment is one in theirs.
#   - Wayland follows NIXOS_OZONE_WL, as for the other Electron apps in
#     ./apps.nix, where it hard-coded the platform.
#
# Unfree; the allow-list entry is in ../../../modules/desktop/default.nix.
#
# The version and hash are in ./claude-desktop.json so Renovate can maintain
# them: a regex manager reads the newest version from Anthropic's apt index,
# then ../../../scripts/renovate-claude-desktop-rehash takes that version's
# SHA-256 from the same index (renovate.jsonc). Releases come about every two
# days, so the bump rides in the one PR for all version bumps.
#
# Sign-in goes through the browser, by xdg-open. The app narrows PATH for
# what it starts to system directories, so the browser has to be in the
# system profile for the default to be honoured: see the Firefox line in
# ../../../modules/desktop/default.nix. It comes back as a claude:// link,
# which the desktop file below registers; `nix run` of a bare package has no
# such entry and the login never returns (tried on the Ubuntu host). At each
# start the app also tries to claim that scheme by writing mimeapps.list,
# which Home Manager keeps in the store: one "Read-only file system" line in
# its log, harmless, since the profile's mimeinfo.cache lists this desktop
# file as the only handler (as long as nothing hides it, see the wrapper
# below). The session is kept through the Secret Service, which is
# gnome-keyring here (../../../modules/desktop/default.nix). State lands in
# ~/.config/Claude, including claude_desktop_config.json where local MCP
# servers are listed: undeclared on purpose, the app rewrites it itself.
#
# Cowork runs in Anthropic's cloud and works through this package as it is.
# The virtual machine it uses to run commands on this machine needs QEMU,
# firmware and virtiofsd at Debian's paths, which is the system's to give:
# ../../../modules/desktop/claude-cowork.nix.
{ lib, pkgs, ... }:
let
  pin = builtins.fromJSON (builtins.readFile ./claude-desktop.json);

  claude-desktop = pkgs.stdenv.mkDerivation {
    pname = "claude-desktop";
    inherit (pin) version;

    src = pkgs.fetchurl {
      url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${pin.version}_amd64.deb";
      inherit (pin) hash;
    };

    nativeBuildInputs = with pkgs; [
      dpkg
      autoPatchelfHook
      makeWrapper
    ];

    # What the binaries link against. autoPatchelfHook resolves each NEEDED
    # entry from these and fails the build on one it cannot find.
    buildInputs = with pkgs; [
      alsa-lib
      at-spi2-atk
      at-spi2-core
      atk
      cairo
      cups
      dbus
      expat
      gdk-pixbuf
      glib
      # Also what sets GSETTINGS_SCHEMAS_PATH for the wrapper below.
      gtk3
      libdrm
      libgbm
      libxkbcommon
      nspr
      nss
      pango
      # Only the virtiofsd in resources/ wants these two, and only Cowork
      # runs it. Named all the same: the alternative is telling the hook to
      # ignore missing libraries, which is the check this build relies on.
      libcap_ng
      libseccomp
      # claude-native-binding.node links libpipewire since 3.x.
      pipewire
      stdenv.cc.cc.lib
      systemdLibs
      libx11
      libxcb
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libxshmfence
    ];

    # What Chromium opens by name at run time, which no NEEDED entry shows:
    # GL, udev, the Secret Service client the login is stored through,
    # notifications, the tray icon, audio and Wayland. autoPatchelfHook adds
    # these to the executables' RUNPATH.
    runtimeDependencies = map lib.getLib (
      with pkgs;
      [
        libGL
        libayatana-appindicator
        libnotify
        libpulseaudio
        libsecret
        systemdLibs
        wayland
      ]
    );

    # dpkg-deb -x would restore the setuid bit on chrome-sandbox, which the
    # build sandbox refuses; through tar the permissions can be left behind.
    unpackPhase = ''
      runHook preUnpack
      dpkg-deb --fsys-tarfile $src | tar --no-same-permissions --no-same-owner -x
      runHook postUnpack
    '';

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib $out/bin $out/share
      cp -r usr/lib/claude-desktop $out/lib/claude-desktop
      cp -r usr/share/applications usr/share/icons $out/share/

      # The setuid helper of Chromium's older sandbox. Nothing in the store
      # can be setuid, so it could only ever fail; without it Chromium has
      # the user-namespace sandbox and nothing else to try.
      rm $out/lib/claude-desktop/chrome-sandbox

      # The .mcpb, .dxt and .skill types the desktop file claims, which the
      # .deb's postinst copies into place on Debian.
      install -Dm644 usr/lib/claude-desktop/resources/linux-mime/com.anthropic.Claude.xml \
        -t $out/share/mime/packages

      runHook postInstall
    '';

    # xdg-open is how the app hands the sign-in to the browser. Suffixed, so
    # the session's own comes first where there is one.
    #
    # The schemas are for GTK's file dialogs, and are all this adds to
    # XDG_DATA_DIRS. Not wrapGAppsHook3, which would also prepend this
    # package's own share/: the browser the app starts inherits the app's
    # environment, and with that directory in front the sign-in never came
    # back (2026-11-24). GIO takes a desktop entry from the first directory
    # that has it and its MIME types from that directory's mimeinfo.cache; a
    # package has no such cache, only a profile does, so the entry found
    # first claimed nothing and hid the indexed one behind it. `gio mime
    # x-scheme-handler/claude` with Firefox's environment said "No default
    # applications", and the app's own log called its handler "shadowed".
    #
    # --password-store names the Secret Service outright. Chromium picks its
    # secret storage from the desktop's name, does not know niri, and falls
    # back to none; the app then warns "No system keyring is available" and
    # forgets the sign-in at every start, with gnome-keyring running and
    # unlocked beside it (2026-11-24).
    #
    # The NIXOS_OZONE_WL line is nixpkgs' convention for Electron programs,
    # without --ozone-platform-hint, which this Electron (45) no longer has.
    # It is shell, expanded when the app starts, so the wrapper has to be a
    # script: makeWrapper's, not makeBinaryWrapper's.
    postFixup = ''
      makeWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
        --prefix XDG_DATA_DIRS : "$GSETTINGS_SCHEMAS_PATH" \
        --suffix PATH : ${lib.makeBinPath [ pkgs.xdg-utils ]} \
        --add-flags "--password-store=gnome-libsecret" \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

      # All three Exec lines: the entry itself and its New Chat and New
      # Claude Code Session actions.
      substituteInPlace $out/share/applications/com.anthropic.Claude.desktop \
        --replace-fail "Exec=claude-desktop" "Exec=$out/bin/claude-desktop"
    '';

    meta = {
      description = "Anthropic's desktop app for Claude (Linux beta)";
      homepage = "https://claude.com/download";
      license = lib.licenses.unfree;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "claude-desktop";
    };
  };
in
{
  home.packages = [ claude-desktop ];
}
