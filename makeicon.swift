#!/usr/bin/swift
import AppKit
import CoreGraphics

// ── Design constants (at 1000×1000 canvas) ──────────────────────────────────
// M occupies x=[100, 560]  D occupies x=[470, 920]  Shared vertical x=[470,560]
// Stroke width 90 (9% of canvas) — converted to filled path via copy(strokingWith:)

func mdFilledPath(s: CGFloat) -> CGPath {
    let k = s / 1000       // scale factor

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x*k, y: y*k) }

    let strokeW = s * 0.093
    let lb: CGFloat = 110   // letter bottom (canvas units)
    let lt: CGFloat = 890   // letter top
    let vm: CGFloat = 390   // V apex height — lower = deeper V

    // Centre-line paths for every stroke of M and D
    let lines = CGMutablePath()

    // M — left vertical
    lines.move(to: p(145, lt));  lines.addLine(to: p(145, lb))
    // M — left diagonal  (top-left → V apex)
    lines.move(to: p(145, lt));  lines.addLine(to: p(345, vm))
    // M — right diagonal (V apex → top of shared vertical)
    lines.move(to: p(345, vm));  lines.addLine(to: p(515, lt))
    // Shared vertical  (right of M = left of D)
    lines.move(to: p(515, lt));  lines.addLine(to: p(515, lb))

    // D — top horizontal bar
    lines.move(to: p(515, lt));  lines.addLine(to: p(695, lt))
    // D — bottom horizontal bar
    lines.move(to: p(515, lb));  lines.addLine(to: p(695, lb))
    // D — right arc (cubic bezier — symmetric, rightmost ~x=882 at mid-height)
    lines.move(to: p(695, lt))
    lines.addCurve(to: p(695, lb),
                   control1: p(960, lt),
                   control2: p(960, lb))

    // Expand strokes → filled region
    return lines.copy(strokingWithWidth: strokeW,
                      lineCap:  .butt,
                      lineJoin: .miter,
                      miterLimit: 3)
}

// ── Rainbow bands ─────────────────────────────────────────────────────────────
// 6 bold, distinct horizontal bands (bottom→top: red → violet)
let rainbowColors: [(CGFloat, CGFloat, CGFloat)] = [
    (0.95, 0.13, 0.13),   // 1 — red
    (1.00, 0.56, 0.05),   // 2 — orange
    (1.00, 0.86, 0.05),   // 3 — yellow
    (0.13, 0.78, 0.37),   // 4 — green
    (0.10, 0.53, 0.98),   // 5 — blue
    (0.65, 0.15, 0.95),   // 6 — violet
]

// ── Draw ──────────────────────────────────────────────────────────────────────

func drawIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus(); return image
    }

    // Background — very dark navy-black
    ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

    // Apply the MD path as a clip
    let letterClip = mdFilledPath(s: s)
    ctx.addPath(letterClip)
    ctx.clip()

    // Draw rainbow bands (bottom→top)
    let nBands = CGFloat(rainbowColors.count)
    let bandH  = s / nBands
    for (i, (r, g, b)) in rainbowColors.enumerated() {
        ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: CGFloat(i) * bandH, width: s, height: bandH))
    }

    // Thin white inner stroke for crispness at large sizes
    ctx.resetClip()
    ctx.addPath(letterClip)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
    ctx.setLineWidth(max(1, s * 0.003))
    ctx.strokePath()

    image.unlockFocus()
    return image
}

// ── Save helpers ──────────────────────────────────────────────────────────────

func savePNG(_ image: NSImage, at path: String, pixelSize: Int) {
    guard let tiff = image.tiffRepresentation,
          let src  = CGImageSourceCreateWithData(tiff as CFData, nil),
          let cg   = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }

    let cs  = CGColorSpaceCreateDeviceRGB()
    guard let bmp = CGContext(data: nil, width: pixelSize, height: pixelSize,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return }

    // Rounded corners at render time (so all sizes match macOS icon shape)
    let radius = CGFloat(pixelSize) * 0.22
    bmp.beginPath()
    bmp.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
    bmp.clip()

    bmp.interpolationQuality = .high
    bmp.draw(cg, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

    guard let scaled = bmp.makeImage() else { return }
    let out = NSMutableData()
    guard let dst = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dst, scaled, nil)
    CGImageDestinationFinalize(dst)
    try? (out as Data).write(to: URL(fileURLWithPath: path))
    print("  \(path.split(separator: "/").last ?? Substring(path))")
}

// ── Main ──────────────────────────────────────────────────────────────────────

let fm   = FileManager.default
let dir  = "./AppIcon.iconset"
try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

// Render at the two largest sizes and scale down for smaller slots
// (avoids re-running the full draw for every size)
print("Rendering icon…")
let master = drawIcon(size: 1024)

let specs: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]
for (size, name) in specs {
    savePNG(master, at: "\(dir)/\(name)", pixelSize: size)
}
print("Done.")
