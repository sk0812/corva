import Foundation
import Observation
import UserNotifications

/// The evening check-in: one notification per tag-based experiment each evening, answered
/// with Yes or No straight from the notification, so tagging takes one tap without opening
/// the app. Randomised experiments also get a heads-up at 6 PM saying whether tonight is an
/// ON or OFF night.
///
/// Notifications are scheduled locally, a week ahead, and rebuilt whenever experiments change
/// or the app comes to the foreground.
@Observable
final class EveningCheckIn: NSObject, UNUserNotificationCenterDelegate {
    /// Whether the user wants check-ins. Stored on this device.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            Task { await reschedule() }
        }
    }

    /// Check-in time, as minutes after midnight. Default 9 PM.
    var minutes: Int {
        didSet {
            UserDefaults.standard.set(minutes, forKey: Keys.minutes)
            Task { await reschedule() }
        }
    }

    /// Whether notifications are allowed, as last checked.
    private(set) var isAuthorized = false

    @ObservationIgnored nonisolated private let account: AccountService
    @ObservationIgnored private let experiments: ExperimentStore
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    private enum Keys {
        static let enabled = "corva.checkIn.enabled"
        static let minutes = "corva.checkIn.minutes"
    }

    nonisolated static let category = "corva.checkIn"
    nonisolated static let yesAction = "corva.checkIn.yes"
    nonisolated static let noAction = "corva.checkIn.no"
    /// How many evenings ahead to schedule. iOS keeps at most 64 pending notifications.
    static let daysAhead = 7

    init(account: AccountService, experiments: ExperimentStore) {
        self.account = account
        self.experiments = experiments
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        minutes = defaults.object(forKey: Keys.minutes) as? Int ?? 21 * 60
        super.init()
    }

    /// Call once at launch: handles notification actions and registers the Yes/No buttons.
    func activate() {
        center.delegate = self
        let yes = UNNotificationAction(identifier: Self.yesAction, title: "Yes, I did")
        let no = UNNotificationAction(identifier: Self.noAction, title: "No")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [yes, no], intentIdentifiers: [])
        ])
        Task { await refreshAuthorization() }
    }

    /// Asks for permission the first time an experiment needs check-ins.
    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        await refreshAuthorization()
        await reschedule()
    }

    private func refreshAuthorization() async {
        let status = await center.notificationSettings().authorizationStatus
        isAuthorized = status == .authorized || status == .provisional
    }

    // MARK: - Scheduling

    /// Replaces every pending check-in with one per running tag-based experiment for each of
    /// the next few evenings.
    func reschedule() async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix("checkin.") || $0.hasPrefix("plan.") }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        await refreshAuthorization()
        guard isEnabled, isAuthorized else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let running = experiments.experiments.filter {
            $0.usesTags && !$0.isComplete(today: today, calendar: calendar)
        }
        for experiment in running {
            for evening in experiment.evenings(calendar: calendar) {
                guard let days = calendar.dateComponents([.day], from: today, to: evening).day,
                      (0..<Self.daysAhead).contains(days) else { continue }
                if experiment.design == .randomised {
                    await schedulePlanReminder(for: experiment, evening: evening, calendar: calendar)
                }
                await scheduleCheckIn(for: experiment, evening: evening, calendar: calendar)
            }
        }
    }

    private func scheduleCheckIn(for experiment: Experiment, evening: Date, calendar: Calendar) async {
        guard let fireDate = calendar.date(byAdding: .minute, value: minutes, to: evening), fireDate > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = experiment.title
        if experiment.design == .randomised {
            content.body = experiment.isOnNight(evening, calendar: calendar)
                ? "Tonight was an ON night. Did you do it?"
                : "Tonight was an OFF night. Did you do it anyway?"
        } else {
            content.body = "Did you do it tonight?"
        }
        content.categoryIdentifier = Self.category
        content.sound = .default
        content.userInfo = ["experimentID": experiment.id.uuidString, "evening": DayCoding.string(from: evening, calendar: calendar)]
        await add(content, id: "checkin.\(experiment.id.uuidString).\(DayCoding.string(from: evening, calendar: calendar))", at: fireDate, calendar: calendar)
    }

    private func schedulePlanReminder(for experiment: Experiment, evening: Date, calendar: Calendar) async {
        guard let fireDate = calendar.date(byAdding: .hour, value: 18, to: evening), fireDate > .now else { return }
        let isOn = experiment.isOnNight(evening, calendar: calendar)
        let content = UNMutableNotificationContent()
        content.title = isOn ? "Tonight is an ON night" : "Tonight is an OFF night"
        content.body = isOn ? "\(experiment.title): do it tonight." : "\(experiment.title): skip it tonight."
        content.sound = .default
        await add(content, id: "plan.\(experiment.id.uuidString).\(DayCoding.string(from: evening, calendar: calendar))", at: fireDate, calendar: calendar)
    }

    private func add(_ content: UNMutableNotificationContent, id: String, at date: Date, calendar: Calendar) async {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }

    // MARK: - Answers

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let experimentID = (info["experimentID"] as? String).flatMap(UUID.init(uuidString:))
        let evening = (info["evening"] as? String).flatMap { DayCoding.date(from: $0) }
        guard let experimentID, let evening else { return }
        switch action {
        case Self.yesAction: await account.setTag(evening: evening, isOn: true, experimentID: experimentID)
        case Self.noAction: await account.setTag(evening: evening, isOn: false, experimentID: experimentID)
        default: break // Tapped the notification itself: the app opens; nothing to record.
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
