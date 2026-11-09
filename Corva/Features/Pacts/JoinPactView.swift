import SwiftUI

/// Joins a friend's head-to-head pact from the code they shared: look it up, read the terms,
/// accept.
struct JoinPactView: View {
    @Environment(AccountService.self) private var account
    @Environment(\.metricFormatter) private var format
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var preview: PactInvitePreview?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. 3f9a1c2b7d4e", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: code) { preview = nil }
                } header: {
                    Text("Invite code")
                } footer: {
                    Text("Your friend sees this code on their pact after creating it.")
                }

                if let preview {
                    Section {
                        Text(terms(preview))
                            .font(.subheadline)
                            .foregroundStyle(CorvaColor.textPrimary)
                    } header: {
                        Text("The deal")
                    } footer: {
                        Text("Your wearable is the referee. Payments aren’t connected yet, so no money moves.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(CorvaColor.alert)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CorvaColor.background)
            .navigationTitle("Join a pact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else if preview != nil {
                        Button("Accept", role: .confirm) { Task { await accept() } }
                            .tint(CorvaColor.pact)
                    } else {
                        Button("Look up", role: .confirm) { Task { await lookUp() } }
                            .disabled(code.trimmingCharacters(in: .whitespaces).count < 6)
                    }
                }
            }
        }
    }

    private func terms(_ preview: PactInvitePreview) -> String {
        let who = preview.inviterName ?? "Your friend"
        let money = format.money(preview.stake, currencyCode: preview.currency)
        guard let goal = Pact.Goal(rawValue: preview.goal) else { return "\(who) invited you to a pact." }
        let noun = format.pactDayNoun(goal)
        let start = DayCoding.date(from: preview.startDate)?.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) ?? preview.startDate
        return "\(who) challenges you: \(format.pactCommitment(goal, target: preview.target).lowercased()) on at least \(preview.requiredDays) of \(preview.lengthDays) \(noun)s, from \(start). Whoever misses pays the other \(money)."
    }

    private func lookUp() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            preview = try await account.previewInvite(code: code)
            if preview == nil {
                errorMessage = "No open pact with that code. It may have expired or already been accepted."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func accept() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await account.acceptInvite(code: code)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// On a head-to-head pact the friend hasn't joined yet: the code to share.
struct PactInviteBlock: View {
    let friendName: String
    let code: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "hourglass")
                    .foregroundStyle(CorvaColor.pact)
                Text("Waiting for \(friendName) to join")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CorvaColor.textPrimary)
            }
            if let code {
                HStack(spacing: Spacing.s) {
                    Text(code)
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .foregroundStyle(CorvaColor.textPrimary)
                        .textSelection(.enabled)
                    Spacer(minLength: Spacing.xs)
                    ShareLink(
                        item: "Join my pact on Corva: open Pacts › + › Join with a code, and enter \(code)",
                        subject: Text("Join my Corva pact"),
                        preview: SharePreview("Corva pact invite")
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                }
                Text("They enter this code in Pacts › + › Join with a code. The pact starts once they accept.")
                    .textStyle(.caption)
            } else {
                Text("Creating the invite…").textStyle(.caption)
            }
        }
    }
}

#Preview("Join a pact") {
    JoinPactView()
        .corvaPreview()
}

#Preview("Invite block") {
    GlassCard {
        PactInviteBlock(friendName: "Alex", code: "3f9a1c2b7d4e")
    }
    .padding(Spacing.screen)
    .corvaPreview()
}
