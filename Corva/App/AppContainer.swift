import Foundation

/// The app's long-lived objects, created once.
///
/// The UI gets them through the SwiftUI environment. Code that runs outside a screen
/// (notification actions, Shortcuts, background refresh) reaches them here, so it acts on the
/// same stores and account as the screens.
@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let settings: AppSettings
    let experiments: ExperimentStore
    let pacts: PactStore
    let account: AccountService
    let checkIn: EveningCheckIn
    let morning: MorningBriefing

    private init() {
        // Demo data until Google Health or Apple Health takes over (AccountService
        // picks the provider; nothing downstream knows which it is). The demo experiments and
        // pacts are seeded from the same simulated behaviour the mock days reflect.
        let mock = MockHealthDataProvider()
        settings = AppSettings()
        experiments = ExperimentStore.mock(lifestyle: mock.lifestyle)
        pacts = PactStore.mock(lifestyle: mock.lifestyle)
        account = AccountService(
            client: SupabaseClient(),
            settings: settings,
            experiments: experiments,
            pacts: pacts,
            demoProvider: mock
        )
        checkIn = EveningCheckIn(account: account, experiments: experiments)
        morning = MorningBriefing(account: account)
    }
}
