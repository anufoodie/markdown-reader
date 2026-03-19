#!/usr/bin/swift
import AppKit
import CoreText
import CoreGraphics

// ── Glyph path for "MD" using Helvetica Neue Heavy ────────────────────────────
// Uses actual font outlines so letterforms are typographically correct.
// Even padding (12% each side) keeps letters well within the square canvas.

func mdGlyphPath(canvasSize s: CGFloat) -> CGPath {
    let padding = s * 0.12
    let maxW    = s - 2 * padding
    let maxH    = s - 2 * padding

    // Pick the heaviest available Helvetica variant
    let candidates = ["HelveticaNeue-Heavy", "HelveticaNeue-Bold", "Helvetica-Bold"]
    func available(_ name: String) -> Bool {
        let f = CTFontCreateWithName(name as CFString, 12, nil)
        return (CTFontCopyPostScriptName(f) as String) == name
    }
    let fontName = candidates.first(where: available) ?? "Helvetica-Bold"

    // Measure at a large trial size, then scale linearly to fit padded area
    let trial: CGFloat = 600
    let trialFont = CTFontCreateWithName(fontName as CFString, trial, nil)
    let trialLine = CTLineCreateWithAttributedString(
        NSAttributedString(string: "MD",
                           attributes: [kCTFontAttributeName as NSAttributedString.Key: trialFont])
    )
    let trialBounds = CTLineGetBoundsWithOptions(trialLine, .useGlyphPathBounds)
    guard trialBounds.width > 0, trialBounds.height > 0 else { return CGMutablePath() }

    let scale    = min(maxW / trialBounds.width, maxH / trialBounds.height)
    let fontSize = trial * scale

    // Final font + line at the target size
    let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: "MD",
                           attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
    )
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

    // Stretch glyphs 20% taller; recentre using the enlarged dimensions
    let vScale: CGFloat = 1.2
    let tx = (s - bounds.width)          / 2 - bounds.origin.x
    let ty = (s - bounds.height * vScale) / 2 - bounds.origin.y * vScale

    // Extract per-glyph CGPath outlines, apply vertical stretch + translation
    let combined = CGMutablePath()
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]
    for run in runs {
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        let n = CTRunGetGlyphCount(run)
        var glyphs    = [CGGlyph](repeating: 0,     count: n)
        var positions = [CGPoint](repeating: .zero, count: n)
        CTRunGetGlyphs(run,    CFRangeMake(0, n), &glyphs)
        CTRunGetPositions(run, CFRangeMake(0, n), &positions)
        for (g, pos) in zip(glyphs, positions) {
            if let path = CTFontCreatePathForGlyph(runFont, g, nil) {
                // a=1 b=0 c=0 d=vScale: scale y, pass x unchanged; then translate
                let t = CGAffineTransform(a: 1, b: 0, c: 0, d: vScale,
                                          tx: tx + pos.x,
                                          ty: ty + pos.y * vScale)
                combined.addPath(path, transform: t)
            }
        }
    }
    return combined
}

// ── Rainbow bands ─────────────────────────────────────────────────────────────
// 6 bold horizontal bands, bottom → top: red → violet

let rainbowColors: [(CGFloat, CGFloat, CGFloat)] = [
    (0.95, 0.13, 0.13),   // red
    (1.00, 0.56, 0.05),   // orange
    (1.00, 0.86, 0.05),   // yellow
    (0.13, 0.78, 0.37),   // green
    (0.05, 0.75, 0.75),   // cyan
    (0.10, 0.53, 0.98),   // blue
    (0.65, 0.15, 0.95),   // violet
    (0.95, 0.15, 0.65),   // magenta
]

// ── Draw ──────────────────────────────────────────────────────────────────────

func drawIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus(); return image
    }

    // Background — deep navy-black
    ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

    // Clip to "MD" glyph outlines
    let glyphs = mdGlyphPath(canvasSize: s)
    ctx.addPath(glyphs)
    ctx.clip()

    // Fill rainbow bands inside the clipped letterforms
    let nBands = CGFloat(rainbowColors.count)
    let bandH  = s / nBands
    for (i, (r, g, b)) in rainbowColors.enumerated() {
        ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: CGFloat(i) * bandH, width: s, height: bandH))
    }

    image.unlockFocus()
    return image
}

// ── Save helpers ──────────────────────────────────────────────────────────────

func savePNG(_ image: NSImage, at path: String, pixelSize: Int) {
    guard let tiff = image.tiffRepresentation,
          let src  = CGImageSourceCreateWithData(tiff as CFData, nil),
          let cg   = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }

    let cs = CGColorSpaceCreateDeviceRGB()
    guard let bmp = CGContext(data: nil, width: pixelSize, height: pixelSize,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return }

    // macOS-style rounded corners
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

let fm  = FileManager.default
let dir = "./AppIcon.iconset"
try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

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
