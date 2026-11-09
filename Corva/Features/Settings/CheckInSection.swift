import SwiftUI

/// Settings for the evening check-in: on or off, and when.
struct CheckInSection: View {
    @Environment(EveningCheckIn.self) private var checkIn

    var body: some View {
        @Bindable var checkIn = checkIn
        Section {
            Toggle("Evening check-in", isOn: $checkIn.isEnabled)
            if checkIn.isEnabled {
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                if !checkIn.isAuthorized {
                    Button("Allow notifications") {
                        Task { await checkIn.requestAuthorizationIfNeeded() }
                    }
                }
            }
        } header: {
            Text("Experiments")
        } footer: {
            Text(footer)
        }
        .listRowBackground(CorvaColor.surface)
    }

    private var footer: String {
        if checkIn.isEnabled && !checkIn.isAuthorized {
            return "Notifications are off for Corva. If tapping Allow does nothing, turn them on in the iOS Settings app."
        }
        return "For on & off and randomised experiments, Corva asks each evening whether you did it. Answer Yes or No right from the notification. Randomised experiments also get a 6 PM heads-up."
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
