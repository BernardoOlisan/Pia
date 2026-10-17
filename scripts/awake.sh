#!/usr/bin/env bash
# Keep the machine awake while a PIA work runs — with the lid closed too, when PIA Awake is installed.
#
#   awake.sh start  <work-dir>   caffeinate for this work, and register it with PIA Awake
#   awake.sh stop   <work-dir>   this work lets go (others keep theirs)
#   awake.sh status <work-dir>   this work's caffeinate, and what PIA Awake sees
#
# caffeinate -dims keeps an open Mac awake, and dies with Claude Code (-w). It cannot stop the Mac from
# sleeping when the lid closes; PIA Awake can (pmset disablesleep, installed once with awake-install.sh).
# It holds while any registered work's caffeinate is alive and lets go when none is.
set -u

cmd="${1:-}"
dir="${2:-}"
if [ -z "$cmd" ] || [ -z "$dir" ]; then
  echo "usage: awake.sh start|stop|status <work-dir>" >&2
  exit 1
fi
if [ ! -d "$dir" ]; then
  echo "awake: work folder not found: $dir" >&2
  exit 1
fi

here="$(cd "$(dirname "$0")" && pwd)"
dir="$(cd "$dir" && pwd)"
pidfile="$dir/caffeinate.pid"
support="${PIA_APP_SUPPORT:-$HOME/Library/Application Support/PIA}"
claims="$support/awake/claims"
claim="$claims/$(printf '%s' "$dir" | shasum | cut -c1-16).claim"

is_caffeinate() {
  local pid="${1:-}"
  [ -n "$pid" ] || return 1
  case "$(ps -p "$pid" -o comm= 2>/dev/null)" in
    *caffeinate) return 0 ;;
    *) return 1 ;;
  esac
}

saved_pid() {
  [ -f "$pidfile" ] && tr -dc '0-9' < "$pidfile"
}

app() {
  bash "$here/pia-app.sh" path 2>/dev/null
}

case "$cmd" in
  start)
    pid="$(saved_pid)"
    if is_caffeinate "$pid"; then
      echo "awake: already running (PID $pid)"
    elif ! command -v caffeinate >/dev/null 2>&1; then
      echo "awake: caffeinate is not available on this system; skipping"
      exit 0
    else
      watch=""
      if [ -n "${CLAUDE_PID:-}" ] && ps -p "$CLAUDE_PID" >/dev/null 2>&1; then
        watch="-w $CLAUDE_PID"
      fi
      # shellcheck disable=SC2086
      nohup caffeinate -dims $watch >/dev/null 2>&1 &
      pid=$!
      echo "$pid" > "$pidfile"
      echo "awake: started caffeinate -dims $watch (PID $pid) → $pidfile"
    fi
    mkdir -p "$claims"
    printf '%s\n%s\n' "$dir" "$pid" > "$claim"
    if bin="$(app)"; then
      if "$bin" awake ensure >/dev/null 2>&1; then
        if sudo -n -l /usr/bin/pmset -a disablesleep 1 >/dev/null 2>&1; then
          echo "awake: PIA Awake keeps the Mac working with the lid closed while this work runs"
        else
          echo "awake: PIA Awake is not installed (bash scripts/awake-install.sh); closing the lid will sleep the Mac"
        fi
      else
        echo "awake: PIA Awake did not start; only caffeinate (closing the lid will sleep the Mac)"
      fi
    else
      bash "$here/pia-app.sh" build >/dev/null 2>&1
      echo "awake: PIA.app is being built; until then only caffeinate (closing the lid will sleep the Mac)"
    fi
    ;;
  stop)
    rm -f "$claim"
    pid="$(saved_pid)"
    if is_caffeinate "$pid"; then
      kill "$pid" 2>/dev/null
      echo "awake: stopped caffeinate (PID $pid)"
    elif [ -f "$pidfile" ]; then
      echo "awake: PID ${pid:-?} is no longer caffeinate; nothing to kill"
    else
      echo "awake: not running (no PID file)"
    fi
    rm -f "$pidfile"
    ;;
  status)
    pid="$(saved_pid)"
    if is_caffeinate "$pid"; then
      echo "awake: running (PID $pid)"
    else
      echo "awake: not running"
    fi
    if bin="$(app)"; then
      "$bin" awake status | python3 "$here/awake-status.py" 2>/dev/null
    fi
    ;;
  *)
    echo "usage: awake.sh start|stop|status <work-dir>" >&2
    exit 1
    ;;
esac
