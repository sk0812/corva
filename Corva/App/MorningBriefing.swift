import BackgroundTasks
import Foundation
import Observation
import UserNotifications

/// The morning recovery notification: once a day, as soon as last night's data is in, your
/// recovery score, how your HRV compares with your average and how long you slept.
///
/// iOS wakes the app in the background now and then (Background App Refresh). Each wake
/// syncs, looks for this morning's summary and, if it's there and you haven't seen it yet,
/// posts it. Opening Today first counts as seeing it, so it never repeats what you've read.
@Observable
final class MorningBriefing {
    nonisolated static let taskIdentifier = "com.corva.corva.app.morning"

    /// Whether the user wants it. Stored on this device.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            if isEnabled { schedule() } else { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier) }
        }
    }

    @ObservationIgnored private let account: AccountService
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    private enum Keys {
        static let enabled = "corva.morning.enabled"
        /// The last day (yyyy-MM-dd) briefed or seen in the app.
        static let lastDay = "corva.morning.lastDay"
    }

    /// No briefing after this hour: a "morning" notification at teatime would be odd.
    private static let latestHour = 14

    init(account: AccountService) {
        self.account = account
        isEnabled = UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true
    }

    /// The background wake, from the scene's app-refresh handler.
    static func handleWake() async {
        await AppContainer.shared.morning.run()
    }

    /// Today's summary was on screen: nothing to send this morning.
    func markSeen(_ day: Date, calendar: Calendar = .current) {
        guard calendar.isDateInToday(day) else { return }
        UserDefaults.standard.set(DayCoding.string(from: day, calendar: calendar), forKey: Keys.lastDay)
    }

    private func hasBriefed(on day: Date, calendar: Calendar) -> Bool {
        UserDefaults.standard.string(forKey: Keys.lastDay) == DayCoding.string(from: day, calendar: calendar)
    }

    // MARK: - Scheduling

    /// Asks iOS to wake the app: every half hour or so through the morning until today's
    /// briefing is sent, otherwise from 5 AM tomorrow. iOS decides the actual time.
    func schedule() {
        guard isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = nextWake()
        try? BGTaskScheduler.shared.submit(request)
    }

    private func nextWake(now: Date = .now, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: now)
        if !hasBriefed(on: now, calendar: calendar), (5..<Self.latestHour).contains(hour) {
            return now.addingTimeInterval(30 * 60)
        }
        let fiveToday = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: now) ?? now
        return hour < 5 ? fiveToday : calendar.date(byAdding: .day, value: 1, to: fiveToday) ?? now
    }

    // MARK: - Briefing

    func run(calendar: Calendar = .current) async {
        defer { schedule() }
        let now = Date.now
        let hour = calendar.component(.hour, from: now)
        guard isEnabled, account.usesRealData, (4..<Self.latestHour).contains(hour),
              !hasBriefed(on: now, calendar: calendar) else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        await account.refreshHealthData()
        let today = calendar.startOfDay(for: now)
        guard let day = try? await account.healthDataProvider.summaries(from: today, through: now).last,
              calendar.isDate(day.date, inSameDayAs: today) else { return }
        WidgetSync.publish(day)
        guard !hasBriefed(on: now, calendar: calendar) else { return }

        let content = UNMutableNotificationContent()
        content.title = Self.title(for: day)
        content.body = Self.body(for: day)
        content.sound = .default
        let request = UNNotificationRequest(identifier: "morning.\(DayCoding.string(from: today, calendar: calendar))", content: content, trigger: nil)
        do {
            try await center.add(request)
            markSeen(today, calendar: calendar)
        } catch {
            // Not sent: the next wake tries again.
        }
    }

    /// "Recovery 72% · High"
    nonisolated static func title(for day: DailySummary) -> String {
        "Recovery \(day.recovery.score)% · \(day.recovery.zone.title)"
    }

    /// "HRV 64 ms, 8% above your average. Slept 7h 12m."
    nonisolated static func body(for day: DailySummary, format: MetricFormatter = MetricFormatter()) -> String {
        var parts: [String] = []
        let hrv = Int(day.vitals.hrv.rounded())
        if let percent = day.hrvChangePercent {
            switch percent {
            case 0: parts.append("HRV \(hrv) ms, right on your average.")
            case 1...: parts.append("HRV \(hrv) ms, \(percent)% above your average.")
            default: parts.append("HRV \(hrv) ms, \(-percent)% below your average.")
            }
        } else {
            parts.append("HRV \(hrv) ms.")
        }
        parts.append("Slept \(format.duration(day.sleep.timeAsleep)).")
        if day.isLikelyUnwell {
            parts.append("Several readings are off your usual range, so take it easy today.")
        }
        return parts.joined(separator: " ")
    }
}
