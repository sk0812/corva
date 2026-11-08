import Foundation
import Observation

enum TrendPeriod: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90

    var id: Int { rawValue }
    var days: Int { rawValue }

    var title: String {
        switch self {
        case .week: "7D"
        case .month: "30D"
        case .quarter: "90D"
        }
    }

    var accessibilityTitle: String { "\(days) days" }
}

@Observable
final class TrendsViewModel {
    /// One metric over the selected period.
    struct Series: Identifiable {
        let metric: Metric
        let points: [DatedValue]
        let average: Double
        let lowest: Double
        let highest: Double
        /// Change across the period along the least-squares trend line.
        let change: Double

        var id: Metric { metric }
    }

    /// Everything that doesn't depend on the selected period; computed once per load.
    struct Content {
        /// All loaded days (up to 90), oldest first.
        let days: [DailySummary]
        let relationships: [Insights.Relationship]
        let recoveryByWeekday: [Insights.WeekdayAverage]
        let strainByWeekday: [Insights.WeekdayAverage]
    }

    var period: TrendPeriod = .month
    var selectedRelationshipID = "strain-recovery"
    private(set) var state: LoadState<Content> = .loading
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func load(using provider: any HealthDataProvider, now: Date = .now) async {
        do {
            let days = try await provider.summaries(endingOn: now, count: TrendPeriod.quarter.days, calendar: calendar)
            guard !days.isEmpty else {
                state = .empty
                return
            }
            state = .loaded(Content(
                days: days,
                relationships: Insights.relationships(in: days),
                recoveryByWeekday: Insights.weekdayAverages(of: .recovery, in: days, calendar: calendar),
                strainByWeekday: Insights.weekdayAverages(of: .strain, in: days, calendar: calendar)
            ))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func periodDays(in content: Content) -> [DailySummary] {
        Array(content.days.suffix(period.days))
    }

    func series(for metric: Metric, in content: Content) -> Series {
        let points = metric.series(in: periodDays(in: content))
        let values = points.map(\.value)
        return Series(
            metric: metric,
            points: points,
            average: Statistics.mean(values),
            lowest: values.min() ?? 0,
            highest: values.max() ?? 0,
            change: Statistics.trendChange(values)
        )
    }

    func distribution(in content: Content) -> [RecoveryZone: Int] {
        Insights.recoveryDistribution(periodDays(in: content))
    }
}
