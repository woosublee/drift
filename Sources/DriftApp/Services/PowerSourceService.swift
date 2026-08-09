import Foundation
import IOKit.ps
import DriftCore

public protocol PowerSourceProviding: AnyObject {
    func snapshot() -> PowerSnapshot
}

public final class NullPowerSourceService: PowerSourceProviding {
    public init() {}
    public func snapshot() -> PowerSnapshot {
        PowerSnapshot(source: .unavailable, percent: nil, isCharging: false)
    }
}

public final class PowerSourceService: PowerSourceProviding {
    public init() {}

    public func snapshot() -> PowerSnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return PowerSnapshot(source: .unavailable, percent: nil, isCharging: false)
        }
        let descriptions: [[String: Any]] = sources.compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        }
        return Self.snapshot(from: descriptions)
    }

    public static func snapshot(from descriptions: [[String: Any]]) -> PowerSnapshot {
        guard let battery = descriptions.first(where: { description in
            (description["Type"] as? String) == "InternalBattery"
                || (description["Transport Type"] as? String) == "Internal"
        }) else {
            return PowerSnapshot(source: .unavailable, percent: nil, isCharging: false)
        }

        let current = battery["Current Capacity"] as? Int
        let maximum = battery["Max Capacity"] as? Int
        let percent: Int?
        if let current, let maximum, maximum > 0 {
            percent = min(100, max(0, Int((Double(current) / Double(maximum) * 100).rounded())))
        } else {
            percent = nil
        }
        let isCharging = battery["Is Charging"] as? Bool ?? false
        let state = battery["Power Source State"] as? String
        let source: PowerSourceKind = state == "Battery Power" ? .battery : .external
        return PowerSnapshot(source: source, percent: percent, isCharging: isCharging)
    }
}
