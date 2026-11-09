import SwiftUI

@main
struct CorvaApp: App {
    @State private var settings: AppSettings
    @State private var experiments: ExperimentStore
    @State private var pacts: PactStore
    @State private var account: AccountService

    init() {
        // Demo data until an account with Google Health connected takes over (AccountService
        // picks the provider; nothing downstream knows which it is).
        let mock = MockHealthDataProvider()
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
            pacts: pacts,
            demoProvider: mock
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                // Rebuilt when the data underneath changes (demo ⇄ real, or a sync lands).
                .id(account.dataVersion)
                .environment(settings)
                .environment(experiments)
                .environment(pacts)
                .environment(account)
                .environment(\.healthDataProvider, account.healthDataProvider)
                .environment(\.isShowingDemoData, !account.usesRealData)
                // Follows the system unless Settings › Appearance picks light or dark.
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(CorvaColor.accent)
        }
    }
}
