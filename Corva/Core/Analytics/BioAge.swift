import Foundation

/// How old your body behaves, estimated from nine fitness, heart, activity and sleep markers.
///
/// Each marker compares your last 30 days with a reference value for your age and sex (or a
/// public-health guideline) and adds or removes years from your calendar age. Every marker is
/// capped so no single one dominates. The bio age is calendar age plus the sum.
///
/// The references and effect sizes are approximations of published population norms and
/// activity guidelines, chosen to be plausible and explainable. They have not been fitted to
/// outcome data, so the result is an estimate, not a medical measurement.
nonisolated enum BioAge {
    static let windowDays = 30

    nonisolated enum Group: String, CaseIterable, Sendable {
        case fitness = "Fitness"
        case heart = "Heart"
        case activity = "Activity"
        case sleep = "Sleep"
    }

    nonisolated enum MarkerKind: String, CaseIterable, Identifiable, Hashable, Sendable {
        case vo2Max
        case restingHeartRate
        case hrv
        case steps
        case moderateMinutes
        case vigorousMinutes
        case strengthSessions
        case sleepDuration
        case sleepConsistency

        var id: String { rawValue }

        var title: String {
            switch self {
            case .vo2Max: "VO2 max"
            case .restingHeartRate: "Resting heart rate"
            case .hrv: "HRV"
            case .steps: "Daily steps"
            case .moderateMinutes: "Moderate cardio"
            case .vigorousMinutes: "Vigorous cardio"
            case .strengthSessions: "Strength training"
            case .sleepDuration: "Sleep duration"
            case .sleepConsistency: "Sleep consistency"
            }
        }

        var group: Group {
            switch self {
            case .vo2Max, .moderateMinutes, .vigorousMinutes, .strengthSessions: .fitness
            case .restingHeartRate, .hrv: .heart
            case .steps: .activity
            case .sleepDuration, .sleepConsistency: .sleep
            }
        }

        /// Most years one marker can add or remove.
        var limit: ClosedRange<Double> {
            switch self {
            case .vo2Max: -4...4
            case .restingHeartRate, .hrv: -2.5...2.5
            case .steps: -1.5...2.5
            case .moderateMinutes: -1.2...1.2
            case .vigorousMinutes, .strengthSessions: -0.8...0.8
            case .sleepDuration: 0...2.5
            case .sleepConsistency: -0.6...1.5
            }
        }
    }

    nonisolated struct Marker: Identifiable, Hashable, Sendable {
        let kind: MarkerKind
        /// Your value over the window. Units: ml/kg/min, bpm, ms, steps a day, minutes a
        /// week, sessions a week, hours a night, consistency score.
        let value: Double
        /// Typical value for your age and sex, or the healthy range for sleep.
        let reference: ClosedRange<Double>
        /// Years added (positive) or taken off (negative).
        let years: Double

        var id: MarkerKind { kind }
    }

    nonisolated struct Estimate: Hashable, Sendable {
        /// The last day of the window.
        let date: Date
        let chronologicalAge: Double
        /// Ordered as `MarkerKind.allCases`.
        let markers: [Marker]

        var biologicalAge: Double { chronologicalAge + difference }
        /// Negative when your body behaves younger than your calendar age.
        var difference: Double { markers.reduce(0) { $0 + $1.years } }
    }

    /// Bio age from the last 30 of `days` (oldest first). Nil with fewer than 14 days.
    static func estimate(from days: [DailySummary], profile: Profile, calendar: Calendar = .current) -> Estimate? {
        let window = Array(days.suffix(windowDays))
        guard window.count >= 14, let last = window.last else { return nil }
        let age = Double(profile.age)
        let weeks = Double(window.count) / 7

        func minutes(in zones: Set<HeartRateZone>) -> Double {
            window.reduce(0) { total, day in
                total + day.strain.heartRateZones.filter { zones.contains($0.zone) }.reduce(0) { $0 + $1.duration / 60 }
            }
        }

        let vo2Max = Statistics.mean(window.map(\.vitals.vo2Max))
        let restingHeartRate = Statistics.mean(window.map(\.vitals.restingHeartRate))
        let hrv = Statistics.mean(window.map(\.vitals.hrv))
        let steps = Statistics.mean(window.map { Double($0.strain.steps) })
        let moderate = minutes(in: [.two, .three]) / weeks
        let vigorous = minutes(in: [.four, .five]) / weeks
        let strength = Double(window.reduce(0) { $0 + $1.strain.activities.filter { $0.kind == .strength }.count }) / weeks
        let sleepHours = Statistics.mean(window.map { $0.sleep.timeAsleep / 3600 })
        let consistency = Double(Scoring.sleepConsistency(window.map(\.sleep), calendar: calendar) ?? 80)

        // Population reference values for this age and sex.
        let vo2Reference = vo2MaxReference(age: age, sex: profile.sex)
        let restingReference = restingHeartRateReference(sex: profile.sex)
        let hrvReference = 92 * exp(-0.022 * age)

        let raw: [(MarkerKind, Double, ClosedRange<Double>, Double)] = [
            (.vo2Max, vo2Max, point(vo2Reference), -0.3 * (vo2Max - vo2Reference)),
            (.restingHeartRate, restingHeartRate, point(restingReference), 0.12 * (restingHeartRate - restingReference)),
            (.hrv, hrv, point(hrvReference), -3 * log(max(hrv, 1) / hrvReference)),
            (.steps, steps, point(7_500), -0.4 * (steps - 7_500) / 1_000),
            (.moderateMinutes, moderate, point(150), 1.2 * (1 - moderate / 150)),
            (.vigorousMinutes, vigorous, point(75), 0.8 * (1 - vigorous / 75)),
            (.strengthSessions, strength, point(2), 0.4 * (2 - strength)),
            (.sleepDuration, sleepHours, 7...9, sleepHours < 7 ? 0.9 * (7 - sleepHours) : max(0, 0.6 * (sleepHours - 9))),
            (.sleepConsistency, consistency, point(80), 0.04 * (80 - consistency)),
        ]

        return Estimate(
            date: last.date,
            chronologicalAge: age,
            markers: raw.map { kind, value, reference, years in
                Marker(kind: kind, value: value, reference: reference, years: clamp(years, kind.limit))
            }
        )
    }

    /// Bio age at the end of each week, each from the 30 days before it, oldest first.
    static func history(from days: [DailySummary], profile: Profile, calendar: Calendar = .current) -> [DatedValue] {
        var points: [DatedValue] = []
        var end = days.count
        while end >= windowDays {
            if let estimate = estimate(from: Array(days[(end - windowDays)..<end]), profile: profile, calendar: calendar) {
                points.append(DatedValue(date: estimate.date, value: estimate.biologicalAge))
            }
            end -= 7
        }
        return points.reversed()
    }

    // MARK: - References

    /// Average VO2 max declines about 0.4 ml/kg/min a year after 25.
    static func vo2MaxReference(age: Double, sex: BiologicalSex) -> Double {
        let atTwentyFive: Double = switch sex {
        case .male: 46
        case .female: 38
        case .notSet: 42
        }
        return atTwentyFive - 0.4 * max(age - 25, 0)
    }

    /// Adult resting heart rate averages in the mid-60s and barely changes with age.
    static func restingHeartRateReference(sex: BiologicalSex) -> Double {
        switch sex {
        case .male: 64
        case .female: 67
        case .notSet: 65.5
        }
    }

    private static func point(_ value: Double) -> ClosedRange<Double> { value...value }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
