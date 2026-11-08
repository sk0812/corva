import SwiftUI

// Maps domain concepts to colour tokens. The only place metrics meet colour.

extension Metric {
    /// The metric's single hue. Recovery is the exception: its hue tracks the score, so
    /// pass the value to `tint(for:)` when there is one.
    var tint: Color {
        switch self {
        case .recovery: CorvaColor.recoveryHigh
        case .strain: CorvaColor.strain
        case .sleep: CorvaColor.sleep
        case .hrv, .restingHeartRate, .respiratoryRate, .bloodOxygen, .skinTemperature: CorvaColor.neutralData
        }
    }

    func tint(for value: Double) -> Color {
        self == .recovery ? RecoveryZone(score: Int(value.rounded())).color : tint
    }
}

extension RecoveryZone {
    var color: Color {
        switch self {
        case .low: CorvaColor.recoveryLow
        case .moderate: CorvaColor.recoveryModerate
        case .high: CorvaColor.recoveryHigh
        }
    }
}

extension SleepStage {
    /// Stages share the sleep hue at descending depth; awake is neutral.
    var color: Color {
        switch self {
        case .awake: CorvaColor.textTertiary
        case .rem: CorvaColor.sleep.opacity(0.75)
        case .light: CorvaColor.sleep.opacity(0.45)
        case .deep: CorvaColor.sleep
        }
    }
}

extension HeartRateZone {
    /// Zones share the strain hue, getting more opaque as effort rises.
    var color: Color {
        CorvaColor.strain.opacity(0.3 + 0.175 * Double(rawValue - 1))
    }
}
