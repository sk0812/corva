import Foundation
import WidgetKit

/// Keeps the Home Screen and Lock Screen widgets in step with the app: writes the latest
/// day into the shared snapshot and reloads the widgets when it changes.
enum WidgetSync {
    /// `nil` means there's nothing of the user's own to show (demo data), so the widgets
    /// ask them to connect a data source instead of showing made-up numbers.
    static func publish(_ day: DailySummary?) {
        let changed = day.map { WidgetSnapshot($0).save() } ?? WidgetSnapshot.clear()
        if changed {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

extension WidgetSnapshot {
    init(_ day: DailySummary) {
        self.init(
            day: day.date,
            recovery: day.recovery.score,
            recoveryZone: day.recovery.zone.rawValue,
            recoveryZoneTitle: day.recovery.zone.title,
            sleep: day.sleep.score,
            strain: day.strain.score,
            hrv: day.vitals.hrv,
            hrvChange: day.hrvChangePercent,
            timeAsleep: day.sleep.timeAsleep
        )
    }
}

extension DailySummary {
    /// HRV against its 30-day average, in whole percent. Nil until there's an average.
    nonisolated var hrvChangePercent: Int? {
        guard let mean = baseline[.hrv]?.mean, mean > 0 else { return nil }
        return Int(((vitals.hrv - mean) / mean * 100).rounded())
    }
}
