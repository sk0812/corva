import Foundation

/// Corva's scoring model.
///
/// Scores are computed by Corva from raw signals rather than taken from a data source, so
/// they mean the same thing whichever provider supplied the underlying data. Every function
/// here is pure and deterministic.
nonisolated enum Scoring {

    // MARK: - Recovery

    /// Contribution of each signal to the recovery score. Sums to 1.
    static let recoveryWeights = (hrv: 0.5, restingHeartRate: 0.2, sleep: 0.3)

    /// Recovery, 0-100, from overnight physiology relative to the personal baseline.
    ///
    /// Each contributor is first mapped onto 0-100:
    /// - HRV: 58 at baseline; every 1% above or below moves it 2.5 points.
    /// - Resting heart rate: 58 at baseline; every beat per minute below adds 8 points.
    /// - Sleep: 100 at full performance; every point short of need costs two, so a night
    ///   at half of need contributes nothing.
    static func recovery(
        hrv: Double,
        hrvBaseline: Double,
        restingHeartRate: Double,
        restingHeartRateBaseline: Double,
        sleepScore: Int
    ) -> Int {
        let weights = recoveryWeights
        let score = weights.hrv * hrvComponent(hrv: hrv, baseline: hrvBaseline)
            + weights.restingHeartRate * restingHeartRateComponent(restingHeartRate: restingHeartRate, baseline: restingHeartRateBaseline)
            + weights.sleep * sleepComponent(sleepScore: sleepScore)
        return Int(score.rounded())
    }

    /// HRV's 0-100 sub-score. 58 at baseline.
    static func hrvComponent(hrv: Double, baseline: Double) -> Double {
        let ratio = baseline > 0 ? hrv / baseline : 1
        return clamp(58 + (ratio - 1) * 250)
    }

    /// Resting heart rate's 0-100 sub-score. 58 at baseline.
    static func restingHeartRateComponent(restingHeartRate: Double, baseline: Double) -> Double {
        clamp(58 - (restingHeartRate - baseline) * 8)
    }

    /// Sleep's 0-100 sub-score.
    static func sleepComponent(sleepScore: Int) -> Double {
        clamp((Double(sleepScore) - 50) * 2)
    }

    // MARK: - Strain

    /// Weight of one minute in each heart-rate zone (Edwards' training impulse).
    static func loadWeight(for zone: HeartRateZone) -> Double {
        Double(zone.rawValue)
    }

    /// Cardiovascular load: zone-weighted minutes.
    static func cardiovascularLoad(_ zones: [ZoneDuration]) -> Double {
        zones.reduce(0) { $0 + ($1.duration / 60) * loadWeight(for: $1.zone) }
    }

    /// Load at which strain reaches ~63 (1 − 1/e). Tuned so an easy day lands near 30 and a
    /// long, hard session near 75.
    static let strainLoadScale = 250.0

    /// Strain, 0-100. Saturating: going from 80 to 90 takes far more work than 20 to 30.
    static func strain(zones: [ZoneDuration]) -> Int {
        let load = cardiovascularLoad(zones)
        let score = 100 * (1 - exp(-load / strainLoadScale))
        return Int(clamp(score).rounded())
    }

    // MARK: - Sleep

    static let baseSleepNeed: TimeInterval = 7.75 * 3600

    /// How much sleep a night calls for.
    ///
    /// Starts from a base need, then adds up to 35 minutes for the previous day's strain above
    /// an easy day, and up to 40 minutes towards repaying accumulated sleep debt.
    static func sleepNeed(previousStrain: Int, sleepDebt: TimeInterval) -> TimeInterval {
        let strainExtra = max(0, Double(previousStrain) - 35) / 65 * 35 * 60
        let debtExtra = min(sleepDebt * 0.3, 40 * 60)
        return baseSleepNeed + strainExtra + debtExtra
    }

    /// Sleep performance, 0-100: time asleep as a share of need.
    static func sleepScore(timeAsleep: TimeInterval, need: TimeInterval) -> Int {
        guard need > 0 else { return 0 }
        return Int(clamp(timeAsleep / need * 100).rounded())
    }

    /// Bed and wake time consistency, 0-100, over a run of nights.
    ///
    /// Takes the standard deviation of bedtimes and of wake times (in minutes) and averages
    /// them; each minute of typical variation costs one point. Nil with fewer than two nights.
    static func sleepConsistency(_ nights: [SleepMetrics], calendar: Calendar) -> Int? {
        guard nights.count > 1 else { return nil }
        let bedtimes = nights.map { $0.minutesSinceEveningAnchor($0.bedtime, calendar: calendar) }
        let wakeTimes = nights.map { $0.minutesSinceEveningAnchor($0.wakeTime, calendar: calendar) }
        let variation = (Statistics.standardDeviation(bedtimes) + Statistics.standardDeviation(wakeTimes)) / 2
        return Int(clamp(100 - variation).rounded())
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}

extension SleepMetrics {
    /// 6 PM on the evening this night began: a stable origin for comparing clock times
    /// across nights, so 11:30 PM and 12:30 AM sit an hour apart rather than 23 hours.
    nonisolated func eveningAnchor(calendar: Calendar) -> Date {
        calendar.startOfDay(for: wakeTime).addingTimeInterval(-6 * 3600)
    }

    nonisolated func minutesSinceEveningAnchor(_ date: Date, calendar: Calendar) -> Double {
        date.timeIntervalSince(eveningAnchor(calendar: calendar)) / 60
    }
}
