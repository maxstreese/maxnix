# Agent of Empires (`aoe`), a tmux-based session manager for coding agents.
#
# From upstream's release binary, not built from source. nixpkgs does not
# carry aoe, and the first attempt here took it from upstream's own flake
# (2026-10-01 to 10-06). A flake like that is a build recipe, a Rust build in
# this case, and nothing serves its result: cache.nixos.org holds what
# nixpkgs builds, and upstream runs no cache. A GitHub runner starts with an
# empty store, so CI compiled aoe on every run, about 35 minutes of each
# (54 and 59 minutes with it, 20 and 21 without; README "Findings worth
# keeping").
#
# Every release ships a tarball per platform with its SHA-256 beside it, and
# that is what this unpacks. The binary is an ordinary glibc one needing
# zlib and libgcc, which autoPatchelfHook points at the store. A download and
# a patch, seconds either way.
#
# What that gives up: this runs what upstream's release pipeline built, not
# what these machines would build from the tagged source. The same footing
# as the other prebuilt programs here (1Password, Slack, Claude Code), and it
# runs as max, never as root. Pinned by hash, so it is the same bytes until
# the pin moves.
#
# The version and hash are in ./aoe.json so Renovate can maintain them: a
# regex manager bumps the version from upstream's GitHub releases, then
# ../../../scripts/renovate-aoe-rehash rewrites the hash (renovate.jsonc).
#
# aoe runs its sessions inside tmux, which ./dev.nix installs.
{ lib, pkgs, ... }:
let
  pin = builtins.fromJSON (builtins.readFile ./aoe.json);

  aoe = pkgs.stdenv.mkDerivation {
    pname = "aoe";
    inherit (pin) version;

    src = pkgs.fetchurl {
      url = "https://github.com/agent-of-empires/agent-of-empires/releases/download/v${pin.version}/aoe-linux-amd64.tar.gz";
      inherit (pin) hash;
    };
    # The tarball has no top-level directory.
    sourceRoot = ".";

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [
      pkgs.zlib
      pkgs.stdenv.cc.cc.lib
    ];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 aoe-linux-amd64 $out/bin/aoe
      install -Dm644 LICENSE THIRD_PARTY_NOTICES.md -t $out/share/doc/aoe
      cp -r licenses $out/share/doc/aoe/
      runHook postInstall
    '';

    # That the patched binary starts at all, and is the release the pin
    # names: a missing library would otherwise show only when aoe is run.
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      $out/bin/aoe --version | grep -F ${lib.escapeShellArg pin.version}
      runHook postInstallCheck
    '';

    meta = {
      description = "Session manager for coding agents, on tmux";
      homepage = "https://github.com/agent-of-empires/agent-of-empires";
      license = lib.licenses.mit;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "x86_64-linux" ];
      mainProgram = "aoe";
    };
  };
in
{
  home.packages = [ aoe ];
}
