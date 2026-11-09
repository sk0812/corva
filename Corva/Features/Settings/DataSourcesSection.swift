import AuthenticationServices
import SwiftUI

/// Where health data comes from: connect, sync and disconnect Google Health.
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
                if let error = google?.lastError, isConnected {
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

            HStack(spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Health").textStyle(.body)
                    Text("Health app on this iPhone").textStyle(.caption)
                }
                Spacer(minLength: Spacing.s)
                Text("Coming soon")
                    .font(.subheadline)
                    .foregroundStyle(CorvaColor.textTertiary)
            }
            .padding(.vertical, Spacing.xxs)
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
            Text("Corva stops syncing, revokes its access at Google and deletes the synced data from your account. Screens go back to demo data.")
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

    private var footer: String {
        if !account.isSignedIn {
            return "Sign in, then connect Google Health to replace demo data with your own."
        }
        if isConnected {
            var text = "Corva syncs every hour and when you open the app."
            if let expires = google?.expiresAt {
                text += " While Corva’s Google project is in testing, Google asks you to reconnect every 7 days (next: \(expires.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))))."
            }
            return text
        }
        return "Connect Google Health to replace demo data with your Fitbit Air’s sleep, heart and activity data. Tokens stay on Corva’s server, never on this phone."
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
