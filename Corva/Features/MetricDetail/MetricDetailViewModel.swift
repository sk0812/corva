import Foundation
import Observation

/// Any single metric against its own 30-day history. Used for the vitals on Today.
@Observable
final class MetricDetailViewModel {
    struct Content {
        let metric: Metric
        let day: DailySummary
        /// The 30 days ending on `day`, oldest first.
        let history: [DailySummary]

        /// Present: `load` only produces content for days with a reading.
        var value: Double { metric.value(in: day) ?? 0 }
        var baseline: Baseline.Stat? { day.baseline[metric] }
        var delta: Double? { day.baseline.delta(for: metric, in: day) }
        var points: [DatedValue] { metric.series(in: history) }
        var lowest: Double? { points.map(\.value).min() }
        var highest: Double? { points.map(\.value).max() }
        var average: Double { Statistics.mean(points.map(\.value)) }
        var isInTypicalRange: Bool { baseline?.contains(value) ?? true }

        /// Days in `history` whose value fell outside that day's own typical range.
        var daysOutsideRange: Int {
            history.filter { day in
                guard let stat = day.baseline[metric], let value = metric.value(in: day) else { return false }
                return !stat.contains(value)
            }.count
        }

        /// Seven-day mean versus the 30-day mean: is it drifting?
        var weekVersusMonth: Double {
            Statistics.mean(points.suffix(7).map(\.value)) - average
        }
    }

    let metric: Metric
    let date: Date
    private(set) var state: LoadState<Content> = .loading
    private let calendar: Calendar

    init(metric: Metric, date: Date, calendar: Calendar = .current) {
        self.metric = metric
        self.date = date
        self.calendar = calendar
    }

    func load(using provider: any HealthDataProvider) async {
        do {
            let history = try await provider.summaries(endingOn: date, count: Baseline.windowDays, calendar: calendar)
            guard let day = history.last, calendar.isDate(day.date, inSameDayAs: date), metric.value(in: day) != nil else {
                state = .empty
                return
            }
            state = .loaded(Content(metric: metric, day: day, history: history))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
