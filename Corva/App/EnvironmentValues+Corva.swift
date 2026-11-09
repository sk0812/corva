import SwiftUI

extension EnvironmentValues {
    /// Where every screen gets its data. Views only ever see the protocol.
    ///
    /// Defaults to the shared mock so previews work without setup; `CorvaApp` injects the
    /// real choice explicitly.
    @Entry var healthDataProvider: any HealthDataProvider = MockHealthDataProvider.preview

    /// Formats values in the user's preferred units. Derived from `AppSettings` at the root.
    @Entry var metricFormatter = MetricFormatter()

    /// True while screens show generated demo data rather than the user's own.
    @Entry var isShowingDemoData = true

    /// Changes whenever the health data underneath changes (demo ⇄ real, or a sync lands).
    /// Screens load with `.task(id: dataVersion)`, so they reload in place instead of being
    /// rebuilt, which keeps open sheets, pushed screens and the chosen day.
    @Entry var dataVersion = 0
}
