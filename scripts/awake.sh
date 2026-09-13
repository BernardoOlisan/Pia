#!/usr/bin/env bash
# Keep the machine awake while a PIA work runs.
# The PID is saved in the work folder so the right process is always the one killed.
#
#   awake.sh start  <work-dir>   run `caffeinate -dims` in the background, save its PID
#   awake.sh stop   <work-dir>   kill that PID (only if it is still caffeinate), remove the file
#   awake.sh status <work-dir>   show whether it is running
#
# When CLAUDE_PID is set (Claude Code sets it for every command), caffeinate also gets `-w CLAUDE_PID`,
# so it exits by itself if Claude Code closes or crashes.
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

pidfile="$dir/caffeinate.pid"

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

case "$cmd" in
  start)
    pid="$(saved_pid)"
    if is_caffeinate "$pid"; then
      echo "awake: already running (PID $pid)"
      exit 0
    fi
    if ! command -v caffeinate >/dev/null 2>&1; then
      echo "awake: caffeinate is not available on this system; skipping"
      exit 0
    fi
    watch=""
    if [ -n "${CLAUDE_PID:-}" ] && ps -p "$CLAUDE_PID" >/dev/null 2>&1; then
      watch="-w $CLAUDE_PID"
    fi
    # shellcheck disable=SC2086
    nohup caffeinate -dims $watch >/dev/null 2>&1 &
    pid=$!
    echo "$pid" > "$pidfile"
    echo "awake: started caffeinate -dims $watch (PID $pid) → $pidfile"
    ;;
  stop)
    pid="$(saved_pid)"
    if [ -z "$pid" ]; then
      echo "awake: not running (no PID file)"
      exit 0
    fi
    if is_caffeinate "$pid"; then
      kill "$pid" 2>/dev/null
      echo "awake: stopped caffeinate (PID $pid)"
    else
      echo "awake: PID $pid is no longer caffeinate; nothing to kill"
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
    ;;
  *)
    echo "usage: awake.sh start|stop|status <work-dir>" >&2
    exit 1
    ;;
esac
