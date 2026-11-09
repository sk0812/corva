import Foundation

/// Derived analytics built on top of daily summaries: targets, load, debt, distributions and
/// relationships between metrics. Deterministic and explainable; no advice, only numbers.
nonisolated enum Insights {

    // MARK: - Strain target

    /// The strain range a day's recovery can absorb: higher recovery, higher range.
    ///
    /// Linear in recovery and ±7 wide: 30% recovery targets ~32–46, 90% targets ~64–78.
    static func strainTarget(recovery: Int) -> ClosedRange<Int> {
        let center = 22 + 0.55 * Double(recovery)
        return Int((center - 7).rounded())...Int((center + 7).rounded())
    }

    // MARK: - Training load

    nonisolated struct TrainingLoad: Hashable, Sendable {
        enum Status: String, Sendable {
            case low = "Below usual"
            case balanced = "Balanced"
            case high = "Above usual"
        }

        /// Mean daily cardiovascular load over the last 7 days.
        let acute: Double
        /// Mean daily cardiovascular load over the last 28 days.
        let chronic: Double

        /// Acute:chronic workload ratio. ~0.8–1.3 means this week matches what the body is used to.
        var ratio: Double { chronic > 0 ? acute / chronic : 1 }

        var status: Status {
            switch ratio {
            case ..<0.8: .low
            case ...1.3: .balanced
            default: .high
            }
        }

        static let balancedRange: ClosedRange<Double> = 0.8...1.3
    }

    /// Acute (last 7 calendar days) versus chronic (last 28) load, from days ordered oldest
    /// first. Nil until there are 28 days of history and enough days in each window, because
    /// with less the "chronic" load is mostly the same week and the ratio says nothing.
    static func trainingLoad(_ days: [DailySummary], calendar: Calendar = .current) -> TrainingLoad? {
        guard let first = days.first, let last = days.last,
              let span = calendar.dateComponents([.day], from: first.date, to: last.date).day, span >= 27,
              let acuteStart = calendar.date(byAdding: .day, value: -6, to: last.date),
              let chronicStart = calendar.date(byAdding: .day, value: -27, to: last.date) else { return nil }
        let load = { (day: DailySummary) in Scoring.cardiovascularLoad(day.strain.heartRateZones) }
        let acute = days.filter { $0.date >= acuteStart }.map(load)
        let chronic = days.filter { $0.date >= chronicStart }.map(load)
        guard acute.count >= 4, chronic.count >= 14 else { return nil }
        return TrainingLoad(acute: Statistics.mean(acute), chronic: Statistics.mean(chronic))
    }

    // MARK: - Sleep

    /// Total shortfall against need across the given nights. Surplus nights don't repay it here;
    /// it shows how much sleep was missed, not a running balance.
    static func sleepDebt(_ nights: [SleepMetrics]) -> TimeInterval {
        // Measured against new need only: need also includes repaying earlier debt, and
        // counting that again would charge the same lost sleep several times.
        nights.reduce(0) { $0 + max(0, $1.need - $1.debtRepayment - $1.timeAsleep) }
    }

    /// Mean duration of each stage across nights.
    static func averageStageDurations(_ nights: [SleepMetrics]) -> [SleepStage: TimeInterval] {
        var result: [SleepStage: TimeInterval] = [:]
        for stage in SleepStage.allCases {
            result[stage] = Statistics.mean(nights.map { $0.duration(of: stage) })
        }
        return result
    }

    // MARK: - Distributions

    static func recoveryDistribution(_ days: [DailySummary]) -> [RecoveryZone: Int] {
        var counts: [RecoveryZone: Int] = [.high: 0, .moderate: 0, .low: 0]
        for day in days {
            counts[day.recovery.zone, default: 0] += 1
        }
        return counts
    }

    nonisolated struct WeekdayAverage: Identifiable, Hashable, Sendable {
        /// Calendar weekday, 1 = Sunday.
        let weekday: Int
        /// 0-based position in the locale's week, for ordering and charting.
        let position: Int
        let shortName: String
        let mean: Double
        let count: Int

        var id: Int { weekday }
    }

    /// Mean of `metric` per weekday, ordered by the calendar's first weekday.
    static func weekdayAverages(of metric: Metric, in days: [DailySummary], calendar: Calendar) -> [WeekdayAverage] {
        let grouped = Dictionary(grouping: days) { calendar.component(.weekday, from: $0.date) }
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return (0..<7).compactMap { position in
            let weekday = (calendar.firstWeekday - 1 + position) % 7 + 1
            guard let group = grouped[weekday] else { return nil }
            let values = group.compactMap(metric.value(in:))
            guard !values.isEmpty else { return nil }
            return WeekdayAverage(
                weekday: weekday,
                position: position,
                shortName: symbols[weekday - 1],
                mean: Statistics.mean(values),
                count: values.count
            )
        }
    }

    // MARK: - Relationships

    nonisolated struct Relationship: Identifiable, Hashable, Sendable {
        enum Strength: String, Sendable {
            case notEnoughData = "Needs 14+ days"
            case none = "No clear link"
            case weak = "Weak"
            case moderate = "Moderate"
            case strong = "Strong"
        }

        let id: String
        let title: String
        let detail: String
        let x: Metric
        let y: Metric
        /// Days between the x value and the y value (1 = x today, y tomorrow).
        let lag: Int
        let pairs: [Pair]
        let fit: Statistics.LinearFit?

        nonisolated struct Pair: Identifiable, Hashable, Sendable {
            let id: Int
            let x: Double
            let y: Double
        }

        var r: Double { fit?.correlation ?? 0 }

        /// Pairs needed before a correlation is shown as anything but "not enough data".
        static let minimumPairs = 14

        var strength: Strength {
            guard pairs.count >= Self.minimumPairs else { return .notEnoughData }
            return switch abs(r) {
            case ..<0.1: .none
            case ..<0.3: .weak
            case ..<0.5: .moderate
            default: .strong
            }
        }
    }

    /// Pairs `x` on one day with `y` `lag` days later and fits a line through them.
    static func relationship(
        id: String,
        title: String,
        detail: String,
        x: Metric,
        y: Metric,
        lag: Int,
        in days: [DailySummary]
    ) -> Relationship {
        // Paired by date, not position, so a gap in the data never pairs one day with a
        // day several days later.
        let calendar = Calendar.current
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        var pairs: [Relationship.Pair] = []
        for (index, day) in days.enumerated() {
            guard let laterDate = calendar.date(byAdding: .day, value: lag, to: day.date),
                  let later = byDate[laterDate],
                  let xValue = x.value(in: day), let yValue = y.value(in: later) else { continue }
            pairs.append(Relationship.Pair(id: index, x: xValue, y: yValue))
        }
        return Relationship(
            id: id,
            title: title,
            detail: detail,
            x: x,
            y: y,
            lag: lag,
            pairs: pairs,
            fit: Statistics.linearFit(x: pairs.map(\.x), y: pairs.map(\.y))
        )
    }

    /// The standard set shown in Trends and on Recovery.
    static func relationships(in days: [DailySummary]) -> [Relationship] {
        [
            relationship(
                id: "strain-recovery",
                title: "Strain → next-day recovery",
                detail: "Day strain against the following morning’s recovery",
                x: .strain, y: .recovery, lag: 1, in: days
            ),
            relationship(
                id: "sleep-recovery",
                title: "Sleep → recovery",
                detail: "Sleep performance against the same morning’s recovery",
                x: .sleep, y: .recovery, lag: 0, in: days
            ),
            relationship(
                id: "strain-hrv",
                title: "Strain → next-day HRV",
                detail: "Day strain against the following night’s HRV",
                x: .strain, y: .hrv, lag: 1, in: days
            ),
            relationship(
                id: "rhr-recovery",
                title: "Resting HR → recovery",
                detail: "Resting heart rate against the same morning’s recovery",
                x: .restingHeartRate, y: .recovery, lag: 0, in: days
            ),
        ]
    }
}

// MARK: - Sleep quality details

extension SleepMetrics {
    /// Time from getting into bed to first falling asleep.
    nonisolated var latency: TimeInterval {
        guard let first = segments.first, first.stage == .awake else { return 0 }
        return first.duration
    }

    /// Times woken between first falling asleep and finally waking.
    nonisolated var awakenings: Int {
        guard segments.count > 2 else { return 0 }
        return segments.dropFirst().dropLast().filter { $0.stage == .awake }.count
    }

    /// Deep plus REM as a share of time asleep, 0-1.
    nonisolated var restorativeShare: Double {
        timeAsleep > 0 ? (duration(of: .deep) + duration(of: .rem)) / timeAsleep : 0
    }
}
