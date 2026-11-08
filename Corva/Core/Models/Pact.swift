import Foundation

/// A goal with money on it, verified by your wearable rather than by honour.
///
/// Solo pacts send your stake to a friend or a charity if you miss. Head-to-head pacts have
/// you and a friend commit to the same goal: whoever misses pays the other.
nonisolated struct Pact: Identifiable, Hashable, Sendable {
    nonisolated enum Goal: String, CaseIterable, Identifiable, Hashable, Sendable {
        case steps
        case sleep
        case exercise
        case strain
        case bedtime

        var id: String { rawValue }

        var title: String {
            switch self {
            case .steps: "Steps"
            case .sleep: "Sleep"
            case .exercise: "Exercise"
            case .strain: "Strain"
            case .bedtime: "Bedtime"
            }
        }

        var symbolName: String {
            switch self {
            case .steps: "figure.walk"
            case .sleep: "bed.double.fill"
            case .exercise: "figure.run"
            case .strain: "flame.fill"
            case .bedtime: "moon.fill"
            }
        }

        /// Bedtime is the one goal where a smaller value (earlier) is better.
        var higherIsBetter: Bool { self != .bedtime }

        /// Activity goals keep counting until midnight. Sleep goals are about the night that
        /// starts on the pact day, so they're settled by the next morning's summary.
        var accumulatesDuringDay: Bool {
            switch self {
            case .steps, .exercise, .strain: true
            case .sleep, .bedtime: false
            }
        }

        /// Days between a pact day and the summary that settles it.
        var summaryOffset: Int { accumulatesDuringDay ? 0 : 1 }

        /// Storage units: steps; seconds asleep; seconds of exercise; strain; minutes after 6 PM.
        var defaultTarget: Double {
            switch self {
            case .steps: 10_000
            case .sleep: 7.5 * 3600
            case .exercise: 30 * 60
            case .strain: 50
            case .bedtime: 270 // 10:30 PM
            }
        }

        var targetStep: Double {
            switch self {
            case .steps: 500
            case .sleep: 15 * 60
            case .exercise: 5 * 60
            case .strain: 5
            case .bedtime: 15
            }
        }

        var targetRange: ClosedRange<Double> {
            switch self {
            case .steps: 2_000...30_000
            case .sleep: 5 * 3600...10 * 3600
            case .exercise: 10 * 60...180 * 60
            case .strain: 10...95
            case .bedtime: 150...390 // 8:30 PM to 12:30 AM
            }
        }

        func value(in day: DailySummary, calendar: Calendar) -> Double {
            switch self {
            case .steps: Double(day.strain.steps)
            case .sleep: day.sleep.timeAsleep
            case .exercise: day.strain.activities.reduce(0) { $0 + $1.duration }
            case .strain: Double(day.strain.score)
            case .bedtime: day.sleep.minutesSinceEveningAnchor(day.sleep.bedtime, calendar: calendar)
            }
        }

        func isMet(_ value: Double, target: Double) -> Bool {
            higherIsBetter ? value >= target : value <= target
        }
    }

    nonisolated enum Recipient: Hashable, Sendable {
        case friend(String)
        case charity(String)

        var name: String {
            switch self {
            case .friend(let name), .charity(let name): name
            }
        }
    }

    nonisolated enum Mode: Hashable, Sendable {
        /// Only you commit. Miss, and the stake goes to the recipient.
        case solo(Recipient)
        /// You and a friend commit to the same goal. Whoever misses pays the other.
        case headToHead(friend: String)

        var friendName: String? {
            switch self {
            case .solo(.friend(let name)), .headToHead(let name): name
            case .solo(.charity): nil
            }
        }
    }

    let id: UUID
    var goal: Goal
    var target: Double
    /// The first pact day, as the start of that calendar day.
    var start: Date
    var length: Int
    /// Days the goal must be hit to keep the pact.
    var requiredDays: Int
    /// Whole units of `currencyCode`.
    var stake: Int
    var currencyCode: String
    var mode: Mode
    /// Days when your vitals show you were unwell don't count. Detected from data, so it
    /// can't be claimed.
    var sickDayPass: Bool
    /// A head-to-head friend's daily values, keyed by pact day. Until friends can connect
    /// their own accounts these are simulated.
    var friendValues: [Date: Double]

    init(
        id: UUID = UUID(),
        goal: Goal,
        target: Double,
        start: Date,
        length: Int,
        requiredDays: Int,
        stake: Int,
        currencyCode: String,
        mode: Mode,
        sickDayPass: Bool,
        friendValues: [Date: Double] = [:]
    ) {
        self.id = id
        self.goal = goal
        self.target = target
        self.start = start
        self.length = length
        self.requiredDays = requiredDays
        self.stake = stake
        self.currencyCode = currencyCode
        self.mode = mode
        self.sickDayPass = sickDayPass
        self.friendValues = friendValues
    }

    func days(calendar: Calendar) -> [Date] {
        (0..<length).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// The morning everything is known: the last day, or the morning after it for sleep goals.
    func settlesOn(calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: length - 1 + goal.summaryOffset, to: start) ?? start
    }

    func isFinished(today: Date, calendar: Calendar) -> Bool {
        calendar.startOfDay(for: today) > settlesOn(calendar: calendar)
    }
}
