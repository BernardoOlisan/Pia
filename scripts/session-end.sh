#!/usr/bin/env bash
# SessionEnd hook: when a lead's session ends, stop the keep-awake of the works it was leading.
# Nothing keeps running once the lead is gone (its teammates end with it), so the machine may sleep.
# Events that carry an agent_id come from a subagent or teammate, not the lead, and are ignored.
set -u

input="$(cat)"
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
work_root="$root/.pia/work"
[ -d "$work_root" ] || exit 0

case "$input" in
  *'"agent_id"'*) exit 0 ;;
esac

session="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
[ -n "$session" ] || exit 0

here="$(cd "$(dirname "$0")" && pwd)"
for state in "$work_root"/*/state.json; do
  [ -f "$state" ] || continue
  lead="$(sed -n 's/.*"lead_session"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$state" | head -n 1)"
  [ "$lead" = "$session" ] || continue
  dir="$(dirname "$state")"
  [ -f "$dir/caffeinate.pid" ] || continue
  bash "$here/awake.sh" stop "$dir" >/dev/null 2>&1
  if [ -f "$dir/log.md" ]; then
    printf '%s · lead · session ended; keep-awake stopped\n' "$(date '+%Y-%m-%d %H:%M')" >> "$dir/log.md"
  fi
done
exit 0
