// Drawing helpers that mirror the Arduino_GFX calls TamaPoke uses, in the
// firmware's 466x466 coordinate space (scaled to the watch's real screen).
// Same shape as the Wear OS port's Gfx.kt, drawing into a SwiftUI Canvas.
import CoreGraphics
import SwiftUI

let SCREEN: CGFloat = 466

func c565(_ r: Int, _ g: Int, _ b: Int) -> UInt32 { 0xFF00_0000 | UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b) }

/// Firmware's lerp565: mix a -> b by i/n.
func lerpColor(_ a: UInt32, _ b: UInt32, _ i: Int, _ n: Int) -> UInt32 {
    if n <= 0 { return a }
    func ch(_ c: UInt32, _ s: UInt32) -> Int { Int((c >> s) & 0xFF) }
    func mix(_ s: UInt32) -> UInt32 { UInt32(ch(a, s) + (ch(b, s) - ch(a, s)) * i / n) }
    return 0xFF00_0000 | mix(16) << 16 | mix(8) << 8 | mix(0)
}

func swiftColor(_ argb: UInt32) -> Color {
    Color(.sRGB,
          red: Double((argb >> 16) & 0xFF) / 255,
          green: Double((argb >> 8) & 0xFF) / 255,
          blue: Double(argb & 0xFF) / 255,
          opacity: Double((argb >> 24) & 0xFF) / 255)
}

final class Gfx {
    var c: GraphicsContext!
    private var size = 1
    private var curX: CGFloat = 0
    private var curY: CGFloat = 0
    var textColor: UInt32 = 0
    private var widths: [String: CGFloat] = [:]

    private func r(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h))
    }

    func fillScreen(_ col: UInt32) {
        c.fill(Path(r(-400, -400, 1266, 1266)), with: .color(swiftColor(col)))
    }

    func fillRect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ col: UInt32) {
        c.fill(Path(r(x, y, w, h)), with: .color(swiftColor(col)))
    }

    func fillCircle(_ x: Int, _ y: Int, _ rad: Int, _ col: UInt32) {
        c.fill(Path(ellipseIn: r(x - rad, y - rad, 2 * rad, 2 * rad)), with: .color(swiftColor(col)))
    }

    func drawCircle(_ x: Int, _ y: Int, _ rad: Int, _ col: UInt32) {
        c.stroke(Path(ellipseIn: r(x - rad, y - rad, 2 * rad, 2 * rad)), with: .color(swiftColor(col)), lineWidth: 1.6)
    }

    func fillRoundRect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ rad: Int, _ col: UInt32) {
        c.fill(Path(roundedRect: r(x, y, w, h), cornerRadius: CGFloat(rad)), with: .color(swiftColor(col)))
    }

    func drawRoundRect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ rad: Int, _ col: UInt32) {
        c.stroke(Path(roundedRect: r(x, y, w, h), cornerRadius: CGFloat(rad)), with: .color(swiftColor(col)), lineWidth: 1.6)
    }

    func fillTriangle(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, _ col: UInt32) {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y0))
        p.addLine(to: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x2, y: y2))
        p.closeSubpath()
        c.fill(p, with: .color(swiftColor(col)))
    }

    func drawLine(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ col: UInt32) {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y0))
        p.addLine(to: CGPoint(x: x1, y: y1))
        c.stroke(p, with: .color(swiftColor(col)), lineWidth: 1.6)
    }

    // ---- text: the firmware's 6x8 classic font, cursor at the top-left ----
    private func font(_ n: Int) -> Font { .system(size: 9 * CGFloat(n), weight: .bold, design: .monospaced) }

    private func resolve(_ s: String, _ n: Int, _ col: UInt32) -> GraphicsContext.ResolvedText {
        c.resolve(SwiftUI.Text(verbatim: s).font(font(n)).foregroundColor(swiftColor(col)))
    }

    func setSize(_ n: Int) { size = n }

    func setCur(_ x: Int, _ y: Int) {
        curX = CGFloat(x)
        curY = CGFloat(y)
    }

    func textW(_ s: String, _ n: Int) -> Int {
        let key = "\(n)|\(s)"
        if let w = widths[key] { return Int(w) }
        let w = resolve(s, n, 0xFF00_0000).measure(in: CGSize(width: 4000, height: 1000)).width
        widths[key] = w
        return Int(w)
    }

    func centerX(_ s: String, _ n: Int) -> Int { 233 - textW(s, n) / 2 }

    func print(_ s: String) {
        let t = resolve(s, size, textColor)
        let sz = t.measure(in: CGSize(width: 4000, height: 1000))
        // the Wear OS port puts the baseline 6.5 px * size under the cursor
        let top = curY + 6.5 * CGFloat(size) - t.firstBaseline(in: sz)
        c.draw(t, in: CGRect(x: curX, y: top, width: sz.width, height: sz.height))
        curX += sz.width
    }

    // ---- bitmaps ----
    func drawBitmap(_ b: Image, _ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        c.draw(b, in: r(x, y, w, h))
    }
}

/// Caches the pixel art as images so a frame is one blit, not a pixel loop.
enum Art {
    static let INK_K: UInt32 = 0xFF1B_1B25

    /// ARGB pixels (0 = transparent) -> a crisp, unfiltered image.
    static func image(_ px: [UInt32], _ w: Int, _ h: Int) -> Image {
        var buf = px
        let cg: CGImage? = buf.withUnsafeMutableBytes { raw -> CGImage? in
            // 0xAARRGGBB as little-endian words is BGRA in memory: premultipliedFirst + 32Little.
            // Pixels are either fully opaque or fully transparent, so premultiplying is a no-op.
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                                          CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
            return ctx.makeImage()
        }
        guard let cg else { return Image(systemName: "questionmark") }
        return Image(decorative: cg, scale: 1).interpolation(.none)
    }

    private struct MapKey: Hashable { let m: [String]; let sil: Bool }
    private static var maps: [MapKey: Image] = [:]

    /// One of the firmware's char-map sprites ('.' = transparent).
    static func map(_ m: [String], _ sil: Bool) -> Image {
        let key = MapKey(m: m, sil: sil)
        if let hit = maps[key] { return hit }
        let n = m.count
        let w = m[0].count
        var px = [UInt32](repeating: 0, count: w * n)
        for (r, row) in m.enumerated() {
            for (col, ch) in row.enumerated() where ch != "." {
                px[r * w + col] = sil ? INK_K : (SpriteTables.COLORS[ch] ?? 0)
            }
        }
        let img = image(px, w, n)
        maps[key] = img
        return img
    }

    final class MonCache {
        let mon: PmdMon
        private var frames: [Int: Image] = [:]

        init(_ mon: PmdMon) { self.mon = mon }

        func frame(_ actId: Int, _ fi: Int, _ sil: Bool) -> Image {
            let key = (actId << 8) | (fi << 1) | (sil ? 1 : 0)
            if let hit = frames[key] { return hit }
            let a = mon.acts[actId]!
            var px = [UInt32](repeating: 0, count: a.w * a.h)
            for y in 0..<a.h {
                for x in 0..<a.w {
                    let k = a.pixel(fi, x, y)
                    if k != 0xFF && k < mon.pal.count { px[y * a.w + x] = sil ? INK_K : mon.pal[k] }
                }
            }
            let img = image(px, a.w, a.h)
            frames[key] = img
            return img
        }
    }

    private struct ThumbKey: Hashable { let t: ObjectIdentifier; let sil: Bool }
    private static var thumbs: [ThumbKey: Image] = [:]

    static func thumb(_ t: Thumb, _ sil: Bool) -> Image {
        let key = ThumbKey(t: ObjectIdentifier(t), sil: sil)
        if let hit = thumbs[key] { return hit }
        var px = [UInt32](repeating: 0, count: t.w * t.h)
        for y in 0..<t.h {
            for x in 0..<t.w {
                let k = t.pixel(x, y)
                if k != 0xFF && k < t.pal.count { px[y * t.w + x] = sil ? INK_K : t.pal[k] }
            }
        }
        let img = image(px, t.w, t.h)
        thumbs[key] = img
        return img
    }
}
