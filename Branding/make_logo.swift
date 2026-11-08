// Renders Corva's app icon (standard, dark and tinted) and a wordmark lockup.
//
//   swift Branding/make_logo.swift <app-icon-set-dir> <branding-dir>
//
// The mark is one open ring, a "C", carrying the app's three metric hues in the order a day
// runs: sleep purple, strain blue, recovery green. Colours match CorvaColor's dark values.

import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
let iconDirectory = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : ".")
let brandingDirectory = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : ".")

// MARK: - Palette

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let sleepPurple = color(0x9B88FF)
let strainBlue = color(0x4B93FF)
let recoveryGreen = color(0x30D07A)
let background = color(0x060607)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Geometry

/// Half the opening of the C, in radians. The gap faces right.
let gapHalfAngle = CGFloat.pi / 4

func context(size: CGSize, opaque: Bool) -> CGContext {
    CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: sRGB,
        bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue
    )!
}

/// The C as a filled outline: a 270° arc with round caps.
func markPath(center: CGPoint, radius: CGFloat, lineWidth: CGFloat) -> CGPath {
    let arc = CGMutablePath()
    arc.addArc(center: center, radius: radius, startAngle: gapHalfAngle, endAngle: 2 * .pi - gapHalfAngle, clockwise: false)
    return arc.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

/// Fills the C with colour that runs the length of the arc, from the top opening to the bottom
/// one, drawn as thin wedges clipped to the C. Each round cap keeps its own end's colour.
func fillMark(in ctx: CGContext, center: CGPoint, radius: CGFloat, lineWidth: CGFloat, colors: [CGColor]) {
    let stops = colors.map { $0.components ?? [1, 1, 1, 1] }
    func mix(_ t: CGFloat) -> CGColor {
        let scaled = min(max(t, 0), 1) * CGFloat(stops.count - 1)
        let index = min(Int(scaled), stops.count - 2)
        let f = scaled - CGFloat(index)
        let a = stops[index], b = stops[index + 1]
        return CGColor(srgbRed: a[0] + (b[0] - a[0]) * f, green: a[1] + (b[1] - a[1]) * f,
                       blue: a[2] + (b[2] - a[2]) * f, alpha: a[3] + (b[3] - a[3]) * f)
    }
    let arcLength = 2 * CGFloat.pi - 2 * gapHalfAngle
    let steps = 720
    ctx.saveGState()
    ctx.addPath(markPath(center: center, radius: radius, lineWidth: lineWidth))
    ctx.clip()
    // The clip keeps its smooth edge; wedges are drawn aliased so their seams don't show.
    ctx.setShouldAntialias(false)
    for step in 0..<steps {
        let a0 = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let a1 = CGFloat(step + 1) / CGFloat(steps) * 2 * .pi + 0.01
        var along = a0 - gapHalfAngle
        if along < 0 { along += 2 * .pi }
        let t: CGFloat = along <= arcLength ? along / arcLength : (along - arcLength < gapHalfAngle ? 1 : 0)
        let wedge = CGMutablePath()
        wedge.move(to: center)
        wedge.addArc(center: center, radius: radius + lineWidth, startAngle: a0, endAngle: a1, clockwise: false)
        wedge.closeSubpath()
        ctx.addPath(wedge)
        ctx.setFillColor(mix(t))
        ctx.fillPath()
    }
    ctx.restoreGState()
}

/// Draws `draw` into a separate layer, blurs it, and composites it underneath: a soft glow.
func glow(in ctx: CGContext, size: CGSize, radius: CGFloat, alpha: CGFloat, draw: (CGContext) -> Void) {
    let layer = context(size: size, opaque: false)
    draw(layer)
    guard let image = layer.makeImage() else { return }
    let input = CIImage(cgImage: image)
    let blurred = input.clampedToExtent()
        .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
        .cropped(to: input.extent)
    let ciContext = CIContext(options: [.workingColorSpace: sRGB])
    guard let output = ciContext.createCGImage(blurred, from: input.extent) else { return }
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.draw(output, in: CGRect(origin: .zero, size: size))
    ctx.restoreGState()
}

// MARK: - Icon

enum Variant {
    /// Opaque near-black tile: the icon everywhere by default.
    case standard
    /// Transparent: iOS supplies the dark backdrop in dark mode.
    case dark
    /// Greyscale on transparent: iOS tints it in tinted mode.
    case tinted
}

func drawIcon(_ variant: Variant, in ctx: CGContext, size: CGFloat) {
    let canvas = CGSize(width: size, height: size)
    let center = CGPoint(x: size / 2, y: size / 2)
    let radius = size * 0.285
    let lineWidth = size * 0.135
    let colors = variant == .tinted
        ? [color(0xFFFFFF, 0.55), color(0xFFFFFF, 0.8), color(0xFFFFFF)]
        : [sleepPurple, strainBlue, recoveryGreen]

    if variant == .standard {
        ctx.setFillColor(background)
        ctx.fill(CGRect(origin: .zero, size: canvas))
        // Light from above in the strain hue, and a little sleep purple from below, so the
        // tile isn't flat black.
        let top = CGGradient(colorsSpace: sRGB, colors: [color(0x4B93FF, 0.30), color(0x4B93FF, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(top, startCenter: CGPoint(x: size * 0.5, y: size * 1.05), startRadius: 0,
                               endCenter: CGPoint(x: size * 0.5, y: size * 1.05), endRadius: size * 0.85, options: [])
        let bottom = CGGradient(colorsSpace: sRGB, colors: [color(0x9B88FF, 0.16), color(0x9B88FF, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(bottom, startCenter: CGPoint(x: size * 0.15, y: -size * 0.05), startRadius: 0,
                               endCenter: CGPoint(x: size * 0.15, y: -size * 0.05), endRadius: size * 0.7, options: [])
    }

    // The unfilled part of the ring, like the track behind every score ring in the app.
    if variant != .tinted {
        ctx.setStrokeColor(color(0xFFFFFF, 0.07))
        ctx.setLineWidth(lineWidth)
        ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    glow(in: ctx, size: canvas, radius: size * 0.045, alpha: variant == .tinted ? 0.35 : 0.85) { layer in
        fillMark(in: layer, center: center, radius: radius, lineWidth: lineWidth, colors: colors)
    }
    fillMark(in: ctx, center: center, radius: radius, lineWidth: lineWidth, colors: colors)
}

func writePNG(_ ctx: CGContext, to url: URL) {
    let image = ctx.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("Wrote \(url.path)")
}

let iconSize: CGFloat = 1024
for (variant, name, opaque) in [(Variant.standard, "AppIcon.png", true), (.dark, "AppIcon-Dark.png", false), (.tinted, "AppIcon-Tinted.png", false)] {
    let ctx = context(size: CGSize(width: iconSize, height: iconSize), opaque: opaque)
    drawIcon(variant, in: ctx, size: iconSize)
    writePNG(ctx, to: iconDirectory.appendingPathComponent(name))
}

// MARK: - Wordmark lockup

/// The icon on a rounded tile beside "Corva" in SF Pro Rounded, on the app's background.
func drawLockup() {
    let canvas = CGSize(width: 2400, height: 900)
    let ctx = context(size: canvas, opaque: true)
    ctx.setFillColor(background)
    ctx.fill(CGRect(origin: .zero, size: canvas))

    let tile: CGFloat = 520
    let tileRect = CGRect(x: 190, y: (canvas.height - tile) / 2, width: tile, height: tile)
    let iconContext = context(size: CGSize(width: tile, height: tile), opaque: false)
    drawIcon(.standard, in: iconContext, size: tile)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: tileRect, cornerWidth: tile * 0.2237, cornerHeight: tile * 0.2237, transform: nil))
    ctx.clip()
    ctx.draw(iconContext.makeImage()!, in: tileRect)
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: tileRect.insetBy(dx: 1, dy: 1), cornerWidth: tile * 0.2237, cornerHeight: tile * 0.2237, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.12))
    ctx.setLineWidth(2)
    ctx.strokePath()

    let base = NSFont.systemFont(ofSize: 300, weight: .semibold)
    let rounded = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 300) } ?? base
    let text = NSAttributedString(string: "Corva", attributes: [
        .font: rounded,
        .foregroundColor: NSColor(srgbRed: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255, alpha: 1),
        .kern: -4,
    ])
    let textSize = text.size()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    text.draw(at: CGPoint(x: tileRect.maxX + 110, y: (canvas.height - textSize.height) / 2 + 12))
    NSGraphicsContext.restoreGraphicsState()

    writePNG(ctx, to: brandingDirectory.appendingPathComponent("Corva-lockup.png"))
}

drawLockup()
