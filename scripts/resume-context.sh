#!/usr/bin/env bash
# SessionStart (compact) hook: after a compaction, tell a PIA agent where its work stands.
#
# Only PIA sessions get anything: the lead of a work and that lead's teammates. In-process teammates
# report the lead's session_id, so matching session_id against state.json → lead_session covers both.
# Any other session in the project compacts normally, with nothing injected.
set -u

input="$(cat)"
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
work_root="$root/.pia/work"
[ -d "$work_root" ] || exit 0

session="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
[ -n "$session" ] || exit 0

field() {
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -n 1
}

now_section() {
  [ -f "$1" ] || return 0
  awk '/^## Now/{on=1; print; next} /^## /{if(on) exit} on{print}' "$1"
}

found=""
for state in "$work_root"/*/state.json; do
  [ -f "$state" ] || continue
  [ "$(field "$state" lead_session)" = "$session" ] || continue
  case "$(field "$state" phase)" in
    done|"") continue ;;
  esac
  found="$found $state"
done

[ -n "$found" ] || exit 0

echo "PIA: context restored after compaction."
echo "Before doing anything else: re-read .pia/PIA.md (\"All agents\" and your phase sections), then the files below."
echo "If you are a teammate (not the lead), also re-read your own log: logs/<your name>.md in the work folder."

for state in $found; do
  dir="$(dirname "$state")"
  id="$(basename "$dir")"
  echo
  echo "## Work $id: $(field "$state" title)"
  echo "phase: $(field "$state" phase) · mode: $(field "$state" mode) · folder: .pia/work/$id"
  now_section "$dir/log.md"
done
exit 0
