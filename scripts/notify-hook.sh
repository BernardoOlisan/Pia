#!/usr/bin/env bash
# Notification hook: when Claude Code waits on a permission prompt or a question in a PIA lead session
# that is in the loop, tell the human with the owl. Other sessions are left to Claude Code's own alerts.
set -u
input="$(cat)"
here="$(cd "$(dirname "$0")" && pwd)"
session="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
[ -n "$session" ] || exit 0
message="$(printf '%s' "$input" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("message",""))
except Exception: print("")')"
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
work="$(python3 "$here/works.py" lead "$session" "$root" 2>/dev/null | head -n 1 | python3 -c 'import json,sys
line=sys.stdin.read().strip()
print(json.loads(line)["dir"] if line else "")')"
[ -n "$work" ] || exit 0
python3 "$here/notify.py" "$work" permission "${message:-Claude Code is waiting for you.}" >/dev/null 2>&1
exit 0
