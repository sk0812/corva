import Foundation
import Observation

/// User preferences. In memory only for now; move to `@AppStorage` or SwiftData when
/// persistence arrives.
@Observable
final class AppSettings {
    var temperatureUnit: TemperatureUnit
    var distanceUnit: DistanceUnit
    /// Calendar age, for bio age reference values.
    var age = 32
    var sex: BiologicalSex = .notSet
    /// Currency for new pact stakes. Existing pacts keep the currency they were made in.
    var currencyCode: String

    /// Defaults follow the region: Fahrenheit and miles for the US, metric elsewhere, and the
    /// region's currency.
    init(locale: Locale = .current) {
        let usesUSUnits = locale.measurementSystem == .us
        temperatureUnit = usesUSUnits ? .fahrenheit : .celsius
        distanceUnit = usesUSUnits ? .miles : .kilometers
        currencyCode = Self.defaultCurrencyCode(locale: locale)
    }

    var formatter: MetricFormatter {
        MetricFormatter(temperatureUnit: temperatureUnit, distanceUnit: distanceUnit)
    }

    var profile: Profile {
        Profile(age: age, sex: sex)
    }

    /// Currencies offered for stakes.
    nonisolated static let stakeCurrencies = ["GBP", "USD", "EUR"]

    nonisolated static func defaultCurrencyCode(locale: Locale = .current) -> String {
        let code = locale.currency?.identifier ?? "GBP"
        return stakeCurrencies.contains(code) ? code : "GBP"
    }
}
