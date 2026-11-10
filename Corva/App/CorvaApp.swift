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
                .environment(container.morning)
                .environment(\.healthDataProvider, container.account.healthDataProvider)
                .environment(\.isShowingDemoData, !container.account.usesRealData)
                // Follows the system unless Settings › Appearance picks light or dark.
                .preferredColorScheme(container.settings.appearance.colorScheme)
                .tint(CorvaColor.accent)
        }
        // iOS wakes the app now and then to send the morning recovery notification.
        .backgroundTask(.appRefresh(MorningBriefing.taskIdentifier)) {
            await MorningBriefing.handleWake()
        }
    }
}
