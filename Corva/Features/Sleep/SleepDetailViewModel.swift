import Foundation
import Observation

@Observable
final class SleepDetailViewModel {
    /// One night positioned on a shared evening-to-morning clock.
    struct Night: Identifiable {
        let date: Date
        /// Hours after 6 PM the evening before.
        let bedtimeHour: Double
        let wakeHour: Double
        let isSelected: Bool

        var id: Date { date }
    }

    struct Content {
        let day: DailySummary
        /// Up to 30 days ending on `day`, oldest first.
        let history: [DailySummary]
        /// The last seven nights ending with `day`, oldest first.
        let nights: [Night]
        /// 0-100, nil with fewer than two nights.
        let consistency: Int?
        let averageBedtime: Date?
        let averageWakeTime: Date?
        /// 6 PM the evening the selected night began; the origin for `Night` hours.
        let eveningAnchor: Date
        /// Mean time in each stage over `history`, excluding the selected night.
        let stageAverages: [SleepStage: TimeInterval]

        var sleep: SleepMetrics { day.sleep }
        var delta: Double? { day.baseline.delta(for: .sleep, in: day) }
        var weeklyDebt: TimeInterval { Insights.sleepDebt(history.suffix(SleepDetailViewModel.consistencyWindow).map(\.sleep)) }
        var fortnight: [DailySummary] { Array(history.suffix(14)) }
    }

    static let consistencyWindow = 7

    let date: Date
    private(set) var state: LoadState<Content> = .loading
    private let calendar: Calendar

    init(date: Date, calendar: Calendar = .current) {
        self.date = date
        self.calendar = calendar
    }

    func load(using provider: any HealthDataProvider) async {
        do {
            let history = try await provider.summaries(endingOn: date, count: Baseline.windowDays, calendar: calendar)
            guard let day = history.last, calendar.isDate(day.date, inSameDayAs: date) else {
                state = .empty
                return
            }
            state = .loaded(makeContent(day: day, history: history))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func makeContent(day: DailySummary, history: [DailySummary]) -> Content {
        let recent = Array(history.suffix(Self.consistencyWindow))
        let nights = recent.map { summary in
            Night(
                date: summary.date,
                bedtimeHour: summary.sleep.minutesSinceEveningAnchor(summary.sleep.bedtime, calendar: calendar) / 60,
                wakeHour: summary.sleep.minutesSinceEveningAnchor(summary.sleep.wakeTime, calendar: calendar) / 60,
                isSelected: summary.date == day.date
            )
        }

        // Average clock times, placed on the selected night's evening so they format as times.
        let anchor = day.sleep.eveningAnchor(calendar: calendar)
        let averageBedtime = nights.isEmpty ? nil
            : anchor.addingTimeInterval(Statistics.mean(nights.map(\.bedtimeHour)) * 3600)
        let averageWakeTime = nights.isEmpty ? nil
            : anchor.addingTimeInterval(Statistics.mean(nights.map(\.wakeHour)) * 3600)

        return Content(
            day: day,
            history: history,
            nights: nights,
            consistency: Scoring.sleepConsistency(recent.map(\.sleep), calendar: calendar),
            averageBedtime: averageBedtime,
            averageWakeTime: averageWakeTime,
            eveningAnchor: anchor,
            stageAverages: Insights.averageStageDurations(history.dropLast().map(\.sleep))
        )
    }
}
