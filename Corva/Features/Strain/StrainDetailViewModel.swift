import Foundation
import Observation

@Observable
final class StrainDetailViewModel {
    struct Content {
        let day: DailySummary
        /// Up to 28 days ending on `day`, oldest first.
        let history: [DailySummary]

        var strain: StrainMetrics { day.strain }
        var delta: Double? { day.baseline.delta(for: .strain, in: day) }
        var target: ClosedRange<Int> { Insights.strainTarget(recovery: day.recovery.score) }
        var trainingLoad: Insights.TrainingLoad? { Insights.trainingLoad(history) }
        var fortnight: [DailySummary] { history.lastDays(14, endingOn: day.date) }
        var averageStrain: Double { Statistics.mean(history.map { Double($0.strain.score) }) }

        var totalZoneTime: TimeInterval { strain.heartRateZones.reduce(0) { $0 + $1.duration } }

        /// Time in zone 3 and above: the part of the day that builds fitness.
        var hardZoneTime: TimeInterval {
            strain.heartRateZones.filter { $0.zone >= .three }.reduce(0) { $0 + $1.duration }
        }
    }

    static let historyDays = 28

    let date: Date
    private(set) var state: LoadState<Content> = .loading
    private let calendar: Calendar

    init(date: Date, calendar: Calendar = .current) {
        self.date = date
        self.calendar = calendar
    }

    func load(using provider: any HealthDataProvider) async {
        do {
            let history = try await provider.summaries(endingOn: date, count: Self.historyDays, calendar: calendar)
            guard let day = history.last, calendar.isDate(day.date, inSameDayAs: date) else {
                state = .empty
                return
            }
            state = .loaded(Content(day: day, history: history))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
