# Does the observability stack in ../hosts/maxnix/observability.nix collect,
# store and serve — and is none of it reachable from where it should not be?
#
# Small nodes that import only that module (and ../hosts/maxnix/dev.nix for
# its options), like ./fleet.nix: the desktop suites boot the whole machine
# already, and nothing here needs a desktop.
#
#   machine  the stack as metal runs it: dashboards from the store. Data goes
#            in the ways it does on the machine — node_exporter scraped by
#            Alloy, a line through journald, OTLP shaped like Claude Code's —
#            and is read back the way an agent would: PromQL, LogQL, Grafana's
#            API, mcp-grafana over stdio. Also Grafana's access rules, and
#            grafana-capture writing a UI-built dashboard into a clone.
#   devbox   the same with maxnix.dev.liveConfig, as the VM runs it: the
#            deployed dashboards while the clone has none, then the clone's —
#            a file appearing and vanishing — with no rebuild, and back to
#            the deployed ones when the clone's directory goes.
#   outside  a second machine, probing every port.
#
# The exposure check runs with the firewall OFF. Loopback binding is the
# security model in that module, and with the firewall on a service listening
# everywhere would pass unnoticed. A deliberately exposed listener is the
# control that shows the probe can see an open port at all.
#
# HOW TO RUN:
#   nix build .#checks.x86_64-linux.observability
let
  stack =
    { pkgs, ... }:
    {
      imports = [
        ../hosts/maxnix/observability.nix
        ../hosts/maxnix/dev.nix
      ];
      maxnix.observability.enable = true;

      # The token's owner, as on the machine.
      users.users.max.isNormalUser = true;

      networking.firewall.enable = false;
      environment.systemPackages = [
        pkgs.jq
        pkgs.netcat
        pkgs.mcp-grafana
      ];
      virtualisation.memorySize = 3072;
    };
in
{
  name = "maxnix-observability";

  nodes.machine = stack;

  nodes.devbox = {
    imports = [ stack ];
    maxnix.dev = {
      liveConfig = true;
      clonePath = "/var/lib/test-clone";
    };
    # A clone without a dashboards directory, as a guest clone from before
    # they existed is.
    systemd.tmpfiles.rules = [ "d /var/lib/test-clone/hosts/maxnix 0755 root root -" ];
  };

  nodes.outside = { pkgs, ... }: { environment.systemPackages = [ pkgs.netcat ]; };

  testScript = ''
    import json, time, urllib.parse

    grafana = "http://localhost:3000"

    def get(node, url, auth=None):
        a = f"-u {auth} " if auth else ""
        return json.loads(node.succeed(f"curl -fsS {a}'{url}'"))

    def promql(q):
        return get(machine, "http://127.0.0.1:9090/api/v1/query?query=" + urllib.parse.quote(q))["data"]["result"]

    def logql(q):
        now = int(time.time())
        url = ("http://127.0.0.1:3100/loki/api/v1/query_range?limit=100"
               f"&start={now - 3600}000000000&end={now + 60}000000000"
               "&query=" + urllib.parse.quote(q))
        return get(machine, url)["data"]["result"]

    def otlp(path, body):
        machine.succeed(
            f"curl -fsS -H 'Content-Type: application/json' "
            f"-d '{json.dumps(body)}' http://127.0.0.1:4318/v1/{path}"
        )

    def wait(cmd, what, node=machine):
        # A short timeout and the evidence on failure, instead of the
        # driver's 15 silent minutes.
        try:
            node.wait_until_succeeds(cmd, timeout=120)
        except Exception:
            print(node.execute("curl -fsS http://127.0.0.1:12345/api/v0/web/components | jq -c '.[] | {id: .localID, health: .health}'")[1])
            print(node.execute("journalctl -u alloy -n 40 --no-pager | grep -v collector")[1])
            print(node.execute("journalctl -u loki -u grafana-dashboards-live -n 30 --no-pager")[1])
            print(node.execute("curl -fsS 'http://localhost:3000/api/search?tag=maxnix' | jq -c '[.[] | {uid, title}]'; ls -la /var/lib/grafana/dashboards-live")[1])
            print(node.execute("journalctl -u grafana -n 20 --no-pager | grep -i provision")[1])
            raise AssertionError(f"timed out waiting for {what}")

    def titles(node, auth=None):
        return sorted(d["title"] for d in get(node, f"{grafana}/api/search?tag=maxnix", auth))

    claude = {"attributes": [{"key": "service.name", "value": {"stringValue": "claude-code"}}]}

    start_all()
    for unit in ["alloy", "prometheus", "loki", "grafana"]:
        machine.wait_for_unit(f"{unit}.service")
    machine.wait_for_open_port(4318)
    machine.wait_for_open_port(3100)

    with subtest("host metrics reach Prometheus, pressure included"):
        wait("curl -fsS 'http://127.0.0.1:9090/api/v1/query?query=node_load1' | jq -e '.data.result | length > 0'",
             "node_load1 in Prometheus")
        assert promql("node_pressure_memory_waiting_seconds_total"), "no PSI metrics"

    with subtest("a journald line reaches Loki, in its own stream"):
        machine.succeed("logger -t obs-probe probe-line-8152")
        wait("curl -fsS -G http://127.0.0.1:3100/loki/api/v1/query_range"
             " --data-urlencode 'query={source=\"journald\", identifier=\"obs-probe\"}'"
             " | grep -q probe-line-8152", "the journald line in Loki")

    with subtest("a Claude Code event over OTLP is findable by session id"):
        now = time.time_ns()
        otlp("logs", {"resourceLogs": [{"resource": claude, "scopeLogs": [{
            "scope": {"name": "com.anthropic.claude_code.events"},
            "logRecords": [{
                "timeUnixNano": str(now),
                "body": {"stringValue": "claude_code.tool_result"},
                "attributes": [
                    {"key": "event.name", "value": {"stringValue": "tool_result"}},
                    {"key": "session.id", "value": {"stringValue": "test-session-4711"}},
                    {"key": "tool_name", "value": {"stringValue": "Bash"}},
                ]}]}]}]})
        # By the field, not a label: session.id becomes structured metadata
        # session_id, inside the service_name stream.
        query = '{service_name="claude-code"} | session_id="test-session-4711"'
        for _ in range(60):
            if logql(query):
                break
            time.sleep(1)
        assert logql(query), f"nothing for {query}"
        # And it must not have become an index label, the one way a session
        # id would hurt Loki.
        labels = get(machine, "http://127.0.0.1:3100/loki/api/v1/labels")["data"]
        assert "session_id" not in labels, f"session_id became a label: {labels}"

    with subtest("a Claude Code metric over OTLP reaches Prometheus"):
        now = time.time_ns()
        otlp("metrics", {"resourceMetrics": [{"resource": claude, "scopeMetrics": [{
            "metrics": [{
                "name": "claude_code.cost.usage", "unit": "USD",
                "sum": {"aggregationTemporality": 2, "isMonotonic": True, "dataPoints": [{
                    "asDouble": 0.42,
                    "startTimeUnixNano": str(now - 10**9), "timeUnixNano": str(now),
                    "attributes": [{"key": "model", "value": {"stringValue": "test-model"}}]}]}}]}]}]})
        # Matched by stem, the same way the dashboard does; logged so the
        # translated name is on record.
        wait("curl -fsS 'http://127.0.0.1:9090/api/v1/query' --data-urlencode"
             " 'query={__name__=~\"claude_code_cost_usage.*\"}' | jq -e '.data.result | length > 0'",
             "the Claude Code metric in Prometheus")
        print(promql('{__name__=~"claude_code_cost_usage.*"}'))

    # Its unit is up well before its HTTP server: migrations run first.
    machine.wait_for_open_port(3000)
    password = machine.succeed("cat /var/lib/grafana/admin-password")
    admin = f"admin:{password}"

    with subtest("Grafana's admin password is generated, root and grafana only"):
        assert len(password) == 32 and password.isalnum(), repr(password)
        mode = machine.succeed("stat -c '%a %U' /var/lib/grafana/admin-password").strip()
        assert mode == "600 grafana", mode
        machine.fail("runuser -u max -- cat /var/lib/grafana/admin-password")

    with subtest("Grafana: both datasources healthy, both dashboards there"):
        for uid in ["prometheus", "loki"]:
            health = get(machine, f"{grafana}/api/datasources/uid/{uid}/health", admin)
            assert health["status"] == "OK", (uid, health)
        assert titles(machine, admin) == ["Claude Code", "Host"], titles(machine, admin)

    with subtest("anonymous visitors can look, not change"):
        assert titles(machine) == ["Claude Code", "Host"], titles(machine)
        code = machine.succeed(
            f"curl -s -o /dev/null -w '%{{http_code}}' -H 'Content-Type: application/json'"
            f" -d '{{\"dashboard\":{{\"title\":\"nope\"}}}}' {grafana}/api/dashboards/db").strip()
        assert code in ("401", "403"), f"anonymous save answered {code}"

    with subtest("only requests for localhost are answered (DNS rebinding)"):
        out = machine.succeed(
            "curl -s -o /dev/null -w '%{http_code} %{redirect_url}'"
            " -H 'Host: rebind.example' http://127.0.0.1:3000/api/search").split()
        assert out[0].startswith("30") and out[1].startswith("http://localhost:3000"), out

    with subtest("mcp-grafana answers over stdio, as max, with the issued token"):
        machine.wait_for_unit("grafana-mcp-token.service")
        mode = machine.succeed("stat -c '%a %U' /var/lib/grafana-mcp/token").strip()
        assert mode == "600 max", mode
        requests = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
                "protocolVersion": "2025-06-18", "capabilities": {},
                "clientInfo": {"name": "test", "version": "0"}}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/call",
             "params": {"name": "list_datasources", "arguments": {}}},
        ]
        machine.succeed("cat > /tmp/mcp.in <<'EOF'\n" + "\n".join(map(json.dumps, requests)) + "\nEOF")
        out = machine.succeed(
            "(cat /tmp/mcp.in; sleep 5) | runuser -u max -- env"
            f" GRAFANA_URL={grafana}"
            " GRAFANA_SERVICE_ACCOUNT_TOKEN_FILE=/var/lib/grafana-mcp/token"
            " timeout 20 mcp-grafana --disable-write || true")
        reply = next(json.loads(l) for l in out.splitlines() if '"id":2' in l.replace(" ", ""))
        text = json.dumps(reply)
        assert "prometheus" in text and "loki" in text, text

    with subtest("a token that stopped working is replaced"):
        machine.succeed("echo garbage > /var/lib/grafana-mcp/token")
        machine.succeed("systemctl restart grafana-mcp-token.service")
        token = machine.succeed("cat /var/lib/grafana-mcp/token")
        assert token != "garbage\n" and token.startswith("glsa_"), token
        # Authenticated as the service account, not passed as anonymous.
        machine.succeed(f"curl -fsS -H 'Authorization: Bearer {token}' {grafana}/api/user"
                        " | jq -e '.login | test(\"mcp-grafana\")'")

    with subtest("grafana-capture writes a UI-built dashboard into the clone"):
        machine.succeed(
            f"curl -fsS -u {admin} -H 'Content-Type: application/json' {grafana}/api/dashboards/db"
            " -d '{\"dashboard\":{\"uid\":\"ui-made\",\"title\":\"UI Made\",\"panels\":[]}}'")
        # As root, which reads the admin password directly; as max it would
        # go through sudo, which this node does not give max.
        machine.succeed("mkdir -p /tmp/clone && touch /tmp/clone/flake.nix")
        print(machine.succeed("MAXNIX_FLAKE=/tmp/clone grafana-capture 2>&1"))
        captured = json.loads(machine.succeed("cat /tmp/clone/hosts/maxnix/dashboards/ui-made.json"))
        assert captured["uid"] == "ui-made" and "id" not in captured and "version" not in captured, captured
        # The provisioned ones are the repo's already, so they are left out.
        files = machine.succeed("ls /tmp/clone/hosts/maxnix/dashboards").split()
        assert files == ["ui-made.json"], files

    with subtest("data survives a restart of the stores"):
        machine.succeed("systemctl restart prometheus loki")
        machine.wait_for_open_port(3100)
        wait("curl -fsS 'http://127.0.0.1:9090/api/v1/query' --data-urlencode"
             " 'query={__name__=~\"claude_code_cost_usage.*\"}' | jq -e '.data.result | length > 0'",
             "the metric after a restart")
        wait("curl -fsS -G http://127.0.0.1:3100/loki/api/v1/query_range"
             " --data-urlencode 'query={service_name=\"claude-code\"} | session_id=\"test-session-4711\"'"
             " | jq -e '.data.result | length > 0'", "the event after a restart")

    with subtest("live dashboards: the deployed ones while the clone has none"):
        devbox.wait_for_open_port(3000)
        wait(f"curl -fsS '{grafana}/api/search?tag=maxnix' | jq -e 'length == 2'",
             "the deployed dashboards, with no directory in the clone", devbox)

    with subtest("live dashboards: the clone's, as soon as it has them, with no rebuild"):
        clone = "/var/lib/test-clone/hosts/maxnix/dashboards"
        probe = {"uid": "live-probe", "title": "Live Probe", "tags": ["maxnix"], "panels": []}
        devbox.succeed(f"mkdir {clone} && cat > {clone}/live-probe.json <<'EOF'\n"
                       + json.dumps(probe) + "\nEOF")
        # The clone wins outright: its one file, not the deployed two.
        wait(f"curl -fsS '{grafana}/api/search?tag=maxnix' | jq -e '[.[].uid] == [\"live-probe\"]'",
             "the clone's directory to replace the deployed dashboards", devbox)
        devbox.succeed(f"cp ${../hosts/maxnix/dashboards}/host.json {clone}/")
        wait(f"curl -fsS '{grafana}/api/search?tag=maxnix' | jq -e 'length == 2'",
             "a new file in the clone to appear in Grafana", devbox)
        devbox.succeed(f"rm {clone}/live-probe.json")
        wait(f"curl -fsS '{grafana}/api/search?tag=maxnix' | jq -e '[.[].uid] == [\"maxnix-host\"]'",
             "a deleted file in the clone to vanish from Grafana", devbox)

    with subtest("live dashboards: back to the deployed ones when the clone's directory goes"):
        devbox.succeed(f"rm -r {clone}")
        wait(f"curl -fsS '{grafana}/api/search?tag=maxnix' | jq -e 'length == 2'",
             "the deployed dashboards again", devbox)

    with subtest("everything listens on loopback only"):
        listeners = machine.succeed("ss -Htln | awk '{print $4}'").split()
        exposed = [l for l in listeners if not (l.startswith("127.0.0.1:") or l.startswith("[::1]:"))]
        assert not exposed, f"listening beyond loopback: {exposed}"
        outside.wait_for_unit("multi-user.target")
        for port in [3000, 3100, 4317, 4318, 9090, 9096, 12345]:
            outside.fail(f"nc -z -w 3 machine {port}")

    with subtest("and the probe does see a port that is open"):
        # The control: with the firewall off, a listener on every interface
        # is reachable, so the failures above mean "not listening", not
        # "probe broken".
        machine.succeed("systemd-run --unit exposed-probe nc -lk 9999")
        machine.wait_for_open_port(9999)
        outside.succeed("nc -z -w 3 machine 9999")
  '';
}
