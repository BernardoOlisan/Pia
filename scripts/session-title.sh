#!/usr/bin/env bash
# SessionStart and UserPromptSubmit hook: a session that leads a PIA work is named after it —
# "PIA lead 002", or "PIA desechable 001" — so `claude --resume "PIA lead 002"` finds it.
# A new lead gets its name at the first prompt after /pia:new created the work. Any other session is
# left alone, and so is a session already carrying that name.
set -u
input="$(cat)"
here="$(cd "$(dirname "$0")" && pwd)"
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
printf '%s' "$input" | python3 "$here/works.py" _title "$root"
exit 0
