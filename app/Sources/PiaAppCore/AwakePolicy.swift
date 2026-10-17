import Foundation

/// What PIA Awake should do right now, from what the Mac says. Pure, so every rule is tested.
///
/// Holding the Mac awake with the lid closed is only ever worth it while a work is running, and never
/// at the price of a dead battery or a Mac cooking in a backpack.
public struct AwakeInputs: Equatable, Sendable {
    public var runningWorks: Int
    /// 0–100, nil on a Mac without a battery.
    public var battery: Int?
    public var onAC: Bool
    /// ProcessInfo.ThermalState raw value: 0 nominal, 1 fair, 2 serious, 3 critical.
    public var thermal: Int
    /// Set by an earlier battery stop; kept until the Mac is charging or has recovered.
    public var stoppedForBattery: Bool

    public init(runningWorks: Int, battery: Int?, onAC: Bool, thermal: Int, stoppedForBattery: Bool = false) {
        self.runningWorks = runningWorks
        self.battery = battery
        self.onAC = onAC
        self.thermal = thermal
        self.stoppedForBattery = stoppedForBattery
    }
}

public struct AwakeSettings: Codable, Equatable, Sendable {
    /// On battery at or below this, Low Power Mode goes on while PIA keeps the Mac awake.
    public var lowPowerAt: Int = 40
    /// On battery at or below this, PIA lets the Mac sleep. 0 turns the battery stop off.
    public var stopAt: Int = 10
    /// Serious heat → Low Power Mode, critical heat → let the Mac sleep.
    public var heatRules: Bool = true

    public init() {}
}

public struct AwakeDecision: Equatable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case running, idle, battery, heat
    }

    public var holdAwake: Bool
    public var lowPower: Bool
    public var reason: Reason
    public var stoppedForBattery: Bool
}

public enum AwakePolicy {
    public static func decide(_ input: AwakeInputs, _ settings: AwakeSettings = AwakeSettings()) -> AwakeDecision {
        var stopped = input.stoppedForBattery
        if let battery = input.battery, settings.stopAt > 0 {
            if !input.onAC && battery <= settings.stopAt {
                stopped = true
            } else if input.onAC || battery >= settings.stopAt + 10 {
                stopped = false
            }
        } else {
            stopped = false
        }

        guard input.runningWorks > 0 else {
            return AwakeDecision(holdAwake: false, lowPower: false, reason: .idle, stoppedForBattery: stopped)
        }
        if settings.heatRules && input.thermal >= 3 {
            return AwakeDecision(holdAwake: false, lowPower: false, reason: .heat, stoppedForBattery: stopped)
        }
        if stopped {
            return AwakeDecision(holdAwake: false, lowPower: false, reason: .battery, stoppedForBattery: true)
        }
        let lowBattery = !input.onAC && (input.battery.map { $0 <= settings.lowPowerAt } ?? false)
        let warm = settings.heatRules && input.thermal >= 2
        return AwakeDecision(holdAwake: true, lowPower: lowBattery || warm, reason: .running, stoppedForBattery: false)
    }
}
