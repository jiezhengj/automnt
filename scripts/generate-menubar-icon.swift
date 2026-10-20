#!/usr/bin/env swift
// Generates the template menu-bar mark from the app icon's infinity loop.
// The blue tile and folder are dropped: at 18 pt only the connected loop survives.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let dir = root.appendingPathComponent("apps/Automnt/Resources/Assets.xcassets/MenuBarIcon.imageset")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

func render(pixels: Int) -> Data? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.scaleBy(x: CGFloat(pixels) / 18.0, y: CGFloat(pixels) / 18.0)
    // Monochrome template: a rounded tile with the loop knocked out.
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 1, y: 1, width: 16, height: 16),
                       cornerWidth: 4, cornerHeight: 4, transform: nil))
    ctx.fillPath()
    let s = 10.5 / 338.0
    let cx: CGFloat = 9, cy: CGFloat = 9
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: cx + (x - 512) * s, y: cy - (y - 568) * s)
    }
    let loop = CGMutablePath()
    loop.move(to: p(512, 565))
    loop.addCurve(to: p(414, 499), control1: p(480, 524), control2: p(450, 499))
    loop.addCurve(to: p(414, 637), control1: p(371, 499), control2: p(371, 637))
    loop.addCurve(to: p(512, 565), control1: p(453, 637), control2: p(478, 608))
    loop.addCurve(to: p(611, 499), control1: p(546, 523), control2: p(573, 499))
    loop.addCurve(to: p(611, 637), control1: p(653, 499), control2: p(653, 637))
    loop.addCurve(to: p(512, 565), control1: p(570, 637), control2: p(544, 609))
    loop.closeSubpath()
    ctx.setBlendMode(.clear)
    ctx.setLineWidth(1.9)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(loop)
    ctx.strokePath()
    ctx.setBlendMode(.normal)
    guard let image = ctx.makeImage() else { return nil }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}

for (scale, pixels) in [(1, 18), (2, 36), (3, 54)] {
    guard let data = render(pixels: pixels) else { fatalError("render failed") }
    try data.write(to: dir.appendingPathComponent("menubar-\(pixels).png"))
    _ = scale
}
let contents: [String: Any] = [
    "images": [
        ["filename": "menubar-18.png", "idiom": "mac", "scale": "1x"],
        ["filename": "menubar-36.png", "idiom": "mac", "scale": "2x"],
        ["filename": "menubar-54.png", "idiom": "mac", "scale": "3x"]
    ],
    "info": ["author": "xcode", "version": 1],
    "properties": ["template-rendering-intent": "template"]
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: dir.appendingPathComponent("Contents.json"))
print("wrote \(dir.path)")
