import Foundation

/// Scores a pact day by day from health data and works out who owes whom.
nonisolated enum PactEvaluation {
    nonisolated enum DayStatus: Hashable, Sendable {
        case met
        case missed
        /// Vitals showed you were unwell, so the day was dropped (sick-day pass).
        case excused
        /// Today, not met yet but still counting (or tonight's sleep, not slept yet).
        case inProgress
        case upcoming
    }

    nonisolated struct Day: Identifiable, Hashable, Sendable {
        let date: Date
        let value: Double?
        let status: DayStatus

        var id: Date { date }
    }

    nonisolated enum Outcome: Hashable, Sendable {
        case open
        /// The goal was hit on enough days. Can happen before the last day.
        case kept
        /// Too many misses to recover. Can also happen early.
        case broken
    }

    nonisolated struct Standing: Hashable, Sendable {
        let days: [Day]
        /// Days needed, after any excused days are dropped from the pact.
        let required: Int

        var met: Int { days.filter { $0.status == .met }.count }
        var missed: Int { days.filter { $0.status == .missed }.count }
        var excused: Int { days.filter { $0.status == .excused }.count }
        var remaining: Int { days.filter { $0.status == .inProgress || $0.status == .upcoming }.count }
        /// Misses still allowed before the pact breaks.
        var sparesLeft: Int { max(met + remaining - required, 0) }

        var outcome: Outcome {
            if met >= required { return .kept }
            if met + remaining < required { return .broken }
            return .open
        }
    }

    nonisolated enum Settlement: Hashable, Sendable {
        case pending
        case noMoneyMoves
        case youPay(to: String)
        case youReceive(from: String)
    }

    /// Your standing, from your daily summaries.
    static func standing(
        for pact: Pact,
        days summaries: [DailySummary],
        today: Date,
        calendar: Calendar = .current
    ) -> Standing {
        let byDate = Dictionary(summaries.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let days = pact.days(calendar: calendar).map { date in
            let settlingDate = calendar.date(byAdding: .day, value: pact.goal.summaryOffset, to: date) ?? date
            let summary = byDate[settlingDate]
            let value = summary.map { pact.goal.value(in: $0, calendar: calendar) }
            let isUnwell = pact.sickDayPass && (summary?.isLikelyUnwell ?? false)
            return day(date: date, value: value, isUnwell: isUnwell, pact: pact, today: today, calendar: calendar)
        }
        return makeStanding(days: days, pact: pact)
    }

    /// A head-to-head friend's standing, from the values they've shared. Nil until there are
    /// any (a real pact before the server has settled a day).
    static func friendStanding(for pact: Pact, today: Date, calendar: Calendar = .current) -> Standing? {
        guard case .headToHead = pact.mode, !pact.friendValues.isEmpty else { return nil }
        let days = pact.days(calendar: calendar).map { date in
            day(date: date, value: pact.friendValues[date], isUnwell: false, pact: pact, today: today, calendar: calendar)
        }
        return makeStanding(days: days, pact: pact)
    }

    static func settlement(for pact: Pact, you: Standing, friend: Standing?) -> Settlement {
        switch pact.mode {
        case .solo(let recipient):
            switch you.outcome {
            case .open: return .pending
            case .kept: return .noMoneyMoves
            case .broken: return .youPay(to: recipient.name)
            }
        case .headToHead(let name):
            guard let friend else { return .pending }
            switch (you.outcome, friend.outcome) {
            case (.kept, .broken): return .youReceive(from: name)
            case (.broken, .kept): return .youPay(to: name)
            case (.kept, .kept), (.broken, .broken): return .noMoneyMoves
            default: return .pending
            }
        }
    }

    // MARK: - Helpers

    private static func day(
        date: Date,
        value: Double?,
        isUnwell: Bool,
        pact: Pact,
        today: Date,
        calendar: Calendar
    ) -> Day {
        let today = calendar.startOfDay(for: today)
        let settlingDate = calendar.date(byAdding: .day, value: pact.goal.summaryOffset, to: date) ?? date

        if date > today {
            return Day(date: date, value: nil, status: .upcoming)
        }
        if settlingDate > today {
            // Tonight's sleep hasn't happened yet.
            return Day(date: date, value: nil, status: .inProgress)
        }
        guard let value else {
            // No data for a finished day counts as a miss: the wearable is the referee.
            return Day(date: date, value: nil, status: date == today ? .inProgress : .missed)
        }
        if pact.goal.isMet(value, target: pact.target) {
            return Day(date: date, value: value, status: .met)
        }
        if pact.goal.accumulatesDuringDay && date == today {
            return Day(date: date, value: value, status: .inProgress)
        }
        return Day(date: date, value: value, status: isUnwell ? .excused : .missed)
    }

    private static func makeStanding(days: [Day], pact: Pact) -> Standing {
        let excused = days.filter { $0.status == .excused }.count
        return Standing(days: days, required: min(pact.requiredDays, pact.length - excused))
    }
}

extension DailySummary {
    /// Vitals outside their typical range in the direction illness pushes them: HRV and
    /// blood oxygen down; resting heart rate, breathing rate and skin temperature up.
    nonisolated var unwellSignals: [Metric] {
        Metric.vitals.filter { metric in
            guard let range = baseline[metric]?.typicalRange else { return false }
            let value = metric.value(in: self)
            switch metric {
            case .hrv, .bloodOxygen: return value < range.lowerBound
            case .restingHeartRate, .respiratoryRate, .skinTemperature: return value > range.upperBound
            case .recovery, .strain, .sleep: return false
            }
        }
    }

    /// Three or more vitals off at once, the way a cold or other illness moves them. Used to
    /// set days aside from comparisons and pacts, never to diagnose anything.
    nonisolated var isLikelyUnwell: Bool {
        unwellSignals.count >= 3
    }
}
