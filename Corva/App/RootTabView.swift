import SwiftUI

enum AppTab: Hashable {
    case today
    case trends
    case lab
    case pacts
    case settings
}

/// The system tab bar, which adopts Liquid Glass on its own.
struct RootTabView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AccountService.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .today

    var body: some View {
        // Data tabs are rebuilt when the data underneath changes (demo ⇄ real, or a sync
        // lands), so they reload. Settings isn't, so a sync started there stays put.
        TabView(selection: $selection) {
            Tab("Today", systemImage: "waveform.path.ecg", value: AppTab.today) {
                TodayView().id(account.dataVersion)
            }
            Tab("Trends", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.trends) {
                TrendsView().id(account.dataVersion)
            }
            Tab("Lab", systemImage: "flask", value: AppTab.lab) {
                LabView().id(account.dataVersion)
            }
            Tab("Pacts", systemImage: "target", value: AppTab.pacts) {
                PactsView().id(account.dataVersion)
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: selection)
        .task { await account.start() }
        .onChange(of: settings.syncedValues) { account.settingsChanged() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await account.syncIfStale() } }
        }
        // Derived here, inside a view, so unit changes in Settings re-render every screen.
        .environment(\.metricFormatter, settings.formatter)
    }
}

#Preview {
    RootTabView()
        .corvaPreview()
}
