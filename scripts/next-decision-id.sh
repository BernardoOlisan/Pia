#!/usr/bin/env bash
# Reserve decision IDs safely, even when two works run at the same time.
#
#   next-decision-id.sh <project-root> <work-id> [count]
#
# Takes a lock, finds the highest D-NNN used anywhere in .pia/, appends one "reserved" line per new ID
# to .pia/DECISIONS.md, releases the lock, and prints the reserved IDs (one per line).
# The researcher later replaces each reserved line with the real one.
set -u

root="${1:-}"
work="${2:-}"
count="${3:-1}"
if [ -z "$root" ] || [ -z "$work" ]; then
  echo "usage: next-decision-id.sh <project-root> <work-id> [count]" >&2
  exit 1
fi
case "$count" in
  ''|*[!0-9]*) echo "next-decision-id: count must be a number" >&2; exit 1 ;;
esac

pia="$root/.pia"
memory="$pia/DECISIONS.md"
lock="$pia/.decision-id.lock"
[ -f "$memory" ] || { echo "next-decision-id: $memory not found (run /pia:init)" >&2; exit 1; }

# mkdir is atomic: whoever creates the lock folder first wins. Stale locks (older than 2 minutes) are cleared.
tries=0
until mkdir "$lock" 2>/dev/null; do
  if [ -n "$(find "$lock" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
    rmdir "$lock" 2>/dev/null
    continue
  fi
  tries=$((tries + 1))
  if [ "$tries" -gt 100 ]; then
    echo "next-decision-id: could not get the lock at $lock" >&2
    exit 1
  fi
  sleep 0.1
done
trap 'rmdir "$lock" 2>/dev/null' EXIT

# Highest ID used in the project memory and in every work's decision map, ignoring <!-- comments -->
# (templates carry example IDs there). PIA.md is not scanned: it only contains examples.
highest="$(cat "$memory" "$pia"/work/*/decisions.md 2>/dev/null \
  | perl -0777 -pe 's/<!--.*?-->//gs' \
  | grep -oE 'D-[0-9]{3,}' | sed 's/D-//' | sort -n | tail -n 1)"
next=$(( 10#${highest:-0} + 1 ))

i=0
while [ "$i" -lt "$count" ]; do
  id="$(printf 'D-%03d' "$next")"
  printf '%s  ⏳  [reserved] · work/%s · reserved\n' "$id" "$work" >> "$memory"
  echo "$id"
  next=$((next + 1))
  i=$((i + 1))
done
