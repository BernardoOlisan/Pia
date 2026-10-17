#!/usr/bin/env bash
# SessionEnd hook: when a lead's session ends, stop the keep-awake of the works it was leading.
# Nothing keeps running once the lead is gone (its teammates end with it), so the machine may sleep.
# Events that carry an agent_id come from a subagent or teammate, not the lead, and are ignored.
set -u

input="$(cat)"
case "$input" in
  *'"agent_id"'*) exit 0 ;;
esac

session="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
[ -n "$session" ] || exit 0

here="$(cd "$(dirname "$0")" && pwd)"
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
python3 "$here/works.py" list "$root" 2>/dev/null | python3 "$here/works.py" _dirs-led-by "$session" | while IFS= read -r dir; do
  [ -f "$dir/caffeinate.pid" ] || continue
  bash "$here/awake.sh" stop "$dir" >/dev/null 2>&1
  if [ -f "$dir/log.md" ]; then
    bash "$here/log.sh" "$dir/log.md" "session ended; keep-awake stopped" --doing "waiting for the lead to come back" >/dev/null 2>&1
  fi
done
exit 0
