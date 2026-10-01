"""Report which entries in docs/blocked.toml are still blocked upstream.

Every entry is a workaround or a deferral that waits on a third party, and
carries a check that decides whether it still has to. Each entry ends up as
one of four statuses:

  blocked    the condition is not met yet
  unblocked  the condition is met: do what the entry's `then` says
  manual     no deterministic check; a person or an LLM has to look
  error      the check itself failed, so nothing is known

`error` is kept apart from `blocked` on purpose. A check that breaks (a typo,
the network, a GitHub rate limit) would otherwise read as "still blocked"
forever, which is the one failure this tool exists to prevent.

Exit status: 0 when every check ran, 1 when at least one returned `error`,
2 when the file is invalid, and 3 with --fail-on-unblocked when something is
unblocked and nothing errored.
"""

import argparse
import concurrent.futures
import datetime
import json
import re
import subprocess
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path

BLOCKED = "blocked"
UNBLOCKED = "unblocked"
MANUAL = "manual"
ERROR = "error"
STATUSES = (UNBLOCKED, BLOCKED, MANUAL, ERROR)

ENTRY_KEYS = {"id", "title", "upstream", "workaround", "then", "check"}
REQUIRED_KEYS = {"id", "title", "check"}
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
REPO_REF_RE = re.compile(r"^([\w.-]+/[\w.-]+) (\S+)$")
REPO_NUM_RE = re.compile(r"^([\w.-]+/[\w.-]+)#([0-9]+)$")

# A hung `nix eval` or `gh` must not hang the whole run.
TIMEOUT = 300


class CheckError(Exception):
    """A check could not decide; reported as `error`."""


@dataclass
class Result:
    status: str
    evidence: str


@dataclass
class Context:
    root: Path
    pkgs: str


def run(argv, cwd):
    try:
        return subprocess.run(
            argv, cwd=cwd, capture_output=True, text=True, timeout=TIMEOUT
        )
    except subprocess.TimeoutExpired:
        raise CheckError(f"{argv[0]} timed out after {TIMEOUT}s")


def first_line(text):
    for line in text.splitlines():
        if line.strip():
            return line.strip()
    return ""


def nix_error(stderr):
    # nix prints warnings and a trace around the message; the line that
    # starts with "error:" is the one that says what went wrong.
    for line in stderr.splitlines():
        if line.startswith("error:"):
            return line
    return first_line(stderr) or "nix eval failed"


def gh_api(ctx, path):
    """Return the decoded response, or None for a 404."""
    proc = run(["gh", "api", path], ctx.root)
    if proc.returncode == 0:
        return json.loads(proc.stdout)
    if "(HTTP 404)" in proc.stderr:
        return None
    raise CheckError(first_line(proc.stderr) or f"gh exited {proc.returncode}")


def require_repo(ctx, repo):
    # A missing tag and a misspelt repository are both a 404. Only the first
    # means "still blocked"; the second would read that way forever.
    if gh_api(ctx, f"repos/{repo}") is None:
        raise CheckError(f"repository {repo} not found")


def day(timestamp):
    return (timestamp or "")[:10]


# ── Checks ──────────────────────────────────────────────────────────────────


def check_nix(ctx, expr):
    proc = run(
        [
            "nix",
            "eval",
            "--json",
            f"{ctx.root}#{ctx.pkgs}",
            "--apply",
            expr,
        ],
        ctx.root,
    )
    if proc.returncode != 0:
        raise CheckError(nix_error(proc.stderr))
    value = json.loads(proc.stdout)
    # A bare boolean, or { unblocked = bool; evidence = "..."; } for an
    # entry that wants to say more than true or false.
    if isinstance(value, bool):
        evidence = "nix check returned " + ("true" if value else "false")
        return Result(UNBLOCKED if value else BLOCKED, evidence)
    if (
        isinstance(value, dict)
        and isinstance(value.get("unblocked"), bool)
        and isinstance(value.get("evidence", ""), str)
    ):
        status = UNBLOCKED if value["unblocked"] else BLOCKED
        return Result(status, value.get("evidence", ""))
    raise CheckError(
        "nix check must return a boolean or { unblocked; evidence; }, "
        f"got {json.dumps(value)[:80]}"
    )


def check_github_tag(ctx, arg):
    repo, tag = REPO_REF_RE.match(arg).groups()
    # git/ref (singular) matches exactly; git/refs would also answer for a
    # mere prefix of the tag.
    if gh_api(ctx, f"repos/{repo}/git/ref/tags/{tag}") is None:
        require_repo(ctx, repo)
        return Result(BLOCKED, f"tag {tag} not found in {repo}")
    return Result(UNBLOCKED, f"tag {tag} exists in {repo}")


def check_github_release(ctx, arg):
    repo, tag = REPO_REF_RE.match(arg).groups()
    release = gh_api(ctx, f"repos/{repo}/releases/tags/{tag}")
    if release is None:
        require_repo(ctx, repo)
        return Result(BLOCKED, f"release {tag} not found in {repo}")
    kind = "pre-release" if release.get("prerelease") else "release"
    when = day(release.get("published_at"))
    return Result(UNBLOCKED, f"{kind} {tag} published {when}")


def check_github_pr_merged(ctx, arg):
    repo, number = REPO_NUM_RE.match(arg).groups()
    pr = gh_api(ctx, f"repos/{repo}/pulls/{number}")
    if pr is None:
        raise CheckError(f"{repo}#{number} is not a pull request")
    if pr.get("merged_at"):
        return Result(UNBLOCKED, f"{arg} merged {day(pr['merged_at'])}")
    if pr.get("state") == "closed":
        return Result(BLOCKED, f"{arg} closed without merging")
    return Result(BLOCKED, f"{arg} is open")


def check_github_issue_closed(ctx, arg):
    repo, number = REPO_NUM_RE.match(arg).groups()
    issue = gh_api(ctx, f"repos/{repo}/issues/{number}")
    if issue is None:
        raise CheckError(f"{repo}#{number} not found")
    if issue.get("state") != "closed":
        return Result(BLOCKED, f"{arg} is open")
    # Closed as not_planned still counts as closed, as the check says; the
    # reason is in the evidence so it is not missed.
    reason = issue.get("state_reason") or "closed"
    return Result(
        UNBLOCKED, f"{arg} closed ({reason}) {day(issue.get('closed_at'))}"
    )


def check_command(ctx, script):
    proc = run(["bash", "-c", script], ctx.root)
    said = first_line(proc.stdout) or first_line(proc.stderr)
    if proc.returncode == 0:
        return Result(UNBLOCKED, said or "command exited 0")
    if proc.returncode == 1:
        return Result(BLOCKED, said or "command exited 1")
    raise CheckError(
        first_line(proc.stderr) or f"command exited {proc.returncode}"
    )


def check_manual(ctx, question):
    return Result(MANUAL, question)


def check_all(ctx, checks):
    results = [evaluate(ctx, c) for c in checks]
    # One unmet condition settles `all`, whatever the others say.
    for status in (BLOCKED, ERROR, MANUAL):
        found = [r.evidence for r in results if r.status == status]
        if found:
            return Result(status, "; ".join(found))
    return Result(UNBLOCKED, "; ".join(r.evidence for r in results))


def check_any(ctx, checks):
    results = [evaluate(ctx, c) for c in checks]
    # One met condition settles `any`, whatever the others say.
    for status in (UNBLOCKED, ERROR, MANUAL):
        found = [r.evidence for r in results if r.status == status]
        if found:
            return Result(status, "; ".join(found))
    return Result(BLOCKED, "; ".join(r.evidence for r in results))


CHECKS = {
    "nix": check_nix,
    "github-tag": check_github_tag,
    "github-release": check_github_release,
    "github-pr-merged": check_github_pr_merged,
    "github-issue-closed": check_github_issue_closed,
    "command": check_command,
    "manual": check_manual,
    "all": check_all,
    "any": check_any,
}

ARG_FORMATS = {
    "github-tag": (REPO_REF_RE, "'owner/repo tag'"),
    "github-release": (REPO_REF_RE, "'owner/repo tag'"),
    "github-pr-merged": (REPO_NUM_RE, "'owner/repo#123'"),
    "github-issue-closed": (REPO_NUM_RE, "'owner/repo#123'"),
}


def evaluate(ctx, check):
    (kind, arg), = check.items()
    try:
        return CHECKS[kind](ctx, arg)
    except CheckError as e:
        return Result(ERROR, str(e))


# ── Validation ──────────────────────────────────────────────────────────────


def validate_check(check, where):
    if not isinstance(check, dict) or len(check) != 1:
        return [f"{where}: a check is a table with exactly one key"]
    (kind, arg), = check.items()
    if kind not in CHECKS:
        known = ", ".join(sorted(CHECKS))
        return [f"{where}: unknown check '{kind}' (known: {known})"]
    if kind in ("all", "any"):
        if not isinstance(arg, list) or not arg:
            return [f"{where}: '{kind}' takes a non-empty list of checks"]
        problems = []
        for i, sub in enumerate(arg):
            problems += validate_check(sub, f"{where}.{kind}[{i}]")
        return problems
    if not isinstance(arg, str) or not arg.strip():
        return [f"{where}: '{kind}' takes a non-empty string"]
    if kind in ARG_FORMATS:
        pattern, shape = ARG_FORMATS[kind]
        if not pattern.match(arg):
            return [f"{where}: '{kind}' takes {shape}, got '{arg}'"]
    return []


def validate(data):
    problems = []
    for key in data:
        if key not in ("settings", "entry"):
            problems.append(f"unknown top-level key '{key}'")
    settings = data.get("settings")
    if not isinstance(settings, dict) or not isinstance(
        settings.get("pkgs"), str
    ):
        problems.append("[settings] needs pkgs = '<flake attribute>'")
    entries = data.get("entry", [])
    if not isinstance(entries, list):
        return problems + ["'entry' must be an array of tables, [[entry]]"]
    seen = set()
    for i, entry in enumerate(entries):
        where = f"entry[{i}]"
        if not isinstance(entry, dict):
            problems.append(f"{where}: not a table")
            continue
        if isinstance(entry.get("id"), str):
            where = f"entry '{entry['id']}'"
        for key in sorted(REQUIRED_KEYS - entry.keys()):
            problems.append(f"{where}: missing '{key}'")
        for key in sorted(entry.keys() - ENTRY_KEYS):
            problems.append(f"{where}: unknown key '{key}'")
        for key in sorted((ENTRY_KEYS - {"check"}) & entry.keys()):
            if not isinstance(entry[key], str):
                problems.append(f"{where}: '{key}' must be a string")
        ident = entry.get("id")
        if isinstance(ident, str):
            if not ID_RE.match(ident):
                problems.append(f"{where}: id must match {ID_RE.pattern}")
            if ident in seen:
                problems.append(f"{where}: duplicate id")
            seen.add(ident)
        if "check" in entry:
            problems += validate_check(entry["check"], f"{where}: check")
    return problems


# ── Output ──────────────────────────────────────────────────────────────────


def git(root, *args):
    proc = subprocess.run(
        ["git", *args], cwd=root, capture_output=True, text=True
    )
    return proc.stdout.strip() if proc.returncode == 0 else None


def render_json(root, entries, results):
    report = {
        "checked_at": datetime.datetime.now(datetime.timezone.utc)
        .replace(microsecond=0)
        .isoformat(),
        "revision": git(root, "rev-parse", "HEAD"),
        "dirty": bool(git(root, "status", "--porcelain")),
        "entries": [
            {
                "id": e["id"],
                "title": e["title"],
                "status": r.status,
                "evidence": r.evidence,
                "upstream": e.get("upstream"),
                "workaround": e.get("workaround"),
                "then": e.get("then"),
            }
            for e, r in zip(entries, results)
        ],
    }
    print(json.dumps(report, indent=2))


def render_human(entries, results):
    rows = [("STATUS", "ID", "EVIDENCE")] + [
        (r.status, e["id"], r.evidence) for e, r in zip(entries, results)
    ]
    widths = [max(len(row[i]) for row in rows) for i in (0, 1)]
    for status, ident, evidence in rows:
        print(f"{status:<{widths[0]}}  {ident:<{widths[1]}}  {evidence}")

    todo = [
        (e, r) for e, r in zip(entries, results) if r.status == UNBLOCKED
    ]
    if todo:
        print("\nUnblocked, so now:")
        for e, _ in todo:
            print(f"  {e['id']}: {e.get('then', e['title'])}")

    counts = {s: sum(r.status == s for r in results) for s in STATUSES}
    summary = ", ".join(f"{n} {s}" for s, n in counts.items() if n)
    print(f"\n{len(results)} entries: {summary or 'none'}")


# ── Main ────────────────────────────────────────────────────────────────────


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="blocked",
        description="Check which workarounds are still blocked upstream.",
    )
    parser.add_argument(
        "--file",
        type=Path,
        help="the list to check (default: docs/blocked.toml in this repo)",
    )
    parser.add_argument(
        "--format",
        choices=("human", "json"),
        default="human",
        help="a table for people, or JSON for programs (default: human)",
    )
    parser.add_argument(
        "--fail-on-unblocked",
        action="store_true",
        help="exit 3 when any entry is unblocked",
    )
    args = parser.parse_args(argv)

    toplevel = git(Path.cwd(), "rev-parse", "--show-toplevel")
    if toplevel is None:
        print("blocked: run this inside the repository", file=sys.stderr)
        return 2
    root = Path(toplevel)
    path = args.file or root / "docs" / "blocked.toml"

    try:
        data = tomllib.loads(path.read_text())
    except (OSError, tomllib.TOMLDecodeError) as e:
        print(f"blocked: {path}: {e}", file=sys.stderr)
        return 2
    problems = validate(data)
    if problems:
        for problem in problems:
            print(f"blocked: {path}: {problem}", file=sys.stderr)
        return 2

    ctx = Context(root=root, pkgs=data["settings"]["pkgs"])
    entries = data.get("entry", [])
    # Checks are network calls and nix evaluations, so they overlap well.
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(lambda e: evaluate(ctx, e["check"]), entries))

    if args.format == "json":
        render_json(root, entries, results)
    else:
        render_human(entries, results)

    if any(r.status == ERROR for r in results):
        return 1
    if args.fail_on_unblocked and any(r.status == UNBLOCKED for r in results):
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
