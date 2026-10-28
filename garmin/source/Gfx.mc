// Drawing helpers that mirror the Arduino_GFX calls TamaPoke uses, in the
// firmware's 466x466 coordinate space, scaled to the watch's screen.
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class Gfx {
    var dc as Dc?;
    var s = 1.0;          // screen px per firmware px
    var textColor = 0;
    private var size = 1;
    private var curX = 0;
    private var curY = 0;
    private var fonts as Dictionary = {};
    private var bitmaps as Dictionary = {};

    function initialize() {}

    function begin(d as Dc) as Void {
        dc = d;
        var w = d.getWidth() < d.getHeight() ? d.getWidth() : d.getHeight();
        s = w / 466.0;
        if (d has :setAntiAlias) {
            d.setAntiAlias(true);
        }
    }

    function x(v) as Number { return (v * s).toNumber(); }

    function fillScreen(col as Number) as Void {
        dc.setColor(col, col);
        dc.clear();
    }

    function fillRect(px, py, w, h, col as Number) as Void {
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        var x0 = x(px);
        var y0 = x(py);
        dc.fillRectangle(x0, y0, x(px + w) - x0, x(py + h) - y0);
    }

    function fillCircle(px, py, r, col as Number) as Void {
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x(px), x(py), x(r));
    }

    function drawCircle(px, py, r, col as Number) as Void {
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(x(px), x(py), x(r));
    }

    function fillRoundRect(px, py, w, h, r, col as Number) as Void {
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        var x0 = x(px);
        var y0 = x(py);
        dc.fillRoundedRectangle(x0, y0, x(px + w) - x0, x(py + h) - y0, x(r));
    }

    function drawRoundRect(px, py, w, h, r, col as Number) as Void {
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        var x0 = x(px);
        var y0 = x(py);
        dc.drawRoundedRectangle(x0, y0, x(px + w) - x0, x(py + h) - y0, x(r));
    }

    function fillTriangle(x0, y0, x1, y1, x2, y2, col as Number) as Void {
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x(x0), x(y0)], [x(x1), x(y1)], [x(x2), x(y2)]]);
    }

    function drawLine(x0, y0, x1, y1, col as Number) as Void {
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(x(x0), x(y0), x(x1), x(y1));
    }

    // ---- text: the firmware's 6x8 font sizes, cursor at the top-left ----
    function font(n as Number) {
        var f = fonts.get(n);
        if (f != null) {
            return f;
        }
        var px = (8 * n * s * 1.25).toNumber();
        if (Graphics has :getVectorFont) {
            f = Graphics.getVectorFont({
                :face => ["RobotoCondensedBold", "RobotoCondensedRegular", "RobotoRegular", "BionicBold"],
                :size => px
            });
        }
        if (f == null) {
            // no vector fonts on this watch: the biggest built-in font that fits
            var list = [Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL,
                        Graphics.FONT_TINY, Graphics.FONT_XTINY];
            f = Graphics.FONT_XTINY;
            for (var i = 0; i < list.size(); i++) {
                if (dc.getFontHeight(list[i]) <= px * 1.15) {
                    f = list[i];
                    break;
                }
            }
        }
        fonts.put(n, f);
        return f;
    }

    function setSize(n as Number) as Void { size = n; }

    function setCur(px, py) as Void {
        curX = px;
        curY = py;
    }

    // width in firmware px
    function textW(str as String, n as Number) as Number {
        return (dc.getTextWidthInPixels(str, font(n)) / s).toNumber();
    }

    function centerX(str as String, n as Number) as Number {
        return 233 - textW(str, n) / 2;
    }

    function print(str as String) as Void {
        var f = font(size);
        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        // TamaPoke's y is the top of the glyphs; nudge up by the font's
        // internal leading so the text sits where the 6x8 font would
        var h = dc.getFontHeight(f);
        var top = x(curY) - (h - 8 * size * s) / 3;
        dc.drawText(x(curX), top, f, str, Graphics.TEXT_JUSTIFY_LEFT);
        curX += textW(str, size);
    }

    // ---- bitmaps (already scaled to the screen by the resource compiler) ----
    function bitmap(id) as WatchUi.BitmapResource? {
        if (id == null) {
            return null;
        }
        var b = bitmaps.get(id);
        if (b == null) {
            b = WatchUi.loadResource(id);
            bitmaps.put(id, b);
        }
        return b as WatchUi.BitmapResource;
    }

    function forget(id) as Void {
        if (id != null) {
            bitmaps.remove(id);
        }
    }

    function drawBitmap(id, px, py) as Void {
        var b = bitmap(id);
        if (b != null) {
            dc.drawBitmap(x(px), x(py), b);
        }
    }

    // frame `fi` of a horizontal strip of `frames` frames
    function drawFrame(id, frames as Number, fi as Number, px, py) as Void {
        var b = bitmap(id);
        if (b == null || frames <= 0) {
            return;
        }
        var fw = b.getWidth() / frames;
        var x0 = x(px);
        var y0 = x(py);
        dc.setClip(x0, y0, fw, b.getHeight());
        dc.drawBitmap(x0 - fi * fw, y0, b);
        dc.clearClip();
    }
}

// firmware colours, as Garmin 0xRRGGBB
module Ui {
    const BG_DAY = 0xF2EFE1;
    const BG_NIGHT = 0x141828;
    const INK = 0x2A2A36;
    const INK_NIGHT = 0xD8DCF0;
    const TRACK = 0xD8D2BD;
    const BAR_OK = 0x58B868;
    const BAR_WARN = 0xE8A23C;
    const BAR_BAD = 0xE8503A;
    const WHITE = 0xFFFFFF;
    const BLUE = 0x4F93C4;
    const INK_K = 0x1B1B25;

    function lerp(a as Number, b as Number, i as Number, n as Number) as Number {
        if (n <= 0) {
            return a;
        }
        var r = ((a >> 16) & 0xFF) + (((b >> 16) & 0xFF) - ((a >> 16) & 0xFF)) * i / n;
        var g = ((a >> 8) & 0xFF) + (((b >> 8) & 0xFF) - ((a >> 8) & 0xFF)) * i / n;
        var bl = (a & 0xFF) + ((b & 0xFF) - (a & 0xFF)) * i / n;
        return (r << 16) | (g << 8) | bl;
    }
}
