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
                PactsView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: selection)
        // Derived here, inside a view, so unit changes in Settings re-render every screen.
        .environment(\.metricFormatter, settings.formatter)
    }
}

#Preview {
    RootTabView()
        .corvaPreview()
}
