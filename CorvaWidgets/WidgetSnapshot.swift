import Foundation

/// What the widgets show: the latest day's scores. The app writes it into the shared App
/// Group container whenever it has fresh numbers; the widget extension only reads it.
///
/// Shared by the app and the widget extension (the file belongs to both targets), so it
/// carries only plain values, with the app doing all the scoring.
nonisolated struct WidgetSnapshot: Codable, Sendable, Equatable {
    static let appGroup = "group.com.corva.corva.app"
    private static let fileName = "widget-snapshot.json"

    /// The morning these numbers belong to.
    var day: Date
    /// 0-100.
    var recovery: Int
    /// "low", "moderate" or "high", as the app bands it.
    var recoveryZone: String
    /// "Low", "Moderate" or "High".
    var recoveryZoneTitle: String
    /// 0-100.
    var sleep: Int
    /// 0-100.
    var strain: Int
    /// Milliseconds.
    var hrv: Double
    /// Percent above (+) or below (−) the 30-day average, once there is one.
    var hrvChange: Int?
    var timeAsleep: TimeInterval

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Writes the snapshot. Returns whether it changed, so callers only reload widgets then.
    @discardableResult
    func save() -> Bool {
        guard let url = Self.fileURL, Self.load() != self, let data = try? JSONEncoder().encode(self) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Removes the snapshot (demo data, or no data source). Returns whether there was one.
    @discardableResult
    static func clear() -> Bool {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path()) else { return false }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    /// For widget previews and the gallery.
    static let sample = WidgetSnapshot(
        day: .now, recovery: 78, recoveryZone: "high", recoveryZoneTitle: "High",
        sleep: 84, strain: 41, hrv: 64, hrvChange: 8, timeAsleep: 7 * 3600 + 12 * 60
    )
}
