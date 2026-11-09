import Foundation

/// A personal trial: change one thing and measure what it does to your own numbers.
///
/// Dates are evenings, because most changes (a drink, a supplement, an earlier bedtime) happen
/// in the evening and show up in the next morning's summary. The morning after `start` is the
/// first measured day.
nonisolated struct Experiment: Identifiable, Hashable, Sendable {
    nonisolated enum Design: String, CaseIterable, Identifiable, Hashable, Sendable {
        /// Do the new thing every day, compared with the four weeks before you started.
        case beforeAfter
        /// Do it on some days and not others, compared within the same weeks.
        case onOff
        /// Corva picks which nights are ON and which are OFF, at random and balanced by
        /// weekday, so habits that come with the behaviour (late Fridays) can't masquerade as
        /// its effect.
        case randomised

        var id: String { rawValue }

        var title: String {
            switch self {
            case .beforeAfter: "Before & after"
            case .onOff: "On & off days"
            case .randomised: "Randomised nights"
            }
        }

        var explanation: String {
            switch self {
            case .beforeAfter:
                "Do it every day. Corva compares the experiment with your previous four weeks."
            case .onOff:
                "Do it on some days only and tag them. Corva compares the mornings after with the rest."
            case .randomised:
                "Corva picks your ON and OFF nights at random, balanced across weekdays. It’s the most reliable way to see what something really does."
            }
        }
    }

    let id: UUID
    var title: String
    var design: Design
    /// The first evening of the experiment, as the start of that calendar day.
    var start: Date
    /// Planned length in days.
    var length: Int
    /// Metrics to compare. The first is the headline.
    var outcomes: [Metric]
    /// Evenings the behaviour happened. On & off designs only.
    var taggedEvenings: Set<Date>

    init(
        id: UUID = UUID(),
        title: String,
        design: Design,
        start: Date,
        length: Int,
        outcomes: [Metric],
        taggedEvenings: Set<Date> = []
    ) {
        self.id = id
        self.title = title
        self.design = design
        self.start = start
        self.length = length
        self.outcomes = outcomes
        self.taggedEvenings = taggedEvenings
    }

    /// Mornings measured so far, 0 to `length`.
    func daysElapsed(today: Date, calendar: Calendar) -> Int {
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: today)).day ?? 0
        return min(max(days, 0), length)
    }

    func isComplete(today: Date, calendar: Calendar) -> Bool {
        daysElapsed(today: today, calendar: calendar) >= length
    }

    /// Every evening of the experiment, from `start`, oldest first.
    func evenings(calendar: Calendar) -> [Date] {
        (0..<length).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Compares tagged mornings against untagged ones (on & off and randomised designs).
    var usesTags: Bool { design != .beforeAfter }

    /// For randomised experiments: whether `evening` is an ON night in the plan.
    func isOnNight(_ evening: Date, calendar: Calendar) -> Bool {
        taggedEvenings.contains(calendar.startOfDay(for: evening))
    }

    /// A random plan for `length` evenings from `start`: within each weekday, half the
    /// evenings are ON (alternating which half gets the odd one out), so ON and OFF nights are
    /// spread evenly across the week.
    static func randomPlan(start: Date, length: Int, calendar: Calendar) -> Set<Date> {
        var generator = SystemRandomNumberGenerator()
        return randomPlan(start: start, length: length, calendar: calendar, using: &generator)
    }

    static func randomPlan<G: RandomNumberGenerator>(start: Date, length: Int, calendar: Calendar, using generator: inout G) -> Set<Date> {
        let evenings = (0..<length).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let byWeekday = Dictionary(grouping: evenings) { calendar.component(.weekday, from: $0) }
        var on: Set<Date> = []
        var extraGoesOn = Bool.random(using: &generator)
        for weekday in byWeekday.keys.sorted() {
            let group = byWeekday[weekday]!.shuffled(using: &generator)
            var count = group.count / 2
            if group.count % 2 == 1 {
                if extraGoesOn { count += 1 }
                extraGoesOn.toggle()
            }
            on.formUnion(group.prefix(count))
        }
        return on
    }

    func isTagged(morning: Date, calendar: Calendar) -> Bool {
        guard let evening = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: morning)) else { return false }
        return taggedEvenings.contains(evening)
    }
}

extension Metric {
    /// Which way counts as an improvement, for metrics where there is one. Strain, breathing
    /// rate and skin temperature are reported as changes without a judgement.
    nonisolated var preferredDirection: TrendDirection? {
        switch self {
        case .recovery, .sleep, .hrv, .bloodOxygen: .up
        case .restingHeartRate: .down
        case .strain, .respiratoryRate, .skinTemperature: nil
        }
    }
}
