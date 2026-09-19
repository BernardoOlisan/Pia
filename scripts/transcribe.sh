#!/usr/bin/env bash
# UserPromptExpansion hook for /pia:transcribe: start or stop a dictation, and block the command
# (exit 2) so it never reaches Claude. The text lands in the clipboard, not in the conversation.
#
# "/pia:transcribe follow" records a take that is added to the last one, so the clipboard carries
# everything said since the last fresh take. The shortcut for the same thing is ⌥⇧Space.
set -u

prompt="$(cat)"
append=""
case "$prompt" in
  *follow*) append="--append" ;;
esac

here="$(cd "$(dirname "$0")" && pwd)"
bin="$here/../voice/.build/release/pia-voice"

if [ "$(uname -s)" != Darwin ]; then
  echo "PIA Transcribe needs macOS." >&2
  exit 2
fi

if ! bash "$here/voice-bin.sh" ready; then
  bash "$here/voice-bin.sh" build
  echo "PIA Voice is being built once (a few minutes). Try /pia:transcribe or ⌥Space again when it's ready." >&2
  exit 2
fi

if ! "$bin" dictate toggle $append >/dev/null 2>&1; then
  echo "PIA Transcribe could not start. Log: ~/Library/Application Support/PIA Voice/dictate.log" >&2
  exit 2
fi
if [ -n "$append" ]; then echo "🎙️+" >&2; else echo "🎙️" >&2; fi
exit 2
