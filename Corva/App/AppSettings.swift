import Foundation
import Observation
import SwiftUI

/// User preferences. In memory only for now; move to `@AppStorage` or SwiftData when
/// persistence arrives.
@Observable
final class AppSettings {
    var appearance: Appearance = .system
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

    /// The settings that sync to the account, for change detection.
    var syncedValues: [String] {
        [String(age), sex.rawValue, currencyCode, appearance.rawValue, temperatureUnit.rawValue, distanceUnit.rawValue]
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        /// Nil follows the system setting.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    /// Currencies offered for stakes.
    nonisolated static let stakeCurrencies = ["GBP", "USD", "EUR"]

    nonisolated static func defaultCurrencyCode(locale: Locale = .current) -> String {
        let code = locale.currency?.identifier ?? "GBP"
        return stakeCurrencies.contains(code) ? code : "GBP"
    }
}
