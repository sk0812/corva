import SwiftUI

struct BioAgeView: View {
    @Environment(\.healthDataProvider) private var provider
    @Environment(\.dataVersion) private var dataVersion
    @Environment(AppSettings.self) private var settings
    @State private var model = LabViewModel()

    var body: some View {
        LoadStateView(model.state) { days in
            ScrollView {
                if let profile = settings.profile, let estimate = model.bioAge(in: days, profile: profile) {
                    BioAgeContent(
                        estimate: estimate,
                        history: model.bioAgeHistory(in: days, profile: profile),
                        profile: profile
                    )
                } else if settings.profile == nil {
                    ContentUnavailableView("Add your age", systemImage: "person.crop.circle", description: Text("Bio age compares you with people your age. Set your age in Settings › Profile."))
                } else {
                    ContentUnavailableView("Not enough data", systemImage: "flask", description: Text("Bio age needs at least two weeks of data."))
                }
            }
        }
        .screenBackground(glow: CorvaColor.bioAge)
        .navigationTitle("Bio age")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: dataVersion) { await model.load(using: provider) }
    }
}

private struct BioAgeContent: View {
    let estimate: BioAge.Estimate
    let history: [DatedValue]
    let profile: Profile
    @Environment(\.metricFormatter) private var format

    /// Shared scale for every factor bar: the largest any marker can move.
    private let barLimit = BioAge.MarkerKind.allCases.map { max(abs($0.limit.lowerBound), $0.limit.upperBound) }.max() ?? 4

    var body: some View {
        VStack(spacing: Spacing.m) {
            hero
            groups
            trend
            factors
            Text(footnote)
                .textStyle(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xxs)
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xxl)
    }

    private var hero: some View {
        VStack(spacing: Spacing.s) {
            Text("Bio age").textStyle(.label)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                Text(format.age(estimate.biologicalAge)).textStyle(.heroNumeral)
                Text("years").textStyle(.unit)
            }
            Text(BioAgeText.comparison(estimate, format: format))
                .textStyle(.bodySecondary)
            if let first = history.first, history.count > 1 {
                let change = estimate.biologicalAge - first.value
                DeltaLabel(
                    delta: FormattedDelta(
                        text: "\(format.age(abs(change))) y",
                        direction: abs(change) < 0.05 ? .flat : (change > 0 ? .up : .down)
                    ),
                    suffix: "since \(first.date.formatted(.dateTime.day().month(.abbreviated)))"
                )
            }
            AgeScale(chronological: estimate.chronologicalAge, biological: estimate.biologicalAge)
                .padding(.top, Spacing.s)
        }
        .padding(.vertical, Spacing.m)
    }

    /// Net years from each group of markers.
    private var groups: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "By area", detail: "Years vs your age")
                StatGrid(columns: 4) {
                    ForEach(BioAge.Group.allCases, id: \.self) { group in
                        let years = estimate.markers.filter { $0.kind.group == group }.reduce(0) { $0 + $1.years }
                        StatTile(label: group.rawValue, value: format.signed(years), unit: "y")
                    }
                }
            }
        }
    }

    private var trend: some View {
        GlassCard(tint: CorvaColor.bioAge) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "Trend", tint: CorvaColor.bioAge, detail: "Weekly, each from 30 days")
                TrendChart(
                    points: history,
                    tint: CorvaColor.bioAge,
                    reference: estimate.chronologicalAge,
                    formatValue: { format.age($0) },
                    height: Size.compactChartHeight
                )
                ChartLegend(items: [
                    .init(label: "Bio age", color: CorvaColor.bioAge),
                    .init(label: "Your age", color: CorvaColor.textTertiary),
                ])
            }
        }
    }

    private var factors: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.s) {
                CardHeader(title: "What’s moving it", detail: "Most younger first")
                HStack {
                    Text("Younger")
                    Spacer()
                    Text("Older")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CorvaColor.textTertiary)
                VStack(spacing: 0) {
                    let sorted = estimate.markers.sorted { $0.years < $1.years }
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, marker in
                        if index > 0 { CardDivider() }
                        MarkerRow(marker: marker, barLimit: barLimit)
                    }
                }
            }
        }
    }

    private var footnote: String {
        var text = "An estimate from population reference values and activity guidelines, using your last 30 days. Not a medical test."
        if !estimate.markers.contains(where: { $0.kind == .vo2Max }) {
            text += " VO2 max isn’t available from your tracker, so it’s left out; it can move bio age by up to 4 years either way."
        }
        if profile.sex == .notSet {
            text += " Set your sex in Settings for sex-specific references."
        }
        return text
    }
}

private struct MarkerRow: View {
    let marker: BioAge.Marker
    let barLimit: Double
    @Environment(\.metricFormatter) private var format

    var body: some View {
        let value = format.bioMarker(marker.value, kind: marker.kind)
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(marker.kind.title).textStyle(.body)
                    Text("\(value.value) \(value.unit) · typical \(format.bioMarkerReference(marker))")
                        .textStyle(.caption)
                        .monospacedDigit()
                }
                Spacer(minLength: Spacing.xs)
                Text("\(format.signed(marker.years)) y")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(marker.years.magnitude < 0.05 ? CorvaColor.textSecondary : (marker.years < 0 ? CorvaColor.better : CorvaColor.worse))
            }
            DivergingBar(value: marker.years, limit: barLimit)
        }
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(marker.kind.title), \(value.value) \(value.unit), \(format.signed(marker.years)) years")
    }
}

/// Calendar age and bio age on one scale: a tick for the calendar, a glowing dot for the body.
struct AgeScale: View {
    let chronological: Double
    let biological: Double
    @Environment(\.metricFormatter) private var format

    private var domain: ClosedRange<Double> {
        let spread = max(8, abs(biological - chronological) + 3)
        return (chronological - spread)...(chronological + spread)
    }

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let calendarX = x(chronological, width: width)
                let bodyX = x(biological, width: width)
                ZStack(alignment: .leading) {
                    Capsule().fill(CorvaColor.ringTrack).frame(height: 6)
                    Capsule()
                        .fill(LinearGradient(colors: [CorvaColor.bioAge.opacity(0.2), CorvaColor.bioAge.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: abs(calendarX - bodyX), height: 6)
                        .offset(x: min(calendarX, bodyX))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(CorvaColor.textPrimary)
                        .frame(width: 2, height: 16)
                        .offset(x: calendarX - 1)
                    Circle()
                        .fill(CorvaColor.bioAge)
                        .frame(width: 14, height: 14)
                        .shadow(color: CorvaColor.bioAge.opacity(0.8), radius: 6)
                        .offset(x: bodyX - 7)
                }
                .frame(height: proxy.size.height)
            }
            .frame(height: 16)
            HStack {
                Text("\(Int(domain.lowerBound.rounded()))")
                Spacer()
                Text("Your age \(Int(chronological))")
                Spacer()
                Text("\(Int(domain.upperBound.rounded()))")
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(CorvaColor.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bio age \(format.age(biological)), calendar age \(Int(chronological))")
    }

    private func x(_ value: Double, width: CGFloat) -> CGFloat {
        let fraction = (value - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
        return CGFloat(min(max(fraction, 0), 1)) * width
    }
}

enum BioAgeText {
    /// "4.5 years younger than your age, 32"
    static func comparison(_ estimate: BioAge.Estimate, format: MetricFormatter) -> String {
        let difference = estimate.difference
        let age = Int(estimate.chronologicalAge)
        if abs(difference) < 0.05 { return "The same as your age, \(age)" }
        let years = format.age(abs(difference))
        return difference < 0
            ? "\(years) years younger than your age, \(age)"
            : "\(years) years older than your age, \(age)"
    }
}

#Preview {
    NavigationStack {
        BioAgeView()
    }
    .corvaPreview()
}

#Preview("Age scale") {
    AgeScale(chronological: 32, biological: 27.5)
        .padding(Spacing.screen)
        .corvaPreview()
}
