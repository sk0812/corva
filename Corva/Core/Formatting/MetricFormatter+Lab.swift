import Foundation

// Formatting for bio age, day comparisons, experiments and pacts.
nonisolated extension MetricFormatter {

    // MARK: - Signs

    /// "+3.1" or "−3.1", with a true minus sign.
    func signed(_ value: Double, fractionDigits: Int = 1) -> String {
        let scale = pow(10, Double(fractionDigits))
        let rounded = (value * scale).rounded() / scale
        let magnitude = abs(rounded).formatted(.number.precision(.fractionLength(fractionDigits)))
        if rounded > 0 { return "+" + magnitude }
        if rounded < 0 { return "−" + magnitude }
        return magnitude
    }

    /// A signed change in a metric's display unit: "−7.7 ms", "+3%".
    ///
    /// With `keepingNonZero`, a small non-zero value gets an extra decimal rather than
    /// rounding to 0, so an interval that excludes zero never appears to touch it.
    func signedChange(_ delta: Double, for metric: Metric, keepingNonZero: Bool = false) -> String {
        let converted = convertDelta(delta, for: metric)
        var digits = fractionDigits(for: metric)
        if keepingNonZero, converted != 0, abs(converted) < 0.5 / pow(10, Double(digits)) {
            digits += 1
        }
        let number = signed(converted, fractionDigits: digits)
        let unit = unit(for: metric)
        switch unit {
        case "": return number
        case "%", temperatureUnit.symbol: return number + unit
        default: return "\(number) \(unit)"
        }
    }

    // MARK: - Clock times

    /// A clock time stored as minutes after 6 PM: 300 → "11:00 PM".
    func clockTime(minutesAfterSixPM minutes: Double, calendar: Calendar = .current) -> String {
        let anchor = calendar.startOfDay(for: .now).addingTimeInterval(-6 * 3600)
        return clockTime(anchor.addingTimeInterval((minutes * 60).rounded()))
    }

    // MARK: - Bio age

    /// "27.5"
    func age(_ years: Double) -> String {
        years.formatted(.number.precision(.fractionLength(1)))
    }

    /// Value and unit for a bio age marker.
    func bioMarker(_ value: Double, kind: BioAge.MarkerKind) -> (value: String, unit: String) {
        switch kind {
        case .vo2Max: (value.formatted(.number.precision(.fractionLength(1))), "ml/kg/min")
        case .restingHeartRate: (value.formatted(.number.precision(.fractionLength(0))), "bpm")
        case .hrv: (value.formatted(.number.precision(.fractionLength(0))), "ms")
        case .steps: (steps(Int(value.rounded())), "a day")
        case .moderateMinutes, .vigorousMinutes: (value.formatted(.number.precision(.fractionLength(0))), "min a week")
        case .strengthSessions: (value.formatted(.number.precision(.fractionLength(1))), "a week")
        case .sleepDuration: (duration(value * 3600), "a night")
        case .sleepConsistency: (value.formatted(.number.precision(.fractionLength(0))), "/ 100")
        }
    }

    func bioMarkerReference(_ marker: BioAge.Marker) -> String {
        let low = bioMarker(marker.reference.lowerBound, kind: marker.kind)
        if marker.reference.lowerBound == marker.reference.upperBound {
            return "\(low.value) \(low.unit)"
        }
        let high = bioMarker(marker.reference.upperBound, kind: marker.kind)
        return "\(low.value)–\(high.value) \(high.unit)"
    }

    // MARK: - Day comparison

    func factor(_ value: Double, kind: DayContrast.FactorKind) -> String {
        switch kind {
        case .priorStrain: value.formatted(.number.precision(.fractionLength(0)))
        case .priorHardMinutes: "\(value.formatted(.number.precision(.fractionLength(0)))) min"
        case .priorSteps: steps(Int(value.rounded()))
        case .bedtime, .wakeTime: clockTime(minutesAfterSixPM: value)
        case .timeInBed, .timeAsleep, .restorativeSleep: duration(value)
        case .awakenings: value.formatted(.number.precision(.fractionLength(1)))
        case .weekend, .unwell, .tag: percent(value)
        }
    }

    // MARK: - Pacts

    /// "£5"
    func money(_ amount: Int, currencyCode: String) -> String {
        amount.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))
    }

    func pactValue(_ value: Double, goal: Pact.Goal) -> String {
        switch goal {
        case .steps: steps(Int(value.rounded()))
        case .sleep, .exercise: duration(value)
        case .strain: value.formatted(.number.precision(.fractionLength(0)))
        case .bedtime: clockTime(minutesAfterSixPM: value)
        }
    }

    /// The goal as a phrase: "10,000 steps a day", "In bed by 10:30 PM".
    func pactGoal(_ goal: Pact.Goal, target: Double) -> String {
        switch goal {
        case .steps: "\(pactValue(target, goal: goal)) steps a day"
        case .sleep: "\(pactValue(target, goal: goal)) asleep a night"
        case .exercise: "\(pactValue(target, goal: goal)) exercise a day"
        case .strain: "Strain \(pactValue(target, goal: goal)) a day"
        case .bedtime: "In bed by \(pactValue(target, goal: goal))"
        }
    }

    /// The goal as an instruction: "Walk 10,000 steps", "Be in bed by 10:30 PM".
    func pactCommitment(_ goal: Pact.Goal, target: Double) -> String {
        let value = pactValue(target, goal: goal)
        return switch goal {
        case .steps: "Walk \(value) steps"
        case .sleep: "Sleep \(value)"
        case .exercise: "Exercise for \(value)"
        case .strain: "Reach strain \(value)"
        case .bedtime: "Be in bed by \(value)"
        }
    }

    /// "Day", or "Night" for sleep goals.
    func pactDayNoun(_ goal: Pact.Goal) -> String {
        goal.accumulatesDuringDay ? "day" : "night"
    }
}
