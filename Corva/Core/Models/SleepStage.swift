import Foundation

nonisolated enum SleepStage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case awake
    case rem
    case light
    case deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .awake: "Awake"
        case .rem: "REM"
        case .light: "Light"
        case .deep: "Deep"
        }
    }

    var isAsleep: Bool { self != .awake }
}

/// One contiguous block of a single sleep stage. A night is an ordered, gap-free list of these.
nonisolated struct SleepSegment: Identifiable, Hashable, Sendable {
    let stage: SleepStage
    let start: Date
    let end: Date

    var id: Date { start }
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// The night that ended on the morning of a `DailySummary`.
///
/// Durations and efficiency are derived from `segments`, so the hypnogram and the headline
/// numbers can never disagree.
nonisolated struct SleepMetrics: Hashable, Sendable {
    /// Sleep performance, 0-100: time asleep as a share of `need`, capped at 100.
    let score: Int
    /// When the user got into bed.
    let bedtime: Date
    /// When the user got out of bed.
    let wakeTime: Date
    /// How much sleep the night called for, given recent strain and sleep debt.
    let need: TimeInterval
    /// Ordered stages within `bedtime...wakeTime`.
    let segments: [SleepSegment]
    /// Time asleep as the source reports it, when it does. Preferred over adding up stages,
    /// which can have gaps.
    var reportedTimeAsleep: TimeInterval? = nil
    /// False for "classic" sleep, where the tracker recorded asleep or awake but no stages.
    var hasStages = true
    /// The part of `need` that's repaying earlier sleep debt (not new need).
    var debtRepayment: TimeInterval = 0

    var timeInBed: TimeInterval { wakeTime.timeIntervalSince(bedtime) }

    var timeAsleep: TimeInterval {
        reportedTimeAsleep ?? segments.filter(\.stage.isAsleep).reduce(0) { $0 + $1.duration }
    }

    /// Share of time in bed actually spent asleep, 0-1.
    var efficiency: Double {
        timeInBed > 0 ? timeAsleep / timeInBed : 0
    }

    func duration(of stage: SleepStage) -> TimeInterval {
        segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
    }
}
