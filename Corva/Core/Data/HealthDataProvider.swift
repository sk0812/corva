import Foundation

/// The only way the UI gets health data.
///
/// Views and view models depend on this protocol, never on a concrete provider, so the mock
/// can be replaced by Google Health and Apple Health implementations (or a provider that
/// merges both) without touching any UI code.
///
/// Requirements are deliberately minimal: a provider only needs to answer "which days do
/// you have in this range" and "are you connected". Conveniences live in the extension.
nonisolated protocol HealthDataProvider: Sendable {
    /// Every available daily summary whose `date` falls within `start...end`, oldest first.
    /// Days with no data are omitted rather than padded.
    func summaries(from start: Date, through end: Date) async throws -> [DailySummary]

    func connectionStatus(for source: DataSource) async -> ConnectionStatus
}

nonisolated extension HealthDataProvider {
    /// The `count` calendar days ending on (and including) `day`, oldest first.
    func summaries(endingOn day: Date, count: Int, calendar: Calendar = .current) async throws -> [DailySummary] {
        let end = calendar.startOfDay(for: day)
        let start = calendar.date(byAdding: .day, value: -(max(count, 1) - 1), to: end) ?? end
        return try await summaries(from: start, through: end)
    }

    func summary(for day: Date, calendar: Calendar = .current) async throws -> DailySummary? {
        try await summaries(endingOn: day, count: 1, calendar: calendar).last
    }
}
