# Claude Code, and what ties it to this machine: telemetry into the local
# observability stack, and the grafana-local MCP server.
#
# Unfree: the allow-list entry is in ../../../modules/base/default.nix, next to
# where this layer is imported. Home Manager cannot declare it itself — with
# useGlobalPkgs it borrows the system's nixpkgs config.
{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  observability = osConfig.maxnix.observability;

  # Claude Code's OpenTelemetry export, to the local Alloy in
  # ../../../modules/base/observability. A wrapper rather than session
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
    # modules/base/default.nix, matched on pname) covers the wrapper.
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

  # mcp-grafana against the local Grafana, with its write tools: the token
  # is an Editor's, so the agent can build dashboards to iterate on before
  # grafana-capture puts them in the repo (modules/base/observability,
  # grafana-mcp-token, for why Editor and not more). A separate server from
  # any other Grafana MCP already configured (a work one, say), named
  # grafana-local (plugin:hm:grafana-local in Claude Code, see below). Its token is issued by the machine and readable only by
  # this user; see grafana-mcp-token in modules/base/observability.
  grafanaLocalMcp = pkgs.writeShellApplication {
    name = "grafana-local-mcp";
    runtimeInputs = [ pkgs.mcp-grafana ];
    text = ''
      # localhost, not 127.0.0.1: Grafana enforces its domain (see
      # modules/base/observability).
      export GRAFANA_URL=http://localhost:3000
      export GRAFANA_SERVICE_ACCOUNT_TOKEN_FILE=${observability.mcpTokenFile}
      exec mcp-grafana "$@"
    '';
  };
in
{
  # Through Home Manager's programs.claude-code since 2026-11-10, so MCP
  # servers, settings, skills and the rest of ~/.claude can be declared here.
  programs.claude-code = {
    enable = true;

    # Claude Code, the `claude` CLI. First run: `claude` opens the browser
    # for OAuth against the same Claude account as the web app. The resulting
    # token is kept in ~/.claude, since Linux gets no keychain integration.
    # An API key via `op read` works too, if that is ever preferred.
    # Wrapped to send telemetry when the observability stack is on (above).
    package = if observability.enable then claudeWithTelemetry else pkgs.claude-code;

    # ~/.claude/settings.json stays a writable file that `settings` (none
    # declared yet) is merged into on activation, rather than a read-only
    # store symlink: /config and "always allow" on a permission prompt write
    # there. Declared keys win, arrays whole (a declared permissions.allow
    # drops what Claude added since); a key no longer declared stays in the
    # file until deleted by hand.
    mutableSettings = true;

    # Not in ~/.claude.json, which Claude Code rewrites constantly: the
    # module writes these into a plugin of its own, named `hm`, in the store
    # and linked into ~/.claude/skills. So the server shows up as
    # plugin:hm:grafana-local and its tools as mcp__plugin_hm_grafana-local__*,
    # in every project, and a rebuild changes or removes it.
    mcpServers = lib.mkIf observability.enable {
      grafana-local.command = lib.getExe grafanaLocalMcp;
    };
  };

  # Until 2026-11-10 the server was registered once through `claude mcp add
  # --scope user`, which left an entry in ~/.claude.json pointing at
  # ~/.nix-profile/bin/grafana-local-mcp. That path is gone now, so the entry
  # would show as a second, failing grafana-local. Removed here, once; delete
  # this block when the VM and z690-wsl have both activated past it.
  home.activation.grafanaLocalMcpLegacy = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Checked by reading ~/.claude.json, not by asking `claude mcp get`:
    # starting claude takes seconds, and this runs in home-manager-max,
    # which login waits for — it put 2.5 s on every boot (2026-10-09).
    # claude itself only runs when the entry is actually there, bounded so
    # one that tries the network offline cannot hang it.
    if ${pkgs.jq}/bin/jq -e '.mcpServers["grafana-local"]' "$HOME/.claude.json" >/dev/null 2>&1; then
      run ${pkgs.coreutils}/bin/timeout 30 ${pkgs.claude-code}/bin/claude mcp remove --scope user grafana-local \
        || warnEcho "could not remove the old grafana-local MCP server from ~/.claude.json"
    fi
  '';
}
