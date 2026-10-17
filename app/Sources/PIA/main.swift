import Foundation

let usage = """
usage: PIA notify --kind ready|done|stalled|permission --title "…" [--subtitle "…"] [--body "…"]
       PIA awake ensure|serve|status|recover|stop
       PIA hotspot set <ssid> | clear | join | show

Run it from inside PIA.app (scripts/pia-app.sh path). Notifications need the bundle; so does the icon.
"""

var arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.isEmpty ? "" : arguments.removeFirst()
switch command {
case "notify": exit(Notify.run(arguments))
case "awake": exit(Awake.run(arguments))
case "hotspot": exit(Hotspot.run(arguments))
case "-h", "--help": print(usage); exit(0)
default:
    FileHandle.standardError.write((usage + "\n").data(using: .utf8)!)
    exit(2)
}
