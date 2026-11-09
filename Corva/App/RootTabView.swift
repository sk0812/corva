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
    @Environment(ExperimentStore.self) private var experiments
    @Environment(EveningCheckIn.self) private var checkIn
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "waveform.path.ecg", value: AppTab.today) {
                TodayView()
            }
            Tab("Trends", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.trends) {
                TrendsView()
            }
            Tab("Lab", systemImage: "flask", value: AppTab.lab) {
                LabView()
            }
            Tab("Pacts", systemImage: "target", value: AppTab.pacts) {
                // Pacts are paused for launch; PactsView returns here when they're ready.
                PactsComingSoonView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: selection)
        .task { await account.start() }
        .onChange(of: settings.syncedValues) { account.settingsChanged() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await account.syncIfStale()
                    await account.reloadAppleHealthIfStale()
                    await checkIn.reschedule()
                }
            }
        }
        .onChange(of: experiments.experiments) { Task { await checkIn.reschedule() } }
        // Derived here, inside a view, so unit changes in Settings re-render every screen.
        .environment(\.metricFormatter, settings.formatter)
        .environment(\.dataVersion, account.dataVersion)
    }
}

#Preview {
    RootTabView()
        .corvaPreview()
}
