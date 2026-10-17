#!/usr/bin/env python3
"""One line from PIA Awake's status JSON (stdin), for awake.sh status and /pia:status."""
import json
import sys

s = json.load(sys.stdin)
if not s.get("running", True):
    print("PIA Awake: idle (no work is running)")
    sys.exit(0)
if s.get("holdingAwake"):
    hold = "holding the Mac awake"
elif not s.get("installed"):
    hold = "not installed (bash scripts/awake-install.sh)"
else:
    hold = f"not holding ({s.get('reason', '')})"
lid = "lid closed" if s.get("lidClosed") else "lid open"
battery = s.get("battery")
power = ("charging" if s.get("onAC") else "battery") + (f" {battery}%" if battery is not None else "")
works = len(s.get("runningWorks", []))
print(f"PIA Awake: {hold} · {lid} · {power} · network {s.get('network')} · {works} work{'s' if works != 1 else ''}")
