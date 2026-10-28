// Readers for TamaPoke's packed sprite formats (port of sdmon.cpp, MIT,
// (c) 2026 Quique Tortosa). The files themselves are made on your own
// computer by tools/pack_pmd.py and tools/make_thumbs.py; they are not shipped.
package com.pokewatch.game

const val PMD_IDLE = 0
const val PMD_WALKL = 1
const val PMD_WALKR = 2
const val PMD_SLEEP = 3
const val PMD_EAT = 4
const val PMD_HURT = 5
const val PMD_ATTACK = 6
const val PMD_POSE = 7
const val PMD_HOP = 8
const val PMD_NOD = 9
const val PMD_BREATH = 10
const val PMD_SIT = 11
const val PMD_NACTS = 12

private fun u16(b: ByteArray, o: Int) = (b[o].toInt() and 0xFF) or ((b[o + 1].toInt() and 0xFF) shl 8)
private fun u32(b: ByteArray, o: Int) = u16(b, o).toLong() or (u16(b, o + 2).toLong() shl 16)

fun rgb565ToArgb(v: Int): Int {
    val r = (v shr 11) and 31
    val g = (v shr 5) and 63
    val b = v and 31
    return (0xFF shl 24) or ((r * 255 / 31) shl 16) or ((g * 255 / 63) shl 8) or (b * 255 / 31)
}

class PmdAct(
    val w: Int,
    val h: Int,
    val ms: IntArray,
    /** palette index per pixel, frames*w*h, 0xFF = transparent */
    val data: ByteArray,
    val offset: Int,
    /** row+1 of the lowest opaque pixel (anchor by the feet, not the canvas) */
    val base: Int,
) {
    val frames get() = ms.size
    fun totalMs(): Long = ms.sum().toLong().let { if (it == 0L) 100 else it }

    fun frameAt(tIn: Long, loop: Boolean): Int {
        val total = totalMs()
        if (!loop && tIn >= total) return frames - 1
        var t = tIn % total
        var i = 0
        var guard = 0
        while (guard < frames && t >= ms[i]) {
            t -= ms[i]
            i = (i + 1) % frames
            guard++
        }
        return i
    }

    fun pixel(frame: Int, x: Int, y: Int): Int =
        data[offset + frame * w * h + y * w + x].toInt() and 0xFF
}

class PmdMon(val pal: IntArray, val acts: Array<PmdAct?>) {
    fun has(a: Int) = a in 0 until PMD_NACTS && acts[a] != null

    companion object {
        /** Parses a TPK2 blob; null if it is malformed (same checks as the firmware). */
        fun parse(blob: ByteArray): PmdMon? {
            val size = blob.size
            if (size < 7 || String(blob, 0, 4, Charsets.US_ASCII) != "TPK2") return null
            val nActs = blob[4].toInt() and 0xFF
            val palCount = u16(blob, 5)
            if (palCount > 256 || 7 + palCount * 2 > size) return null
            val pal = IntArray(palCount) { rgb565ToArgb(u16(blob, 7 + it * 2)) }
            val acts = arrayOfNulls<PmdAct>(PMD_NACTS)
            var p = 7 + palCount * 2
            for (i in 0 until nActs) {
                if (p + 4 > size) break
                val id = blob[p].toInt() and 0xFF
                val w = blob[p + 1].toInt() and 0xFF
                val h = blob[p + 2].toInt() and 0xFF
                val nf = blob[p + 3].toInt() and 0xFF
                p += 4
                if (id >= PMD_NACTS || nf > 24) return null
                val bytes = nf * 2 + w * h * nf
                if (w == 0 || h == 0 || nf == 0 || p + bytes > size) return null
                val ms = IntArray(nf) { k -> u16(blob, p + k * 2).let { if (it == 0) 100 else it } }
                p += nf * 2
                val off = p
                p += w * h * nf
                var base = 1
                for (f in 0 until nf) {
                    val fo = off + f * w * h
                    for (r in h - 1 downTo 0) {
                        var any = false
                        for (c in 0 until w) if ((blob[fo + r * w + c].toInt() and 0xFF) != 0xFF) { any = true; break }
                        if (any) {
                            if (r + 1 > base) base = r + 1
                            break
                        }
                    }
                }
                acts[id] = PmdAct(w, h, ms, blob, off, base)
            }
            return PmdMon(pal, acts)
        }
    }
}

/** One gallery thumbnail out of thumbs.bin (TPTH). */
class Thumb(val w: Int, val h: Int, val pal: IntArray, val data: ByteArray, val offset: Int) {
    fun pixel(x: Int, y: Int) = data[offset + y * w + x].toInt() and 0xFF
}

class Thumbs(private val data: ByteArray) {
    private val count: Int = if (data.size >= 10 && String(data, 0, 4, Charsets.US_ASCII) == "TPTH") u16(data, 4) else 0
    private val cache = HashMap<Int, Thumb?>()

    fun get(dex: Int): Thumb? {
        if (dex < 1 || dex > count || 6 + 4 * count > data.size) return null
        return cache.getOrPut(dex) {
            val off = u32(data, 6 + 4 * (dex - 1))
            val size = data.size.toLong()
            if (off > size - 3) return@getOrPut null
            val o = off.toInt()
            val w = data[o].toInt() and 0xFF
            val h = data[o + 1].toInt() and 0xFF
            val n = data[o + 2].toInt() and 0xFF
            if (w == 0 || h == 0) return@getOrPut null
            val need = 3L + n * 2 + w * h
            if (need > size || off > size - need) return@getOrPut null
            val pal = IntArray(n) { rgb565ToArgb(u16(data, o + 3 + it * 2)) }
            Thumb(w, h, pal, data, o + 3 + n * 2)
        }
    }
}
