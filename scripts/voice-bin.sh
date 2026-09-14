#!/usr/bin/env bash
# The pia-voice binary. A plugin can't ship compiled Swift, so it's built on this Mac, and again when the sources change.
#
#   voice-bin.sh ready      exit 0 if the binary exists and no source is newer
#   voice-bin.sh building   exit 0 while a background build runs
#   voice-bin.sh build      build in the background (one at a time), then start the dictation process
#
# Build output: voice/.build/pia-build.log
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
voice="$root/voice"
bin="$voice/.build/release/pia-voice"
lock="$voice/.build/pia-build.pid"

ready() {
  [ -x "$bin" ] || return 1
  [ -z "$(find "$voice/Sources" "$voice/Package.swift" "$voice/Package.resolved" -newer "$bin" -print -quit 2>/dev/null)" ]
}

building() {
  [ -f "$lock" ] && kill -0 "$(tr -dc '0-9' < "$lock")" 2>/dev/null
}

case "${1:-}" in
  ready) ready ;;
  building) building ;;
  build)
    ready && exit 0
    building && exit 0
    command -v swift >/dev/null 2>&1 || { echo "voice-bin: swift not found (install Xcode or the command line tools)" >&2; exit 1; }
    mkdir -p "$voice/.build"
    # touch: a no-op build doesn't relink, and the binary must end up newer than the sources.
    nohup bash -c '
      echo $$ > "$1"
      if nice -n 10 swift build -c release --package-path "$2" > "$3" 2>&1; then
        touch "$4"
        "$4" dictate ensure >/dev/null 2>&1
      fi
      rm -f "$1"
    ' _ "$lock" "$voice" "$voice/.build/pia-build.log" "$bin" >/dev/null 2>&1 &
    ;;
  *)
    echo "usage: voice-bin.sh ready|building|build" >&2
    exit 1
    ;;
esac
