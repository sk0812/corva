import AuthenticationServices
import SwiftUI

/// Where health data comes from: Google Health through the account, and Apple Health on
/// this phone.
struct DataSourcesSection: View {
    @Environment(AccountService.self) private var account
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isConfirmingDisconnect = false

    private var google: GoogleHealthStatus? { account.googleHealth }
    private var isConnected: Bool { google?.connected == true }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google Health").textStyle(.body)
                        Text("Fitbit Air").textStyle(.caption)
                    }
                    Spacer(minLength: Spacing.s)
                    googleStatus
                }
                if let error = isConnected ? google?.lastError : account.googleHealthConnectError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(CorvaColor.alert)
                }
            }
            .padding(.vertical, Spacing.xxs)

            if account.isSignedIn {
                if isConnected {
                    Button("Sync now") {
                        Task { await account.syncGoogleHealth() }
                    }
                    .disabled(account.isWorking)
                    Button("Disconnect Google Health", role: .destructive) {
                        isConfirmingDisconnect = true
                    }
                    .disabled(account.isWorking)
                } else {
                    Button {
                        Task { await connect() }
                    } label: {
                        Label("Connect Google Health", systemImage: "link")
                    }
                    .disabled(account.isWorking)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Health").textStyle(.body)
                        Text("Apple Watch and apps on this iPhone").textStyle(.caption)
                    }
                    Spacer(minLength: Spacing.s)
                    Text(appleStatus)
                        .font(account.appleHealthEnabled ? .subheadline.weight(.medium) : .subheadline)
                        .foregroundStyle(account.appleHealthEnabled ? CorvaColor.textPrimary : CorvaColor.textTertiary)
                }
                if let error = account.appleHealthError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(CorvaColor.alert)
                }
            }
            .padding(.vertical, Spacing.xxs)

            if AppleHealthSource.isAvailable {
                if account.appleHealthEnabled {
                    Button("Stop using Apple Health", role: .destructive) {
                        Task { await account.disconnectAppleHealth() }
                    }
                } else {
                    Button {
                        Task { await account.connectAppleHealth() }
                    } label: {
                        Label("Connect Apple Health", systemImage: "heart.text.square")
                    }
                }
            }
        } header: {
            Text("Data sources")
        } footer: {
            Text(footer)
        }
        .listRowBackground(CorvaColor.surface)
        .confirmationDialog("Disconnect Google Health?", isPresented: $isConfirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                Task { await account.disconnectGoogleHealth() }
            }
        } message: {
            Text(account.appleHealthEnabled
                ? "Corva stops syncing, revokes its access at Google and deletes the synced data from your account. Screens keep showing your Apple Health data."
                : "Corva stops syncing, revokes its access at Google and deletes the synced data from your account. Screens go back to demo data.")
        }
    }

    @ViewBuilder
    private var googleStatus: some View {
        if !account.isSignedIn {
            Text("Sign in first")
                .font(.subheadline)
                .foregroundStyle(CorvaColor.textTertiary)
        } else if google == nil {
            ProgressView()
        } else if isConnected {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Connected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CorvaColor.textPrimary)
                Text(syncText)
                    .textStyle(.caption)
            }
        } else {
            Text("Not connected")
                .font(.subheadline)
                .foregroundStyle(CorvaColor.textTertiary)
        }
    }

    private var syncText: String {
        if let last = google?.lastSynced {
            return "Synced \(last.formatted(.relative(presentation: .named)))"
        }
        return account.isWorking ? "First sync…" : "Waiting for first sync"
    }

    private var appleStatus: String {
        if !AppleHealthSource.isAvailable { return "Not available" }
        return account.appleHealthEnabled ? "Connected" : "Not connected"
    }

    private var footer: String {
        [googleFooter, appleFooter].joined(separator: "\n\n")
    }

    private var googleFooter: String {
        if !account.isSignedIn {
            return "Google Health: sign in, then connect it to use your Fitbit’s data."
        }
        if isConnected {
            var text = "Google Health syncs every hour and when you open the app."
            if let expires = google?.expiresAt {
                text += " While Corva’s Google project is in testing, Google asks you to reconnect every 7 days (next: \(expires.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))))."
            }
            return text
        }
        return "Connect Google Health to use your Fitbit Air’s sleep, heart and activity data. Tokens stay on Corva’s server, never on this phone."
    }

    private var appleFooter: String {
        if account.appleHealthEnabled {
            var text = "Apple Health is read on this iPhone and never uploaded."
            if isConnected {
                text += " Each reading comes from one source, Google Health first, so nothing is counted twice."
            }
            text += " To change what Corva can read: Health app › your profile › Apps › Corva."
            return text
        }
        return "Apple Health needs no account. Recovery scores need sleep and heart-rate variability, from an Apple Watch or another wearable that writes to Health."
    }

    private func connect() async {
        await account.connectGoogleHealth { url in
            try await webAuthenticationSession.authenticate(
                using: url,
                callback: .customScheme(BackendConfig.authCallbackURL.scheme ?? "corva"),
                preferredBrowserSession: .ephemeral,
                additionalHeaderFields: [:]
            )
        }
    }
}

#Preview {
    List {
        DataSourcesSection()
    }
    .scrollContentBackground(.hidden)
    .corvaPreview()
}
