#!/usr/bin/env bash
# PIA.app: notifications with the owl, and PIA Awake. A plugin can't ship compiled Swift, so it is
# built on this Mac the first time it's needed, and again when its sources change.
#
#   pia-app.sh ready         exit 0 if PIA.app exists and no source is newer
#   pia-app.sh build         build in the background (one at a time)
#   pia-app.sh build --wait  build now, in the foreground
#   pia-app.sh path          print the executable inside PIA.app (exit 1 if it isn't built)
#
# The app lives at a fixed path, ~/Library/Application Support/PIA/PIA.app, so macOS remembers that
# PIA may post notifications across rebuilds and across installed copies of the plugin. Swift builds
# into a shared scratch folder there too, never inside the repo (see voice-bin.sh for why).
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/app"
support="${PIA_APP_SUPPORT:-$HOME/Library/Application Support/PIA}"
app="$support/PIA.app"
bin="$app/Contents/MacOS/PIA"
scratch="$support/build"
lock="$scratch/pia-app-build.pid"
log="$scratch/pia-app-build.log"

ready() {
  [ -x "$bin" ] || return 1
  [ -z "$(find "$src/Sources" "$src/Package.swift" "$root/scripts/make-app-assets.py" -newer "$bin" -print -quit 2>/dev/null)" ]
}

building() {
  [ -f "$lock" ] && kill -0 "$(tr -dc '0-9' < "$lock")" 2>/dev/null
}

do_build() {
  set -e
  swift build -c release --package-path "$src" --scratch-path "$scratch/swift"
  local stage
  stage="$(mktemp -d "$support/.PIA.app.XXXXXX")"
  mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Resources"
  cp "$scratch/swift/release/PIA" "$stage/Contents/MacOS/PIA"
  python3 "$root/scripts/make-app-assets.py" "$stage/Contents/Resources"
  cat > "$stage/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.bernardoolisan.pia</string>
  <key>CFBundleName</key><string>PIA</string>
  <key>CFBundleDisplayName</key><string>PIA</string>
  <key>CFBundleExecutable</key><string>PIA</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
  codesign --force --sign - "$stage" >/dev/null
  # Swap the whole bundle in with renames: a daemon running from the old one keeps its inode.
  if [ -d "$app" ]; then
    mv "$app" "$support/.PIA.app.old.$$"
  fi
  mv "$stage" "$app"
  rm -rf "$support/.PIA.app.old.$$"
  # Tell LaunchServices about the new bundle, so the notification icon updates.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app" >/dev/null 2>&1 || true
}

case "${1:-}" in
  ready) ready ;;
  building) building ;;
  path)
    ready || [ -x "$bin" ] || exit 1
    echo "$bin"
    ;;
  build)
    ready && exit 0
    command -v swift >/dev/null 2>&1 || { echo "pia-app: swift not found (install Xcode or the command line tools)" >&2; exit 1; }
    mkdir -p "$scratch"
    if [ "${2:-}" = "--wait" ]; then
      building && { echo "pia-app: a build is already running; see $log" >&2; exit 1; }
      echo $$ > "$lock"
      ( do_build ) > "$log" 2>&1
      status=$?
      rm -f "$lock"
      [ $status -eq 0 ] || { tail -20 "$log" >&2; exit $status; }
      echo "pia-app: built $app"
    else
      building && exit 0
      nohup bash -c 'echo $$ > "$1"; bash "$2" build --wait > /dev/null 2>&1; rm -f "$1"' _ "$lock.bg" "$0" >/dev/null 2>&1 &
    fi
    ;;
  *)
    echo "usage: pia-app.sh ready|building|build [--wait]|path" >&2
    exit 1
    ;;
esac
