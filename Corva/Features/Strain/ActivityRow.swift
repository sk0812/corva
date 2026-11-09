import SwiftUI

/// One recorded activity. Compact on Today; detailed on Strain with its own zone breakdown.
struct ActivityRow: View {
    enum Style {
        case compact
        case detailed
    }

    let activity: Activity
    var style: Style = .detailed
    @Environment(\.metricFormatter) private var format

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Image(systemName: activity.symbolName)
                    .font(style == .detailed ? .title3 : .body)
                    .foregroundStyle(CorvaColor.strain)
                    .frame(width: style == .detailed ? 40 : 28, height: style == .detailed ? 40 : 28)
                    .glassEffect(.regular.tint(CorvaColor.strain.opacity(0.18)), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title).textStyle(.body)
                    Text(summary).textStyle(.caption)
                }
                Spacer(minLength: Spacing.s)
                // Strain comes from heart rate; without it there's nothing honest to show.
                if activity.averageHeartRate > 0 {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(activity.strain, format: .number).textStyle(.smallNumeral)
                        Text("Strain").textStyle(.label)
                    }
                }
            }
            if style == .detailed {
                SegmentedBar(
                    segments: activity.heartRateZones.map {
                        .init(id: $0.zone.title, value: $0.duration, color: $0.zone.color)
                    },
                    height: 6
                )
                HStack(spacing: Spacing.m) {
                    if activity.averageHeartRate > 0 {
                        detailStat("Avg", "\(activity.averageHeartRate) bpm")
                    }
                    if activity.maxHeartRate > 0 {
                        detailStat("Max", "\(activity.maxHeartRate) bpm")
                    }
                    if activity.energy > 0 {
                        detailStat("Energy", format.energy(activity.energy))
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func detailStat(_ label: String, _ value: String) -> some View {
        HStack(spacing: Spacing.xxs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(CorvaColor.textTertiary)
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(CorvaColor.textSecondary)
        }
    }

    private var summary: String {
        var parts = [format.clockTime(activity.start), format.duration(activity.duration)]
        if let distance = activity.distance {
            parts.append(format.distance(distance))
        }
        return parts.joined(separator: " · ")
    }
}

extension Activity {
    /// A symbol for the named sport when there is one (badminton, hockey…), else the kind's.
    var symbolName: String {
        let name = (self.name ?? "").lowercased()
        let named: [(String, String)] = [
            ("badminton", "figure.badminton"), ("tennis", "figure.tennis"), ("squash", "figure.squash"),
            ("hockey", "figure.hockey"), ("football", "figure.soccer"), ("soccer", "figure.soccer"),
            ("basketball", "figure.basketball"), ("cricket", "figure.cricket"), ("rugby", "figure.rugby"),
            ("boxing", "figure.boxing"), ("climb", "figure.climbing"), ("row", "figure.rower"),
            ("dance", "figure.dance"), ("golf", "figure.golf"), ("hiit", "figure.highintensity.intervaltraining"),
        ]
        return named.first { name.contains($0.0) }?.1 ?? kind.symbolName
    }
}

extension ActivityKind {
    var symbolName: String {
        switch self {
        case .run: "figure.run"
        case .ride: "figure.outdoor.cycle"
        case .strength: "figure.strengthtraining.traditional"
        case .walk: "figure.walk"
        case .swim: "figure.pool.swim"
        case .yoga: "figure.yoga"
        case .other: "figure.mixed.cardio"
        }
    }
}

#Preview("Activity rows") {
    let activities = MockHealthDataProvider.preview.days.flatMap(\.strain.activities).suffix(3)
    GlassCard {
        VStack(spacing: 0) {
            ForEach(Array(activities)) { activity in
                ActivityRow(activity: activity)
            }
            ActivityRow(activity: activities.first!, style: .compact)
        }
    }
    .padding(Spacing.screen)
    .corvaPreview()
}
