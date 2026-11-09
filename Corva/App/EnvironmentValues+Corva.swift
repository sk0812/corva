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
}
