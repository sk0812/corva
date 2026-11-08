import Foundation
import Observation

/// The user's pacts. In memory for now. Real pacts need a backend: to hold stakes with a
/// payment provider, and to receive a head-to-head friend's verified numbers.
@Observable
final class PactStore {
    private(set) var pacts: [Pact]

    init(pacts: [Pact] = []) {
        self.pacts = pacts
    }

    func pact(id: Pact.ID) -> Pact? {
        pacts.first { $0.id == id }
    }

    /// Adds a pact. Head-to-head friends get simulated numbers until friends can connect.
    func add(_ pact: Pact, calendar: Calendar = .current) {
        var pact = pact
        if case .headToHead = pact.mode, pact.friendValues.isEmpty {
            pact.friendValues = MockFriend.values(for: pact, seed: UInt64(truncatingIfNeeded: pact.id.hashValue), calendar: calendar)
        }
        pacts.insert(pact, at: 0)
    }
}

// MARK: - Mock

extension PactStore {
    static let preview = PactStore.mock(lifestyle: MockHealthDataProvider.preview.lifestyle)

    /// Two live pacts and three finished ones over the mock data. Outcomes aren't scripted:
    /// they're whatever the generated days say.
    static func mock(
        lifestyle: MockLifestyle,
        currencyCode: String = AppSettings.defaultCurrencyCode(),
        calendar: Calendar = .current
    ) -> PactStore {
        let today = lifestyle.today
        let day = { (offset: Int) in calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        let friend = "Sam"

        var pacts = [
            Pact(
                goal: .steps, target: 10_000, start: day(-2), length: 7, requiredDays: 5,
                stake: 5, currencyCode: currencyCode, mode: .headToHead(friend: friend), sickDayPass: true
            ),
            Pact(
                goal: .sleep, target: 7.25 * 3600, start: day(-9), length: 14, requiredDays: 10,
                stake: 10, currencyCode: currencyCode, mode: .solo(.charity("Local food bank")), sickDayPass: true
            ),
            Pact(
                goal: .steps, target: 8_000, start: day(-27), length: 7, requiredDays: 6,
                stake: 5, currencyCode: currencyCode, mode: .headToHead(friend: friend), sickDayPass: true
            ),
            Pact(
                goal: .strain, target: 35, start: day(-65), length: 7, requiredDays: 6,
                stake: 10, currencyCode: currencyCode, mode: .headToHead(friend: "Jordan"), sickDayPass: true
            ),
            Pact(
                goal: .exercise, target: 30 * 60, start: day(-41), length: 7, requiredDays: 5,
                stake: 10, currencyCode: currencyCode, mode: .solo(.friend(friend)), sickDayPass: false
            ),
            Pact(
                goal: .bedtime, target: 270, start: lifestyle.earlyBedtimeStart, length: lifestyle.earlyBedtimeNights,
                requiredDays: 10, stake: 20, currencyCode: currencyCode, mode: .solo(.friend("Priya")), sickDayPass: false
            ),
        ]
        for index in pacts.indices where pacts[index].friendValues.isEmpty {
            if case .headToHead = pacts[index].mode {
                pacts[index].friendValues = MockFriend.values(for: pacts[index], seed: UInt64(index + 1), calendar: calendar)
            }
        }
        return PactStore(pacts: pacts)
    }
}

/// Stand-in numbers for a friend: hovering just above the target, missing now and then.
private nonisolated enum MockFriend {
    static func values(for pact: Pact, seed: UInt64, calendar: Calendar) -> [Date: Double] {
        var random = SeededRandomNumberGenerator(seed: 0xF417_E7D0 ^ seed)
        var values: [Date: Double] = [:]
        for date in pact.days(calendar: calendar) {
            let spread = pact.goal == .bedtime ? 25 : abs(pact.target) * 0.14
            let lean = pact.goal.higherIsBetter ? spread * 0.6 : -spread * 0.6
            values[date] = max(0, random.normal(mean: pact.target + lean, standardDeviation: spread))
        }
        return values
    }
}
