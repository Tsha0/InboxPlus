#!/usr/bin/env swift

import AppKit
import CoreText

let fontURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
var fontError: Unmanaged<CFError>?
guard CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &fontError),
      let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [NSFontDescriptor],
      let bold = descriptors.first(where: { $0.postscriptName?.hasSuffix("_Bold") == true }),
      let headline = NSFont(descriptor: bold, size: 54),
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1400, pixelsHigh: 800,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not prepare the installer artwork")
}

let context = graphics.cgContext
bitmap.size = NSSize(width: 700, height: 400)
context.translateBy(x: 0, y: 800)
context.scaleBy(x: 2, y: -2)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

NSColor(white: 24 / 255, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 700, height: 400)).fill()
NSColor(white: 1, alpha: 0.12).setFill()
for x in stride(from: 12, to: 700, by: 24) {
    for y in stride(from: 12, to: 400, by: 24) {
        NSBezierPath(ovalIn: NSRect(x: Double(x) - 0.7, y: Double(y) - 0.7, width: 1.4, height: 1.4)).fill()
    }
}

func asterisk(x: CGFloat, y: CGFloat, size: CGFloat, angle: CGFloat, color: NSColor) {
    context.saveGState()
    context.translateBy(x: x, y: y)
    context.rotate(by: angle * .pi / 180)
    context.scaleBy(x: size / 100, y: size / 100)
    color.setFill()
    for _ in 0..<4 {
        NSBezierPath(roundedRect: NSRect(x: -8, y: -47, width: 16, height: 94), xRadius: 4, yRadius: 4).fill()
        context.rotate(by: .pi / 4)
    }
    context.restoreGState()
}

asterisk(x: 702, y: 392, size: 290, angle: 16, color: NSColor(white: 1, alpha: 0.035))
asterisk(x: 634, y: 59, size: 26, angle: 13, color: NSColor(srgbRed: 249 / 255, green: 211 / 255, blue: 229 / 255, alpha: 1))
asterisk(x: 51, y: 333, size: 16, angle: -12, color: NSColor(srgbRed: 216 / 255, green: 243 / 255, blue: 232 / 255, alpha: 1))

func text(_ string: String, y: CGFloat, font: NSFont, gray: CGFloat, kern: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: NSColor(white: gray / 255, alpha: 1), .kern: kern,
    ]
    let size = (string as NSString).size(withAttributes: attributes)
    (string as NSString).draw(at: NSPoint(x: (700 - size.width) / 2, y: y), withAttributes: attributes)
}

text("Inbox+", y: 39, font: headline, gray: 243, kern: -3)
text("Drag into Applications. Make yourself at home.", y: 111, font: .systemFont(ofSize: 13), gray: 188)
text("Then open Inbox+ from Applications.", y: 360, font: .systemFont(ofSize: 11), gray: 163)

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 320, y: 226))
arrow.curve(to: NSPoint(x: 378, y: 220), controlPoint1: NSPoint(x: 338, y: 215), controlPoint2: NSPoint(x: 354, y: 216))
arrow.move(to: NSPoint(x: 368, y: 212))
arrow.line(to: NSPoint(x: 380, y: 220))
arrow.line(to: NSPoint(x: 367, y: 226))
arrow.lineWidth = 1.6
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(white: 151 / 255, alpha: 1).setStroke()
arrow.stroke()

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the installer artwork")
}
try png.write(to: outputURL)
