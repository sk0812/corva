import Foundation
import Observation

/// The user's experiments. In memory for now; this becomes a SwiftData store (or a sync
/// service) when persistence arrives, behind the same methods.
@Observable
final class ExperimentStore {
    private(set) var experiments: [Experiment]

    init(experiments: [Experiment] = []) {
        self.experiments = experiments
    }

    func experiment(id: Experiment.ID) -> Experiment? {
        experiments.first { $0.id == id }
    }

    func add(_ experiment: Experiment) {
        experiments.insert(experiment, at: 0)
    }

    /// Tags or untags the evening for an on & off experiment.
    func toggleTag(evening: Date, in id: Experiment.ID) {
        guard let index = experiments.firstIndex(where: { $0.id == id }) else { return }
        if experiments[index].taggedEvenings.contains(evening) {
            experiments[index].taggedEvenings.remove(evening)
        } else {
            experiments[index].taggedEvenings.insert(evening)
        }
    }

    /// Stops an experiment early by shortening it to the days already measured.
    func end(_ id: Experiment.ID, today: Date, calendar: Calendar = .current) {
        guard let index = experiments.firstIndex(where: { $0.id == id }) else { return }
        experiments[index].length = max(experiments[index].daysElapsed(today: today, calendar: calendar), 1)
    }

    func delete(_ id: Experiment.ID) {
        experiments.removeAll { $0.id == id }
    }
}

// MARK: - Mock

extension ExperimentStore {
    static let preview = ExperimentStore.mock(lifestyle: MockHealthDataProvider.preview.lifestyle)

    /// Three experiments over the mock data: one with a real negative effect (alcohol), one
    /// with none (magnesium), and a finished one with a real positive effect (earlier bedtime).
    static func mock(lifestyle: MockLifestyle, calendar: Calendar = .current) -> ExperimentStore {
        let today = lifestyle.today
        let day = { (offset: Int) in calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        let alcoholStart = day(-34)

        return ExperimentStore(experiments: [
            Experiment(
                title: "Evening alcohol",
                design: .onOff,
                start: alcoholStart,
                length: 42,
                outcomes: [.hrv, .restingHeartRate, .recovery, .sleep],
                taggedEvenings: lifestyle.alcoholEvenings.filter { $0 >= alcoholStart && $0 < today }
            ),
            Experiment(
                title: "Magnesium before bed",
                design: .beforeAfter,
                start: lifestyle.magnesiumStart,
                length: 21,
                outcomes: [.sleep, .hrv, .recovery]
            ),
            Experiment(
                title: "In bed by 10:30 PM",
                design: .beforeAfter,
                start: lifestyle.earlyBedtimeStart,
                length: lifestyle.earlyBedtimeNights,
                outcomes: [.recovery, .sleep, .hrv, .restingHeartRate]
            ),
        ])
    }
}
