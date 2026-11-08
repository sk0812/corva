import SwiftUI

/// 4-point spacing scale.
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48

    /// Horizontal margin for screen content.
    static let screen: CGFloat = 20
}

enum Radius {
    static let s: CGFloat = 12
    static let m: CGFloat = 20
    /// Full-width glass cards.
    static let l: CGFloat = 28
}

/// Fixed dimensions shared across screens.
enum Size {
    /// Height of the data-driven ambient glow at the top of a screen.
    static let ambientGlowHeight: CGFloat = 560
    static let sparklineHeight: CGFloat = 28
    static let chartHeight: CGFloat = 160
    static let compactChartHeight: CGFloat = 112
}
