import SwiftUI

@main
struct CorvaApp: App {
    private let container = AppContainer.shared

    init() {
        container.checkIn.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(container.settings)
                .environment(container.experiments)
                .environment(container.pacts)
                .environment(container.account)
                .environment(container.checkIn)
                .environment(\.healthDataProvider, container.account.healthDataProvider)
                .environment(\.isShowingDemoData, !container.account.usesRealData)
                // Follows the system unless Settings › Appearance picks light or dark.
                .preferredColorScheme(container.settings.appearance.colorScheme)
                .tint(CorvaColor.accent)
        }
    }
}
