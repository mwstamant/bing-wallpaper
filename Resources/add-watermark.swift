#!/usr/bin/swift
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("Usage: add-watermark <image-path> <title> [description] [size]\n", stderr)
    exit(1)
}

let imagePath  = args[1]
let title      = args[2]
let description = args.count >= 4 ? args[3] : nil
let sizePreset  = args.count >= 5 ? args[4].lowercased() : "medium"

// Size presets: scale factor relative to image height
let sizeScale: CGFloat
switch sizePreset {
case "small": sizeScale = 0.010
case "large": sizeScale = 0.018
case "xl":    sizeScale = 0.024
default:      sizeScale = 0.014 // medium
}

guard let image = NSImage(contentsOfFile: imagePath) else {
    fputs("Failed to load image: \(imagePath)\n", stderr)
    exit(1)
}

let size = image.size
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Failed to create bitmap rep\n", stderr)
    exit(1)
}

NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(origin: .zero, size: size))

let titleSize: CGFloat = max(size.height * sizeScale, 11)
let descSize:  CGFloat = max(titleSize * 0.78, 9)
let padding:   CGFloat = titleSize * 0.65
let lineGap:   CGFloat = titleSize * 0.25

// Account for "Fill Screen" cropping on non-16:9 displays (e.g. MacBook 16:10).
// macOS scales the image so height fills the screen, cropping equal amounts from
// left and right. Offset the watermark X by that crop amount so it stays visible.
let screenSize = NSScreen.main?.frame.size ?? size
let fillScale  = max(screenSize.width / size.width, screenSize.height / size.height)
let visibleW   = screenSize.width / fillScale
let cropX      = max((size.width - visibleW) / 2, 0)

let marginX: CGFloat = cropX + titleSize * 0.7
let marginY: CGFloat = titleSize * 0.7

// Text shadow for contrast against any background image
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
shadow.shadowBlurRadius = 3
shadow.shadowOffset = NSSize(width: 0, height: -1)

let titleAttrs: [NSAttributedString.Key: Any] = [
    .font:            NSFont.systemFont(ofSize: titleSize, weight: .semibold),
    .foregroundColor: NSColor.white,
    .shadow:          shadow
]
let descAttrs: [NSAttributedString.Key: Any] = [
    .font:            NSFont.systemFont(ofSize: descSize, weight: .regular),
    .foregroundColor: NSColor.white.withAlphaComponent(0.90),
    .shadow:          shadow
]

let titleStr = NSAttributedString(string: title, attributes: titleAttrs)
let descStr  = description.map { NSAttributedString(string: $0, attributes: descAttrs) }

let titleTextSize = titleStr.size()
let descTextSize  = descStr?.size() ?? .zero

let contentWidth  = max(titleTextSize.width, descTextSize.width)
let contentHeight = titleTextSize.height
    + (descStr != nil ? lineGap + descTextSize.height : 0)

let bgRect = NSRect(
    x: marginX,
    y: marginY - titleSize * 0.4,
    width:  contentWidth  + padding * 2,
    height: contentHeight + padding * 1.4
)

// Pill background — increased opacity for legibility on bright images
let pill = NSBezierPath(roundedRect: bgRect, xRadius: bgRect.height / 3, yRadius: bgRect.height / 3)
NSColor.black.withAlphaComponent(0.55).setFill()
pill.fill()

// Draw title at top, description below
let innerY = bgRect.minY + padding * 0.7
let titleY = innerY + (descStr != nil ? descTextSize.height + lineGap : 0)

titleStr.draw(at: NSPoint(x: bgRect.minX + padding, y: titleY))
descStr?.draw(at:  NSPoint(x: bgRect.minX + padding, y: innerY))

NSGraphicsContext.current = nil

guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(value: 0.92)]) else {
    fputs("Failed to encode JPEG\n", stderr)
    exit(1)
}

do {
    try data.write(to: URL(fileURLWithPath: imagePath))
} catch {
    fputs("Failed to write file: \(error)\n", stderr)
    exit(1)
}
