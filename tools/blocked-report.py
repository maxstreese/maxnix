"""Turn `blocked --format json` into GitHub issues, so doable work notifies.

This is what .github/workflows/blocked.yml runs. The checker decides; this
only keeps the repository's issues in step with what it decided:

  unblocked entry       one open issue per entry, labelled `unblocked`,
                        opened the first time (that is the notification)
                        and only edited afterwards, which notifies nobody
  entry removed         its issue is closed: the work was done, and the
                        commit that did it deleted the entry
  back to blocked       its issue is closed with a comment saying why
  error or manual       its issue is left alone; a failing check says
                        nothing about whether the work is still doable
  any check errors      one issue labelled `blocked-error` lists them all,
                        and is closed once every check passes again

Issues are found again by a hidden marker in their body, never by title, so
retitling one by hand changes nothing. --dry-run prints every action and
touches nothing; --input reads a saved report instead of running the
checker, which is how the transitions above can be tried without waiting
for upstream to move.
"""

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys

LABELS = {
    "unblocked": ("0e8a16", "docs/blocked.toml: upstream has unblocked this"),
    "blocked-error": ("d93f0b", "docs/blocked.toml: a check is failing"),
}
ENTRY_MARKER = "<!-- blocked-id: {} -->"
ENTRY_MARKER_RE = re.compile(r"<!-- blocked-id: ([a-z0-9-]+) -->")
ERROR_MARKER = "<!-- blocked-errors -->"
# Everything above this line is compared to decide whether to edit an issue;
# the footer below it records the run that opened it and is never rewritten.
FOOTER = "\n\n---\n"


class GitHubError(Exception):
    pass


def gh(*args, payload=None):
    proc = subprocess.run(
        ["gh", "api", *args] + (["--input", "-"] if payload else []),
        input=json.dumps(payload) if payload else None,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise GitHubError(proc.stderr.strip() or f"gh api {args[0]} failed")
    return json.loads(proc.stdout) if proc.stdout.strip() else None


def run_url():
    keys = ("GITHUB_SERVER_URL", "GITHUB_REPOSITORY", "GITHUB_RUN_ID")
    if all(os.environ.get(k) for k in keys):
        server, repo, run = (os.environ[k] for k in keys)
        return f"{server}/{repo}/actions/runs/{run}"
    return None


def cell(text):
    return (text or "").replace("|", "\\|").replace("\n", " ")


# ── Issue bodies ────────────────────────────────────────────────────────────


def entry_body(entry):
    lines = [
        ENTRY_MARKER.format(entry["id"]),
        "`nix run .#blocked` reports this entry in `docs/blocked.toml` as "
        "unblocked.",
        "",
        f"**Evidence:** {entry['evidence']}",
    ]
    for key, label in (
        ("upstream", "Upstream"),
        ("workaround", "Workaround"),
        ("then", "Then"),
    ):
        if entry.get(key):
            lines.append(f"**{label}:** {entry[key]}")
    lines += [
        "",
        "Once it is done, delete the entry in the same commit; the next run "
        "closes this issue.",
    ]
    return "\n".join(lines)


def error_body(entries):
    lines = [
        ERROR_MARKER,
        "These checks in `docs/blocked.toml` failed, so nothing is known "
        "about them. Fix the check, not the entry's status.",
        "",
        "| ID | Error |",
        "| --- | --- |",
    ]
    lines += [f"| `{e['id']}` | {cell(e['evidence'])} |" for e in entries]
    return "\n".join(lines)


def footer(report):
    where = f"[this run]({run_url()})" if run_url() else "a local run"
    rev = (report.get("revision") or "unknown")[:12]
    return f"{FOOTER}<sub>Opened by {where} at {rev}.</sub>"


def content(body):
    return (body or "").split(FOOTER, 1)[0]


# ── Planning ────────────────────────────────────────────────────────────────


def plan(report, open_entry_issues, open_error_issue):
    """Return the actions to take, as (verb, description, call) tuples."""
    actions = []
    by_id = {e["id"]: e for e in report["entries"]}

    for entry in report["entries"]:
        if entry["status"] != "unblocked":
            continue
        issue = open_entry_issues.get(entry["id"])
        body = entry_body(entry)
        if issue is None:
            actions.append(
                (
                    "open",
                    f"Unblocked: {entry['title']}",
                    (
                        "POST",
                        "issues",
                        {
                            "title": f"Unblocked: {entry['title']}",
                            "body": body + footer(report),
                            "labels": ["unblocked"],
                        },
                    ),
                )
            )
        elif content(issue["body"]) != body:
            tail = issue["body"][len(content(issue["body"])):]
            actions.append(
                (
                    "edit",
                    f"#{issue['number']} ({entry['id']})",
                    (
                        "PATCH",
                        f"issues/{issue['number']}",
                        {"body": body + tail},
                    ),
                )
            )

    for ident, issue in open_entry_issues.items():
        entry = by_id.get(ident)
        if entry is None:
            note = (
                f"`{ident}` is no longer in `docs/blocked.toml` at "
                f"{(report.get('revision') or 'unknown')[:12]}, so the work "
                "is done. Closing."
            )
            reason = "completed"
        elif entry["status"] == "blocked":
            note = (
                f"Blocked again: {entry['evidence']}. Closing; a new issue "
                "opens if it unblocks again."
            )
            reason = "not_planned"
        else:
            # error or manual: the check could not say, so neither can we.
            continue
        actions += close(issue, ident, note, reason)

    errors = [e for e in report["entries"] if e["status"] == "error"]
    if errors:
        body = error_body(errors)
        if open_error_issue is None:
            actions.append(
                (
                    "open",
                    "blocked: checks failing",
                    (
                        "POST",
                        "issues",
                        {
                            "title": "blocked: checks failing",
                            "body": body + footer(report),
                            "labels": ["blocked-error"],
                        },
                    ),
                )
            )
        elif content(open_error_issue["body"]) != body:
            issue = open_error_issue
            tail = issue["body"][len(content(issue["body"])):]
            actions.append(
                (
                    "edit",
                    f"#{issue['number']} (checks failing)",
                    (
                        "PATCH",
                        f"issues/{issue['number']}",
                        {"body": body + tail},
                    ),
                )
            )
    elif open_error_issue is not None:
        actions += close(
            open_error_issue,
            "checks failing",
            "Every check runs again. Closing.",
            "completed",
        )
    return actions


def close(issue, what, note, reason):
    number = issue["number"]
    return [
        (
            "comment",
            f"#{number} ({what}): {note}",
            ("POST", f"issues/{number}/comments", {"body": note}),
        ),
        (
            "close",
            f"#{number} ({what})",
            (
                "PATCH",
                f"issues/{number}",
                {"state": "closed", "state_reason": reason},
            ),
        ),
    ]


# ── GitHub state ────────────────────────────────────────────────────────────


def open_issues(repo, label):
    issues = gh(f"repos/{repo}/issues?state=open&labels={label}&per_page=100")
    # The issues endpoint also returns pull requests.
    return [i for i in issues if "pull_request" not in i]


def ensure_labels(repo):
    existing = {label["name"] for label in gh(f"repos/{repo}/labels")}
    for name, (color, description) in LABELS.items():
        if name not in existing:
            gh(
                "-X",
                "POST",
                f"repos/{repo}/labels",
                payload={
                    "name": name,
                    "color": color,
                    "description": description,
                },
            )


def current_repo():
    if os.environ.get("GITHUB_REPOSITORY"):
        return os.environ["GITHUB_REPOSITORY"]
    proc = subprocess.run(
        ["gh", "repo", "view", "--json", "nameWithOwner", "-q",
         ".nameWithOwner"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise GitHubError(proc.stderr.strip() or "cannot tell which repo")
    return proc.stdout.strip()


# ── Main ────────────────────────────────────────────────────────────────────


def load_report(path):
    if path is not None:
        return json.loads(path.read_text())
    proc = subprocess.run(
        ["blocked", "--format", "json"], capture_output=True, text=True
    )
    # 1 only means some checks returned `error`; the report is still whole,
    # and reporting those errors is part of this tool's job.
    if proc.returncode not in (0, 1):
        sys.stderr.write(proc.stderr)
        raise SystemExit(proc.returncode)
    return json.loads(proc.stdout)


def write_summary(report, actions):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    lines = [
        "## docs/blocked.toml",
        "",
        "| Status | ID | Evidence |",
        "| --- | --- | --- |",
    ]
    lines += [
        f"| {e['status']} | `{e['id']}` | {cell(e['evidence'])} |"
        for e in report["entries"]
    ]
    lines += ["", "### Issue changes", ""]
    lines += [f"- {verb}: {cell(what)}" for verb, what, _ in actions] or [
        "- none"
    ]
    with open(path, "a") as f:
        f.write("\n".join(lines) + "\n")


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="blocked-report",
        description="Keep GitHub issues in step with `nix run .#blocked`.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print what would change on GitHub, and change nothing",
    )
    parser.add_argument(
        "--input",
        type=pathlib.Path,
        help="a saved `blocked --format json` report, instead of running it",
    )
    args = parser.parse_args(argv)

    report = load_report(args.input)
    try:
        repo = current_repo()
        entry_issues = {}
        for issue in open_issues(repo, "unblocked"):
            match = ENTRY_MARKER_RE.search(issue.get("body") or "")
            if match:
                entry_issues[match.group(1)] = issue
        error_issue = next(
            (
                i
                for i in open_issues(repo, "blocked-error")
                if ERROR_MARKER in (i.get("body") or "")
            ),
            None,
        )
        actions = plan(report, entry_issues, error_issue)

        prefix = "would " if args.dry_run else ""
        for verb, what, _ in actions:
            print(f"{prefix}{verb}: {what}")
        if not actions:
            print("no issue changes")

        if not args.dry_run:
            if actions:
                ensure_labels(repo)
            for _, _, (method, path, payload) in actions:
                gh("-X", method, f"repos/{repo}/{path}", payload=payload)
    except GitHubError as e:
        print(f"blocked-report: {e}", file=sys.stderr)
        return 1

    write_summary(report, actions)
    return 0


if __name__ == "__main__":
    sys.exit(main())
