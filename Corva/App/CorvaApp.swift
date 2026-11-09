import SwiftUI

@main
struct CorvaApp: App {
    @State private var settings: AppSettings
    @State private var experiments: ExperimentStore
    @State private var pacts: PactStore
    @State private var account: AccountService

    /// The single place the app chooses where data comes from. Swap in a Google Health or
    /// Apple Health provider here; nothing downstream needs to change.
    private let provider: any HealthDataProvider

    init() {
        let mock = MockHealthDataProvider()
        provider = mock
        let settings = AppSettings()
        // Demo data, seeded from the same simulated behaviour the mock days reflect. Signing
        // in swaps in the account's own experiments and pacts.
        let experiments = ExperimentStore.mock(lifestyle: mock.lifestyle)
        let pacts = PactStore.mock(lifestyle: mock.lifestyle)
        _settings = State(initialValue: settings)
        _experiments = State(initialValue: experiments)
        _pacts = State(initialValue: pacts)
        _account = State(initialValue: AccountService(
            client: SupabaseClient(),
            settings: settings,
            experiments: experiments,
            pacts: pacts
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(settings)
                .environment(experiments)
                .environment(pacts)
                .environment(account)
                .environment(\.healthDataProvider, provider)
                // Follows the system unless Settings › Appearance picks light or dark.
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(CorvaColor.accent)
        }
    }
}
