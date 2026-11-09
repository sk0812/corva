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

extension Array where Element == DailySummary {
    /// The summaries in the `days` calendar days ending on `end` (inclusive). With gaps in the
    /// data this can hold fewer than `days` entries, which is the point: "last 7 days" means
    /// the last 7 days, not the last 7 entries.
    nonisolated func lastDays(_ days: Int, endingOn end: Date, calendar: Calendar = .current) -> [DailySummary] {
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: end)) else { return [] }
        return filter { $0.date >= start && $0.date <= end }
    }
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
///
/// HRV and resting heart rate are required: without them there's no recovery score, so a day
/// missing them isn't summarised at all. The others are nil on nights the wearable didn't
/// report them (not every device measures every one).
nonisolated struct Vitals: Hashable, Sendable {
    /// Heart rate variability (RMSSD), milliseconds.
    let hrv: Double
    /// Beats per minute.
    let restingHeartRate: Double
    /// Breaths per minute.
    let respiratoryRate: Double?
    /// Average overnight blood oxygen saturation (SpO₂), percent.
    let bloodOxygen: Double?
    /// Absolute nightly skin temperature, degrees Celsius. Converted for display only.
    let skinTemperature: Double?
    /// Estimated VO2 max (cardio fitness), ml/kg/min. Sources update it after qualifying
    /// outdoor workouts, so it moves slowly; the latest estimate is carried on every day.
    let vo2Max: Double?
}
