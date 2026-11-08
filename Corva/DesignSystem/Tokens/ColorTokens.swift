import SwiftUI
import UIKit

/// Every colour in the app. Views never use literal colours.
///
/// Each token carries a light and a dark value and resolves against the current colour
/// scheme, so supporting a light theme later is a matter of tuning the light values and
/// removing the forced dark scheme in `CorvaApp`. Light values are placeholders until then.
enum CorvaColor {

    // MARK: Surfaces and text

    /// Near-black canvas behind everything.
    static let background = Color(light: 0xF4F4F6, dark: 0x060607)
    /// Opaque rows in system lists (Settings), one step up from the background.
    static let surface = Color(light: 0xFFFFFF, dark: 0x131315)
    static let textPrimary = Color(light: 0x0B0B0C, dark: 0xF5F5F7)
    static let textSecondary = Color(light: 0x0B0B0C, dark: 0xF5F5F7, opacity: 0.58)
    static let textTertiary = Color(light: 0x0B0B0C, dark: 0xF5F5F7, opacity: 0.36)
    static let separator = Color(light: 0x0B0B0C, dark: 0xFFFFFF, opacity: 0.10)
    /// Unfilled part of a score ring.
    static let ringTrack = Color(light: 0x0B0B0C, dark: 0xFFFFFF, opacity: 0.08)
    static let chartGrid = Color(light: 0x0B0B0C, dark: 0xFFFFFF, opacity: 0.08)
    /// The typical-range band behind vitals charts.
    static let chartBand = Color(light: 0x0B0B0C, dark: 0xFFFFFF, opacity: 0.07)
    /// Lines and marks for data with no metric colour of its own (vitals).
    static let neutralData = Color(light: 0x2C2C2E, dark: 0xE5E5EA)
    /// A vital outside its typical range.
    static let alert = Color(light: 0xC4720A, dark: 0xFF9F43)
    /// System tint: controls and the selected tab stay neutral.
    static let accent = Color(light: 0x0B0B0C, dark: 0xF5F5F7)

    // MARK: Metrics: one hue each

    static let recoveryHigh = Color(light: 0x14A35C, dark: 0x30D07A)
    static let recoveryModerate = Color(light: 0xC98A0B, dark: 0xF2B23E)
    static let recoveryLow = Color(light: 0xD63A36, dark: 0xF2564F)
    static let strain = Color(light: 0x1F6FE5, dark: 0x4B93FF)
    static let sleep = Color(light: 0x6A55E0, dark: 0x9B88FF)
    static let bioAge = Color(light: 0x0E9E92, dark: 0x3ED6C8)
    static let pact = Color(light: 0xC93F8C, dark: 0xF27BC0)

    // MARK: Outcomes

    /// Better than before, younger, goal met. Shares recovery's green so "good" reads the
    /// same everywhere.
    static let better = recoveryHigh
    /// Worse than before, older, goal missed.
    static let worse = recoveryLow
}

extension Color {
    /// A colour that resolves to `light` or `dark` hex values with the trait collection.
    init(light: UInt32, dark: UInt32, opacity: Double = 1) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: opacity
            )
        })
    }
}

#Preview("Colour tokens") {
    let swatches: [(String, Color)] = [
        ("background", CorvaColor.background),
        ("textPrimary", CorvaColor.textPrimary),
        ("textSecondary", CorvaColor.textSecondary),
        ("textTertiary", CorvaColor.textTertiary),
        ("neutralData", CorvaColor.neutralData),
        ("recoveryHigh", CorvaColor.recoveryHigh),
        ("recoveryModerate", CorvaColor.recoveryModerate),
        ("recoveryLow", CorvaColor.recoveryLow),
        ("strain", CorvaColor.strain),
        ("sleep", CorvaColor.sleep),
        ("bioAge", CorvaColor.bioAge),
        ("pact", CorvaColor.pact),
    ]
    return ScrollView {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(swatches, id: \.0) { name, color in
                HStack(spacing: Spacing.m) {
                    RoundedRectangle(cornerRadius: Radius.s)
                        .fill(color)
                        .overlay(RoundedRectangle(cornerRadius: Radius.s).strokeBorder(CorvaColor.separator))
                        .frame(width: 44, height: 44)
                    Text(name).textStyle(.body)
                }
            }
        }
        .padding(Spacing.screen)
    }
    .corvaPreview()
}
