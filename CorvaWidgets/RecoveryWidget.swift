import SwiftUI
import WidgetKit

/// This morning's recovery on the Home Screen and Lock Screen.
struct RecoveryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecoveryWidget", provider: RecoveryProvider()) { entry in
            RecoveryWidgetView(entry: entry)
        }
        .configurationDisplayName("Recovery")
        .description("This morning’s recovery, HRV and sleep.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct RecoveryEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct RecoveryProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecoveryEntry {
        RecoveryEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecoveryEntry) -> Void) {
        let snapshot = WidgetSnapshot.load()
        completion(RecoveryEntry(date: .now, snapshot: context.isPreview ? snapshot ?? .sample : snapshot))
    }

    /// The app reloads the widget whenever it has new numbers; the hourly refresh only keeps
    /// the "Yesterday" label honest after midnight.
    func getTimeline(in context: Context, completion: @escaping (Timeline<RecoveryEntry>) -> Void) {
        let entry = RecoveryEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

// MARK: - Views

struct RecoveryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecoveryEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .accessoryCircular: CircularView(snapshot: snapshot)
                case .accessoryRectangular: RectangularView(snapshot: snapshot, now: entry.date)
                case .accessoryInline: Text("Recovery \(snapshot.recovery)% · \(snapshot.recoveryZoneTitle)")
                case .systemMedium: MediumView(snapshot: snapshot, now: entry.date)
                default: SmallView(snapshot: snapshot, now: entry.date)
                }
            } else {
                NoDataView(family: family)
            }
        }
        .containerBackground(for: .widget) {
            WidgetColor.background
        }
    }
}

private struct SmallView: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RECOVERY")
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                DayLabel(day: snapshot.day, now: now)
            }
            Ring(progress: Double(snapshot.recovery) / 100, color: WidgetColor.recovery(snapshot.recoveryZone), lineWidth: 9) {
                VStack(spacing: -2) {
                    Text("\(snapshot.recovery)%")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text(snapshot.recoveryZoneTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetColor.recovery(snapshot.recoveryZone))
                }
            }
            .frame(maxWidth: .infinity)
            Text(snapshot.hrvLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct MediumView: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("CORVA")
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Spacer()
                DayLabel(day: snapshot.day, now: now)
            }
            HStack(spacing: 0) {
                dial("Sleep", value: "\(snapshot.sleep)%", progress: Double(snapshot.sleep) / 100, color: WidgetColor.sleep)
                dial("Recovery", value: "\(snapshot.recovery)%", progress: Double(snapshot.recovery) / 100, color: WidgetColor.recovery(snapshot.recoveryZone))
                dial("Strain", value: "\(snapshot.strain)", progress: Double(snapshot.strain) / 100, color: WidgetColor.strain)
            }
            Text("\(snapshot.hrvLine) · Slept \(snapshot.sleepText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func dial(_ title: String, value: String, progress: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            Ring(progress: progress, color: color, lineWidth: 7) {
                Text(value)
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 62, height: 62)
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CircularView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Gauge(value: Double(snapshot.recovery), in: 0...100) {
            Text("REC")
        } currentValueLabel: {
            Text("\(snapshot.recovery)")
        }
        .gaugeStyle(.accessoryCircular)
    }
}

private struct RectangularView: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Recovery \(snapshot.recovery)% · \(snapshot.recoveryZoneTitle)")
                .font(.headline)
                .widgetAccentable()
            Text(snapshot.hrvLine)
            Text("Slept \(snapshot.sleepText)")
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NoDataView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("Corva: no data yet")
        case .accessoryCircular:
            Image(systemName: "waveform.path.ecg")
                .font(.title2)
        case .accessoryRectangular:
            Text("Open Corva to connect your data")
                .font(.caption)
        default:
            VStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundStyle(WidgetColor.recovery("high"))
                Text("Connect Google Health or Apple Health in Corva to see your recovery here.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// "Yesterday" or a weekday when the numbers aren't this morning's.
private struct DayLabel: View {
    let day: Date
    let now: Date

    var body: some View {
        let calendar = Calendar.current
        if !calendar.isDate(day, inSameDayAs: now) {
            Text(calendar.isDate(day, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now) ?? now)
                 ? "Yesterday"
                 : day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct Ring<Label: View>: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    @ViewBuilder let label: Label

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.01, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label
        }
        .padding(lineWidth / 2)
    }
}

private extension WidgetSnapshot {
    /// "HRV 64 ms · +8%"
    var hrvLine: String {
        let base = "HRV \(Int(hrv.rounded())) ms"
        guard let hrvChange else { return base }
        return hrvChange >= 0 ? "\(base) · +\(hrvChange)%" : "\(base) · −\(-hrvChange)%"
    }

    /// "7h 12m"
    var sleepText: String {
        Duration.seconds(timeAsleep.rounded()).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}

/// The app's colours, for the widget (which can't see the app's design system).
private enum WidgetColor {
    static let background = dynamic(light: 0xF7F8FA, dark: 0x111214)
    static let strain = dynamic(light: 0x1F6FE5, dark: 0x4B93FF)
    static let sleep = dynamic(light: 0x6A55E0, dark: 0x9B88FF)

    static func recovery(_ zone: String) -> Color {
        switch zone {
        case "low": dynamic(light: 0xD63A36, dark: 0xF2564F)
        case "moderate": dynamic(light: 0xC98A0B, dark: 0xF2B23E)
        default: dynamic(light: 0x14A35C, dark: 0x30D07A)
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

#Preview(as: .systemSmall) {
    RecoveryWidget()
} timeline: {
    RecoveryEntry(date: .now, snapshot: .sample)
    RecoveryEntry(date: .now, snapshot: nil)
}

#Preview(as: .systemMedium) {
    RecoveryWidget()
} timeline: {
    RecoveryEntry(date: .now, snapshot: .sample)
}

#Preview(as: .accessoryRectangular) {
    RecoveryWidget()
} timeline: {
    RecoveryEntry(date: .now, snapshot: .sample)
}
