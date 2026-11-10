import SwiftUI

/// Notification settings: the morning recovery briefing, and the evening check-in for
/// experiments (on or off, and when).
struct CheckInSection: View {
    @Environment(EveningCheckIn.self) private var checkIn
    @Environment(MorningBriefing.self) private var morning

    var body: some View {
        @Bindable var checkIn = checkIn
        @Bindable var morning = morning
        Section {
            Toggle("Morning recovery", isOn: $morning.isEnabled)
            Toggle("Evening check-in", isOn: $checkIn.isEnabled)
            if checkIn.isEnabled {
                DatePicker("Check-in time", selection: time, displayedComponents: .hourAndMinute)
            }
            if (checkIn.isEnabled || morning.isEnabled) && !checkIn.isAuthorized {
                Button("Allow notifications") {
                    Task { await checkIn.requestAuthorizationIfNeeded() }
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(footer)
        }
        .listRowBackground(CorvaColor.surface)
        .onChange(of: morning.isEnabled) { _, isOn in
            if isOn { Task { await checkIn.requestAuthorizationIfNeeded() } }
        }
    }

    private var footer: String {
        var text = "Morning recovery: your score, HRV and sleep as soon as last night’s data is in. Skipped if you’ve already looked at Today. Needs Background App Refresh on for Corva."
        text += "\n\nEvening check-in: for on & off and randomised experiments, Corva asks each evening whether you did it. Answer Yes or No right from the notification. Randomised experiments also get a 6 PM heads-up."
        if (checkIn.isEnabled || morning.isEnabled) && !checkIn.isAuthorized {
            text += "\n\nNotifications are off for Corva. If tapping Allow does nothing, turn them on in the iOS Settings app."
        }
        return text
    }

    /// `minutes` as a time today, for the picker.
    private var time: Binding<Date> {
        Binding {
            Calendar.current.date(byAdding: .minute, value: checkIn.minutes, to: Calendar.current.startOfDay(for: .now)) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            checkIn.minutes = (parts.hour ?? 21) * 60 + (parts.minute ?? 0)
        }
    }
}

#Preview {
    List {
        CheckInSection()
    }
    .scrollContentBackground(.hidden)
    .corvaPreview()
}
