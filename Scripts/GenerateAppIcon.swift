#!/usr/bin/env swift
import AppKit
import Foundation

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

func renderIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let margin = s * 0.06
    let corner = s * 0.22
    let rect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let colors = [
        CGColor(srgbRed: 0.28, green: 0.20, blue: 0.10, alpha: 1),
        CGColor(srgbRed: 0.10, green: 0.08, blue: 0.05, alpha: 1),
        CGColor(srgbRed: 0.04, green: 0.03, blue: 0.02, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.52, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    if let highlight = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(srgbRed: 1, green: 0.95, blue: 0.80, alpha: 0.16),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            highlight,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.midY),
            options: []
        )
    }

    drawGlyph(in: ctx, size: s, bounds: rect)
    ctx.restoreGState()

    ctx.setStrokeColor(CGColor(srgbRed: 0.93, green: 0.75, blue: 0.34, alpha: 0.55))
    ctx.setLineWidth(max(1.0, s * 0.012))
    ctx.addPath(path)
    ctx.strokePath()

    return ctx.makeImage()
}

func drawGlyph(in ctx: CGContext, size s: CGFloat, bounds rect: CGRect) {
    let brass = CGColor(srgbRed: 0.93, green: 0.75, blue: 0.34, alpha: 1)
    let brassDark = CGColor(srgbRed: 0.62, green: 0.44, blue: 0.16, alpha: 1)
    let ink = CGColor(srgbRed: 0.06, green: 0.05, blue: 0.03, alpha: 1)

    let bowCX = rect.minX + rect.width * 0.36
    let bowCY = rect.midY + s * 0.015
    let bowR = min(rect.width, rect.height) * (s < 32 ? 0.24 : 0.20)
    let holeR = bowR * 0.42

    ctx.setFillColor(brass)
    ctx.fillEllipse(in: CGRect(x: bowCX - bowR, y: bowCY - bowR, width: bowR * 2, height: bowR * 2))
    ctx.setStrokeColor(brassDark)
    ctx.setLineWidth(max(0.6, s * 0.018))
    ctx.strokeEllipse(in: CGRect(x: bowCX - bowR, y: bowCY - bowR, width: bowR * 2, height: bowR * 2))

    ctx.setFillColor(ink)
    ctx.fillEllipse(in: CGRect(x: bowCX - holeR, y: bowCY - holeR, width: holeR * 2, height: holeR * 2))

    let shaftH = max(2.0, s * 0.075)
    let shaftLeft = bowCX + bowR * 0.55
    let shaftRight = rect.maxX - rect.width * 0.16
    let shaftRect = CGRect(x: shaftLeft, y: bowCY - shaftH / 2, width: shaftRight - shaftLeft, height: shaftH)
    ctx.setFillColor(brass)
    ctx.addPath(CGPath(
        roundedRect: shaftRect,
        cornerWidth: shaftH / 2,
        cornerHeight: shaftH / 2,
        transform: nil
    ))
    ctx.fillPath()

    if s >= 24 {
        let bitW = max(2.0, s * 0.055)
        let gap = max(1.0, s * 0.025)
        let tall = s * 0.16
        let short = s * 0.10
        let startX = shaftRight - bitW * 2 - gap - s * 0.01
        let bits: [(CGFloat, CGFloat)] = [(tall, startX), (short, startX + bitW + gap)]
        for (height, x) in bits {
            let tooth = CGRect(
                x: x,
                y: bowCY - shaftH / 2 - height + shaftH * 0.15,
                width: bitW,
                height: height
            )
            ctx.setFillColor(brass)
            ctx.addPath(CGPath(
                roundedRect: tooth,
                cornerWidth: max(0.6, bitW * 0.25),
                cornerHeight: max(0.6, bitW * 0.25),
                transform: nil
            ))
            ctx.fillPath()
        }
    }
}

func pngData(_ image: CGImage) -> Data? {
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets")
let iconset = assets.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for item in sizes {
    guard let cg = renderIcon(size: item.px), let png = pngData(cg) else {
        fputs("Failed to render \(item.name)\n", stderr)
        exit(1)
    }
    try png.write(to: iconset.appendingPathComponent("\(item.name).png"))
    print("Wrote \(item.name).png")
}

if let master = renderIcon(size: 1024), let png = pngData(master) {
    try png.write(to: assets.appendingPathComponent("AppIcon-1024.png"))
}

let icns = assets.appendingPathComponent("AppIcon.icns")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try proc.run()
proc.waitUntilExit()
if proc.terminationStatus != 0 {
    fputs("iconutil failed\n", stderr)
    exit(1)
}
print("Created \(icns.path)")
