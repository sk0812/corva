import Foundation

/// Every number Corva tracks over time.
///
/// `Metric` is the single vocabulary shared by baselines, trends, charts and formatting, so a
/// new metric only needs to be added here (plus a colour and a format) to appear everywhere.
nonisolated enum Metric: String, CaseIterable, Identifiable, Hashable, Sendable {
    case recovery
    case strain
    case sleep
    case hrv
    case restingHeartRate
    case respiratoryRate
    case bloodOxygen
    case skinTemperature

    static let scores: [Metric] = [.recovery, .strain, .sleep]
    static let vitals: [Metric] = [.hrv, .restingHeartRate, .respiratoryRate, .bloodOxygen, .skinTemperature]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recovery: "Recovery"
        case .strain: "Strain"
        case .sleep: "Sleep"
        case .hrv: "HRV"
        case .restingHeartRate: "Resting heart rate"
        case .respiratoryRate: "Respiratory rate"
        case .bloodOxygen: "Blood oxygen"
        case .skinTemperature: "Skin temperature"
        }
    }

    /// Fits in a quarter of the screen width.
    var shortTitle: String {
        switch self {
        case .recovery: "Recovery"
        case .strain: "Strain"
        case .sleep: "Sleep"
        case .hrv: "HRV"
        case .restingHeartRate: "RHR"
        case .respiratoryRate: "Resp"
        case .bloodOxygen: "SpO₂"
        case .skinTemperature: "Temp"
        }
    }

    /// Scores are 0-100 composites computed by Corva; everything else is a measured vital.
    var isScore: Bool { Metric.scores.contains(self) }

    func value(in summary: DailySummary) -> Double {
        switch self {
        case .recovery: Double(summary.recovery.score)
        case .strain: Double(summary.strain.score)
        case .sleep: Double(summary.sleep.score)
        case .hrv: summary.vitals.hrv
        case .restingHeartRate: summary.vitals.restingHeartRate
        case .respiratoryRate: summary.vitals.respiratoryRate
        case .bloodOxygen: summary.vitals.bloodOxygen
        case .skinTemperature: summary.vitals.skinTemperature
        }
    }
}

nonisolated enum TrendDirection: Hashable, Sendable {
    case up
    case down
    case flat
}

/// One metric value on one day: the unit of every chart.
nonisolated struct DatedValue: Identifiable, Hashable, Sendable {
    let date: Date
    let value: Double

    var id: Date { date }
}

extension Metric {
    nonisolated func series(in summaries: [DailySummary]) -> [DatedValue] {
        summaries.map { DatedValue(date: $0.date, value: value(in: $0)) }
    }
}
