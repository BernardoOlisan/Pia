#!/usr/bin/env bash
# Install PIA Awake: the Mac stays up with the lid closed while a PIA work runs.
#
#   bash awake-install.sh             install (asks for your password once, for the sudoers rule)
#   bash awake-install.sh --uninstall remove it and undo anything it left behind
#
# What it installs, and nothing else:
#   - /etc/sudoers.d/pia-awake: lets YOUR user run exactly these four commands as root without a
#     password — pmset -a disablesleep 1|0 and pmset -a lowpowermode 1|0. No other command, no shell.
#   - a LaunchAgent that runs `PIA awake recover` every minute: if the daemon ever dies while holding
#     the Mac awake, sleep comes back within a minute.
#   - ~/.pia/config.json with the language for PIA's notifications, if it doesn't exist.
#   - optionally your iPhone's hotspot (name here, password in the login Keychain), joined when the
#     Wi-Fi drops while a work runs.
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
sudoers="/etc/sudoers.d/pia-awake"
agent_id="com.bernardoolisan.pia.awake-recover"
agent="$HOME/Library/LaunchAgents/$agent_id.plist"
user="$(id -un)"

if [ "${1:-}" = "--uninstall" ]; then
  if bin="$(bash "$here/pia-app.sh" path 2>/dev/null)"; then
    "$bin" awake stop || true
    sleep 1
    "$bin" awake recover || true
  fi
  launchctl bootout "gui/$(id -u)/$agent_id" 2>/dev/null || true
  rm -f "$agent"
  sudo rm -f "$sudoers"
  sudo /usr/bin/pmset -a disablesleep 0 || true
  echo "PIA Awake: removed. Closing the lid sleeps the Mac again."
  exit 0
fi

echo "PIA Awake: building PIA.app (a minute the first time)…"
bash "$here/pia-app.sh" build --wait
bin="$(bash "$here/pia-app.sh" path)"

tmp="$(mktemp)"
cat > "$tmp" <<EOF
# PIA Awake: keep the Mac awake with the lid closed while a PIA work runs. Installed by awake-install.sh.
$user ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a lowpowermode 1, /usr/bin/pmset -a lowpowermode 0
EOF
echo "PIA Awake: installing the sudoers rule (your password, once)…"
sudo /usr/sbin/visudo -cf "$tmp" >/dev/null
sudo install -m 0440 -o root -g wheel "$tmp" "$sudoers"
rm -f "$tmp"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$agent_id</string>
  <key>ProgramArguments</key>
  <array><string>$bin</string><string>awake</string><string>recover</string></array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>/dev/null</string>
  <key>StandardErrorPath</key><string>/dev/null</string>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/$agent_id" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$agent"

mkdir -p "$HOME/.pia"
if [ ! -f "$HOME/.pia/config.json" ]; then
  lang="$(defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n"(),' | cut -c1-2)"
  printf '{\n  "language": "%s"\n}\n' "${lang:-en}" > "$HOME/.pia/config.json"
fi

if [ -t 0 ]; then
  printf "Your iPhone's hotspot name, to join when the Wi-Fi drops (Enter to skip): "
  read -r ssid
  if [ -n "$ssid" ]; then
    printf "Its password: "
    read -rs password
    echo
    printf '%s\n' "$password" | "$bin" hotspot set "$ssid"
  fi
fi

if sudo -n -l /usr/bin/pmset -a disablesleep 1 >/dev/null 2>&1; then
  echo "PIA Awake: installed. While a PIA work runs, closing the lid keeps the Mac working."
else
  echo "PIA Awake: the sudoers rule did not take effect; check $sudoers" >&2
  exit 1
fi
