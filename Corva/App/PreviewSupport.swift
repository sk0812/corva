import SwiftUI

extension View {
    /// Wraps a preview in the app's environment: mock data, default settings, dark scheme.
    func corvaPreview() -> some View {
        self
            .environment(AppSettings())
            .environment(ExperimentStore.preview)
            .environment(PactStore.preview)
            .environment(AccountService.preview)
            .environment(EveningCheckIn(account: AccountService.preview, experiments: ExperimentStore.preview))
            .environment(\.healthDataProvider, MockHealthDataProvider.preview)
            .preferredColorScheme(.dark)
            .tint(CorvaColor.accent)
            .screenBackground()
    }
}

extension DailySummary {
    /// The latest mock day, for component previews.
    static var preview: DailySummary {
        let days = MockHealthDataProvider.preview.days
        return days[days.count - 1]
    }

    /// The last seven mock days, oldest first.
    static var previewWeek: [DailySummary] {
        Array(MockHealthDataProvider.preview.days.suffix(7))
    }
}
