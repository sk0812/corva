import Foundation

/// Turns domain values into display strings, honouring the user's unit preferences.
///
/// All numbers in the UI pass through here so precision and units stay consistent between
/// Today, the detail screens and Trends.
nonisolated struct MetricFormatter: Hashable, Sendable {
    var temperatureUnit: TemperatureUnit = .celsius
    var distanceUnit: DistanceUnit = .kilometers

    // MARK: - Metrics

    func value(_ value: Double, for metric: Metric) -> String {
        convert(value, for: metric)
            .formatted(.number.precision(.fractionLength(fractionDigits(for: metric))))
    }

    /// Empty for strain, which is a unitless 0-100 score.
    func unit(for metric: Metric) -> String {
        switch metric {
        case .recovery, .sleep, .bloodOxygen: "%"
        case .strain: ""
        case .hrv: "ms"
        case .restingHeartRate: "bpm"
        case .respiratoryRate: "br/min"
        case .skinTemperature: temperatureUnit.symbol
        }
    }

    func valueWithUnit(_ value: Double, for metric: Metric) -> String {
        let number = self.value(value, for: metric)
        let unit = unit(for: metric)
        switch unit {
        case "": return number
        case "%", temperatureUnit.symbol: return number + unit
        default: return "\(number) \(unit)"
        }
    }

    /// A difference between two values of `metric`, unsigned, with its direction separate.
    func delta(_ delta: Double, for metric: Metric) -> FormattedDelta {
        let digits = fractionDigits(for: metric)
        let scale = pow(10, Double(digits))
        let shown = (convertDelta(delta, for: metric) * scale).rounded() / scale
        let direction: TrendDirection = shown > 0 ? .up : (shown < 0 ? .down : .flat)
        let text = abs(shown).formatted(.number.precision(.fractionLength(digits)))
        return FormattedDelta(text: text, direction: direction)
    }

    /// Precision that matches what the sensor can meaningfully resolve.
    func fractionDigits(for metric: Metric) -> Int {
        switch metric {
        case .respiratoryRate, .skinTemperature, .bloodOxygen: 1
        default: 0
        }
    }

    /// Converts from storage units (Celsius) into the preferred display unit.
    func convert(_ value: Double, for metric: Metric) -> Double {
        guard metric == .skinTemperature, temperatureUnit == .fahrenheit else { return value }
        return value * 9 / 5 + 32
    }

    func convertDelta(_ delta: Double, for metric: Metric) -> Double {
        guard metric == .skinTemperature, temperatureUnit == .fahrenheit else { return delta }
        return delta * 9 / 5
    }

    // MARK: - Other quantities

    /// "7h 42m"
    func duration(_ interval: TimeInterval) -> String {
        Duration.seconds(interval.rounded())
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    /// A difference between two durations, rounded to the minute: "12m" up or down.
    func durationDelta(_ delta: TimeInterval) -> FormattedDelta {
        let minutes = (delta / 60).rounded()
        let direction: TrendDirection = minutes > 0 ? .up : (minutes < 0 ? .down : .flat)
        return FormattedDelta(text: duration(abs(minutes) * 60), direction: direction)
    }

    /// "11:04 PM", in the user's locale.
    func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "8.4 km"
    func distance(_ meters: Double) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        let converted = measurement.converted(to: distanceUnit == .kilometers ? .kilometers : .miles)
        let number = converted.value.formatted(.number.precision(.fractionLength(1)))
        return "\(number) \(distanceUnit.symbol)"
    }

    /// "8,412"
    func steps(_ count: Int) -> String {
        count.formatted(.number)
    }

    /// "1.12"
    func ratio(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    /// "612 kcal"
    func energy(_ kilocalories: Double) -> String {
        "\(kilocalories.formatted(.number.precision(.fractionLength(0)))) kcal"
    }

    /// "93%", from a 0-1 fraction.
    func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    /// "Sunday, 8 November" style, in the user's locale.
    func dayTitle(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// A formatted, unsigned difference plus its direction, ready for `DeltaLabel`.
nonisolated struct FormattedDelta: Hashable, Sendable {
    let text: String
    let direction: TrendDirection
}
