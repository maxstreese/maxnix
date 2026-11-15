"""Turn an `nvd diff` report into the Markdown posted on a lock PR.

nvd's report is the source: this only regroups it and adds links. The
table at the top holds what the configuration names: the packages in
environment.systemPackages and in max's Home Manager profile, the kernel,
and whatever nvd marks as selected (the `*` or `+` after the status
letter). What merely came along as a dependency is folded away below it,
as are additions, removals and nvd's own text.

Links come from nixpkgs' metadata, looked up by name in the flake's package
set (--flake) where a package of that name exists: the name links to its
homepage and "changes" to `meta.changelog`, which many packages point at
the release notes of the very version. A store name is not always an
attribute name, so some rows have no link, and none is guessed.

  closure-table.py --nvd report.txt [--flake .] [--base-rev REV]
                   [--base-lock FILE --head-lock FILE]
"""

import argparse
import json
import re
import subprocess
import sys

LIMIT = 60000  # GitHub refuses a comment over 65536 characters.

ROW = re.compile(r"^\[(?P<status>[UDCAR])(?P<sel>[.*+])\]\s+#\d+\s+"
                 r"(?P<name>\S+)\s+(?P<rest>.*)$")
SUFFIX = re.compile(r"-[a-z_]+$")


def versions(text):
    """nvd's version list, reduced to the versions themselves.

    "5.3p15 x3, 5.3p15-doc, 5.3p15-man x2" is one version in several
    outputs; "<none>" is a path without a version, such as a config file.
    """
    seen = []
    for part in text.split(", "):
        part = re.sub(r" x\d+$", "", part.strip())
        if part in ("", "<none>"):
            continue
        base = SUFFIX.sub("", part)
        if re.search(r"\d", base):
            part = base
        if part not in seen:
            seen.append(part)
    return ", ".join(seen)


def parse(report):
    changed, added, removed, size = [], [], [], ""
    for line in report.splitlines():
        if line.startswith("Closure size:"):
            size = line
            continue
        m = ROW.match(line)
        if not m:
            continue
        status, name, rest = m["status"], m["name"], m["rest"]
        if status == "A":
            added.append((name, versions(rest)))
        elif status == "R":
            removed.append((name, versions(rest)))
        elif " -> " in rest:
            # Without an arrow it is one of nvd's "Selection state changes"
            # ([C+] hello 2.12.3): a package that became, or stopped being,
            # named by the system. Its version did not move.
            old, _, new = rest.partition(" -> ")
            changed.append({
                "name": name,
                "old": versions(old),
                "new": versions(new),
                "selected": m["sel"] != ".",
                "downgrade": status == "D",
            })
    return changed, added, removed, size


META_EXPR = """
pkgs: names:
let
  find = name:
    let
      py = builtins.match "python3\\\\.[0-9]+-(.*)" name;
    in
    if py != null then pkgs.python3Packages.${builtins.head py} or null
    else pkgs.${name} or null;
  one = name:
    let
      r = builtins.tryEval (
        let p = find name; in
        if p == null || !(p ? meta) then null
        else {
          homepage = p.meta.homepage or null;
          changelog = p.meta.changelog or null;
        }
      );
    in
    { inherit name; value = if r.success then r.value else null; };
in
builtins.listToAttrs (map one names)
"""


def metadata(flake, names):
    """homepage and changelog per name, or {} if the lookup fails."""
    if not flake or not names:
        return {}
    expr = "pkgs: (%s) pkgs (builtins.fromJSON ''%s'')" % (
        META_EXPR, json.dumps(sorted(names)))
    attr = flake + "#nixosConfigurations.t14s.pkgs"
    try:
        out = subprocess.run(
            ["nix", "eval", "--json", attr, "--apply", expr],
            check=True, capture_output=True, text=True).stdout
        return {k: v for k, v in json.loads(out).items() if v}
    except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
        print("closure-table: no links, lookup failed: %s" % e,
              file=sys.stderr)
        return {}


NAMED_EXPR = """
c:
let
  name = p: p.pname or (builtins.parseDrvName (p.name or "")).name;
in
map name (
  c.environment.systemPackages
  ++ c.home-manager.users.max.home.packages
  ++ [ c.boot.kernelPackages.kernel ]
)
"""


def named_by_config(flake):
    """Names the configuration installs itself, or an empty set."""
    if not flake:
        return set()
    attr = flake + "#nixosConfigurations.t14s.config"
    try:
        out = subprocess.run(
            ["nix", "eval", "--json", attr, "--apply", NAMED_EXPR],
            check=True, capture_output=True, text=True).stdout
        return set(json.loads(out))
    except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
        print("closure-table: grouping by nvd's marks only: %s" % e,
              file=sys.stderr)
        return set()


def nixpkgs_rev(lock_file):
    try:
        with open(lock_file) as f:
            lock = json.load(f)
        node = lock["nodes"][lock["nodes"]["root"]["inputs"]["nixpkgs"]]
        return node["locked"]["rev"]
    except (OSError, KeyError, json.JSONDecodeError):
        return None


def table(rows, meta):
    lines = ["| package | from | to | |", "|---|---|---|---|"]
    for r in rows:
        m = meta.get(r["name"], {})
        name = r["name"]
        if m.get("homepage"):
            name = "[%s](%s)" % (name, m["homepage"])
        notes = []
        if m.get("changelog"):
            notes.append("[changes](%s)" % m["changelog"])
        if r["downgrade"]:
            notes.append("downgrade")
        lines.append("| %s | %s | %s | %s |" % (
            name, r["old"], r["new"], ", ".join(notes)))
    return "\n".join(lines)


def folded(title, body):
    return "<details><summary>%s</summary>\n\n%s\n\n</details>" % (
        title, body)


def listing(items):
    return ", ".join(
        "%s %s" % (n, v) if v else n for n, v in items)


def render(report, meta, base_rev=None, base_nixpkgs=None,
           head_nixpkgs=None, config_names=frozenset()):
    changed, added, removed, size = parse(report)
    moved = [r for r in changed if r["old"] != r["new"]]
    same = [r for r in changed if r["old"] == r["new"]]

    def is_named(r):
        return r["selected"] or r["name"] in config_names

    named = [r for r in moved if is_named(r)]
    pulled = [r for r in moved if not is_named(r)]

    head = ["### Package changes on metal", ""]
    intro = "metal at %s (base) against this PR" % (
        base_rev[:7] if base_rev else "the base")
    if base_nixpkgs and head_nixpkgs and base_nixpkgs != head_nixpkgs:
        intro += (", nixpkgs [%s…%s](https://github.com/NixOS/nixpkgs/"
                  "compare/%s...%s)" % (base_nixpkgs[:7], head_nixpkgs[:7],
                                        base_nixpkgs, head_nixpkgs))
    head.append(intro + ". From `nix run .#closure-diff -- --markdown`.")
    if size:
        head += ["", size]

    parts = []
    if named:
        parts.append("**Installed by name (%d)**\n\n%s" % (
            len(named), table(named, meta)))
    if pulled:
        parts.append(folded(
            "Came along as dependencies (%d)" % len(pulled),
            table(pulled, meta)))
    if added:
        parts.append(folded("Added (%d)" % len(added), listing(added)))
    if removed:
        parts.append(folded("Removed (%d)" % len(removed),
                            listing(removed)))
    if same:
        parts.append(folded(
            "Same version, different outputs or builds (%d)" % len(same),
            ", ".join(r["name"] for r in same)))
    if not (moved or added or removed):
        parts.append("No package changes version.")
    raw = folded("nvd's report", "```\n%s\n```" % report.strip())

    # Too long for one comment: nvd's text goes first, being a repeat, then
    # the folded sections from the end.
    def text(sections):
        return "\n\n".join(["\n".join(head)] + sections) + "\n"

    sections = parts + [raw]
    while len(text(sections)) > LIMIT and len(sections) > 1:
        sections.pop()
    out = text(sections)
    if len(sections) < len(parts) + 1:
        out += ("\nShortened to fit a comment; `nix run .#closure-diff` "
                "prints all of it.\n")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--nvd", required=True)
    ap.add_argument("--flake")
    ap.add_argument("--base-rev")
    ap.add_argument("--base-lock")
    ap.add_argument("--head-lock")
    args = ap.parse_args()

    with open(args.nvd) as f:
        report = f.read()
    changed, _, _, _ = parse(report)
    names = {r["name"] for r in changed if r["old"] != r["new"]}
    sys.stdout.write(render(
        report,
        metadata(args.flake, names),
        base_rev=args.base_rev,
        base_nixpkgs=args.base_lock and nixpkgs_rev(args.base_lock),
        head_nixpkgs=args.head_lock and nixpkgs_rev(args.head_lock),
        config_names=named_by_config(args.flake),
    ))


if __name__ == "__main__":
    main()
