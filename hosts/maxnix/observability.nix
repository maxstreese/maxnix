# The machine observing itself: metrics, logs and (later) traces and
# profiles, kept for months to years, for a person or an agent to dig into.
#
# ── Shape ────────────────────────────────────────────────────────────────
#
#   Claude Code ─OTLP─┐
#   journald ─────────┤               ┌─ remote write ─► Prometheus  :9090
#   node_exporter* ───┼─► Alloy ──────┤
#                     │   OTLP :4317  └─ OTLP / push ─► Loki        :3100
#                     │        :4318                         ▲
#   (* built into Alloy)  UI   :12345      Grafana :3000 ────┘ ◄── mcp-grafana
#
# Everything listens on loopback only. That is the security model, not the
# firewall: ../../tests/observability.nix turns the firewall off and checks
# that nothing is reachable from another machine anyway.
#
# ── Why these pieces (decided 2026-10-08) ────────────────────────────────
#
# The comparison is in the README's decision table; the short version:
#
#   Alloy        One binary for every input planned here: OTLP, the host's
#                metrics (node_exporter is compiled in), journald, and later
#                eBPF network telemetry (beyla.ebpf) and profiling
#                (pyroscope.ebpf), both GA in Alloy where the OTel Collector's
#                equivalents are not. nixpkgs builds it with both.
#   Prometheus   Storage only — it scrapes nothing; Alloy pushes. Mimir would
#                add clustering, tenants and object storage, none of which one
#                machine needs, and the PromQL API is the same either way.
#   Loki         Weak at finding a record by an unindexed, high-cardinality
#                field such as Claude Code's session.id — but the cost of that
#                is the size of the streams a query selects, not of the store.
#                Claude Code's events arrive as their own stream
#                (service_name="claude-code", from service.name) at megabytes
#                a day, so a year of them scans quickly. Never make those IDs
#                labels; journald stays in separate streams.
#   Grafana      Dashboards, and the API mcp-grafana talks to, so an agent can
#                query everything above with PromQL and LogQL.
#
# ── Claude Code ──────────────────────────────────────────────────────────
#
# Its exporter settings are in ../../home/max/apps.nix, as a wrapper around
# the `claude` binary rather than session variables: OTEL_* in the session
# would redirect every program with an OpenTelemetry SDK, not just this one.
# Its counters are set to cumulative there. Prometheus rejects OTLP deltas
# without an experimental flag, and on delta data the rate() an agent reaches
# for first gives wrong answers.
#
# ── Grafana: who can do what ─────────────────────────────────────────────
#
# Anonymous visitors are Viewers: browsing needs no login. Editing does — as
# admin, with a password generated on this machine at first start and kept
# root-only in /var/lib/grafana/admin-password (`sudo cat` it). Not sops:
# Grafana applies admin_password only when it first creates its database, so
# a value in sops would look like control over something it cannot change,
# and the password guards nothing that outlives /var/lib/grafana anyway.
# Decided 2026-10-08.
#
# enforce_domain makes Grafana answer only requests addressed to `localhost`
# and redirect everything else. Loopback stops other machines; this stops a
# web page in the local browser from reaching Grafana by DNS rebinding — a
# hostname of its own that resolves to 127.0.0.1 — and reading what an
# anonymous Viewer can, which includes Claude Code's Bash commands. So every
# URL for Grafana here is http://localhost:3000, never 127.0.0.1.
#
# ── Dashboards ───────────────────────────────────────────────────────────
#
# Plain Grafana JSON in ./dashboards, the format Grafana imports and exports,
# provisioned read-only (allowUiUpdates = false): the repo is the source of
# truth. Three ways in:
#
#   UI      log in as admin, build a dashboard, then `grafana-capture` (below)
#           writes it into the clone as JSON; review, commit, rebuild.
#   by hand edit the JSON. With maxnix.dev.liveConfig (the VM), a path unit
#           copies ./dashboards from the clone into Grafana's provisioning
#           directory on every change and Grafana rereads it within seconds —
#           no rebuild. Elsewhere the store copy is provisioned, as on metal.
#
#           Only while the clone has that directory. The guest's clone is its
#           own checkout and lags whatever the host deployed until it pulls;
#           without the directory (a fresh VM, a clone from before
#           2026-10-09) the deployed store copy is used instead, so a deploy
#           from the host never leaves Grafana empty. Once the directory is
#           there, the clone wins outright, deletions included — the same
#           rule as liveConfig for Quickshell.
#   agent   Claude Code queries real metric and label names through
#           grafana-local (read-only) and edits the JSON, same live loop.
#
# ── State ────────────────────────────────────────────────────────────────
#
# /var/lib/{prometheus2,loki,grafana} and Alloy's /var/lib/private/alloy (its
# journal read position and remote-write WAL) are on /persist
# (./persistence.nix) and excluded from backups (./backup.nix): rebuildable
# in the sense that losing them costs history, not configuration.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.maxnix.observability;

  ports = {
    prometheus = 9090;
    loki = 3100;
    lokiGrpc = 9096;
    grafana = 3000;
    otlpGrpc = 4317;
    otlpHttp = 4318;
    # Alloy's own UI, its default. Shows every component and what flows
    # between them — the first place to look when something does not arrive.
    alloy = 12345;
  };

  prometheusUrl = "http://127.0.0.1:${toString ports.prometheus}";
  lokiUrl = "http://127.0.0.1:${toString ports.loki}";
  # localhost, not 127.0.0.1: see enforce_domain above.
  grafanaUrl = "http://localhost:${toString ports.grafana}";

  alloyConfig = pkgs.writeText "config.alloy" ''
    // ── Host metrics ─────────────────────────────────────────────────────
    // node_exporter, compiled into Alloy. Prometheus-shaped names
    // (node_cpu_seconds_total, …) are what dashboards and LLMs know best.
    prometheus.exporter.unix "host" {
      // On top of the defaults: per-unit state, process counts, and
      // pressure (PSI), which shows "the machine felt slow" better than
      // utilisation does.
      enable_collectors = ["systemd", "processes", "pressure"]
    }

    prometheus.scrape "host" {
      targets         = prometheus.exporter.unix.host.targets
      forward_to      = [prometheus.remote_write.local.receiver]
      scrape_interval = "15s"
    }

    // The stack watching itself, so "why is Loki slow" has data too.
    prometheus.scrape "self" {
      targets = [
        {"__address__" = "127.0.0.1:${toString ports.alloy}",      "job" = "alloy"},
        {"__address__" = "127.0.0.1:${toString ports.prometheus}", "job" = "prometheus"},
        {"__address__" = "127.0.0.1:${toString ports.loki}",       "job" = "loki"},
        {"__address__" = "localhost:${toString ports.grafana}",    "job" = "grafana"},
      ]
      forward_to      = [prometheus.remote_write.local.receiver]
      scrape_interval = "60s"
    }

    prometheus.remote_write "local" {
      endpoint {
        url = "${prometheusUrl}/api/v1/write"
      }
    }

    // ── journald ─────────────────────────────────────────────────────────
    // Its own streams, labelled by unit, so they never sit in the way of a
    // query for Claude Code's events.
    loki.relabel "journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      rule {
        source_labels = ["__journal__systemd_user_unit"]
        target_label  = "user_unit"
      }
      rule {
        source_labels = ["__journal_priority_keyword"]
        target_label  = "level"
      }
      rule {
        source_labels = ["__journal_syslog_identifier"]
        target_label  = "identifier"
      }

      // Debug priority is the bulk of a busy journal and the least of its
      // value; it stays in journald itself for as long as journald keeps it.
      // Dropped here, on the label: loki.process's stage.drop only sees
      // values extracted from the line, so it could not do this.
      rule {
        source_labels = ["__journal_priority_keyword"]
        regex         = "debug"
        action        = "drop"
      }
    }

    loki.source.journal "journal" {
      forward_to    = [loki.write.local.receiver]
      relabel_rules = loki.relabel.journal.rules
      labels        = {"source" = "journald"}
      // How far back to read when there is no saved position — a first start,
      // or Alloy's state lost. Loki would refuse much older entries anyway.
      max_age       = "12h"
    }

    loki.write "local" {
      endpoint {
        url = "${lokiUrl}/loki/api/v1/push"
      }
    }

    // ── OTLP: Claude Code now, more later ────────────────────────────────
    otelcol.receiver.otlp "default" {
      grpc {
        endpoint = "127.0.0.1:${toString ports.otlpGrpc}"
      }
      http {
        endpoint = "127.0.0.1:${toString ports.otlpHttp}"
      }
      output {
        metrics = [otelcol.processor.batch.default.input]
        logs    = [otelcol.processor.batch.default.input]
      }
    }

    otelcol.processor.batch "default" {
      output {
        metrics = [otelcol.exporter.prometheus.local.input]
        logs    = [otelcol.exporter.otlphttp.loki.input]
      }
    }

    // Into the same remote write as the host metrics, with OTel names
    // translated the Prometheus way (dots to underscores, unit and _total
    // suffixes).
    otelcol.exporter.prometheus "local" {
      forward_to = [prometheus.remote_write.local.receiver]
    }

    // Loki's native OTLP endpoint rather than Alloy's Loki conversion: this
    // keeps every log attribute as structured metadata, queryable as a field
    // (`| session_id="…"`), and makes service.name the service_name label.
    otelcol.exporter.otlphttp "loki" {
      client {
        endpoint = "${lokiUrl}/otlp"
      }
    }
  '';

  # Validated at build time, the way the Loki module validates its own: a
  # typo here should fail `nix build`, not leave Alloy running its last good
  # config with a component quietly marked unhealthy.
  alloyConfigChecked =
    pkgs.runCommand "config.alloy"
      {
        nativeBuildInputs = [ pkgs.grafana-alloy ];
      }
      ''
        alloy validate ${alloyConfig}
        cp ${alloyConfig} $out
      '';

  grafanaDir = config.services.grafana.dataDir;
  adminPasswordFile = "${grafanaDir}/admin-password";

  # See "Dashboards" above. The live copy is Grafana's own: the clone is
  # under /home/max, which the grafana user cannot read.
  dev = config.maxnix.dev;
  cloneDashboards = "${dev.clonePath}/hosts/maxnix/dashboards";
  liveDashboards = "${grafanaDir}/dashboards-live";
  dashboardDir = if dev.liveConfig then liveDashboards else ./dashboards;

  mcpTokenDir = "/var/lib/grafana-mcp";

  # grafana-capture [uid…] — write dashboards built in the UI into the clone.
  #
  # With no arguments, every dashboard that is not already provisioned from
  # the repo; with uids, exactly those. Written as ./dashboards/<slug>.json
  # minus the database's own id and version, which provisioning assigns. A
  # captured dashboard keeps its uid, so after the next rebuild provisioning
  # takes over the UI copy instead of showing it twice. Reads as admin: a
  # dashboard built at the top level is readable by its creator and editors,
  # not by every Viewer — the mcp-grafana token got 403 on exactly that in the
  # test (2026-10-08). The password is root-only, so it comes through sudo,
  # unless this already runs as root. Like dms-capture, it finds the clone by
  # MAXNIX_FLAKE or maxnix.dev.clonePath.
  capture = pkgs.writeShellApplication {
    name = "grafana-capture";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.git
    ];
    text = ''
      clone="''${MAXNIX_FLAKE:-${dev.clonePath}}"
      dest="$clone/hosts/maxnix/dashboards"
      if [ ! -e "$clone/flake.nix" ]; then
        echo "grafana-capture: no flake.nix at $clone" >&2
        echo "set MAXNIX_FLAKE to where the clone is" >&2
        exit 1
      fi
      if [ -r ${adminPasswordFile} ]; then
        password=$(cat ${adminPasswordFile})
      else
        password=$(sudo cat ${adminPasswordFile})
      fi
      api() {
        curl -fsS -u "admin:$password" "${grafanaUrl}$1"
      }

      if [ $# -gt 0 ]; then
        uids=("$@")
      else
        mapfile -t uids < <(api "/api/search?type=dash-db&limit=5000" | jq -r '.[].uid')
      fi

      mkdir -p "$dest"
      captured=0
      for uid in "''${uids[@]}"; do
        d=$(api "/api/dashboards/uid/$uid")
        if [ $# -eq 0 ] && [ "$(jq -r '.meta.provisioned' <<<"$d")" = true ]; then
          continue
        fi
        slug=$(jq -r '.meta.slug' <<<"$d")
        jq '.dashboard | del(.id, .version)' <<<"$d" > "$dest/$slug.json"
        echo "captured $slug ($uid)"
        captured=$((captured + 1))
      done
      if [ "$captured" -eq 0 ]; then
        echo "grafana-capture: nothing to capture — every dashboard is already provisioned" >&2
      fi

      if [ -d "$clone/.git" ]; then
        echo
        git -C "$clone" status --short -- hosts/maxnix/dashboards
        echo "review, then commit hosts/maxnix/dashboards as usual" >&2
      fi
    '';
  };

  # nixpkgs links Alloy's journal reader against systemd-minimal-libs, which
  # is built without zstd — and NixOS compresses its journal with zstd. The
  # reader then opens the journal, skips every file it cannot decompress, and
  # reports itself healthy with zero lines read. Found 2026-10-08 by
  # ../../tests/observability.nix: loki_source_journal_target_lines_total
  # stayed 0 with the probe line plainly in /var/log/journal, and
  # `strings libsystemd.so.0` in that library says "zstd support is not
  # compiled in".
  #
  # Alloy dlopen()s libsystemd through its RUNPATH, so pointing that at the
  # full systemd's libraries is the whole fix — a copy and a patchelf, not a
  # rebuild of Alloy. Listed in ../../docs/blocked.toml.
  alloy =
    pkgs.runCommand "grafana-alloy-${pkgs.grafana-alloy.version}-journal-zstd"
      {
        nativeBuildInputs = [ pkgs.patchelf ];
        inherit (pkgs.grafana-alloy) meta;
      }
      ''
        cp -r --no-preserve=mode ${pkgs.grafana-alloy} $out
        chmod +x $out/bin/*
        patchelf --set-rpath "${lib.getLib pkgs.systemd}/lib:$(patchelf --print-rpath $out/bin/alloy)" \
          $out/bin/alloy
      '';
in
{
  options.maxnix.observability = {
    enable = lib.mkEnableOption "the local observability stack (Alloy, Prometheus, Loki, Grafana)";

    metricsRetention = lib.mkOption {
      type = lib.types.str;
      default = "2y";
      description = "How long Prometheus keeps metrics, as a Prometheus duration.";
    };

    logsRetention = lib.mkOption {
      type = lib.types.str;
      default = "8760h";
      description = "How long Loki keeps logs, in hours (Loki takes no `y` or `d`). 8760h is a year.";
    };

    mcpTokenFile = lib.mkOption {
      type = lib.types.path;
      default = "${mcpTokenDir}/token";
      readOnly = true;
      description = ''
        Where the Grafana service-account token for mcp-grafana is written,
        owned by mcpTokenOwner. See home/max/apps.nix for the consumer.
      '';
    };

    mcpTokenOwner = lib.mkOption {
      type = lib.types.str;
      default = "max";
      description = "The user who runs Claude Code, and so mcp-grafana, and gets to read its token.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ capture ];

    services.alloy = {
      enable = true;
      package = alloy;
      configPath = alloyConfigChecked;
      # Alloy otherwise reports which components are in use to Grafana Labs.
      extraFlags = [ "--disable-reporting" ];
    };

    services.prometheus = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = ports.prometheus;
      retentionTime = cfg.metricsRetention;
      # Alloy pushes; nothing is scraped from here.
      extraFlags = [ "--web.enable-remote-write-receiver" ];
    };

    services.loki = {
      enable = true;
      configuration = {
        auth_enabled = false;
        analytics.reporting_enabled = false;

        server = {
          http_listen_address = "127.0.0.1";
          http_listen_port = ports.loki;
          grpc_listen_address = "127.0.0.1";
          grpc_listen_port = ports.lokiGrpc;
          log_level = "warn";
        };

        # Single binary, one replica, no ring to gossip about: an in-memory
        # ring needs no memberlist port, so there is nothing more to listen.
        common = {
          path_prefix = config.services.loki.dataDir;
          replication_factor = 1;
          instance_addr = "127.0.0.1";
          ring.kvstore.store = "inmemory";
          storage.filesystem = {
            chunks_directory = "${config.services.loki.dataDir}/chunks";
            rules_directory = "${config.services.loki.dataDir}/rules";
          };
        };

        schema_config.configs = [
          {
            from = "2026-10-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }
        ];

        # Retention is off unless the compactor is told to apply it — by
        # default Loki keeps everything forever.
        compactor = {
          working_directory = "${config.services.loki.dataDir}/compactor";
          retention_enabled = true;
          delete_request_store = "filesystem";
        };

        limits_config = {
          retention_period = cfg.logsRetention;
          # What the OTLP endpoint stores log attributes in.
          allow_structured_metadata = true;
          volume_enabled = true;
        };
      };
    };

    services.grafana = {
      enable = true;

      # Grafana 13 no longer bundles even its core datasources: without these
      # it logs "plugin prometheus not found" and tries to download them from
      # grafana.com at every start (found 2026-10-08, in the test's offline
      # VM). Declared, they come from nixpkgs, pinned like everything else,
      # and the module turns the background installer off. The two Drilldown
      # apps are Grafana's query-less browsers for metrics and logs.
      declarativePlugins = with pkgs.grafanaPlugins; [
        prometheus
        loki
        grafana-metricsdrilldown-app
        grafana-lokiexplore-app
      ];

      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = ports.grafana;
          domain = "localhost";
          enforce_domain = true;
        };
        "auth.anonymous" = {
          enabled = true;
          org_role = "Viewer";
        };
        security = {
          admin_user = "admin";
          admin_password = "$__file{${adminPasswordFile}}";
          # Encrypts secrets Grafana stores in its database. Generated with the
          # admin password (below): none of the datasources here has a secret,
          # so losing it costs nothing.
          secret_key = "$__file{${grafanaDir}/secret-key}";
        };
        users.allow_sign_up = false;
        analytics = {
          reporting_enabled = false;
          check_for_updates = false;
          check_for_plugin_updates = false;
          feedback_links_enabled = false;
        };
        news.news_feed_enabled = false;
        # At info it was the loudest unit in the VM's journal by far — 1881
        # lines in its first hour (2026-10-09), every request and index
        # rebuild — and all of that lands in Loki.
        log.level = "warn";
        # Otherwise it fetches plugin-signing keys from grafana.com at start.
        # Plugins come from nixpkgs here (declarativePlugins above).
        plugins.public_key_retrieval_disabled = true;
      };

      provision = {
        enable = true;
        datasources.settings = {
          apiVersion = 1;
          datasources = [
            {
              # Type `prometheus`: the type mcp-grafana's Prometheus tools
              # look for.
              name = "Prometheus";
              uid = "prometheus";
              type = "prometheus";
              url = prometheusUrl;
              isDefault = true;
              jsonData.timeInterval = "15s";
            }
            {
              name = "Loki";
              uid = "loki";
              type = "loki";
              url = lokiUrl;
            }
          ];
        };
        dashboards.settings.providers = [
          {
            name = "maxnix";
            folder = "maxnix";
            options.path = dashboardDir;
            # The source of truth is this repo; edits in the UI are for
            # experimenting and are not saved back.
            allowUiUpdates = false;
          }
        ];
      };
    };

    # Grafana's admin password and secret key, made once on this machine
    # before Grafana first starts, and kept with its database. Readable by
    # grafana (which reads them through $__file{}) and root, nobody else.
    systemd.services.grafana-secrets = {
      description = "Create Grafana's admin password and secret key";
      wantedBy = [ "grafana.service" ];
      before = [ "grafana.service" ];
      path = [ pkgs.coreutils ];
      serviceConfig.Type = "oneshot";
      script = ''
        install -d -o grafana -g grafana -m 0700 ${grafanaDir}
        for f in ${adminPasswordFile} ${grafanaDir}/secret-key; do
          if [ ! -s "$f" ]; then
            (umask 077; tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 > "$f")
            chown grafana:grafana "$f"
          fi
        done
      '';
    };

    # The live dashboard loop, VM only (see "Dashboards" above). A path unit
    # watching the clone's ./dashboards — its contents, and it appearing or
    # disappearing — and a copy into Grafana's own directory on every change:
    # from the clone while it has the directory, from the store otherwise.
    # Deletions included, so removing a file removes the dashboard.
    systemd.paths.grafana-dashboards-live = lib.mkIf dev.liveConfig {
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathChanged = cloneDashboards;
        Unit = "grafana-dashboards-live.service";
      };
    };
    systemd.services.grafana-dashboards-live = lib.mkIf dev.liveConfig {
      description = "Copy the clone's (or the deployed) dashboards to Grafana";
      wantedBy = [ "grafana.service" ];
      before = [ "grafana.service" ];
      after = [ "grafana-secrets.service" ];
      path = [ pkgs.coreutils ];
      serviceConfig.Type = "oneshot";
      script = ''
        if [ -d ${cloneDashboards} ]; then
          src=${cloneDashboards}
        else
          src=${./dashboards}
        fi
        echo "dashboards from $src"

        # In place, file by file. This used to replace the whole directory,
        # leaving a moment with none at all, and a deleted dashboard then
        # stayed in Grafana in one test run of two (2026-10-09) — most likely
        # Grafana scanning in that moment. In place, it has not recurred.
        install -d -o grafana -g grafana -m 0750 ${liveDashboards}
        for f in ${liveDashboards}/*.json; do
          [ -e "$f" ] || continue
          [ -e "$src/''${f##*/}" ] || rm -f "$f"
        done
        for f in "$src"/*.json; do
          [ -e "$f" ] || continue
          install -o grafana -g grafana -m 0640 "$f" ${liveDashboards}/
        done
      '';
    };

    # A Viewer service account for mcp-grafana, and a token for it. Grafana
    # provisioning cannot create either, so this does, through the API, after
    # every Grafana start. The token lives in /var/lib/grafana-mcp, which is
    # NOT persisted: a fresh boot just makes a new one and removes the old,
    # so no token outlives the machine state that issued it.
    #
    # Viewer because mcp-grafana runs with --disable-write anyway (see
    # home/max/apps.nix), and a reader is all an agent analysing data needs.
    systemd.services.grafana-mcp-token = {
      description = "Issue a Grafana service-account token for mcp-grafana";
      after = [
        "grafana.service"
        "grafana-secrets.service"
      ];
      requires = [ "grafana.service" ];
      wantedBy = [ "grafana.service" ];
      path = [
        pkgs.curl
        pkgs.jq
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "15s";
        StateDirectory = "grafana-mcp";
        StateDirectoryMode = "0755";
      };
      script = ''
        set -euo pipefail
        url=${grafanaUrl}
        token=${cfg.mcpTokenFile}
        auth="admin:$(cat ${adminPasswordFile})"
        api() { curl -fsS -u "$auth" -H 'Content-Type: application/json' "$@"; }

        # Grafana's unit is up long before its HTTP server answers: its first
        # start runs database migrations, measured at over a minute in a busy
        # test VM (2026-10-08). Five minutes here, and systemd retries beyond.
        for _ in $(seq 300); do
          curl -fsS "$url/api/health" >/dev/null 2>&1 && break
          sleep 1
        done

        # A token that still works is kept. "Works" means Grafana says who it
        # is: with anonymous access on, a dead token is not refused, it is
        # quietly treated as an anonymous Viewer, so any request that merely
        # succeeds would keep a broken token forever. Caught by the test.
        if [ -s "$token" ] && curl -fsS -H "Authorization: Bearer $(cat "$token")" \
            "$url/api/user" 2>/dev/null | jq -e '.login | test("mcp-grafana")' >/dev/null; then
          exit 0
        fi

        id=$(api "$url/api/serviceaccounts/search?query=mcp-grafana" \
          | jq -r '.serviceAccounts[] | select(.name == "mcp-grafana") | .id')
        if [ -z "$id" ]; then
          id=$(api -X POST "$url/api/serviceaccounts" \
            -d '{"name":"mcp-grafana","role":"Viewer"}' | jq -r .id)
        fi

        # One live token at a time.
        for old in $(api "$url/api/serviceaccounts/$id/tokens" | jq -r '.[].id'); do
          api -X DELETE "$url/api/serviceaccounts/$id/tokens/$old" >/dev/null
        done

        key=$(api -X POST "$url/api/serviceaccounts/$id/tokens" \
          -d "{\"name\":\"mcp-grafana-$(date +%s)\"}" | jq -r .key)
        (umask 077; printf '%s' "$key" > "$token.new")
        chown ${cfg.mcpTokenOwner} "$token.new"
        mv "$token.new" "$token"
      '';
    };
  };
}
