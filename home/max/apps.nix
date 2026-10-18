# Daily-driver applications that need an account.
#
# Nothing here carries a credential. Each signs in once through Firefox with
# the 1Password extension (see ./firefox.nix and
# ../../modules/desktop/onepassword.nix) and keeps its own session state on
# the guest disk from then on.
#
# Both packages are unfree. Home Manager cannot declare that itself here —
# with useGlobalPkgs it borrows the system's nixpkgs config — so the
# allow-list entries live next to the home-manager block in
# hosts/maxnix/configuration.nix.
{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  observability = osConfig.maxnix.observability;

  # Claude Code's OpenTelemetry export, to the local Alloy in
  # ../../modules/base/observability. A wrapper rather than session
  # variables, for two reasons: home.sessionVariables never reaches a
  # terminal here (see modules/base/default.nix), and system-wide
  # OTEL_* would redirect every program with an OpenTelemetry SDK, not just
  # this one. --set-default, so a single run can still override any of them.
  #
  # What is sent: metrics (cost, tokens, sessions, lines, edit decisions) and
  # events (each prompt, tool call, API request and error), with Bash
  # commands and file paths (OTEL_LOG_TOOL_DETAILS). Not the text of prompts
  # or responses — decided 2026-10-08; OTEL_LOG_USER_PROMPTS=1 would add it.
  #
  # Traces (beta, since 2026-10-09), into Tempo: interactive sessions root
  # each prompt in a claude_code.interaction span, with model requests and
  # tool calls under it and a tool's wait on a permission prompt as its own
  # span. `claude -p` has no interaction span; measured 2026-10-12, its
  # trace's root is the claude_code.llm_request itself.
  claudeWithTelemetry = pkgs.symlinkJoin {
    # claude-code's own pname, so the unfree allow-list entry for it (in
    # hosts/maxnix/configuration.nix, matched on pname) covers the wrapper.
    pname = "claude-code";
    inherit (pkgs.claude-code) version;
    paths = [ pkgs.claude-code ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude \
        --set-default CLAUDE_CODE_ENABLE_TELEMETRY 1 \
        --set-default OTEL_METRICS_EXPORTER otlp \
        --set-default OTEL_LOGS_EXPORTER otlp \
        --set-default OTEL_TRACES_EXPORTER otlp \
        --set-default CLAUDE_CODE_ENHANCED_TELEMETRY_BETA 1 \
        --set-default OTEL_EXPORTER_OTLP_PROTOCOL grpc \
        --set-default OTEL_EXPORTER_OTLP_ENDPOINT http://127.0.0.1:4317 \
        --set-default OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE cumulative \
        --set-default OTEL_METRIC_EXPORT_INTERVAL 10000 \
        --set-default OTEL_LOG_TOOL_DETAILS 1
    '';
    inherit (pkgs.claude-code) meta;
  };

  # mcp-grafana against the local Grafana, read-only. A separate server from
  # any other Grafana MCP already configured (a work one, say), named
  # grafana-local. Its token is issued by the machine and readable only by
  # this user; see grafana-mcp-token in modules/base/observability.
  grafanaLocalMcp = pkgs.writeShellApplication {
    name = "grafana-local-mcp";
    runtimeInputs = [ pkgs.mcp-grafana ];
    text = ''
      # localhost, not 127.0.0.1: Grafana enforces its domain (see
      # modules/base/observability).
      export GRAFANA_URL=http://localhost:3000
      export GRAFANA_SERVICE_ACCOUNT_TOKEN_FILE=${observability.mcpTokenFile}
      exec mcp-grafana --disable-write "$@"
    '';
  };
in
{
  # Registered with Claude Code at user scope, so it is there in every
  # project. Claude Code keeps its MCP servers in ~/.claude.json, a file it
  # rewrites constantly, so this cannot be a Home Manager-managed file; it is
  # added through Claude's own CLI instead, once, and left alone after.
  # Pointed at the profile's stable path, not a store path, so a rebuild does
  # not leave it dangling.
  home.activation.grafanaLocalMcp = lib.mkIf observability.enable (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      # Checked by reading ~/.claude.json, not by asking `claude mcp get`:
      # starting claude takes seconds, and this runs in home-manager-max,
      # which login waits for — it put 2.5 s on every boot (2026-10-09).
      # claude itself only runs when the server is actually missing,
      # bounded so one that tries the network offline cannot hang it.
      if ! ${pkgs.jq}/bin/jq -e '.mcpServers["grafana-local"]' "$HOME/.claude.json" >/dev/null 2>&1; then
        run ${pkgs.coreutils}/bin/timeout 30 ${pkgs.claude-code}/bin/claude mcp add --scope user grafana-local \
          -- ${config.home.profileDirectory}/bin/grafana-local-mcp \
          || warnEcho "could not register the grafana-local MCP server with Claude Code"
      fi
    ''
  );

  home.packages =
    lib.optional observability.enable grafanaLocalMcp
    ++ (with pkgs; [
      # Spotify's Linux client is Chromium-based. It runs natively on Wayland
      # when NIXOS_OZONE_WL=1 is in the environment, which the desktop layer
      # sets; without it, it falls back to XWayland. First start: "Log in with
      # browser" hands the login to Firefox. State lands in ~/.config/spotify.
      spotify

      # Claude Code, the `claude` CLI. First run: `claude` opens the browser
      # for OAuth against the same Claude account as the web app. The resulting
      # token is kept in ~/.claude, since Linux gets no keychain integration.
      # An API key via `op read` works too, if that is ever preferred.
      # Wrapped to send telemetry when the observability stack is on (above).
      (if observability.enable then claudeWithTelemetry else claude-code)

      # Slack. Electron, so it follows NIXOS_OZONE_WL onto Wayland like the
      # others. Sign-in is the usual workspace URL and email link, handled in
      # Firefox; the session then lives in ~/.config/Slack.
      slack

      # Discord, also Electron. Home Manager has a programs.discord module,
      # unused on purpose: all it adds is writing settings.json, and Discord
      # rewrites that file itself — the same fight the greeter's colour file
      # lost. The package alone is what is wanted.
      discord

      # No account needed for these two; they sit here as the other desktop
      # applications.
      obs-studio
      gimp
    ]);
}
