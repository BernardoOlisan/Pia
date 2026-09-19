#!/usr/bin/env bash
# The pia-voice binary. A plugin can't ship compiled Swift, so it's built on this Mac, and again when the sources change.
#
#   voice-bin.sh ready      exit 0 if the binary exists and no source is newer
#   voice-bin.sh building   exit 0 while a background build runs
#   voice-bin.sh build      build in the background (one at a time), then start the dictation process
#
# Swift builds into a SHARED scratch folder, not into the plugin. Every installed version of the plugin
# is its own copy, so building in place gave each one its own ~5 GB of checkouts and intermediates, and
# nothing was ever reused. Now the heavy tree lives once under Application Support, the finished 36 MB
# binary is copied into the plugin where every caller already expects it, and a new version's build is
# incremental instead of from scratch.
#
# Build output: ~/Library/Application Support/PIA Voice/build/pia-build.log
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
voice="$root/voice"
bin="$voice/.build/release/pia-voice"

shared="$HOME/Library/Application Support/PIA Voice/build"
# The lock is shared too: two installed versions must never build at the same time into one scratch path.
lock="$shared/pia-build.pid"
log="$shared/pia-build.log"

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
    mkdir -p "$shared" "$voice/.build/release"
    # cp, not a symlink: Prompts.locate resolves symlinks and then walks up looking for prompts/intent,
    # which only exists next to the plugin's copy.
    nohup bash -c '
      echo $$ > "$1"
      if nice -n 10 swift build -c release --package-path "$2" --scratch-path "$5" > "$3" 2>&1; then
        cp -f "$5/release/pia-voice" "$4" && "$4" dictate ensure >/dev/null 2>&1
      fi
      rm -f "$1"
    ' _ "$lock" "$voice" "$log" "$bin" "$shared" >/dev/null 2>&1 &
    ;;
  *)
    echo "usage: voice-bin.sh ready|building|build" >&2
    exit 1
    ;;
esac
