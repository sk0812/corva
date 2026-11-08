import SwiftUI

/// One compact number with its label: the building block of stat grids.
struct StatTile: View {
    let label: String
    let value: String
    var unit: String?
    /// Context under the value. Ignored when `delta` is set.
    var detail: String?
    var delta: FormattedDelta?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .textStyle(.label)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).textStyle(.smallNumeral)
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(CorvaColor.textSecondary)
                        .lineLimit(1)
                }
            }
            if let delta {
                DeltaLabel(delta: delta)
            } else if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(CorvaColor.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Equal-width columns of `StatTile`s.
struct StatGrid<Content: View>: View {
    private let columns: Int
    private let content: Content

    init(columns: Int = 3, @ViewBuilder content: () -> Content) {
        self.columns = columns
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.m, alignment: .topLeading), count: columns),
            alignment: .leading,
            spacing: Spacing.m
        ) {
            content
        }
    }
}

#Preview("Stat grid") {
    GlassCard {
        StatGrid {
            StatTile(label: "Active", value: "705", unit: "kcal")
            StatTile(label: "Steps", value: "12,408")
            StatTile(label: "Avg HR", value: "69", unit: "bpm", delta: FormattedDelta(text: "2", direction: .up))
            StatTile(label: "Max HR", value: "171", unit: "bpm")
            StatTile(label: "Latency", value: "14m", detail: "to fall asleep")
            StatTile(label: "Wakes", value: "3")
        }
    }
    .padding(Spacing.screen)
    .corvaPreview()
}
