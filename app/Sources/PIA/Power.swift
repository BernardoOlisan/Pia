import Foundation
import IOKit
import IOKit.ps
import PiaAppCore

/// What the Mac's power hardware says right now.
enum Power {
    /// (percent, on AC). A Mac with no battery reports (nil, true).
    static func battery() -> (percent: Int?, onAC: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return (nil, true) }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }
            let current = d[kIOPSCurrentCapacityKey] as? Int
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let state = d[kIOPSPowerSourceStateKey] as? String
            let percent = current.map { Int((Double($0) / Double(Swift.max(max, 1)) * 100).rounded()) }
            return (percent, state == kIOPSACPowerValue)
        }
        return (nil, true)
    }

    /// Whether the lid is closed (IOPMrootDomain's AppleClamshellState).
    static func lidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? Bool) ?? false
    }

    static var thermal: Int { ProcessInfo.processInfo.thermalState.rawValue }
    static var lowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    /// `pmset -g` → SleepDisabled 1 while the lid-closed hold is on.
    static func sleepDisabled() -> Bool {
        let out = Shell.run("/usr/bin/pmset", ["-g"]).out
        return out.split(separator: "\n").contains { line in
            let parts = line.split(whereSeparator: \.isWhitespace)
            return parts.count >= 2 && parts[0] == "SleepDisabled" && parts[1] == "1"
        }
    }

    static func displayOff() {
        Shell.run("/usr/bin/pmset", ["displaysleepnow"])
    }
}
