import SwiftUI

@main
struct CorvaApp: App {
    @State private var settings = AppSettings()
    @State private var experiments: ExperimentStore
    @State private var pacts: PactStore

    /// The single place the app chooses where data comes from. Swap in a Google Health or
    /// Apple Health provider here; nothing downstream needs to change.
    private let provider: any HealthDataProvider

    init() {
        let mock = MockHealthDataProvider()
        provider = mock
        // Seeded from the same simulated behaviour the mock days reflect.
        _experiments = State(initialValue: .mock(lifestyle: mock.lifestyle))
        _pacts = State(initialValue: .mock(lifestyle: mock.lifestyle))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(settings)
                .environment(experiments)
                .environment(pacts)
                .environment(\.healthDataProvider, provider)
                // Follows the system unless Settings › Appearance picks light or dark.
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(CorvaColor.accent)
        }
    }
}
