import SwiftUI

/// Goals with money on them, refereed by your wearable.
struct PactsView: View {
    @Environment(\.healthDataProvider) private var provider
    @Environment(AccountService.self) private var account
    @State private var model = PactsViewModel()
    @State private var isAddingPact = false
    @State private var isJoiningPact = false
    @State private var isShowingSignInNote = false

    var body: some View {
        NavigationStack {
            LoadStateView(model.state) { days in
                ScrollView {
                    PactsContent(days: days, model: model, addPact: { isAddingPact = true })
                }
                .refreshable {
                    await account.refresh()
                    await model.load(using: provider)
                }
            }
            .screenBackground(glow: CorvaColor.pact.opacity(0.8))
            .navigationTitle("Pacts")
            // The title sits in the top bar row, not on its own row below it.
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Add", systemImage: "plus") {
                        Button("New pact", systemImage: "target") { isAddingPact = true }
                        Button("Join with a code", systemImage: "person.2") {
                            if account.isSignedIn {
                                isJoiningPact = true
                            } else {
                                isShowingSignInNote = true
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: Pact.ID.self) { id in
                PactDetailView(id: id)
            }
            .sheet(isPresented: $isAddingPact) {
                NewPactView()
            }
            .sheet(isPresented: $isJoiningPact) {
                JoinPactView()
            }
            .alert("Sign in to join a pact", isPresented: $isShowingSignInNote) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Joining a friend’s pact needs an account. Sign in from Settings › Account.")
            }
        }
        .task { await model.load(using: provider) }
    }
}

private struct PactsContent: View {
    let days: [DailySummary]
    let model: PactsViewModel
    let addPact: () -> Void
    @Environment(AccountService.self) private var account
    @Environment(PactStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.metricFormatter) private var format

    var body: some View {
        let evaluations = store.pacts.map { model.evaluate($0, days: days) }
        let active = evaluations.filter { !$0.isFinished }
        let finished = evaluations.filter(\.isFinished)

        VStack(spacing: Spacing.m) {
            LedgerCard(ledger: model.ledger(evaluations, currencyCode: settings.currencyCode), currencyCode: settings.currencyCode)

            SectionHeader(title: "Active", detail: active.isEmpty ? nil : "\(active.count)")
                .padding(.top, Spacing.s)
            if active.isEmpty {
                EmptyPactsCard(action: addPact)
            } else {
                GlassEffectContainer(spacing: Spacing.m) {
                    VStack(spacing: Spacing.m) {
                        ForEach(active) { evaluation in
                            NavigationLink(value: evaluation.pact.id) {
                                ActivePactCard(evaluation: evaluation, today: model.today)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !finished.isEmpty {
                SectionHeader(title: "Finished", detail: "\(finished.count)")
                    .padding(.top, Spacing.s)
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(finished.enumerated()), id: \.element.id) { index, evaluation in
                            if index > 0 { CardDivider() }
                            NavigationLink(value: evaluation.pact.id) {
                                FinishedPactRow(evaluation: evaluation)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text(account.isSignedIn
                 ? "Payments aren’t connected yet: Corva tracks each stake, but no money moves. A friend’s days appear once the server starts settling pacts."
                 : "Demo pacts. Payments aren’t connected yet: Corva tracks each stake, but no money moves. Friends’ numbers here are simulated.")
                .textStyle(.caption)
                .padding(.horizontal, Spacing.xxs)
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xxl)
    }
}

// MARK: - Ledger

private struct LedgerCard: View {
    let ledger: PactsViewModel.Ledger
    let currencyCode: String
    @Environment(\.metricFormatter) private var format

    var body: some View {
        GlassCard(tint: CorvaColor.pact) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Record", tint: CorvaColor.pact, detail: "Finished pacts")
                StatGrid {
                    StatTile(label: "Kept", value: "\(ledger.kept)", unit: "of \(ledger.finished)")
                    StatTile(label: "Won", value: format.money(ledger.received, currencyCode: currencyCode))
                    StatTile(label: "Paid", value: format.money(ledger.paid, currencyCode: currencyCode))
                }
            }
        }
    }
}

// MARK: - Active pact

private struct ActivePactCard: View {
    let evaluation: PactsViewModel.Evaluation
    let today: Date
    @Environment(\.metricFormatter) private var format

    private var pact: Pact { evaluation.pact }

    var body: some View {
        GlassCard(tint: CorvaColor.pact, isInteractive: true) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                PactTitle(pact: pact, showsChevron: true)
                VStack(spacing: Spacing.s) {
                    ParticipantRow(name: "You", standing: evaluation.you)
                    if let friend = evaluation.friend, let name = pact.mode.friendName {
                        ParticipantRow(name: name, standing: friend)
                    }
                }
                if let sync = pact.sync, sync.status == .pending, sync.isCreator, let name = pact.mode.friendName {
                    PactInviteBlock(friendName: name, code: sync.inviteCode)
                }
                if let progress = todayProgress {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        ProgressBar(fraction: progress.value / pact.target, tint: CorvaColor.pact, height: 6)
                        Text(progress.isMet
                             ? "\(format.pactValue(progress.value, goal: pact.goal)) today · goal hit"
                             : "\(format.pactValue(progress.value, goal: pact.goal)) of \(format.pactValue(pact.target, goal: pact.goal)) today")
                            .textStyle(.caption)
                            .monospacedDigit()
                    }
                }
                PactStatusLine(evaluation: evaluation)
            }
        }
    }

    /// Today's running total for activity goals that are still counting.
    private var todayProgress: (value: Double, isMet: Bool)? {
        guard pact.goal.accumulatesDuringDay,
              let day = evaluation.you.days.first(where: { $0.date == today }),
              let value = day.value else { return nil }
        return (value, day.status == .met)
    }
}

private struct FinishedPactRow: View {
    let evaluation: PactsViewModel.Evaluation
    @Environment(\.metricFormatter) private var format

    var body: some View {
        HStack(spacing: Spacing.s) {
            GoalIcon(goal: evaluation.pact.goal, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(format.pactGoal(evaluation.pact.goal, target: evaluation.pact.target))
                    .textStyle(.body)
                    .lineLimit(1)
                Text(PactText.settlement(evaluation, format: format))
                    .textStyle(.caption)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.xs)
            OutcomeBadge(outcome: evaluation.you.outcome)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CorvaColor.textTertiary)
        }
        .padding(.vertical, Spacing.s)
        .contentShape(.rect)
    }
}

private struct EmptyPactsCard: View {
    let action: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Put money on a goal")
                    .font(.headline)
                    .foregroundStyle(CorvaColor.textPrimary)
                Text("Commit to steps, sleep or exercise. Miss, and your stake goes to a friend or a charity. Your wearable is the referee.")
                    .textStyle(.bodySecondary)
                Button("New pact", action: action)
                    .buttonStyle(.glass)
                    .padding(.top, Spacing.xxs)
            }
        }
    }
}

// MARK: - Shared pieces

/// Goal icon, goal phrase and terms.
struct PactTitle: View {
    let pact: Pact
    var showsChevron = false
    @Environment(\.metricFormatter) private var format

    var body: some View {
        HStack(spacing: Spacing.s) {
            GoalIcon(goal: pact.goal, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(format.pactGoal(pact.goal, target: pact.target))
                    .font(.headline)
                    .foregroundStyle(CorvaColor.textPrimary)
                Text(PactText.terms(pact, format: format))
                    .textStyle(.caption)
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CorvaColor.textTertiary)
            }
        }
    }
}

struct GoalIcon: View {
    let goal: Pact.Goal
    let size: CGFloat

    var body: some View {
        Image(systemName: goal.symbolName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(CorvaColor.pact)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(CorvaColor.pact.opacity(0.15)), in: .circle)
            .accessibilityHidden(true)
    }
}

/// A name, one dot per day, and days met against days needed.
struct ParticipantRow: View {
    let name: String
    let standing: PactEvaluation.Standing

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CorvaColor.textPrimary)
                .lineLimit(1)
                .frame(width: 56, alignment: .leading)
            DayDots(days: standing.days)
            Spacer(minLength: Spacing.xs)
            Text("\(standing.met)/\(standing.required)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(CorvaColor.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(standing.met) of \(standing.required) days met, \(standing.missed) missed")
    }
}

struct DayDots: View {
    let days: [PactEvaluation.Day]

    private var size: CGFloat { days.count > 10 ? 9 : 14 }

    var body: some View {
        HStack(spacing: days.count > 10 ? 3 : 5) {
            ForEach(days) { day in
                dot(day.status)
                    .frame(width: size, height: size)
            }
        }
    }

    @ViewBuilder
    private func dot(_ status: PactEvaluation.DayStatus) -> some View {
        switch status {
        case .met:
            Circle().fill(CorvaColor.better).shadow(color: CorvaColor.better.opacity(0.6), radius: 3)
        case .missed:
            Circle().fill(CorvaColor.worse)
        case .excused:
            Circle().strokeBorder(CorvaColor.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
        case .inProgress:
            Circle().strokeBorder(CorvaColor.pact, lineWidth: 2)
        case .upcoming:
            Circle().fill(CorvaColor.ringTrack)
        }
    }
}

/// Where the pact stands, in one line.
struct PactStatusLine: View {
    let evaluation: PactsViewModel.Evaluation
    @Environment(\.metricFormatter) private var format

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(PactText.status(evaluation, format: format))
                .foregroundStyle(CorvaColor.textPrimary)
        }
        .font(.subheadline.weight(.medium))
    }

    private var symbol: String {
        switch evaluation.you.outcome {
        case .kept: "checkmark.circle.fill"
        case .broken: "xmark.circle.fill"
        case .open: evaluation.you.sparesLeft == 0 ? "exclamationmark.circle.fill" : "circle.dashed"
        }
    }

    private var color: Color {
        switch evaluation.you.outcome {
        case .kept: CorvaColor.better
        case .broken: CorvaColor.worse
        case .open: evaluation.you.sparesLeft == 0 ? CorvaColor.alert : CorvaColor.textSecondary
        }
    }
}

struct OutcomeBadge: View {
    let outcome: PactEvaluation.Outcome

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xxs)
            .glassEffect(.regular.tint(color.opacity(0.2)), in: .capsule)
    }

    private var title: String {
        switch outcome {
        case .kept: "Kept"
        case .broken: "Broken"
        case .open: "Open"
        }
    }

    private var color: Color {
        switch outcome {
        case .kept: CorvaColor.better
        case .broken: CorvaColor.worse
        case .open: CorvaColor.textSecondary
        }
    }
}

/// Wording shared by the list and the detail screen.
enum PactText {
    static func terms(_ pact: Pact, format: MetricFormatter) -> String {
        let stake = format.money(pact.stake, currencyCode: pact.currencyCode)
        let noun = format.pactDayNoun(pact.goal)
        let rule = "\(pact.requiredDays) of \(pact.length) \(noun)s"
        switch pact.mode {
        case .solo(let recipient):
            return "\(rule) · \(stake) to \(recipient.name) if you miss"
        case .headToHead(let friend):
            return "\(rule) · vs \(friend), \(stake) each"
        }
    }

    static func status(_ evaluation: PactsViewModel.Evaluation, format: MetricFormatter) -> String {
        let you = evaluation.you
        let pact = evaluation.pact
        let stake = format.money(pact.stake, currencyCode: pact.currencyCode)
        let noun = format.pactDayNoun(pact.goal)

        switch evaluation.settlement {
        case .youPay(let name):
            return "Broken · you owe \(name) \(stake)"
        case .youReceive(let name):
            return "\(name) missed · they owe you \(stake)"
        case .noMoneyMoves:
            if you.outcome == .kept {
                if case .headToHead = pact.mode { return "You both kept it · no money moves" }
                return "Kept · your \(stake) stays with you"
            }
            return "You both missed · no money moves"
        case .pending:
            switch you.outcome {
            case .kept:
                return "You’ve kept it · waiting on \(pact.mode.friendName ?? "your friend")"
            case .broken:
                return "Broken · you owe \(pact.mode.friendName ?? "them") \(stake) if they keep theirs"
            case .open:
                let left = you.remaining == 1 ? "1 \(noun) to go" : "\(you.remaining) \(noun)s to go"
                switch you.sparesLeft {
                case 0: return "No misses left · \(left)"
                case 1: return "1 miss to spare · \(left)"
                default: return "\(you.sparesLeft) misses to spare · \(left)"
                }
            }
        }
    }

    static func settlement(_ evaluation: PactsViewModel.Evaluation, format: MetricFormatter) -> String {
        let pact = evaluation.pact
        let stake = format.money(pact.stake, currencyCode: pact.currencyCode)
        let end = pact.days(calendar: .current).last ?? pact.start
        let date = end.formatted(.dateTime.day().month(.abbreviated))
        switch evaluation.settlement {
        case .youPay(let name): return "Paid \(name) \(stake) · \(date)"
        case .youReceive(let name): return "\(name) paid you \(stake) · \(date)"
        case .noMoneyMoves, .pending: return "\(evaluation.you.met) of \(pact.length) \(format.pactDayNoun(pact.goal))s · \(date)"
        }
    }
}

#Preview {
    PactsView()
        .corvaPreview()
}
