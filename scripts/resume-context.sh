#!/usr/bin/env bash
# SessionStart (compact) hook: after a compaction, tell the agent where its PIA work stands.
# Prints the state and the "## Now" section of every active work (the one this session leads first).
set -u

input="$(cat)"
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
work_root="$root/.pia/work"
[ -d "$work_root" ] || exit 0

session="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

field() {
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -n 1
}

now_section() {
  [ -f "$1" ] || return 0
  awk '/^## Now/{on=1; print; next} /^## /{if(on) exit} on{print}' "$1"
}

mine=""
others=""
for state in "$work_root"/*/state.json; do
  [ -f "$state" ] || continue
  phase="$(field "$state" phase)"
  case "$phase" in
    done|"") continue ;;
  esac
  if [ -n "$session" ] && [ "$(field "$state" lead_session)" = "$session" ]; then
    mine="$mine $state"
  else
    others="$others $state"
  fi
done

[ -n "$mine$others" ] || exit 0

print_work() {
  local state="$1" dir id
  dir="$(dirname "$state")"
  id="$(basename "$dir")"
  echo
  echo "### Work $id: $(field "$state" title)"
  echo "phase: $(field "$state" phase) · mode: $(field "$state" mode) · folder: .pia/work/$id"
  now_section "$dir/log.md"
}

echo "PIA: context restored after compaction."
echo "Before doing anything else: re-read .pia/PIA.md (\"All agents\" and your phase sections), then state.json and the \"## Now\" section of log.md for your work."

if [ -n "$mine" ]; then
  echo
  echo "## The work this session leads"
  for s in $mine; do print_work "$s"; done
fi
if [ -n "$others" ]; then
  echo
  echo "## Other active works in this project"
  for s in $others; do print_work "$s"; done
fi
exit 0
