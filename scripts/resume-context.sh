#!/usr/bin/env bash
# SessionStart (compact) hook: after a compaction, tell a PIA agent where its work stands.
#
# Only PIA sessions get anything: the lead of a work and that lead's teammates. In-process teammates
# report the lead's session_id, so matching session_id against state.json → lead_session covers both.
# Disposable works (outside the repo) count too. Any other session compacts normally, with nothing injected.
set -u

input="$(cat)"
session="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
[ -n "$session" ] || exit 0

here="$(cd "$(dirname "$0")" && pwd)"
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
python3 "$here/works.py" resume "$session" "$root" 2>/dev/null
exit 0
