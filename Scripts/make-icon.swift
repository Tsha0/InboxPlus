#!/usr/bin/env swift
//
// Builds Mimo's app icon from the mascot artwork.
//
//   swift Scripts/make-icon.swift [source.png] [output.icns]
//
// The source is a face-focused avatar on a square canvas. Place the complete head on a warm
// cream macOS plate, with a tighter face crop for the smallest Finder and menu-bar slots.

import AppKit
import Foundation

let arguments = CommandLine.arguments
let sourcePath = arguments.count > 1 ? arguments[1] : "docs/assets/mimo-mascot.png"
let outputPath = arguments.count > 2 ? arguments[2] : "Resources/AppIcon.icns"

// macOS icon geometry: a 1024 canvas whose artwork occupies the middle 824, leaving the margin
// the system relies on for its own shadow and alignment with other icons in the Dock.
let canvas: CGFloat = 1024
let plateInset: CGFloat = 100
let plateSize = canvas - plateInset * 2
let cornerRadius = plateSize * 0.2237

/// The region of the source holding the head, as fractions of the image so the crop survives the
/// artwork being re-exported at another resolution.
let cropOrigin = CGPoint(x: 0, y: 0)
let cropSize: CGFloat = 1.0

/// A tighter crop on the face alone, used for the smallest slots.
///
/// At 16pt the whole head leaves too few pixels for the eyes and smile. The small slots zoom
/// to the face so these features still read.
let smallCropOrigin = CGPoint(x: 0.25, y: 0.30)
let smallCropSize: CGFloat = 0.500
/// Slots at or below this pixel size use the tighter crop.
let smallSlotThreshold = 32

guard let sourceImage = NSImage(contentsOfFile: sourcePath),
      let sourceCG = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("error: could not read \(sourcePath)\n".utf8))
    exit(1)
}

let width = CGFloat(sourceCG.width)
let height = CGFloat(sourceCG.height)
let cropRect = CGRect(
    x: cropOrigin.x * width,
    y: cropOrigin.y * height,
    width: cropSize * width,
    height: cropSize * height
)
guard let head = sourceCG.cropping(to: cropRect) else {
    FileHandle.standardError.write(Data("error: crop fell outside the image\n".utf8))
    exit(1)
}

let smallCropRect = CGRect(
    x: smallCropOrigin.x * width,
    y: smallCropOrigin.y * height,
    width: smallCropSize * width,
    height: smallCropSize * height
)
let face = sourceCG.cropping(to: smallCropRect) ?? head

// The avatar has transparency; an explicit cream plate keeps it legible on any desktop.
let plateColour = CGColor(red: 0.98, green: 0.95, blue: 0.87, alpha: 1)

func renderPlate(artwork: CGImage) -> CGImage? {
guard let context = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    return nil
}

context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

let plateRect = CGRect(x: plateInset, y: plateInset, width: plateSize, height: plateSize)
let plate = CGPath(
    roundedRect: plateRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil
)

// A soft shadow under the plate, matching how macOS renders its own icons.
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -canvas * 0.012),
    blur: canvas * 0.028,
    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.22)
)
context.addPath(plate)
context.setFillColor(plateColour)
context.fillPath()
context.restoreGState()

// The head is clipped to the plate so nothing bleeds past the rounded corners, and inset slightly
// so it does not crowd the edges at small sizes.
context.saveGState()
context.addPath(plate)
context.clip()

let artInset = plateSize * 0.045
let artRect = plateRect.insetBy(dx: artInset, dy: artInset)
context.setBlendMode(.normal)
context.draw(artwork, in: artRect)
context.restoreGState()

// A hairline edge keeps the plate from dissolving into a light desktop background.
context.saveGState()
context.addPath(plate)
context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.06))
context.setLineWidth(canvas * 0.0025)
context.strokePath()
context.restoreGState()

return context.makeImage()
}

guard let master = renderPlate(artwork: head),
      let smallMaster = renderPlate(artwork: face) else {
    FileHandle.standardError.write(Data("error: could not render the icon\n".utf8))
    exit(1)
}

// MARK: - Iconset

let fileManager = FileManager.default
let workingDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("MimoIcon-\(UUID().uuidString)")
let iconset = workingDirectory.appendingPathComponent("AppIcon.iconset")
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

/// Every size macOS asks for. Omitting one makes the system scale a neighbour, which is what makes
/// an icon look soft in exactly one place.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for variant in variants {
    guard let scaled = CGContext(
        data: nil, width: variant.pixels, height: variant.pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { continue }
    scaled.interpolationQuality = .high
    scaled.clear(CGRect(x: 0, y: 0, width: variant.pixels, height: variant.pixels))
    let artwork = variant.pixels <= smallSlotThreshold ? smallMaster : master
    scaled.draw(artwork, in: CGRect(x: 0, y: 0, width: variant.pixels, height: variant.pixels))

    guard let image = scaled.makeImage() else { continue }
    let destinationURL = iconset.appendingPathComponent(variant.name)
    guard let destination = CGImageDestinationCreateWithURL(
        destinationURL as CFURL, "public.png" as CFString, 1, nil
    ) else { continue }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let outputURL = URL(fileURLWithPath: outputPath)
try? fileManager.createDirectory(
    at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()

// Keep the 1024 master beside the icns: it is what a website or a README needs, and regenerating
// it by hand later would drift from the icon actually shipped.
let previewURL = outputURL.deletingLastPathComponent().appendingPathComponent("AppIcon-1024.png")
if let destination = CGImageDestinationCreateWithURL(
    previewURL as CFURL, "public.png" as CFString, 1, nil
) {
    CGImageDestinationAddImage(destination, master, nil)
    CGImageDestinationFinalize(destination)
}

try? fileManager.removeItem(at: workingDirectory)

guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("error: iconutil failed\n".utf8))
    exit(1)
}
print("wrote \(outputURL.path) and \(previewURL.path)")
