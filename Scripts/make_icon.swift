#!/usr/bin/env swift
// Renders the DiskSage app icon — a brand-gradient squircle with a white
// multi-ring sunburst, matching the in-app logo. Writes the ten PNGs that
// make up a macOS .iconset into the directory passed as the first argument.
//
//   swift Scripts/make_icon.swift path/to/AppIcon.iconset
//
// Self-contained: only depends on AppKit. No assets, no network.

import AppKit

let brandStart = (r: 0.36, g: 0.42, b: 0.95) // matches Theme.brandStart
let brandEnd   = (r: 0.20, g: 0.80, b: 0.74) // matches Theme.brandEnd

func deg(_ d: Double) -> CGFloat { CGFloat(d * .pi / 180) }

/// One annulus (ring) wedge from a0→a1 at the given inner/outer radii.
func wedge(_ ctx: CGContext, cx: CGFloat, cy: CGFloat,
           rIn: CGFloat, rOut: CGFloat, a0: Double, a1: Double, white: CGFloat) {
    let c = CGPoint(x: cx, y: cy)
    let p = CGMutablePath()
    p.addArc(center: c, radius: rOut, startAngle: deg(a0), endAngle: deg(a1), clockwise: false)
    p.addArc(center: c, radius: rIn,  startAngle: deg(a1), endAngle: deg(a0), clockwise: true)
    p.closeSubpath()
    ctx.addPath(p)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: white))
    ctx.fillPath()
}

func renderPNG(pixels n: Int) -> Data {
    let s = CGFloat(n)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext

    // Squircle clip (Apple-ish corner radius).
    let radius = s * 0.2237
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()

    // Brand gradient, top-leading → bottom-trailing (CG y is up).
    let space = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: brandStart.r, green: brandStart.g, blue: brandStart.b, alpha: 1),
        CGColor(red: brandEnd.r,   green: brandEnd.g,   blue: brandEnd.b,   alpha: 1)
    ] as CFArray
    let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    let cx = s / 2, cy = s / 2
    let gap = 7.0 // angular gap between wedges, degrees

    // Outer ring — three wedges (the dominant "this folder is big" segments).
    let oIn = s * 0.205, oOut = s * 0.320
    wedge(ctx, cx: cx, cy: cy, rIn: oIn, rOut: oOut, a0: -90 + gap,      a1: 70 - gap,  white: 0.97)
    wedge(ctx, cx: cx, cy: cy, rIn: oIn, rOut: oOut, a0: 70 + gap,       a1: 190 - gap, white: 0.80)
    wedge(ctx, cx: cx, cy: cy, rIn: oIn, rOut: oOut, a0: 190 + gap,      a1: 270 - gap, white: 0.90)

    // Inner ring — two wedges.
    let iIn = s * 0.085, iOut = s * 0.180
    wedge(ctx, cx: cx, cy: cy, rIn: iIn, rOut: iOut, a0: -90 + gap,      a1: 120 - gap, white: 0.95)
    wedge(ctx, cx: cx, cy: cy, rIn: iIn, rOut: iOut, a0: 120 + gap,      a1: 270 - gap, white: 0.78)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make_icon.swift <output.iconset>\n".utf8))
    exit(2)
}
let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// (filename, pixel size) for a complete macOS iconset.
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),     ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),     ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),  ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),  ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),  ("icon_512x512@2x.png", 1024)
]
for (name, px) in variants {
    let data = renderPNG(pixels: px)
    try! data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
print("✓ wrote \(variants.count) icon variants to \(outDir)")
