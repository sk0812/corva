import Foundation
import Observation

/// Receives local experiment changes to push to an account.
protocol ExperimentSyncing: AnyObject {
    func experimentSaved(_ experiment: Experiment)
    func experimentDeleted(_ id: Experiment.ID)
    func experimentTag(evening: Date, isOn: Bool, in id: Experiment.ID)
}

/// The user's experiments. In memory; when signed in, every change is also pushed through
/// `remote`, and a sign-in or refresh replaces the contents with the account's.
@Observable
final class ExperimentStore {
    private(set) var experiments: [Experiment]
    @ObservationIgnored weak var remote: (any ExperimentSyncing)?

    init(experiments: [Experiment] = []) {
        self.experiments = experiments
    }

    func experiment(id: Experiment.ID) -> Experiment? {
        experiments.first { $0.id == id }
    }

    func add(_ experiment: Experiment) {
        experiments.insert(experiment, at: 0)
        remote?.experimentSaved(experiment)
    }

    /// Swaps in a whole set (the account's, or demo data on sign-out) without pushing anything.
    func replace(with experiments: [Experiment]) {
        self.experiments = experiments
    }

    /// Tags or untags the evening for an on & off experiment.
    func toggleTag(evening: Date, in id: Experiment.ID) {
        guard let index = experiments.firstIndex(where: { $0.id == id }) else { return }
        let isOn = !experiments[index].taggedEvenings.contains(evening)
        if isOn {
            experiments[index].taggedEvenings.insert(evening)
        } else {
            experiments[index].taggedEvenings.remove(evening)
        }
        remote?.experimentTag(evening: evening, isOn: isOn, in: id)
    }

    /// Stops an experiment early by shortening it to the days already measured.
    func end(_ id: Experiment.ID, today: Date, calendar: Calendar = .current) {
        guard let index = experiments.firstIndex(where: { $0.id == id }) else { return }
        experiments[index].length = max(experiments[index].daysElapsed(today: today, calendar: calendar), 1)
        remote?.experimentSaved(experiments[index])
    }

    func delete(_ id: Experiment.ID) {
        experiments.removeAll { $0.id == id }
        remote?.experimentDeleted(id)
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
