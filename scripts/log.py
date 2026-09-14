#!/usr/bin/env python3
"""Write one PIA log entry and refresh the log's "## Now" in the same step.

    log.sh <log file> "<what happened>" --doing "<what you're doing now>"
           [--next "..."] [--blockers "..."] [--phase "..."] [--team "..."]

The time comes from the machine clock, so it is never guessed. `--doing` is required: every
entry also says what the agent is doing now, so "## Now" never goes stale.
"""
import argparse
import datetime
import os
import sys
import tempfile

NOW_FIELDS = [("phase", "Phase"), ("doing", "Doing"), ("team", "Team"), ("next", "Next"), ("blockers", "Blockers")]


def section_bounds(lines, title):
    """(start, end) of the lines inside a `## title` section, or None."""
    for i, line in enumerate(lines):
        if line.strip() == f"## {title}":
            end = len(lines)
            for j in range(i + 1, len(lines)):
                if lines[j].startswith("## "):
                    end = j
                    break
            return i + 1, end
    return None


def main():
    p = argparse.ArgumentParser(prog="log.sh", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("file")
    p.add_argument("text")
    p.add_argument("--doing", required=True)
    for key, _ in NOW_FIELDS:
        if key != "doing":
            p.add_argument(f"--{key}")
    args = p.parse_args()

    if not os.path.isfile(args.file):
        sys.exit(f"log: file not found: {args.file} (create it from the template first)")

    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    with open(args.file, encoding="utf-8") as f:
        lines = f.read().split("\n")

    # 1. Refresh "## Now".
    bounds = section_bounds(lines, "Now")
    if bounds is None:
        lines[1:1] = ["", "## Now", ""]
        bounds = section_bounds(lines, "Now")
    start, end = bounds
    body = lines[start:end]
    updates = [(label, getattr(args, key)) for key, label in NOW_FIELDS if getattr(args, key) is not None]
    updates.append(("Updated", stamp))
    for label, value in updates:
        text = " ".join(str(value).split())
        prefix = f"- **{label}:**"
        new = f"{prefix} {text}"
        for k, line in enumerate(body):
            if line.startswith(prefix):
                body[k] = new
                break
        else:
            last = max((k for k, line in enumerate(body) if line.startswith("- **")), default=-1)
            body.insert(last + 1, new)
    lines[start:end] = body

    # 2. Append the entry at the end of "## Entries".
    bounds = section_bounds(lines, "Entries")
    if bounds is None:
        lines += ["", "## Entries"]
        bounds = section_bounds(lines, "Entries")
    start, end = bounds
    insert_at = end
    while insert_at > start and lines[insert_at - 1].strip() == "":
        insert_at -= 1
    text_lines = args.text.strip().split("\n")
    entry = [f"- {stamp} · {text_lines[0]}"] + [f"  {line}" for line in text_lines[1:]]
    lines[insert_at:insert_at] = entry

    content = "\n".join(lines)
    if not content.endswith("\n"):
        content += "\n"
    folder = os.path.dirname(os.path.abspath(args.file))
    fd, tmp = tempfile.mkstemp(dir=folder, prefix=".log-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(content)
    os.replace(tmp, args.file)
    print(f"logged {stamp}")


if __name__ == "__main__":
    main()
