#!/usr/bin/env python3
"""Where a project's works live, so every script and hook finds the same ones.

A project has two kinds of work:
  - **repo** works, in `<project>/.pia/work/<id>/`, committed with the project;
  - **disposable** works, in `~/.pia/disposable/<project key>/<id>/`, outside the repo, never committed.

    works.py root [dir]                 the project root for a folder (git top level, else the folder)
    works.py disposable-home [root]     where this project's disposable works live
    works.py list [root]                one JSON object per work: dir, id, kind, title, phase, round, mode, lead_session
    works.py lead <session id> [root]   the works this session leads that are not done, same format
    works.py next-id <slug> [root] [--disposable]   the folder a new work should get, e.g. .../003-export-pdf
"""
import json
import os
import re
import subprocess
import sys

HOME = os.environ.get("PIA_HOME") or os.path.join(os.path.expanduser("~"), ".pia")


def project_root(start=None):
    start = os.path.abspath(start or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    try:
        top = subprocess.run(["git", "-C", start, "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, timeout=5).stdout.strip()
        if top:
            return os.path.realpath(top)
    except (OSError, subprocess.SubprocessError):
        pass
    return os.path.realpath(start)


def project_key(root):
    """The same key Claude Code uses for its own per-project folders: the path, with every other character a dash."""
    return re.sub(r"[^A-Za-z0-9]", "-", os.path.realpath(root))


def disposable_home(root):
    return os.path.join(HOME, "disposable", project_key(root))


def work_dirs(root):
    found = []
    for base, kind in ((os.path.join(root, ".pia", "work"), "repo"), (disposable_home(root), "disposable")):
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            d = os.path.join(base, name)
            if os.path.isfile(os.path.join(d, "state.json")):
                found.append((d, kind))
    return found


def all_works(root):
    return [d for d, _ in work_dirs(root)]


def describe(d, kind):
    try:
        with open(os.path.join(d, "state.json"), encoding="utf-8") as f:
            state = json.load(f)
    except (OSError, ValueError):
        state = {}
    return {
        "dir": d,
        "id": state.get("id") or os.path.basename(d),
        "kind": state.get("kind") or kind,
        "title": state.get("title", ""),
        "phase": state.get("phase", ""),
        "round": state.get("round", 0),
        "mode": state.get("mode", ""),
        "lead_session": state.get("lead_session", ""),
    }


def listing(root):
    return [describe(d, kind) for d, kind in work_dirs(root)]


def next_id(slug, root, disposable):
    base = disposable_home(root) if disposable else os.path.join(root, ".pia", "work")
    highest = 0
    if os.path.isdir(base):
        for name in os.listdir(base):
            m = re.match(r"^(\d{3,})-", name)
            if m:
                highest = max(highest, int(m.group(1)))
    slug = re.sub(r"[^a-z0-9]+", "-", slug.lower()).strip("-") or "work"
    return os.path.join(base, f"{highest + 1:03d}-{slug}")


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    cmd, args = argv[1], argv[2:]
    if cmd == "root":
        print(project_root(args[0] if args else None))
    elif cmd == "disposable-home":
        print(disposable_home(project_root(args[0] if args else None)))
    elif cmd == "list":
        for w in listing(project_root(args[0] if args else None)):
            print(json.dumps(w, ensure_ascii=False))
    elif cmd == "lead" and args:
        root = project_root(args[1] if len(args) > 1 else None)
        for w in listing(root):
            if w["lead_session"] == args[0] and w["phase"] not in ("done", ""):
                print(json.dumps(w, ensure_ascii=False))
    elif cmd == "next-id" and args:
        disposable = "--disposable" in args
        rest = [a for a in args if a != "--disposable"]
        print(next_id(rest[0], project_root(rest[1] if len(rest) > 1 else None), disposable))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
