import Foundation

/// Everything Corva knows about one calendar day.
///
/// A summary describes the *morning-anchored* day: `sleep` is the night that ended on the
/// morning of `date`, `recovery` is scored from that night, and `strain` accumulates over
/// the rest of the day. This mirrors how the data is experienced: you wake up, see how
/// recovered you are, then spend the day building strain.
nonisolated struct DailySummary: Identifiable, Hashable, Sendable {
    /// Start of the local calendar day this summary describes.
    let date: Date
    let recovery: RecoveryMetrics
    let strain: StrainMetrics
    let sleep: SleepMetrics
    let vitals: Vitals
    /// The rolling baseline as it stood on this day, computed from the preceding days only.
    ///
    /// Stored per day (rather than recomputed on the fly) so that a historical score can
    /// always be explained against the baseline it was actually scored with.
    let baseline: Baseline

    var id: Date { date }
}

nonisolated struct RecoveryMetrics: Hashable, Sendable {
    /// 0-100.
    let score: Int

    var zone: RecoveryZone { RecoveryZone(score: score) }
}

/// Recovery bands. Thresholds follow the widely used thirds convention so scores feel familiar.
nonisolated enum RecoveryZone: String, CaseIterable, Sendable {
    case low
    case moderate
    case high

    init(score: Int) {
        switch score {
        case ..<34: self = .low
        case ..<67: self = .moderate
        default: self = .high
        }
    }

    var title: String {
        switch self {
        case .low: "Low"
        case .moderate: "Moderate"
        case .high: "High"
        }
    }
}

/// Overnight physiology, measured during the sleep that ended on the summary's morning.
nonisolated struct Vitals: Hashable, Sendable {
    /// Heart rate variability (RMSSD), milliseconds.
    let hrv: Double
    /// Beats per minute.
    let restingHeartRate: Double
    /// Breaths per minute.
    let respiratoryRate: Double
    /// Average overnight blood oxygen saturation (SpO₂), percent.
    let bloodOxygen: Double
    /// Absolute nightly skin temperature, degrees Celsius. Converted for display only.
    let skinTemperature: Double
    /// Estimated VO2 max (cardio fitness), ml/kg/min. Sources update it after qualifying
    /// outdoor workouts, so it moves slowly; the latest estimate is carried on every day.
    let vo2Max: Double
}
