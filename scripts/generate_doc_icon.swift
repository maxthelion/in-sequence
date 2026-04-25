#!/usr/bin/env swift

import AppKit
import Foundation

enum IconError: Error {
    case invalidArguments
    case couldNotEncodePNG
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    throw IconError.invalidArguments
}

let outputPath = arguments[1]
let size = CGFloat((arguments.count >= 3 ? Double(arguments[2]) : 1024) ?? 1024)
let canvasWidth: CGFloat = 881
let canvasHeight: CGFloat = 881

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) ?? {
    fatalError("Unable to allocate bitmap image rep")
}()

guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create graphics context")
}

func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
    let scaledX = (x / canvasWidth) * size
    let scaledY = size - ((y / canvasHeight) * size)
    return NSPoint(x: scaledX, y: scaledY)
}

func fillPolygon(_ points: [NSPoint], color: NSColor) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: first)
    for point in points.dropFirst() {
        path.line(to: point)
    }
    path.close()
    color.setFill()
    path.fill()
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

NSColor.black.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let accent = NSColor(calibratedRed: 0.98, green: 0.32, blue: 0.41, alpha: 1.0)

fillPolygon(
    [
        point(23, 23),
        point(131, 23),
        point(23, 129),
    ],
    color: accent
)

fillPolygon(
    [
        point(23, 234),
        point(241, 23),
        point(384, 23),
    ],
    color: accent
)

fillPolygon(
    [
        point(23, 340),
        point(23, 656),
        point(860, 656),
        point(860, 23),
        point(383, 23),
    ],
    color: accent
)

let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .right

let font = NSFont(name: "Helvetica Neue", size: size * 0.13) ?? NSFont.systemFont(ofSize: size * 0.13, weight: .regular)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: accent,
    .paragraphStyle: paragraphStyle,
    .kern: size * 0.002,
]

let text = NSAttributedString(string: "NSEQ", attributes: attributes)
let textRect = NSRect(
    x: size * 0.52,
    y: size * 0.03,
    width: size * 0.42,
    height: size * 0.18
)
text.draw(in: textRect)

NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    throw IconError.couldNotEncodePNG
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: outputURL)
