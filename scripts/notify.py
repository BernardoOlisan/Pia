#!/usr/bin/env python3
"""Tell the human, with a macOS notification, when a work needs them — only while they are in the loop.

    notify.py <work folder> <kind> "<what happened>"
    notify.py --from-log <log file> "<entry text>" [--phase <phase>]     (log.py calls this)

Kinds: ready (decision map finished), done (a build or a round finished), stalled (an agent stopped
moving), permission (Claude Code or the lead needs an answer). A work running out-of-the-loop never
notifies: the human said they are away.

Notifications run in the background and never fail the caller.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

TEXT = {
    "es": {
        "ready": "Tu mapa de decisiones está listo",
        "done_build": "Implementación terminada",
        "done_round": "Ronda {round} terminada",
        "stalled": "Un agente se trabó",
        "permission": "Necesito tu permiso",
        "question": "Tengo una pregunta",
        "ready_body": "Te espera para que lo revises.",
        "done_body": "Lista para que pruebes.",
    },
    "en": {
        "ready": "Your decision map is ready",
        "done_build": "Implementation finished",
        "done_round": "Round {round} finished",
        "stalled": "An agent got stuck",
        "permission": "I need your permission",
        "question": "I have a question",
        "ready_body": "It's waiting for your review.",
        "done_body": "Ready for you to test.",
    },
}


def language():
    try:
        with open(os.path.join(os.path.expanduser("~"), ".pia", "config.json"), encoding="utf-8") as f:
            lang = str(json.load(f).get("language", ""))
    except (OSError, ValueError):
        lang = os.environ.get("LANG", "en")
    return "es" if lang.lower().startswith("es") else "en"


def state(work):
    try:
        with open(os.path.join(work, "state.json"), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def app():
    try:
        out = subprocess.run(["bash", os.path.join(HERE, "pia-app.sh"), "path"], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout.strip() if out.returncode == 0 and out.stdout.strip() else None


def clean(text, limit=160):
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def send(work, kind, title, body):
    s = state(work)
    if not s or s.get("mode") != "in-the-loop":
        return False
    binary = app()
    if not binary:
        subprocess.Popen(["bash", os.path.join(HERE, "pia-app.sh"), "build"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return False
    subtitle = s.get("id", os.path.basename(work))
    if s.get("title"):
        subtitle = f"{subtitle} · {clean(s['title'], 60)}"
    subprocess.Popen(
        [binary, "notify", "--kind", kind, "--title", title, "--subtitle", subtitle, "--body", clean(body), "--thread", s.get("id", "pia")],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
    )
    return True


def map_summary(work):
    try:
        with open(os.path.join(work, "decisions.md"), encoding="utf-8") as f:
            m = re.search(r"^\*\*Summary:\*\*\s*(.*)$", f.read(), re.M)
            return m.group(1) if m else ""
    except OSError:
        return ""


def from_log(log, text, phase):
    """Notify for the moments that need the human, read from the lead's own log entries."""
    work = os.path.dirname(os.path.abspath(log))
    if os.path.basename(log) != "log.md" or not os.path.isfile(os.path.join(work, "state.json")):
        return
    t = TEXT[language()]
    first = text.strip().split("\n")[0]
    upper = first.upper()
    s = state(work) or {}
    if phase == "awaiting-review":
        send(work, "ready", t["ready"], map_summary(work) or t["ready_body"])
    elif upper.startswith("IMPLEMENTATION DONE"):
        send(work, "done", t["done_build"], first.split(":", 1)[-1] if ":" in first else t["done_body"])
    elif upper.startswith("FIXES DONE") or re.match(r"^ROUND \d+ DONE", upper):
        r = s.get("round", "")
        send(work, "done", t["done_round"].format(round=r), first.split(":", 1)[-1] if ":" in first else t["done_body"])
    elif upper.startswith("STALLED"):
        send(work, "stalled", t["stalled"], first.split(":", 1)[-1] if ":" in first else first)
    elif upper.startswith("ASKED"):
        send(work, "permission", t["question"], first.split(":", 1)[-1] if ":" in first else first)


def main(argv):
    try:
        if len(argv) >= 3 and argv[1] == "--from-log":
            phase = argv[argv.index("--phase") + 1] if "--phase" in argv else None
            from_log(argv[2], argv[3] if len(argv) > 3 else "", phase)
        elif len(argv) == 4:
            work, kind, body = argv[1:]
            t = TEXT[language()]
            title = {"ready": t["ready"], "done": t["done_body"], "stalled": t["stalled"], "permission": t["permission"]}.get(kind, "PIA")
            send(work, kind, title, body)
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except Exception as e:  # never break the caller over a notification
        print(f"notify: {e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
