import AuthenticationServices
import SwiftUI

/// Sign in and out, and sync status. Lives at the top of Settings.
struct AccountSection: View {
    @Environment(AccountService.self) private var account
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var isEmailSignInPresented = false
    @State private var isConfirmingSignOut = false

    var body: some View {
        Section {
            if let user = account.user {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title)
                        .foregroundStyle(CorvaColor.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name ?? user.email ?? "Signed in").textStyle(.body)
                        if user.name != nil, let email = user.email {
                            Text(email).textStyle(.caption)
                        }
                    }
                    Spacer(minLength: Spacing.s)
                    if account.isWorking {
                        ProgressView()
                    }
                }
                LabeledContent("Last synced", value: syncText)
                Button("Sync now") {
                    Task { await account.refresh() }
                }
                .disabled(account.isWorking)
                Button("Sign out", role: .destructive) {
                    isConfirmingSignOut = true
                }
            } else {
                Button {
                    Task { await signInWithGoogle() }
                } label: {
                    Label("Continue with Google", systemImage: "g.circle.fill")
                }
                .disabled(account.isWorking)
                Button {
                    isEmailSignInPresented = true
                } label: {
                    Label("Continue with email", systemImage: "envelope.fill")
                }
                .disabled(account.isWorking)
            }
            if let error = account.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(CorvaColor.alert)
            }
        } header: {
            Text("Account")
        } footer: {
            Text(account.isSignedIn
                 ? "Your experiments and settings sync to your account. Health data synced from Google Health is stored in your account so Corva can work with it; disconnecting deletes it."
                 : "Sign in to keep your experiments and to connect your own health data. Until then, Corva shows demo data.")
        }
        .listRowBackground(CorvaColor.surface)
        .sheet(isPresented: $isEmailSignInPresented) {
            EmailSignInView()
        }
        .confirmationDialog("Sign out of Corva?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await account.signOut() }
            }
        } message: {
            Text("Lab and Pacts go back to demo data on this phone. Everything stays in your account.")
        }
    }

    private var syncText: String {
        guard let date = account.lastSynced else { return account.isWorking ? "Syncing…" : "Not yet" }
        return date.formatted(.relative(presentation: .named))
    }

    private func signInWithGoogle() async {
        let scheme = BackendConfig.authCallbackURL.scheme ?? "corva"
        await account.signInWithGoogle { url in
            try await webAuthenticationSession.authenticate(
                using: url,
                callback: .customScheme(scheme),
                preferredBrowserSession: .ephemeral,
                additionalHeaderFields: [:]
            )
        }
    }
}

/// Email sign-in with a one-time code: enter your email, then the code from the message.
struct EmailSignInView: View {
    @Environment(AccountService.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(codeSent)
                } header: {
                    Text("Email")
                } footer: {
                    if !codeSent {
                        Text("Corva emails you a one-time code. New here? This creates your account.")
                    }
                }

                if codeSent {
                    Section {
                        TextField("Code", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                    } header: {
                        Text("Code")
                    } footer: {
                        Text("Check your inbox for a code from Corva. It expires after an hour.")
                    }
                }

                if let error = account.lastError {
                    Section {
                        Text(error).foregroundStyle(CorvaColor.alert)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CorvaColor.background)
            .navigationTitle("Sign in with email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if account.isWorking {
                        ProgressView()
                    } else if codeSent {
                        Button("Sign in", role: .confirm) {
                            Task {
                                if await account.verifyEmailCode(code.trimmingCharacters(in: .whitespaces), email: trimmedEmail) {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(code.trimmingCharacters(in: .whitespaces).count < 6)
                    } else {
                        Button("Send code", role: .confirm) {
                            Task { codeSent = await account.sendEmailCode(to: trimmedEmail) }
                        }
                        .disabled(!trimmedEmail.contains("@"))
                    }
                }
            }
        }
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

#Preview("Account section") {
    List {
        AccountSection()
    }
    .scrollContentBackground(.hidden)
    .corvaPreview()
}

#Preview("Email sign-in") {
    EmailSignInView()
        .corvaPreview()
}
