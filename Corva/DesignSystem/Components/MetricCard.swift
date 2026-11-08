import SwiftUI

/// Glass card for one metric: label, value with unit, optional context, and change vs baseline.
struct MetricCard: View {
    enum Style {
        /// Half-width card with an optional sparkline.
        case regular
        /// Quarter-width tile; unit sits under the value so long units still fit.
        case compact
    }

    let label: String
    let value: String
    var unit: String?
    var delta: FormattedDelta?
    /// Context for the delta, e.g. "vs avg".
    var deltaSuffix: String?
    /// A short line of supporting context, e.g. "7h 42m asleep".
    var detail: String?
    /// Recent values for a sparkline (regular style only).
    var trend: [Double] = []
    /// The metric's colour, used for the marker dot and sparkline. Nil keeps the card neutral.
    var tint: Color?
    var style: Style = .regular
    /// Use when the card is a navigation link, so the glass responds to touch.
    var isInteractive = false

    var body: some View {
        VStack(alignment: .leading, spacing: style == .regular ? Spacing.s : Spacing.xs) {
            header
            valueView
            if let detail {
                Text(detail)
                    .textStyle(.caption)
                    .lineLimit(1)
            }
            if style == .regular, trend.count > 1 {
                Sparkline(values: trend, tint: tint ?? CorvaColor.neutralData)
                    .frame(height: Size.sparklineHeight)
            }
            Spacer(minLength: 0)
            if let delta {
                DeltaLabel(delta: delta, suffix: deltaSuffix)
            }
        }
        .padding(style == .regular ? Spacing.m : Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Glass isn't hit-testable on its own; without this only the text would be tappable.
        .contentShape(.rect(cornerRadius: cornerRadius))
        .glassEffect(
            .regular.tint(tint.map { $0.opacity(0.12) }).interactive(isInteractive),
            in: .rect(cornerRadius: cornerRadius)
        )
        .accessibilityElement(children: .combine)
    }

    private var cornerRadius: CGFloat {
        style == .regular ? Radius.l : Radius.m
    }

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            if let tint {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .shadow(color: tint.opacity(0.8), radius: 3)
            }
            Text(label)
                .textStyle(.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    @ViewBuilder
    private var valueView: some View {
        switch style {
        case .regular:
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).textStyle(.numeral)
                if let unit, !unit.isEmpty {
                    Text(unit).textStyle(.unit)
                }
            }
        case .compact:
            VStack(alignment: .leading, spacing: 0) {
                Text(value).textStyle(.smallNumeral)
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(CorvaColor.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}

#Preview("Metric cards") {
    let day = DailySummary.preview
    VStack(spacing: Spacing.m) {
        HStack(spacing: Spacing.s) {
            MetricCard(
                label: "Strain",
                value: "\(day.strain.score)",
                delta: FormattedDelta(text: "8", direction: .up),
                deltaSuffix: "vs avg",
                detail: "2 activities",
                trend: DailySummary.previewWeek.map { Double($0.strain.score) },
                tint: CorvaColor.strain
            )
            MetricCard(
                label: "Sleep",
                value: "\(day.sleep.score)",
                unit: "%",
                delta: FormattedDelta(text: "3", direction: .down),
                deltaSuffix: "vs avg",
                detail: "7h 42m asleep",
                trend: DailySummary.previewWeek.map { Double($0.sleep.score) },
                tint: CorvaColor.sleep
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: Spacing.xs) {
            MetricCard(label: "HRV", value: "64", unit: "ms", delta: FormattedDelta(text: "6", direction: .up), style: .compact)
            MetricCard(label: "RHR", value: "52", unit: "bpm", delta: FormattedDelta(text: "2", direction: .down), style: .compact)
            MetricCard(label: "Resp", value: "14.6", unit: "br/min", delta: FormattedDelta(text: "0.2", direction: .up), style: .compact)
            MetricCard(label: "Temp", value: "33.8", unit: "°C", delta: FormattedDelta(text: "0.0", direction: .flat), style: .compact)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(Spacing.screen)
    .corvaPreview()
}
