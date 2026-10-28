// Drawing helpers that mirror the Arduino_GFX calls TamaPoke uses, in the
// firmware's 466x466 coordinate space (scaled to the watch's real screen).
package com.pokewatch

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import com.pokewatch.game.PmdAct
import com.pokewatch.game.PmdMon
import com.pokewatch.game.SpriteTables
import com.pokewatch.game.Thumb

const val SCREEN = 466f

fun c565(r: Int, g: Int, b: Int): Int = (0xFF shl 24) or (r shl 16) or (g shl 8) or b

/** Firmware's lerp565: mix a -> b by i/n. */
fun lerpColor(a: Int, b: Int, i: Int, n: Int): Int {
    if (n <= 0) return a
    fun ch(c: Int, s: Int) = (c shr s) and 0xFF
    fun mix(s: Int) = ch(a, s) + (ch(b, s) - ch(a, s)) * i / n
    return (0xFF shl 24) or (mix(16) shl 16) or (mix(8) shl 8) or mix(0)
}

class Gfx {
    lateinit var c: Canvas
    private val fill = Paint().apply { style = Paint.Style.FILL; isAntiAlias = false }
    private val stroke = Paint().apply { style = Paint.Style.STROKE; strokeWidth = 1.6f; isAntiAlias = true }
    private val text = Paint().apply {
        typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        isAntiAlias = true
    }
    private val bmp = Paint().apply { isFilterBitmap = false; isAntiAlias = false }
    private val rf = RectF()
    private val src = Rect()
    private val path = Path()

    private var size = 1
    private var curX = 0f
    private var curY = 0f
    var textColor = 0
    var wide = false // CJK glyphs: the monospace advance doesn't apply

    fun fillScreen(col: Int) = c.drawColor(col)

    fun fillRect(x: Number, y: Number, w: Number, h: Number, col: Int) {
        fill.color = col
        c.drawRect(x.toFloat(), y.toFloat(), x.toFloat() + w.toFloat(), y.toFloat() + h.toFloat(), fill)
    }

    fun fillCircle(x: Number, y: Number, r: Number, col: Int) {
        fill.color = col
        fill.isAntiAlias = true
        c.drawCircle(x.toFloat(), y.toFloat(), r.toFloat(), fill)
        fill.isAntiAlias = false
    }

    fun drawCircle(x: Number, y: Number, r: Number, col: Int) {
        stroke.color = col
        c.drawCircle(x.toFloat(), y.toFloat(), r.toFloat(), stroke)
    }

    fun fillRoundRect(x: Number, y: Number, w: Number, h: Number, r: Number, col: Int) {
        fill.color = col
        fill.isAntiAlias = true
        rf.set(x.toFloat(), y.toFloat(), x.toFloat() + w.toFloat(), y.toFloat() + h.toFloat())
        c.drawRoundRect(rf, r.toFloat(), r.toFloat(), fill)
        fill.isAntiAlias = false
    }

    fun drawRoundRect(x: Number, y: Number, w: Number, h: Number, r: Number, col: Int) {
        stroke.color = col
        rf.set(x.toFloat(), y.toFloat(), x.toFloat() + w.toFloat(), y.toFloat() + h.toFloat())
        c.drawRoundRect(rf, r.toFloat(), r.toFloat(), stroke)
    }

    fun fillTriangle(x0: Number, y0: Number, x1: Number, y1: Number, x2: Number, y2: Number, col: Int) {
        fill.color = col
        fill.isAntiAlias = true
        path.reset()
        path.moveTo(x0.toFloat(), y0.toFloat())
        path.lineTo(x1.toFloat(), y1.toFloat())
        path.lineTo(x2.toFloat(), y2.toFloat())
        path.close()
        c.drawPath(path, fill)
        fill.isAntiAlias = false
    }

    fun drawLine(x0: Number, y0: Number, x1: Number, y1: Number, col: Int) {
        stroke.color = col
        c.drawLine(x0.toFloat(), y0.toFloat(), x1.toFloat(), y1.toFloat(), stroke)
    }

    // ---- text: the firmware's 6x8 classic font, cursor at the top-left ----
    fun setSize(n: Int) {
        size = n
        text.textSize = 9f * n
    }

    fun setCur(x: Number, y: Number) {
        curX = x.toFloat()
        curY = y.toFloat()
    }

    fun textW(s: String, n: Int): Int {
        text.textSize = 9f * n
        val w = text.measureText(s)
        text.textSize = 9f * size
        return w.toInt()
    }

    fun centerX(s: String, n: Int) = 233 - textW(s, n) / 2

    fun print(s: String) {
        text.color = textColor
        c.drawText(s, curX, curY + 6.5f * size, text)
        curX += text.measureText(s)
    }

    // ---- bitmaps ----
    fun drawBitmap(b: Bitmap, x: Number, y: Number, w: Number, h: Number) {
        src.set(0, 0, b.width, b.height)
        rf.set(x.toFloat(), y.toFloat(), x.toFloat() + w.toFloat(), y.toFloat() + h.toFloat())
        c.drawBitmap(b, src, rf, bmp)
    }
}

/** Caches the pixel art as bitmaps so a frame is one blit, not a pixel loop. */
object Art {
    private const val INK_K = 0xFF1B1B25.toInt()
    private val maps = HashMap<Pair<Array<String>, Boolean>, Bitmap>()

    /** One of the firmware's char-map sprites ('.' = transparent). */
    fun map(m: Array<String>, sil: Boolean): Bitmap = maps.getOrPut(m to sil) {
        val n = m.size
        val w = m[0].length
        val px = IntArray(w * n)
        for (r in 0 until n) for (col in 0 until w) {
            val ch = m[r][col]
            if (ch == '.') continue
            px[r * w + col] = if (sil) INK_K else SpriteTables.COLORS[ch] ?: 0
        }
        Bitmap.createBitmap(px, w, n, Bitmap.Config.ARGB_8888)
    }

    class MonCache(val mon: PmdMon) {
        private val frames = HashMap<Int, Bitmap>()

        fun frame(actId: Int, fi: Int, sil: Boolean): Bitmap {
            val key = (actId shl 8) or (fi shl 1) or (if (sil) 1 else 0)
            return frames.getOrPut(key) {
                val a: PmdAct = mon.acts[actId]!!
                val px = IntArray(a.w * a.h)
                for (y in 0 until a.h) for (x in 0 until a.w) {
                    val k = a.pixel(fi, x, y)
                    if (k != 0xFF) px[y * a.w + x] = if (sil) INK_K else mon.pal[k]
                }
                Bitmap.createBitmap(px, a.w, a.h, Bitmap.Config.ARGB_8888)
            }
        }
    }

    private val thumbs = HashMap<Pair<Thumb, Boolean>, Bitmap>()

    fun thumb(t: Thumb, sil: Boolean): Bitmap = thumbs.getOrPut(t to sil) {
        val px = IntArray(t.w * t.h)
        for (y in 0 until t.h) for (x in 0 until t.w) {
            val k = t.pixel(x, y)
            if (k != 0xFF) px[y * t.w + x] = if (sil) INK_K else t.pal[k]
        }
        Bitmap.createBitmap(px, t.w, t.h, Bitmap.Config.ARGB_8888)
    }
}
