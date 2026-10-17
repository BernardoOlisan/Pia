#!/usr/bin/env python3
"""The decision map's bookkeeping, so nobody counts or searches by hand.

    decisions.py summary <decisions.md>
        Recount the cards and rewrite the map's **Summary:** line. Run it after writing or changing cards.

    decisions.py card <project root> D-NNN [D-NNN ...]
        Print those cards, wherever they live (every work, disposable ones too). Read a card this way
        instead of opening a whole decisions.md.

    decisions.py history <work folder> D-NNN "<what it said before>" "<old status>" "<why it changed>"
        Append one line to the work's decisions-history.md. The card itself keeps only what is true now.

    decisions.py check <project root>
        Report what has drifted: reserved IDs never written, a card whose status differs from its line in
        DECISIONS.md, IDs with no card or no line, summaries that no longer match, history stuffed into lines.
"""
import datetime
import os
import re
import sys

import works

CARD_HEAD = re.compile(r"^### (D-\d{3,})\b.*$", re.M)
WEIGHTS = (("🔴", "High"), ("🟡", "Medium"), ("🟢", "Low"))
AWAY = "Asked you during the talk; you were away."


def cards(text):
    """[(id, heading line, body)] for every card in a decisions.md, comments ignored."""
    clean = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    heads = list(CARD_HEAD.finditer(clean))
    out = []
    for i, m in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(clean)
        block = clean[m.start():end]
        block = re.split(r"\n---\s*\n|\n## ", block)[0]
        out.append((m.group(1), m.group(0), block.rstrip()))
    return out


def status_of(block):
    m = re.search(r"^\*\*Status:\*\*\s*([a-z]+)", block, re.M)
    return m.group(1) if m else ""


def weight_of(heading):
    for emoji, _ in WEIGHTS:
        if emoji in heading:
            return emoji
    return ""


def summary(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    found = cards(text)
    counts = {e: 0 for e, _ in WEIGHTS}
    statuses = {}
    away = 0
    for _, head, block in found:
        w = weight_of(head)
        if w:
            counts[w] += 1
        s = status_of(block)
        statuses[s] = statuses.get(s, 0) + 1
        if AWAY in block:
            away += 1
    parts = [f"{counts[e]} {e} {label}" for e, label in WEIGHTS]
    parts.append(f"{statuses.get('human', 0)} decided by you")
    if statuses.get("changed"):
        parts.append(f"{statuses['changed']} changed")
    if away:
        parts.append(f"{away} asked while you were away")
    line = "**Summary:** " + " · ".join(parts)
    if re.search(r"^\*\*Summary:\*\*.*$", text, re.M):
        text = re.sub(r"^\*\*Summary:\*\*.*$", line, text, count=1, flags=re.M)
    else:
        text = re.sub(r"^(# .*\n)", r"\1\n" + line + "\n", text, count=1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print(line)


def all_maps(root):
    for work in works.all_works(root):
        path = os.path.join(work, "decisions.md")
        if os.path.isfile(path):
            yield work, path


def card(root, ids):
    wanted = {i.upper() for i in ids}
    shown = set()
    for work, path in all_maps(root):
        with open(path, encoding="utf-8") as f:
            for cid, _, block in cards(f.read()):
                if cid in wanted:
                    print(f"<!-- {os.path.basename(work)} -->\n{block}\n")
                    shown.add(cid)
    for missing in sorted(wanted - shown):
        print(f"{missing}: no card found", file=sys.stderr)
    return 0 if shown else 1


def history(work, cid, before, old_status, why):
    path = os.path.join(work, "decisions-history.md")
    if not os.path.isfile(path):
        with open(path, "w", encoding="utf-8") as f:
            f.write("# Decision history\n\n> What each changed card used to say. The cards in decisions.md say only what is true now.\n\n")
    day = datetime.date.today().isoformat()
    before = " ".join(before.split())
    why = " ".join(why.split())
    with open(path, "a", encoding="utf-8") as f:
        f.write(f"- {day} · **{cid.upper()}** · was: {before} ({old_status}) · why: {why}\n")
    print(f"history: {cid.upper()} → {os.path.relpath(path)}")


def memory_lines(root):
    path = os.path.join(root, ".pia", "DECISIONS.md")
    lines = {}
    reserved = []
    if not os.path.isfile(path):
        return lines, reserved, path
    with open(path, encoding="utf-8") as f:
        text = re.sub(r"<!--.*?-->", "", f.read(), flags=re.S)
    for line in text.splitlines():
        m = re.match(r"^(D-\d{3,})\s", line)
        if not m:
            continue
        if "⏳" in line:
            reserved.append(m.group(1))
        lines[m.group(1)] = line
    return lines, reserved, path


def check(root):
    problems = []
    lines, reserved, memory = memory_lines(root)
    for cid in reserved:
        problems.append(f"{cid}: still ⏳ reserved in DECISIONS.md (its card was never written)")
    seen = {}
    for work, path in all_maps(root):
        with open(path, encoding="utf-8") as f:
            text = f.read()
        found = cards(text)
        for cid, _, block in found:
            seen.setdefault(cid, []).append(os.path.basename(work))
            line = lines.get(cid)
            if line is None:
                if os.path.isfile(memory):
                    problems.append(f"{cid}: card in {os.path.basename(work)} has no line in DECISIONS.md")
                continue
            card_status = status_of(block)
            line_status = line.rsplit("·", 1)[-1].strip() if "·" in line else ""
            if card_status and line_status and card_status != line_status and "⏳" not in line:
                problems.append(f"{cid}: card says {card_status}, DECISIONS.md says {line_status}")
            if len(line) > 300:
                problems.append(f"{cid}: its DECISIONS.md line is {len(line)} characters; history belongs in decisions-history.md")
        m = re.search(r"^\*\*Summary:\*\*.*$", text, re.M)
        if m:
            real = sum(1 for _, head, _ in found if weight_of(head))
            nums = [int(n) for n in re.findall(r"(\d+) (?:🔴|🟡|🟢)", m.group(0))]
            if nums and sum(nums) != real:
                problems.append(f"{os.path.basename(work)}: summary counts {sum(nums)} cards, the map has {real} (run: decisions.py summary)")
    for cid, where in seen.items():
        if len(where) > 1:
            problems.append(f"{cid}: has a card in more than one work ({', '.join(where)})")
    for cid in lines:
        if cid not in seen and cid not in reserved and "📌" not in lines[cid]:
            problems.append(f"{cid}: line in DECISIONS.md but no card in any work")
    for p in problems:
        print(p)
    if not problems:
        print("decisions: nothing has drifted")
    return 1 if problems else 0


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    cmd, args = argv[1], argv[2:]
    if cmd == "summary" and len(args) == 1:
        summary(args[0])
    elif cmd == "card" and len(args) >= 2:
        sys.exit(card(args[0], args[1:]))
    elif cmd == "history" and len(args) == 5:
        history(*args)
    elif cmd == "check" and len(args) == 1:
        sys.exit(check(args[0]))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
