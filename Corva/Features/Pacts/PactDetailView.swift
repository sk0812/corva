import Charts
import SwiftUI

struct PactDetailView: View {
    let id: Pact.ID
    @Environment(\.healthDataProvider) private var provider
    @Environment(PactStore.self) private var store
    @State private var model = PactsViewModel()

    var body: some View {
        Group {
            if let pact = store.pact(id: id) {
                LoadStateView(model.state) { days in
                    ScrollView {
                        PactDetailContent(evaluation: model.evaluate(pact, days: days))
                    }
                }
            } else {
                ContentUnavailableView("Pact not found", systemImage: "target")
            }
        }
        .screenBackground(glow: CorvaColor.pact.opacity(0.8))
        .navigationTitle("Pact")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(using: provider) }
    }
}

private struct PactDetailContent: View {
    let evaluation: PactsViewModel.Evaluation
    @Environment(\.metricFormatter) private var format

    private var pact: Pact { evaluation.pact }

    var body: some View {
        VStack(spacing: Spacing.m) {
            GlassCard(tint: CorvaColor.pact) {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    PactTitle(pact: pact)
                    VStack(spacing: Spacing.s) {
                        ParticipantRow(name: "You", standing: evaluation.you)
                        if let friend = evaluation.friend, let name = pact.mode.friendName {
                            ParticipantRow(name: name, standing: friend)
                        }
                    }
                    if let sync = pact.sync, sync.status == .pending, sync.isCreator, let name = pact.mode.friendName {
                        PactInviteBlock(friendName: name, code: sync.inviteCode)
                    }
                    PactStatusLine(evaluation: evaluation)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    CardHeader(title: "Each \(format.pactDayNoun(pact.goal))", detail: "Target \(format.pactValue(pact.target, goal: pact.goal))")
                    PactChart(evaluation: evaluation)
                    ChartLegend(items: legendItems)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    CardHeader(title: "Day by day")
                    VStack(spacing: 0) {
                        ForEach(Array(evaluation.you.days.enumerated()), id: \.element.id) { index, day in
                            if index > 0 { CardDivider() }
                            DayRow(day: day, friendValue: evaluation.friend == nil ? nil : pact.friendValues[day.date], goal: pact.goal, friendName: pact.mode.friendName)
                        }
                    }
                }
            }

            GlassCard {
                VStack(spacing: 0) {
                    StatRow(title: "Rule", value: "\(pact.requiredDays) of \(pact.length)", unit: "\(format.pactDayNoun(pact.goal))s")
                    CardDivider()
                    StatRow(title: "Stake", value: format.money(pact.stake, currencyCode: pact.currencyCode), detail: stakeDetail)
                    CardDivider()
                    StatRow(title: "Sick-day pass", value: pact.sickDayPass ? "On" : "Off", detail: pact.sickDayPass ? "Days your vitals show you were unwell don’t count" : nil)
                    CardDivider()
                    StatRow(title: "Dates", value: dates)
                }
            }

            Text("Scored from your Google Health data. Nothing is self-reported, so nothing can be fudged.")
                .textStyle(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xxs)
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xxl)
    }

    private var legendItems: [ChartLegend.Item] {
        var items: [ChartLegend.Item] = [
            .init(label: "Met", color: CorvaColor.better),
            .init(label: "Missed", color: CorvaColor.worse),
        ]
        if let name = pact.mode.friendName, evaluation.friend != nil {
            items.append(.init(label: name, color: CorvaColor.textPrimary))
        }
        return items
    }

    private var stakeDetail: String {
        switch pact.mode {
        case .solo(.friend(let name)): "Goes to \(name) if you miss"
        case .solo(.charity(let name)): "Goes to \(name) if you miss"
        case .headToHead: "Each. If only one of you misses, they pay the other. Otherwise nobody pays."
        }
    }

    private var dates: String {
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        let end = pact.days(calendar: .current).last ?? pact.start
        return "\(pact.start.formatted(style)) – \(end.formatted(style))"
    }
}

private struct DayRow: View {
    let day: PactEvaluation.Day
    let friendValue: Double?
    let goal: Pact.Goal
    let friendName: String?
    @Environment(\.metricFormatter) private var format

    var body: some View {
        HStack(spacing: Spacing.s) {
            Text(day.date, format: .dateTime.weekday(.abbreviated).day())
                .font(.subheadline)
                .foregroundStyle(CorvaColor.textSecondary)
                .frame(width: 64, alignment: .leading)
            Text(statusTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
            Spacer(minLength: Spacing.xs)
            if let friendValue, day.status != .upcoming, let friendName {
                Text("\(friendName) \(format.pactValue(friendValue, goal: goal))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(CorvaColor.textTertiary)
            }
            Text(day.value.map { format.pactValue($0, goal: goal) } ?? "–")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(CorvaColor.textPrimary)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        switch day.status {
        case .met: "Met"
        case .missed: "Missed"
        case .excused: "Sick day"
        case .inProgress: goal.accumulatesDuringDay ? "Today" : "Tonight"
        case .upcoming: "Upcoming"
        }
    }

    private var statusColor: Color {
        switch day.status {
        case .met: CorvaColor.better
        case .missed: CorvaColor.worse
        case .inProgress: CorvaColor.pact
        case .excused, .upcoming: CorvaColor.textTertiary
        }
    }
}

/// Each day's value against the target line. Bedtime is drawn as points, since earlier is
/// better and a bar from the bottom would read backwards.
private struct PactChart: View {
    let evaluation: PactsViewModel.Evaluation
    @Environment(\.metricFormatter) private var format

    private var pact: Pact { evaluation.pact }

    var body: some View {
        Chart {
            ForEach(evaluation.you.days.filter { $0.value != nil }) { day in
                if pact.goal == .bedtime {
                    PointMark(x: .value("Day", day.date, unit: .day), y: .value("Value", day.value ?? 0))
                        .foregroundStyle(color(day.status))
                        .symbolSize(60)
                } else {
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Value", day.value ?? 0))
                        .foregroundStyle(color(day.status))
                        .cornerRadius(4)
                }
            }
            if evaluation.friend != nil {
                ForEach(evaluation.friend?.days.filter { $0.value != nil && $0.status != .upcoming } ?? []) { day in
                    PointMark(x: .value("Day", day.date, unit: .day), y: .value("Friend", day.value ?? 0))
                        .foregroundStyle(CorvaColor.textPrimary)
                        .symbol(.diamond)
                        .symbolSize(30)
                }
            }
            RuleMark(y: .value("Target", pact.target))
                .foregroundStyle(CorvaColor.pact)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: min(pact.length, 7))) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    .foregroundStyle(CorvaColor.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(CorvaColor.chartGrid)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(format.pactValue(number, goal: pact.goal))
                    }
                }
                .foregroundStyle(CorvaColor.textTertiary)
            }
        }
        .frame(height: Size.chartHeight)
    }

    private var xDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: pact.length, to: pact.start) ?? pact.start
        return pact.start...end
    }

    private var yDomain: ClosedRange<Double> {
        let values = evaluation.you.days.compactMap(\.value)
            + (evaluation.friend?.days.compactMap(\.value) ?? [])
            + [pact.target]
        let high = values.max() ?? pact.target
        if pact.goal == .bedtime {
            let low = values.min() ?? pact.target
            return (low - 20)...(high + 20)
        }
        return 0...(high * 1.1)
    }

    private func color(_ status: PactEvaluation.DayStatus) -> Color {
        switch status {
        case .met: CorvaColor.better
        case .missed: CorvaColor.worse
        case .inProgress: CorvaColor.pact
        case .excused, .upcoming: CorvaColor.textTertiary
        }
    }
}

#Preview {
    NavigationStack {
        PactDetailView(id: PactStore.preview.pacts[0].id)
    }
    .corvaPreview()
}
