import Foundation
import Observation

/// Loads the history the Lab screens analyse and runs the analyses on it. Every Lab screen
/// owns its own instance, so each loads independently like the rest of the app.
@Observable
final class LabViewModel {
    /// Enough for 30-day bio age windows across two months, and a quarter of best/worst days.
    static let historyDays = 90

    private(set) var state: LoadState<[DailySummary]> = .loading
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    var today: Date { calendar.startOfDay(for: .now) }

    func load(using provider: any HealthDataProvider) async {
        do {
            let days = try await provider.summaries(endingOn: today, count: Self.historyDays, calendar: calendar)
            state = days.isEmpty ? .empty : .loaded(days)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Analyses

    func bioAge(in days: [DailySummary], profile: Profile) -> BioAge.Estimate? {
        BioAge.estimate(from: days, profile: profile, calendar: calendar)
    }

    func bioAgeHistory(in days: [DailySummary], profile: Profile) -> [DatedValue] {
        BioAge.history(from: days, profile: profile, calendar: calendar)
    }

    func contrast(in days: [DailySummary], rankingBy ranking: DayContrast.Ranking, experiments: [Experiment]) -> DayContrast.Result? {
        DayContrast.analyze(days, rankingBy: ranking, tags: tags(from: experiments), calendar: calendar)
    }

    func analysis(of experiment: Experiment, in days: [DailySummary]) -> ExperimentAnalysis.Result {
        ExperimentAnalysis.analyze(experiment, days: days, today: today, calendar: calendar)
    }

    /// On & off experiments double as tags for the best/worst comparison.
    private func tags(from experiments: [Experiment]) -> [DayContrast.Tag] {
        experiments.compactMap { experiment in
            guard experiment.design == .onOff,
                  let lastTracked = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
            let lastEvening = min(experiment.evenings(calendar: calendar).last ?? experiment.start, lastTracked)
            guard lastEvening >= experiment.start else { return nil }
            return DayContrast.Tag(name: experiment.title, evenings: experiment.taggedEvenings, tracked: experiment.start...lastEvening)
        }
    }
}
