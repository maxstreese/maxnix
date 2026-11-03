# Wait timing and timeout scaling, for every runNixOSTest suite.
#
# A test module rather than a string each suite imports: `testScript` merges
# as lines, so `mkBefore` puts this ahead of whatever the suite wrote
# (including tests/vnc.nix, which uses `scaled` and `timed` from here).
# flake.nix adds it to each suite with the scale that suite's tier gets.
#
# Why (2026-11-03). Waits that pass locally have timed out on GitHub runners,
# which are slower and vary in speed, and there was no record of how close
# any wait came to its limit. So:
#
#   1. Every wait is timed. Each one is logged as it finishes, appended to
#      $out/waits.jsonl, and summarised tightest-first when the driver exits,
#      failed runs included. A wait over half its limit is marked TIGHT. That
#      separates "the limit is too close to what the runner needs" from "it
#      hung", which a bigger limit would not help.
#
#   2. Every *explicit* timeout is multiplied by one factor, so a slow
#      runner's margin is a single number and not fifty literals. The waits
#      poll a condition, so a bigger limit only delays a run that was failing
#      anyway. Waits left at the driver's 15-minute default are not scaled,
#      to keep a hang from taking half an hour to report.
#
# The disko-based suites (metal-boots, metal-install) are not covered: they go
# through makeDiskoTest rather than runNixOSTest, and they only make
# default-timeout waits.
#
# Interactive runs (`nix run .#test-*`) read MAXNIX_TIMEOUT_SCALE as an override.
# Sandboxed builds cannot see the caller's environment, so for them the value
# baked in here is the one in effect.
{ scale }:
{ lib, ... }:
{
  testScript = lib.mkBefore ''
    import atexit as _atexit
    import datetime as _dt
    import functools as _functools
    import inspect as _inspect
    import json as _json
    import os as _os
    import threading as _threading
    import time as _time
    from contextlib import contextmanager as _contextmanager
    from pathlib import Path as _Path

    TIMEOUT_SCALE = float(_os.environ.get("MAXNIX_TIMEOUT_SCALE") or "${toString scale}")
    TIGHT = 0.5  # fraction of its limit a wait may use before it is flagged

    _waits = []
    _waits_file = _Path(driver.out_dir) / "waits.jsonl"
    # The driver's own waits call each other (and subclasses call their base),
    # so only the outermost one is scaled and recorded.
    _wait_depth = _threading.local()


    def _seconds(duration):
        if duration is None:
            return None
        if isinstance(duration, _dt.timedelta):
            return duration.total_seconds()
        return float(duration)


    def scaled(seconds):
        """An explicit timeout, in seconds, multiplied by TIMEOUT_SCALE."""
        return seconds * TIMEOUT_SCALE


    def _record(node, what, took, limit, ok):
        entry = {"node": node, "wait": what, "took": round(took, 1),
                 "limit": None if limit is None else round(limit, 1), "ok": ok}
        _waits.append(entry)
        share = "" if not limit else f" ({took / limit:.0%})"
        mark = " TIGHT" if limit and took / limit > TIGHT else ""
        mark = mark if ok else " FAILED"
        shown = "-" if limit is None else f"{limit:g}"
        print(f"wait: {node} {what}: {took:.1f}s of {shown}s{share}{mark}", flush=True)
        try:
            with _waits_file.open("a") as f:
                f.write(_json.dumps(entry) + "\n")
        except OSError:
            pass  # a read-only or vanished out_dir must not fail the test


    @_contextmanager
    def timed(node, what, limit):
        """Time a hand-rolled wait (one that is not a driver method)."""
        start = _time.monotonic()
        ok = False
        try:
            yield
            ok = True
        finally:
            _record(node, what, _time.monotonic() - start, limit, ok)


    def _wrap(cls, name):
        original = cls.__dict__[name]
        signature = _inspect.signature(original)
        default = signature.parameters["timeout"].default

        @_functools.wraps(original)
        def wrapper(self, *args, **kwargs):
            depth = getattr(_wait_depth, "n", 0)
            if depth:
                return original(self, *args, **kwargs)
            bound = signature.bind(self, *args, **kwargs)
            if bound.arguments.get("timeout") is not None:
                limit = scaled(_seconds(bound.arguments["timeout"]))
                bound.arguments["timeout"] = _dt.timedelta(seconds=limit)
            else:
                limit = _seconds(default) if default is not _inspect.Parameter.empty else None
            # The unit, command, port or file waited on: the first argument.
            given = list(bound.arguments.values())
            subject = str(given[1])[:100] if len(given) > 1 else ""
            what = f"{name}({subject})"
            _wait_depth.n = 1
            try:
                with timed(self.name, what, limit):
                    return original(*bound.args, **bound.kwargs)
            finally:
                _wait_depth.n = 0

        setattr(cls, name, wrapper)


    for _cls in (BaseMachine, QemuMachine, NspawnMachine):
        for _name, _member in list(vars(_cls).items()):
            if (_name.startswith("wait_") and callable(_member)
                    and not getattr(_member, "__isabstractmethod__", False)
                    and "timeout" in _inspect.signature(_member).parameters):
                _wrap(_cls, _name)


    @_atexit.register
    def _summarise_waits():
        timed_waits = [w for w in _waits if w["limit"]]
        if not timed_waits:
            return
        timed_waits.sort(key=lambda w: w["took"] / w["limit"], reverse=True)
        print(f"\nwaits, tightest first (timeout scale x{TIMEOUT_SCALE:g}, "
              f"TIGHT = over {TIGHT:.0%} of the limit):", flush=True)
        for w in timed_waits:
            share = w["took"] / w["limit"]
            flag = "TIGHT" if share > TIGHT else ""
            flag = "FAILED" if not w["ok"] else flag
            print(f"  {share:5.0%} {w['took']:7.1f}s / {w['limit']:6.0f}s  {flag:6} "
                  f"{w['node']} {w['wait']}", flush=True)
  '';
}
