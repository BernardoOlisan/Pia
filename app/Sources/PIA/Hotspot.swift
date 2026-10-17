import Foundation
import PiaAppCore

/// The iPhone's hotspot as a fallback: when the Wi-Fi drops while a work runs (walking with the lid
/// closed), PIA joins the phone's network so the agents keep their connection.
///
///   PIA hotspot set <ssid>     the password is read from stdin and kept in the login Keychain
///   PIA hotspot clear
///   PIA hotspot join           join it now (to test)
///   PIA hotspot show
///
/// The password goes through /usr/bin/security, like the OpenAI key for dictation: an item created by
/// `security` is already trusted, while a rebuilt app would look new to the Keychain every time.
enum Hotspot {
    static let service = "pia-hotspot"

    static func config() -> HotspotConfig? {
        guard let data = try? Data(contentsOf: PiaPaths.hotspot) else { return nil }
        return try? JSONDecoder().decode(HotspotConfig.self, from: data)
    }

    static func run(_ arguments: [String]) -> Int32 {
        var args = arguments
        let action = args.isEmpty ? "show" : args.removeFirst()
        switch action {
        case "set":
            guard let ssid = args.first, !ssid.isEmpty else { return fail("usage: PIA hotspot set <ssid> (password on stdin)") }
            let password = (readLine(strippingNewline: true) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !password.isEmpty else { return fail("no password on stdin") }
            Shell.run("/usr/bin/security", ["delete-generic-password", "-s", service, "-a", ssid])
            let added = Shell.run("/usr/bin/security", ["add-generic-password", "-s", service, "-a", ssid, "-w", password])
            guard added.code == 0 else { return fail("could not save the password: \(added.out)") }
            PiaPaths.ensure()
            if let data = try? JSONEncoder().encode(HotspotConfig(ssid: ssid)) { try? data.write(to: PiaPaths.hotspot, options: .atomic) }
            print("hotspot: \(ssid) saved")
            return 0
        case "clear":
            if let c = config() { Shell.run("/usr/bin/security", ["delete-generic-password", "-s", service, "-a", c.ssid]) }
            try? FileManager.default.removeItem(at: PiaPaths.hotspot)
            print("hotspot: cleared")
            return 0
        case "join":
            return join() ? 0 : 1
        case "show":
            print(config().map { "hotspot: \($0.ssid) (joins after \(Int($0.after)) s without network)" } ?? "hotspot: not set")
            return 0
        default:
            return fail("usage: PIA hotspot set <ssid> | clear | join | show")
        }
    }

    static func wifiDevice() -> String? {
        let out = Shell.run("/usr/sbin/networksetup", ["-listallhardwareports"]).out
        var lastPort = ""
        for line in out.split(separator: "\n") {
            if line.hasPrefix("Hardware Port: ") { lastPort = String(line.dropFirst("Hardware Port: ".count)) }
            if line.hasPrefix("Device: "), lastPort == "Wi-Fi" { return String(line.dropFirst("Device: ".count)) }
        }
        return nil
    }

    @discardableResult
    static func join() -> Bool {
        guard let c = config() else { print("hotspot: not set"); return false }
        let password = Shell.run("/usr/bin/security", ["find-generic-password", "-s", service, "-a", c.ssid, "-w"])
        guard password.code == 0 else { print("hotspot: no password in the Keychain for \(c.ssid)"); return false }
        guard let device = wifiDevice() else { print("hotspot: no Wi-Fi device"); return false }
        let pw = password.out.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = Shell.run("/usr/sbin/networksetup", ["-setairportnetwork", device, c.ssid, pw], timeout: 40)
        // networksetup prints an error and still exits 0 when it can't join.
        let ok = result.code == 0 && result.out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        print(ok ? "hotspot: joined \(c.ssid)" : "hotspot: could not join \(c.ssid): \(result.out.trimmingCharacters(in: .whitespacesAndNewlines))")
        return ok
    }

    static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write("PIA hotspot: \(message)\n".data(using: .utf8)!)
        return 2
    }
}
