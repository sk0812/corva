import Foundation

/// A personal baseline: the mean and spread of each metric over the preceding 30 days.
///
/// Corva compares everything against *your own* history rather than population norms,
/// because day-to-day physiology varies far more between people than within one person.
nonisolated struct Baseline: Hashable, Sendable {
    static let windowDays = 30
    /// Readings a metric needs before its baseline counts. Fewer, and the spread is
    /// meaningless (two equal nights give a "typical range" of a single point), so the metric
    /// stays uncalibrated: no range, no delta, and recovery treats it as neutral.
    static let minimumDays = 7
    /// Half-width of the typical range, in standard deviations.
    static let typicalRangeWidth = 1.5

    nonisolated struct Stat: Hashable, Sendable {
        let mean: Double
        let standardDeviation: Double

        /// Mean ± 1.5 standard deviations: roughly seven days in eight fall inside it, so a
        /// value outside it is unusual enough to flag without crying wolf.
        var typicalRange: ClosedRange<Double> {
            let halfWidth = standardDeviation * Baseline.typicalRangeWidth
            return (mean - halfWidth)...(mean + halfWidth)
        }

        func contains(_ value: Double) -> Bool {
            typicalRange.contains(value)
        }
    }

    private let stats: [Metric: Stat]

    init(stats: [Metric: Stat]) {
        self.stats = stats
    }

    /// Builds a baseline from the days that precede the day being scored.
    init(history: [DailySummary]) {
        var stats: [Metric: Stat] = [:]
        guard !history.isEmpty else {
            self.init(stats: stats)
            return
        }
        for metric in Metric.allCases {
            let values = history.compactMap(metric.value(in:))
            guard values.count >= Self.minimumDays else { continue }
            stats[metric] = Stat(
                mean: Statistics.mean(values),
                standardDeviation: Statistics.standardDeviation(values)
            )
        }
        self.init(stats: stats)
    }

    subscript(metric: Metric) -> Stat? { stats[metric] }

    /// True once HRV and resting heart rate have enough history for recovery to mean something.
    var isCalibrated: Bool { stats[.hrv] != nil && stats[.restingHeartRate] != nil }

    /// The days before `date` that fall inside the baseline window: the previous 30 calendar
    /// days, not the previous 30 entries, so a gap in the data doesn't stretch the window.
    static func window(before date: Date, in history: [DailySummary], calendar: Calendar = .current) -> [DailySummary] {
        guard let start = calendar.date(byAdding: .day, value: -windowDays, to: date) else { return [] }
        return history.filter { $0.date >= start && $0.date < date }
    }

    /// How far a day's value sits from this baseline, in the metric's own unit.
    func delta(for metric: Metric, in summary: DailySummary) -> Double? {
        guard let stat = stats[metric], let value = metric.value(in: summary) else { return nil }
        return value - stat.mean
    }
}
