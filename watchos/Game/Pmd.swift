// Readers for TamaPoke's packed sprite formats (port of sdmon.cpp, MIT,
// (c) 2026 Quique Tortosa). The files themselves are made on your own
// computer by tools/pack_pmd.py and tools/make_thumbs.py; they are not shipped.
import Foundation

let PMD_IDLE = 0
let PMD_WALKL = 1
let PMD_WALKR = 2
let PMD_SLEEP = 3
let PMD_EAT = 4
let PMD_HURT = 5
let PMD_ATTACK = 6
let PMD_POSE = 7
let PMD_HOP = 8
let PMD_NOD = 9
let PMD_BREATH = 10
let PMD_SIT = 11
let PMD_NACTS = 12

private func u16(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | (Int(b[o + 1]) << 8) }
private func u32(_ b: [UInt8], _ o: Int) -> Int { u16(b, o) | (u16(b, o + 2) << 16) }

func rgb565ToArgb(_ v: Int) -> UInt32 {
    let r = (v >> 11) & 31
    let g = (v >> 5) & 63
    let b = v & 31
    return 0xFF00_0000 | UInt32(r * 255 / 31) << 16 | UInt32(g * 255 / 63) << 8 | UInt32(b * 255 / 31)
}

final class PmdAct {
    let w: Int
    let h: Int
    let ms: [Int]
    /// palette index per pixel, frames*w*h, 0xFF = transparent
    let data: [UInt8]
    let offset: Int
    /// row+1 of the lowest opaque pixel (anchor by the feet, not the canvas)
    let base: Int

    init(w: Int, h: Int, ms: [Int], data: [UInt8], offset: Int, base: Int) {
        self.w = w; self.h = h; self.ms = ms; self.data = data; self.offset = offset; self.base = base
    }

    var frames: Int { ms.count }
    func totalMs() -> Int { let t = ms.reduce(0, +); return t == 0 ? 100 : t }

    func frameAt(_ tIn: Int, loop: Bool) -> Int {
        let total = totalMs()
        if !loop && tIn >= total { return frames - 1 }
        var t = tIn % total
        var i = 0
        var guardN = 0
        while guardN < frames && t >= ms[i] {
            t -= ms[i]
            i = (i + 1) % frames
            guardN += 1
        }
        return i
    }

    func pixel(_ frame: Int, _ x: Int, _ y: Int) -> Int {
        Int(data[offset + frame * w * h + y * w + x])
    }
}

final class PmdMon {
    let pal: [UInt32]
    let acts: [PmdAct?]

    init(pal: [UInt32], acts: [PmdAct?]) { self.pal = pal; self.acts = acts }

    func has(_ a: Int) -> Bool { a >= 0 && a < PMD_NACTS && acts[a] != nil }

    /// Parses a TPK2 blob; nil if it is malformed (same checks as the firmware).
    static func parse(_ blob: [UInt8]) -> PmdMon? {
        let size = blob.count
        if size < 7 || blob[0] != 0x54 || blob[1] != 0x50 || blob[2] != 0x4B || blob[3] != 0x32 { return nil } // "TPK2"
        let nActs = Int(blob[4])
        let palCount = u16(blob, 5)
        if palCount > 256 || 7 + palCount * 2 > size { return nil }
        let pal = (0..<palCount).map { rgb565ToArgb(u16(blob, 7 + $0 * 2)) }
        var acts = [PmdAct?](repeating: nil, count: PMD_NACTS)
        var p = 7 + palCount * 2
        for _ in 0..<nActs {
            if p + 4 > size { break }
            let id = Int(blob[p])
            let w = Int(blob[p + 1])
            let h = Int(blob[p + 2])
            let nf = Int(blob[p + 3])
            p += 4
            if id >= PMD_NACTS || nf > 24 { return nil }
            let bytes = nf * 2 + w * h * nf
            if w == 0 || h == 0 || nf == 0 || p + bytes > size { return nil }
            let ms = (0..<nf).map { k -> Int in let v = u16(blob, p + k * 2); return v == 0 ? 100 : v }
            p += nf * 2
            let off = p
            p += w * h * nf
            var base = 1
            for f in 0..<nf {
                let fo = off + f * w * h
                for r in stride(from: h - 1, through: 0, by: -1) {
                    var any = false
                    for c in 0..<w where blob[fo + r * w + c] != 0xFF { any = true; break }
                    if any {
                        if r + 1 > base { base = r + 1 }
                        break
                    }
                }
            }
            acts[id] = PmdAct(w: w, h: h, ms: ms, data: blob, offset: off, base: base)
        }
        return PmdMon(pal: pal, acts: acts)
    }
}

/// One gallery thumbnail out of thumbs.bin (TPTH).
final class Thumb {
    let w: Int, h: Int
    let pal: [UInt32]
    let data: [UInt8]
    let offset: Int

    init(w: Int, h: Int, pal: [UInt32], data: [UInt8], offset: Int) {
        self.w = w; self.h = h; self.pal = pal; self.data = data; self.offset = offset
    }

    func pixel(_ x: Int, _ y: Int) -> Int { Int(data[offset + y * w + x]) }
}

final class Thumbs {
    private let data: [UInt8]
    private let count: Int
    private var cache: [Int: Thumb?] = [:]

    init(_ data: [UInt8]) {
        self.data = data
        let magic = data.count >= 10 && data[0] == 0x54 && data[1] == 0x50 && data[2] == 0x54 && data[3] == 0x48 // "TPTH"
        count = magic ? u16(data, 4) : 0
    }

    func get(_ dex: Int) -> Thumb? {
        if dex < 1 || dex > count || 6 + 4 * count > data.count { return nil }
        if let hit = cache[dex] { return hit }
        let t = load(dex)
        cache[dex] = .some(t)
        return t
    }

    private func load(_ dex: Int) -> Thumb? {
        let off = u32(data, 6 + 4 * (dex - 1))
        let size = data.count
        if off > size - 3 { return nil }
        let w = Int(data[off])
        let h = Int(data[off + 1])
        let n = Int(data[off + 2])
        if w == 0 || h == 0 { return nil }
        let need = 3 + n * 2 + w * h
        if need > size || off > size - need { return nil }
        let pal = (0..<n).map { rgb565ToArgb(u16(data, off + 3 + $0 * 2)) }
        return Thumb(w: w, h: h, pal: pal, data: data, offset: off + 3 + n * 2)
    }
}
