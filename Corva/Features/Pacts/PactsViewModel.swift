import Foundation
import Observation

/// Loads the days pacts are judged on, and scores each pact against them.
@Observable
final class PactsViewModel {
    static let historyDays = 90

    /// One pact with its standings and who owes whom.
    struct Evaluation: Identifiable {
        let pact: Pact
        let you: PactEvaluation.Standing
        let friend: PactEvaluation.Standing?
        let settlement: PactEvaluation.Settlement
        let isFinished: Bool

        var id: Pact.ID { pact.id }
    }

    /// Totals across finished pacts, in one currency.
    struct Ledger {
        let finished: Int
        let kept: Int
        let received: Int
        let paid: Int
    }

    private(set) var state: LoadState<[DailySummary]> = .loading
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    var today: Date { calendar.startOfDay(for: .now) }

    func load(using provider: any HealthDataProvider) async {
        do {
            let days = try await provider.summaries(endingOn: today, count: Self.historyDays, calendar: calendar)
            state = .loaded(days)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func evaluate(_ pact: Pact, days: [DailySummary]) -> Evaluation {
        let you = PactEvaluation.standing(for: pact, days: days, today: today, calendar: calendar)
        let friend = PactEvaluation.friendStanding(for: pact, today: today, calendar: calendar)
        return Evaluation(
            pact: pact,
            you: you,
            friend: friend,
            settlement: PactEvaluation.settlement(for: pact, you: you, friend: friend),
            isFinished: pact.isFinished(today: today, calendar: calendar)
        )
    }

    func ledger(_ evaluations: [Evaluation], currencyCode: String) -> Ledger {
        let finished = evaluations.filter { $0.isFinished && $0.pact.currencyCode == currencyCode }
        var received = 0
        var paid = 0
        for evaluation in finished {
            switch evaluation.settlement {
            case .youReceive: received += evaluation.pact.stake
            case .youPay: paid += evaluation.pact.stake
            case .pending, .noMoneyMoves: break
            }
        }
        return Ledger(
            finished: finished.count,
            kept: finished.filter { $0.you.outcome == .kept }.count,
            received: received,
            paid: paid
        )
    }
}
