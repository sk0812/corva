import Foundation

/// What your best days had in common, compared with your worst.
///
/// Ranks days by a score, takes the top and bottom quarter, and compares the behaviour that
/// led into them: the previous day's training, bed and wake times, how much you slept, and
/// any experiment tags. Factors are ordered by standardised difference (Cohen's d), so the
/// biggest separators come first whatever their unit. It shows association, not cause.
nonisolated enum DayContrast {
    /// Share of days in each group.
    static let groupShare = 0.25

    nonisolated enum Ranking: String, CaseIterable, Identifiable, Hashable, Sendable {
        case recovery
        case hrv
        case sleep

        var id: String { rawValue }

        var metric: Metric {
            switch self {
            case .recovery: .recovery
            case .hrv: .hrv
            case .sleep: .sleep
            }
        }
    }

    nonisolated enum FactorKind: Hashable, Sendable {
        case priorStrain
        case priorHardMinutes
        case priorSteps
        case bedtime
        case wakeTime
        case timeInBed
        case timeAsleep
        case restorativeSleep
        case awakenings
        case weekend
        /// Three or more vitals outside their typical range that morning.
        case unwell
        /// An on & off experiment's behaviour, the evening before.
        case tag(String)

        var title: String {
            switch self {
            case .priorStrain: "Strain the day before"
            case .priorHardMinutes: "Hard minutes the day before"
            case .priorSteps: "Steps the day before"
            case .bedtime: "Bedtime"
            case .wakeTime: "Wake time"
            case .timeInBed: "Time in bed"
            case .timeAsleep: "Time asleep"
            case .restorativeSleep: "Deep and REM sleep"
            case .awakenings: "Times woken"
            case .weekend: "Weekend mornings"
            case .unwell: "Vitals flagged unwell"
            case .tag(let name): "Tagged: \(name)"
            }
        }

        /// Whether the value is a 0–1 share of days rather than a quantity.
        var isShare: Bool {
            switch self {
            case .weekend, .unwell, .tag: true
            default: false
            }
        }
    }

    nonisolated enum Strength: String, Hashable, Sendable {
        case none = "No real difference"
        case small = "Small difference"
        case moderate = "Clear difference"
        case large = "Big difference"

        init(effectSize: Double) {
            switch abs(effectSize) {
            case ..<0.2: self = .none
            case ..<0.5: self = .small
            case ..<0.8: self = .moderate
            default: self = .large
            }
        }
    }

    nonisolated struct Factor: Identifiable, Hashable, Sendable {
        let kind: FactorKind
        /// Mean on best days. Shares are 0–1; times are minutes after 6 PM; durations seconds.
        let best: Double
        let worst: Double
        /// Where most days fall (10th to 90th percentile, widened to include both means), for
        /// drawing both means on one scale.
        let spread: ClosedRange<Double>
        /// Best minus worst, in pooled standard deviations.
        let effectSize: Double

        var id: FactorKind { kind }
        var strength: Strength { Strength(effectSize: effectSize) }
    }

    /// Evenings an on & off experiment's behaviour happened, and the stretch of evenings it
    /// was tracked over. Days outside that stretch are unknown, not untagged.
    nonisolated struct Tag: Hashable, Sendable {
        let name: String
        let evenings: Set<Date>
        let tracked: ClosedRange<Date>
    }

    nonisolated struct Result: Hashable, Sendable {
        let ranking: Ranking
        /// Every day considered, oldest first.
        let dates: [Date]
        let bestDates: Set<Date>
        let worstDates: Set<Date>
        let bestMean: Double
        let worstMean: Double
        /// Largest difference first.
        let factors: [Factor]

        var groupSize: Int { bestDates.count }
    }

    static func analyze(
        _ days: [DailySummary],
        rankingBy ranking: Ranking,
        tags: [Tag] = [],
        calendar: Calendar = .current
    ) -> Result? {
        // Each candidate needs the day before it.
        let candidates = Array(days.indices.dropFirst())
        guard candidates.count >= 12 else { return nil }

        let score = { (index: Int) in ranking.metric.value(in: days[index]) ?? 0 }
        let sorted = candidates.sorted { score($0) > score($1) }
        let size = max(3, Int((Double(candidates.count) * groupShare).rounded()))
        let best = Array(sorted.prefix(size))
        let worst = Array(sorted.suffix(size))

        var kinds: [FactorKind] = [
            .priorStrain, .priorHardMinutes, .priorSteps, .bedtime, .wakeTime,
            .timeInBed, .timeAsleep, .restorativeSleep, .awakenings, .weekend, .unwell,
        ]
        // Sleep performance is time asleep over need, so comparing time asleep would be circular.
        if ranking == .sleep { kinds.removeAll { $0 == .timeAsleep } }
        kinds += tags.map { .tag($0.name) }

        let factors: [Factor] = kinds.compactMap { kind in
            let value = { (index: Int) in factorValue(kind, at: index, in: days, tags: tags, calendar: calendar) }
            // Tags only count on days whose evening before was tracked.
            let isKnown = { (index: Int) -> Bool in
                guard case .tag(let name) = kind else { return true }
                guard let tag = tags.first(where: { $0.name == name }),
                      let evening = calendar.date(byAdding: .day, value: -1, to: days[index].date) else { return false }
                return tag.tracked.contains(evening)
            }
            let all = candidates.filter(isKnown).map(value).sorted()
            let bestValues = best.filter(isKnown).map(value)
            let worstValues = worst.filter(isKnown).map(value)
            guard bestValues.count >= 3, worstValues.count >= 3 else { return nil }
            let bestMean = Statistics.mean(bestValues)
            let worstMean = Statistics.mean(worstValues)
            let low = min(percentile(all, 0.1), bestMean, worstMean)
            let high = max(percentile(all, 0.9), bestMean, worstMean)
            return Factor(
                kind: kind,
                best: bestMean,
                worst: worstMean,
                spread: low...(high > low ? high : low + 1),
                effectSize: cohensD(bestValues, worstValues)
            )
        }

        return Result(
            ranking: ranking,
            dates: candidates.map { days[$0].date },
            bestDates: Set(best.map { days[$0].date }),
            worstDates: Set(worst.map { days[$0].date }),
            bestMean: Statistics.mean(best.map(score)),
            worstMean: Statistics.mean(worst.map(score)),
            factors: factors.sorted { abs($0.effectSize) > abs($1.effectSize) }
        )
    }

    private static func factorValue(
        _ kind: FactorKind,
        at index: Int,
        in days: [DailySummary],
        tags: [Tag],
        calendar: Calendar
    ) -> Double {
        let day = days[index]
        let previous = days[index - 1]
        switch kind {
        case .priorStrain:
            return Double(previous.strain.score)
        case .priorHardMinutes:
            return previous.strain.heartRateZones.filter { $0.zone >= .four }.reduce(0) { $0 + $1.duration / 60 }
        case .priorSteps:
            return Double(previous.strain.steps)
        case .bedtime:
            return day.sleep.minutesSinceEveningAnchor(day.sleep.bedtime, calendar: calendar)
        case .wakeTime:
            return day.sleep.minutesSinceEveningAnchor(day.sleep.wakeTime, calendar: calendar)
        case .timeInBed:
            return day.sleep.timeInBed
        case .timeAsleep:
            return day.sleep.timeAsleep
        case .restorativeSleep:
            return day.sleep.duration(of: .deep) + day.sleep.duration(of: .rem)
        case .awakenings:
            return Double(day.sleep.awakenings)
        case .weekend:
            return calendar.isDateInWeekend(day.date) ? 1 : 0
        case .unwell:
            return day.isLikelyUnwell ? 1 : 0
        case .tag(let name):
            guard let tag = tags.first(where: { $0.name == name }),
                  let evening = calendar.date(byAdding: .day, value: -1, to: day.date) else { return 0 }
            return tag.evenings.contains(evening) ? 1 : 0
        }
    }

    /// Difference in means over the pooled standard deviation. Zero when either group is
    /// constant and identical.
    static func cohensD(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count > 1, b.count > 1 else { return 0 }
        let pooledVariance = (Double(a.count - 1) * pow(Statistics.standardDeviation(a), 2)
            + Double(b.count - 1) * pow(Statistics.standardDeviation(b), 2))
            / Double(a.count + b.count - 2)
        guard pooledVariance > 0 else { return 0 }
        return (Statistics.mean(a) - Statistics.mean(b)) / pooledVariance.squareRoot()
    }

    /// Nearest-rank percentile of already sorted values.
    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[min(max(index, 0), sorted.count - 1)]
    }
}
