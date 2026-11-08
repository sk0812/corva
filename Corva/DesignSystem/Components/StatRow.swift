import SwiftUI

/// One labelled value in a list: title (and optional explanation) on the left, value on the
/// right, with either a delta or a secondary value beneath it.
struct StatRow: View {
    let title: String
    let value: String
    var unit: String?
    /// Explanation under the title, e.g. "Baseline 58 ms".
    var detail: String?
    /// Change shown under the value.
    var delta: FormattedDelta?
    /// Secondary value under the value, e.g. a percentage. Ignored when `delta` is set.
    var trailingDetail: String?
    /// Colour key, for rows that double as a chart legend.
    var swatch: Color?

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            if let swatch {
                RoundedRectangle(cornerRadius: 3)
                    .fill(swatch)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(.body)
                if let detail {
                    Text(detail).textStyle(.caption)
                }
            }
            Spacer(minLength: Spacing.s)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value).textStyle(.smallNumeral)
                    if let unit, !unit.isEmpty {
                        Text(unit).textStyle(.unit)
                    }
                }
                if let delta {
                    DeltaLabel(delta: delta)
                } else if let trailingDetail {
                    Text(trailingDetail)
                        .textStyle(.caption)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Stat rows") {
    GlassCard {
        VStack(spacing: 0) {
            StatRow(title: "HRV", value: "64", unit: "ms", detail: "Baseline 58 ms", delta: FormattedDelta(text: "6", direction: .up))
            CardDivider()
            StatRow(title: "Deep", value: "1h 42m", trailingDetail: "22%", swatch: CorvaColor.sleep)
            CardDivider()
            StatRow(title: "Efficiency", value: "93%")
        }
    }
    .padding(Spacing.screen)
    .corvaPreview()
}
