import AppIntents
import Foundation

/// A running experiment as Shortcuts and Siri see it.
struct ExperimentEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Experiment"
    static let defaultQuery = ExperimentQuery()

    let id: UUID
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

/// Experiments you can log tonight: running on & off and randomised ones.
struct ExperimentQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ExperimentEntity] {
        taggable().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ExperimentEntity] {
        taggable()
    }

    @MainActor
    private func taggable() -> [ExperimentEntity] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return AppContainer.shared.experiments.experiments
            .filter { $0.usesTags && !$0.isComplete(today: today, calendar: calendar) }
            .map { ExperimentEntity(id: $0.id, title: $0.title) }
    }
}

/// "Log tonight": records whether you did an experiment's behaviour this evening, without
/// opening the app. Works from Shortcuts, Siri and the Action button.
struct LogTonightIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Tonight"
    static let description = IntentDescription("Record whether you did an experiment’s behaviour this evening.")

    @Parameter(title: "Experiment")
    var experiment: ExperimentEntity

    @Parameter(title: "Did it", default: true)
    var didIt: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$experiment) tonight") {
            \.$didIt
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let evening = Calendar.current.startOfDay(for: .now)
        await AppContainer.shared.account.setTag(evening: evening, isOn: didIt, experimentID: experiment.id)
        return .result(dialog: didIt ? "Logged \(experiment.title) for tonight." : "Logged no \(experiment.title) tonight.")
    }
}

struct CorvaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogTonightIntent(),
            phrases: [
                "Log tonight in \(.applicationName)",
                "Log \(\.$experiment) in \(.applicationName)",
            ],
            shortTitle: "Log Tonight",
            systemImageName: "flask"
        )
    }
}
