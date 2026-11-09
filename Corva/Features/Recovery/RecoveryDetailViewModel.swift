import Foundation
import Observation

@Observable
final class RecoveryDetailViewModel {
    /// One input to the recovery score, compared with its baseline.
    struct Contributor: Identifiable {
        let metric: Metric
        let value: Double
        let baseline: Double?
        /// Share of the recovery score this input accounts for, 0-1.
        let weight: Double
        /// This input's own 0-100 score before weighting.
        let subScore: Double

        var id: Metric { metric }
        var delta: Double? { baseline.map { value - $0 } }
    }

    struct Content {
        let day: DailySummary
        /// The 30 days ending on `day`, oldest first.
        let history: [DailySummary]
        /// Up to 90 days ending on `day`, for relationships.
        let longHistory: [DailySummary]
        let contributors: [Contributor]

        var baselineScore: Double? { day.baseline[.recovery]?.mean }
        var distribution: [RecoveryZone: Int] { Insights.recoveryDistribution(history) }
        var average: Double { Statistics.mean(history.map { Double($0.recovery.score) }) }
        var best: Int { history.map(\.recovery.score).max() ?? 0 }
        var lowest: Int { history.map(\.recovery.score).min() ?? 0 }

        var strainRelationship: Insights.Relationship {
            Insights.relationship(
                id: "strain-recovery",
                title: "Strain → next-day recovery",
                detail: "Day strain against the following morning’s recovery",
                x: .strain, y: .recovery, lag: 1, in: longHistory
            )
        }
    }

    let date: Date
    private(set) var state: LoadState<Content> = .loading
    private let calendar: Calendar

    init(date: Date, calendar: Calendar = .current) {
        self.date = date
        self.calendar = calendar
    }

    func load(using provider: any HealthDataProvider) async {
        do {
            let longHistory = try await provider.summaries(endingOn: date, count: 90, calendar: calendar)
            guard let day = longHistory.last, calendar.isDate(day.date, inSameDayAs: date) else {
                state = .empty
                return
            }
            state = .loaded(Content(
                day: day,
                history: longHistory.lastDays(Baseline.windowDays, endingOn: day.date),
                longHistory: longHistory,
                contributors: Self.contributors(for: day)
            ))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private static func contributors(for day: DailySummary) -> [Contributor] {
        let weights = Scoring.recoveryWeights
        let hrvBaseline = day.baseline[.hrv]?.mean
        let rhrBaseline = day.baseline[.restingHeartRate]?.mean
        return [
            Contributor(
                metric: .hrv,
                value: day.vitals.hrv,
                baseline: hrvBaseline,
                weight: weights.hrv,
                subScore: Scoring.hrvComponent(hrv: day.vitals.hrv, baseline: hrvBaseline ?? day.vitals.hrv)
            ),
            Contributor(
                metric: .restingHeartRate,
                value: day.vitals.restingHeartRate,
                baseline: rhrBaseline,
                weight: weights.restingHeartRate,
                subScore: Scoring.restingHeartRateComponent(
                    restingHeartRate: day.vitals.restingHeartRate,
                    baseline: rhrBaseline ?? day.vitals.restingHeartRate
                )
            ),
            Contributor(
                metric: .sleep,
                value: Double(day.sleep.score),
                baseline: day.baseline[.sleep]?.mean,
                weight: weights.sleep,
                subScore: Scoring.sleepComponent(sleepScore: day.sleep.score)
            ),
        ]
    }
}
