import Foundation

/// A recorded workout or other bout of deliberate activity.
nonisolated struct Activity: Identifiable, Hashable, Sendable {
    let id: String
    let kind: ActivityKind
    let start: Date
    let duration: TimeInterval
    /// Strain of this activity alone, 0-100, on the same scale as day strain.
    let strain: Int
    let averageHeartRate: Int
    let maxHeartRate: Int
    /// Active energy, kilocalories.
    let energy: Double
    /// Metres, for activities where distance is meaningful.
    let distance: Double?
    let heartRateZones: [ZoneDuration]

    var end: Date { start.addingTimeInterval(duration) }
}

nonisolated enum ActivityKind: String, CaseIterable, Hashable, Sendable {
    case run
    case ride
    case strength
    case walk
    case swim
    case yoga

    var title: String {
        switch self {
        case .run: "Run"
        case .ride: "Ride"
        case .strength: "Strength"
        case .walk: "Walk"
        case .swim: "Swim"
        case .yoga: "Yoga"
        }
    }
}

/// Heart-rate zones as a share of maximum heart rate (the common five-zone model).
nonisolated enum HeartRateZone: Int, CaseIterable, Identifiable, Comparable, Hashable, Sendable {
    case one = 1, two, three, four, five

    var id: Int { rawValue }

    var title: String { "Zone \(rawValue)" }

    /// Lower and upper bound as a fraction of max heart rate.
    var bounds: ClosedRange<Double> {
        switch self {
        case .one: 0.50...0.60
        case .two: 0.60...0.70
        case .three: 0.70...0.80
        case .four: 0.80...0.90
        case .five: 0.90...1.00
        }
    }

    static func < (lhs: HeartRateZone, rhs: HeartRateZone) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated struct ZoneDuration: Identifiable, Hashable, Sendable {
    let zone: HeartRateZone
    let duration: TimeInterval

    var id: HeartRateZone { zone }
}

/// The day's cardiovascular load and the activities that produced it.
nonisolated struct StrainMetrics: Hashable, Sendable {
    /// 0-100. Saturating, so each additional point costs more effort than the last.
    let score: Int
    /// Time in each zone across the whole day (activities plus everyday movement), zone 1 to 5.
    let heartRateZones: [ZoneDuration]
    /// Ordered by start time.
    let activities: [Activity]
    /// Active energy, kilocalories.
    let activeEnergy: Double
    /// Average heart rate across waking hours, bpm.
    let averageHeartRate: Int
    /// Highest heart rate of the day, bpm.
    let maxHeartRate: Int
    let steps: Int
}
