import SwiftUI

/// Shown on Today when three or more vitals moved the way illness moves them: which ones,
/// in plain words, and what Corva does about it. Never a diagnosis.
struct IllnessBanner: View {
    let signals: [Metric]

    var body: some View {
        GlassCard(tint: CorvaColor.alert) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "thermometer.medium")
                        .foregroundStyle(CorvaColor.alert)
                        .accessibilityHidden(true)
                    Text("Your body may be fighting something")
                        .font(.headline)
                        .foregroundStyle(CorvaColor.textPrimary)
                }
                Text("\(signals.count) of \(Metric.vitals.count) vitals moved the way they usually do when you’re unwell: \(description).")
                    .textStyle(.bodySecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Not a diagnosis. Corva leaves days like this out of experiments so they don’t skew results.")
                    .textStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var description: String {
        signals.map { metric -> String in
            switch metric {
            case .hrv: "HRV is low"
            case .restingHeartRate: "resting heart rate is high"
            case .respiratoryRate: "breathing rate is high"
            case .bloodOxygen: "blood oxygen is low"
            case .skinTemperature: "skin temperature is up"
            default: metric.title.lowercased()
            }
        }
        .formatted(.list(type: .and))
    }
}

#Preview {
    IllnessBanner(signals: [.hrv, .restingHeartRate, .skinTemperature])
        .padding(Spacing.screen)
        .corvaPreview()
}
