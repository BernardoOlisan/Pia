#!/usr/bin/env bash
# SessionStart hook: keep the dictation process (the ⌥Space shortcut and /pia:transcribe) running while Claude Code is open.
# The first time, it builds pia-voice in the background and starts it when the build finishes.
# Prints nothing: SessionStart output would reach Claude.
set -u
cat >/dev/null

[ "$(uname -s)" = Darwin ] || exit 0
[ -z "${CLAUDE_CODE_REMOTE:-}" ] || exit 0

here="$(cd "$(dirname "$0")" && pwd)"
if bash "$here/voice-bin.sh" ready; then
  "$here/../voice/.build/release/pia-voice" dictate ensure >/dev/null 2>&1
else
  bash "$here/voice-bin.sh" build >/dev/null 2>&1
fi
exit 0
