import Foundation
import Observation

@Observable
final class TodayViewModel {
    struct Content {
        let day: DailySummary
        /// Up to 30 days ending on `day`, oldest first.
        let history: [DailySummary]
        /// Today was asked for but last night hasn't synced, so this is the latest day there is.
        var isEarlierDay = false

        var week: [DailySummary] { history.lastDays(7, endingOn: day.date) }

        /// The day's value minus its 30-day baseline.
        func delta(_ metric: Metric) -> Double? {
            day.baseline.delta(for: metric, in: day)
        }

        var strainTarget: ClosedRange<Int> {
            Insights.strainTarget(recovery: day.recovery.score)
        }

        func isInTypicalRange(_ metric: Metric) -> Bool {
            guard let value = metric.value(in: day) else { return true }
            return day.baseline[metric]?.contains(value) ?? true
        }

        /// The vitals this night has readings for.
        var availableVitals: [Metric] {
            Metric.vitals.filter { $0.value(in: day) != nil }
        }

        var vitalsInRange: Int {
            availableVitals.filter(isInTypicalRange).count
        }

        /// Sleep missed against need over the last seven nights.
        var weeklySleepDebt: TimeInterval {
            Insights.sleepDebt(week.map(\.sleep))
        }

        func weekAverage(_ metric: Metric) -> Double {
            Statistics.mean(week.compactMap(metric.value(in:)))
        }
    }

    private(set) var date: Date
    private(set) var state: LoadState<Content> = .loading
    private let calendar: Calendar

    init(date: Date = .now, calendar: Calendar = .current) {
        self.date = calendar.startOfDay(for: date)
        self.calendar = calendar
    }

    var isToday: Bool { calendar.isDateInToday(date) }
    var isYesterday: Bool { calendar.isDateInYesterday(date) }

    func load(using provider: any HealthDataProvider) async {
        do {
            let history = try await provider.summaries(endingOn: date, count: Baseline.windowDays, calendar: calendar)
            guard let day = history.last else {
                state = .empty
                return
            }
            if calendar.isDate(day.date, inSameDayAs: date) {
                state = .loaded(Content(day: day, history: history))
            } else if isToday, let gap = calendar.dateComponents([.day], from: day.date, to: date).day, gap <= 3 {
                // Before last night syncs, show the latest day rather than nothing.
                state = .loaded(Content(day: day, history: history, isEarlierDay: true))
            } else {
                state = .empty
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Moves the overview one or more days back (negative) or forward, never past today.
    func step(by days: Int, using provider: any HealthDataProvider) async {
        guard let next = calendar.date(byAdding: .day, value: days, to: date),
              next <= calendar.startOfDay(for: .now) else { return }
        date = next
        await load(using: provider)
    }
}
