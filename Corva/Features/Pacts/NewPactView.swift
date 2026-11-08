import SwiftUI

/// Sets up a pact: the goal, the rule, who's in, what's at stake.
struct NewPactView: View {
    private enum Opponent: Hashable {
        case solo
        case headToHead
    }

    private enum RecipientKind: Hashable {
        case friend
        case charity
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(PactStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.metricFormatter) private var format

    @State private var goal: Pact.Goal = .steps
    @State private var target = Pact.Goal.steps.defaultTarget
    @State private var length = 7
    @State private var requiredDays = 6
    @State private var opponent: Opponent = .headToHead
    @State private var recipientKind: RecipientKind = .friend
    @State private var name = ""
    @State private var stake = 5
    @State private var sickDayPass = true

    private static let lengths = [3, 7, 14, 30]
    private static let stakes = [1, 5, 10, 20, 50]

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    Picker("Goal", selection: $goal) {
                        ForEach(Pact.Goal.allCases) { goal in
                            Label(goal.title, systemImage: goal.symbolName).tag(goal)
                        }
                    }
                    .onChange(of: goal) { _, newGoal in target = newGoal.defaultTarget }
                    Stepper(value: $target, in: goal.targetRange, step: goal.targetStep) {
                        LabeledContent(goal == .bedtime ? "In bed by" : "Target", value: format.pactValue(target, goal: goal))
                    }
                    Picker("Length", selection: $length) {
                        ForEach(Self.lengths, id: \.self) { days in
                            Text("\(days) \(format.pactDayNoun(goal))s").tag(days)
                        }
                    }
                    .onChange(of: length) { _, newLength in
                        requiredDays = min(requiredDays, newLength)
                        if requiredDays == 0 { requiredDays = newLength }
                    }
                    Stepper(value: $requiredDays, in: 1...length) {
                        LabeledContent("Must hit", value: "\(requiredDays) of \(length)")
                    }
                }

                Section {
                    Picker("Who’s in", selection: $opponent) {
                        Text("Head to head").tag(Opponent.headToHead)
                        Text("Just me").tag(Opponent.solo)
                    }
                    .pickerStyle(.segmented)
                    if opponent == .solo {
                        Picker("If I miss, pay", selection: $recipientKind) {
                            Text("A friend").tag(RecipientKind.friend)
                            Text("A charity").tag(RecipientKind.charity)
                        }
                    }
                    TextField(namePrompt, text: $name)
                        .textContentType(opponent == .solo && recipientKind == .charity ? .organizationName : .name)
                } header: {
                    Text("Who")
                } footer: {
                    Text(opponent == .headToHead
                         ? "You both commit to the same goal. If only one of you misses, they pay the other. If you both keep it, or both miss, nobody pays."
                         : "Only you commit. Miss, and your stake goes to them.")
                }

                Section("Stake") {
                    Picker("Stake", selection: $stake) {
                        ForEach(Self.stakes, id: \.self) { amount in
                            Text(format.money(amount, currencyCode: settings.currencyCode)).tag(amount)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Sick-day pass", isOn: $sickDayPass)
                } footer: {
                    Text("Days when three or more of your vitals move the way illness moves them don’t count. Corva spots it in your data, so it can’t be claimed.")
                }

                Section {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(CorvaColor.textPrimary)
                } header: {
                    Text("The deal")
                } footer: {
                    Text("Payments aren’t connected yet: Corva tracks the stake, but no money moves.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(CorvaColor.background)
            .navigationTitle("New pact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commit", role: .confirm) {
                        store.add(makePact())
                        dismiss()
                    }
                    .tint(CorvaColor.pact)
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: stake)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var namePrompt: String {
        switch (opponent, recipientKind) {
        case (.headToHead, _): "Friend’s name"
        case (.solo, .friend): "Friend’s name"
        case (.solo, .charity): "Charity"
        }
    }

    private var summary: String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: length - 1, to: start) ?? start
        let endText = end.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let money = format.money(stake, currencyCode: settings.currencyCode)
        let who = trimmedName.isEmpty ? namePrompt.lowercased() : trimmedName
        let rule = "\(format.pactCommitment(goal, target: target)) on at least \(requiredDays) of \(length) \(format.pactDayNoun(goal))s, starting today and ending \(endText)."
        switch opponent {
        case .headToHead:
            return "\(rule) \(who) does the same. Whoever misses pays the other \(money)."
        case .solo:
            return "\(rule) Miss, and \(money) goes to \(who)."
        }
    }

    private func makePact() -> Pact {
        let mode: Pact.Mode = switch opponent {
        case .headToHead: .headToHead(friend: trimmedName)
        case .solo: .solo(recipientKind == .friend ? .friend(trimmedName) : .charity(trimmedName))
        }
        return Pact(
            goal: goal,
            target: target,
            start: Calendar.current.startOfDay(for: .now),
            length: length,
            requiredDays: requiredDays,
            stake: stake,
            currencyCode: settings.currencyCode,
            mode: mode,
            sickDayPass: sickDayPass
        )
    }
}

#Preview {
    NewPactView()
        .corvaPreview()
}
