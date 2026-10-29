// Port of TamaPoke.ino's screens, touch handling and minigames (MIT,
// (c) 2026 Quique Tortosa). Coordinates are the firmware's 466x466 ones; the
// view scales them to the watch. Function names follow the original so the
// two can be read side by side.
package com.pokewatch

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import com.pokewatch.game.*
import java.util.TimeZone
import kotlin.math.abs
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

private const val CX = 233
private const val CY = 233
private const val PET_CY = 202
private const val PET_GROUND = 304
private const val HORIZON = 232

private const val BTN_HALF = 26
private const val BTN_HIT = 36

private const val STARTER_GROUND = 318
private const val STARTER_ARROW_X = 52
private const val STARTER_ARROW_Y = 250
private const val STARTER_BTN_W = 120
private const val STARTER_BTN_H = 52
private const val STARTER_BTN_Y = 392
private const val EVO_BTN_W = 256
private const val EVO_BTN_H = 64
private const val EVO_BTN_X = CX - EVO_BTN_W / 2
private const val EVO_BTN_Y = 172
private const val FAR_BTN_W = 408
private const val FAR_BTN_H = 58
private const val FAR_BTN_X = CX - FAR_BTN_W / 2
private const val FAR_BTN_Y = 176

private const val GAL_X = 73
private const val GAL_Y = 84
private const val GAL_CELL = 80
private const val KB_COLS = 6
private const val KB_X = 40
private const val KB_Y = 150
private const val KB_W = 64
private const val KB_H = 52
private const val KB_KEYS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ.-"
private const val SET_PILL_Y = 200
private const val SET_PILL_H = 44

private val INK_K = 0xFF1B1B25.toInt()
private val STARTER_DEX = intArrayOf(1, 4, 7)
private val CRACK1 = arrayOf(intArrayOf(15, 8), intArrayOf(16, 9), intArrayOf(15, 10))
private val CRACK2 = arrayOf(
    intArrayOf(11, 13), intArrayOf(12, 14), intArrayOf(11, 15),
    intArrayOf(20, 12), intArrayOf(19, 13), intArrayOf(20, 14),
)
private val STARS = arrayOf(
    intArrayOf(120, 140), intArrayOf(330, 120), intArrayOf(370, 210),
    intArrayOf(95, 230), intArrayOf(280, 90), intArrayOf(160, 95),
)
private val BIOME_SOIL = intArrayOf(
    c565(0x7e, 0xc0, 0x7f), c565(0xdc, 0xca, 0x94), c565(0x4f, 0x8a, 0x55),
    c565(0x8a, 0x55, 0x44), c565(0xa8, 0x90, 0x6a), c565(0xe6, 0xee, 0xf5),
)

private class Btn(val cx: Int, val cy: Int, val icon: Array<String>)

@SuppressLint("ViewConstructor")
class GameView(
    context: Context,
    private val sound: Sound,
    private val battery: Battery,
    /** Sprites live in the app's assets/mons, made by tools/fetch_sprites.py. */
    private val readAsset: (String) -> ByteArray? = { path ->
        try {
            context.assets.open(path).use { it.readBytes() }
        } catch (_: Exception) {
            null
        }
    },
) : View(context) {

    private val rnd = Random.Default
    private fun random(n: Int) = rnd.nextInt(n)
    private fun millis() = SystemClock.uptimeMillis()
    private fun timeLeft(deadline: Long) = if (deadline == 0L) 0L else maxOf(0L, deadline - millis())
    private fun sfxPlay(s: Sfx) = sound.play(s)

    val pet = Pet(PrefsStore(context), rnd, ::millis) { sound.play(it) }
    private val g = Gfx()

    private val buttons = arrayOf(
        Btn(140, 390, SpriteTables.SPR_ICON_FOOD),
        Btn(202, 404, SpriteTables.SPR_ICON_PLAY),
        Btn(264, 404, SpriteTables.SPR_ICON_LIGHT),
        Btn(326, 390, SpriteTables.SPR_ICON_CLEAN),
    )

    // ---- sprites ----
    private var pmd: Art.MonCache? = null
    private var evoPmd: Art.MonCache? = null
    private var galleryPmd: Art.MonCache? = null
    private var monFor = -2
    private var monShinyFor = false
    private val thumbs: Thumbs? = readAsset("mons/thumbs.bin")?.let { Thumbs(it) }

    // ---- behaviour of the pet on screen ----
    private var behMode = 0
    private var behAct = PMD_IDLE
    private var behT0 = 0L
    private var behUntil = 0L
    private var behX = 233f
    private var behTargetX = 233f
    private var walkLast = 0L

    // ---- screens / dialogs ----
    private var galleryOpen = false
    private var galleryPage = 0
    private var galleryDetail = 0
    private var cardOpen = false
    private var cardPage = 0
    private var kbOpen = false
    private var nameBuf = ""
    private var settingsOpen = false
    private var bathUntil = 0L
    private var bathPending = false
    private class Bubble(var x: Int = 0, var y: Int = 0, var r: Int = 0, var ph: Int = 0)
    private val bubbles = Array(14) { Bubble() }
    private var feedMenuUntil = 0L
    private var confirmUntil = 0L
    private var choiceKind = 0
    private var choiceUntil = 0L

    // ---- minigame ----
    private var gameOpen = false
    private var gameOverUntil = 0L
    private var ballX = 0f; private var ballY = 0f; private var ballVX = 0f; private var ballVY = 0f
    private var gamePetX = 233f
    private var lastGameStep = 0L
    private var gameScore = 0
    private var gameMisses = 0
    private var hitX = 0f; private var hitY = 0f
    private var hitTime = 0L
    private var gameNewHi = false

    // ---- training bag ----
    private var sackOpen = false
    private var sackUntil = 0L
    private var sackOverUntil = 0L
    private var sackHits = 0
    private var sackShake = 0f
    private var sackGain = 0
    private var sackNewHi = false

    // ---- touch ----
    private var wasPressed = false
    private var tX0 = 0; private var tY0 = 0; private var tXl = 0; private var tYl = 0
    private var tStart = 0L
    private var holdFired = false

    private var gNight = false
    private var starterSel = 0
    private var starterHopAt = 0L
    private var starterPmd: Art.MonCache? = null
    private var starterPmdFor = 0
    private var wasEvoReady = false
    private var wasRunReady = false
    private var lastClock = 0L

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        Text.lang = context.getSharedPreferences("tamapoke", Context.MODE_PRIVATE)
            .getInt("lang", Text.LANG_EN).coerceIn(0, Text.LANG_COUNT - 1)
        pet.begin()
        pet.syncClock(localEpoch())
    }

    /** Local wall-clock seconds: the firmware's RTC holds local time, not UTC. */
    fun localEpoch(): Long {
        val now = System.currentTimeMillis()
        return (now + TimeZone.getDefault().getOffset(now)) / 1000
    }

    fun onResumeGame() {
        pet.syncClock(localEpoch())
        requestFocus()
        invalidate()
    }

    fun onPauseGame() {
        pet.lastSeenEpoch = localEpoch()
        pet.save()
    }

    private fun loadMon(dex: Int, shiny: Boolean): Art.MonCache? {
        val blob = (if (shiny) readAsset("mons/ps%03d.bin".format(dex)) else null)
            ?: readAsset("mons/p%03d.bin".format(dex)) ?: return null
        return PmdMon.parse(blob)?.let { Art.MonCache(it) }
    }

    private fun has(m: Art.MonCache?, a: Int) = m != null && m.mon.has(a)

    private fun ensureMon() {
        if (pet.speciesId == monFor && monShinyFor == pet.shiny) return
        monFor = pet.speciesId
        monShinyFor = pet.shiny
        pmd = null
        behX = 233f; behTargetX = 233f
        behMode = 0
        behUntil = 0
        if (pet.speciesId in 1..DEX_COUNT) pmd = loadMon(pet.speciesId, pet.shiny)
    }

    private fun T(id: S) = Text.t(id)
    private fun dexName(d: Int) = Text.dexName(d)

    // =====================================================================
    // frame loop
    // =====================================================================
    override fun onDraw(canvas: Canvas) {
        val now = millis()
        pet.update(now)

        val evoReady = pet.wantEvolveButton()
        if (evoReady && !wasEvoReady) sfxPlay(Sfx.MEDAL)
        wasEvoReady = evoReady
        val runReady = pet.canRunawayNow()
        if (runReady && !wasRunReady) sfxPlay(Sfx.DENY)
        wasRunReady = runReady

        ensureMon()
        battery.poll(now)
        if (now - lastClock > 30_000) {
            lastClock = now
            pet.lastSeenEpoch = localEpoch()
        }
        if (pet.pendingSave) pet.flushSave()

        val s = minOf(width, height) / SCREEN
        canvas.save()
        canvas.translate((width - SCREEN * s) / 2, (height - SCREEN * s) / 2)
        canvas.scale(s, s)
        g.c = canvas
        g.wide = Text.lang == Text.LANG_JA || Text.lang == Text.LANG_KO
        render()
        canvas.restore()

        // the firmware's frame pacing: 85 ms in the games, 100 ms otherwise
        postInvalidateDelayed(if (gameOpen || sackOpen) 85 else 100)
    }

    // =====================================================================
    // touch
    // =====================================================================
    private fun toScreen(e: MotionEvent): Pair<Int, Int> {
        val s = minOf(width, height) / SCREEN
        val ox = (width - SCREEN * s) / 2
        val oy = (height - SCREEN * s) / 2
        return ((e.x - ox) / s).toInt() to ((e.y - oy) / s).toInt()
    }

    private fun inPetZone(x: Int, y: Int) = x in 111..355 && y in 96..309

    private val handler = android.os.Handler(android.os.Looper.getMainLooper())

    private val holdCheck = object : Runnable {
        override fun run() {
            if (!wasPressed || holdFired) return
            if (!galleryOpen && !cardOpen && !kbOpen && !settingsOpen && millis() - tStart > 3000 &&
                abs(tXl - tX0) < 30 && abs(tYl - tY0) < 30 && inPetZone(tX0, tY0) &&
                !pet.isEgg() && confirmUntil == 0L && pet.ceremony == CER_NONE
            ) {
                confirmUntil = millis() + 10000
                holdFired = true
                performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
                invalidate()
            } else if (millis() - tStart <= 3000) {
                handler.postDelayed(this, 100)
            }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        val (x, y) = toScreen(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                if (sackOpen) {
                    if (y < 72) sackOpen = false else sackTap()
                    wasPressed = true
                    return true
                }
                tX0 = x; tXl = x; tY0 = y; tYl = y
                tStart = millis()
                holdFired = false
                wasPressed = true
                handler.postDelayed(holdCheck, 100)
            }
            MotionEvent.ACTION_MOVE -> {
                tXl = x; tYl = y
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val was = wasPressed
                wasPressed = false
                handler.removeCallbacks(holdCheck)
                if (sackOpen || !was || e.actionMasked == MotionEvent.ACTION_CANCEL) return true
                val dx = tXl - tX0
                val dy = tYl - tY0
                val dt = millis() - tStart
                if (!holdFired) {
                    if (abs(dx) > 80 && abs(dy) < 70 && dt < 800) onSwipe(if (dx > 0) 1 else -1)
                    else if (abs(dy) > 80 && abs(dx) < 70 && dt < 800) onSwipeV(if (dy > 0) 1 else -1)
                    else if (dt < 1500 && abs(dx) < 40 && abs(dy) < 40) onTap(tX0, tY0)
                }
            }
        }
        invalidate()
        return true
    }

    /** Rotating bezel / crown: page through the Pokédex and the card. */
    override fun onGenericMotionEvent(e: MotionEvent): Boolean {
        if (e.action == MotionEvent.ACTION_SCROLL && e.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER)) {
            val v = -e.getAxisValue(MotionEvent.AXIS_SCROLL)
            val dir = if (v > 0) -1 else 1
            if ((galleryOpen && galleryDetail == 0) || cardOpen || pet.awaitingStarter()) onSwipe(dir)
            invalidate()
            return true
        }
        return super.onGenericMotionEvent(e)
    }

    /** The watch's back button closes whatever is open; false = leave the app. */
    fun onBack(): Boolean {
        when {
            kbOpen -> kbOpen = false
            gameOpen -> gameOpen = false
            sackOpen -> sackOpen = false
            galleryOpen && galleryDetail != 0 -> { galleryDetail = 0; galleryPmd = null }
            galleryOpen -> galleryOpen = false
            cardOpen -> cardOpen = false
            settingsOpen -> settingsOpen = false
            choiceKind != 0 -> choiceKind = 0
            confirmUntil != 0L -> confirmUntil = 0
            feedMenuUntil != 0L -> feedMenuUntil = 0
            else -> return false
        }
        invalidate()
        return true
    }

    private fun onSwipeV(dir: Int) {
        if (pet.awaitingStarter()) return
        if (gameOpen || galleryOpen || kbOpen || sackOpen || pet.ceremony != CER_NONE) return
        if (settingsOpen) { settingsOpen = false; return }
        if (cardOpen) {
            if (dir < 0) cardOpen = false
            return
        }
        if (dir > 0) {
            if (confirmUntil == 0L && feedMenuUntil == 0L) settingsOpen = true
        } else if (!pet.isEgg() && confirmUntil == 0L && feedMenuUntil == 0L) {
            cardOpen = true
            cardPage = 0
        }
    }

    private fun onSwipe(dir: Int) {
        if (pet.awaitingStarter()) { starterStep(-dir); return }
        if (gameOpen || kbOpen || settingsOpen) return
        if (cardOpen) {
            val p = cardPage + if (dir > 0) -1 else 1
            cardPage = p.coerceIn(0, 3)
            return
        }
        if (!galleryOpen) {
            if (pet.ceremony == CER_NONE && confirmUntil == 0L) {
                galleryOpen = true
                galleryPage = 0
                galleryDetail = 0
            }
            return
        }
        if (galleryDetail != 0) {
            galleryDetail = 0
            galleryPmd = null
            return
        }
        val np = galleryPage - dir
        if (np < 0) {
            galleryOpen = false
            galleryPmd = null
            return
        }
        galleryPage = minOf(np, 9)
    }

    private fun onTap(x: Int, y: Int) {
        if (pet.awaitingStarter()) { starterTap(x, y); return }
        if (galleryOpen) { galleryTap(x, y); return }
        if (kbOpen) { keyboardTap(x, y); return }
        if (settingsOpen) { settingsTap(x, y); return }
        if (pet.ceremony != CER_NONE) return
        if (cardOpen) {
            if (cardPage == 0 && y < 84) openKeyboard()
            else if (cardPage == 1 && y in 300..340 && x in 96..370) {
                cardOpen = false
                startSack()
            } else {
                cardOpen = false
            }
            return
        }
        if (gameOpen) { gameTap(x, y); return }
        if (choiceKind != 0) {
            val b1 = x in 93..373 && y in 206..258
            val b2 = x in 93..373 && y in 268..320
            if (choiceKind == 1) {
                if (b1) {
                    val old = pet.speciesId
                    pet.evolve()
                    evoPmd = loadMon(old, pet.shiny)
                    monFor = -2 // load the new form
                } else if (b2) pet.declineEvolve()
            } else if (choiceKind == 2) {
                if (b1) pet.startFarewell() else if (b2) pet.declineFarewell()
            }
            choiceKind = 0
            return
        }
        if (confirmUntil != 0L) {
            if (timeLeft(confirmUntil) > 0 && x in 118..218 && y in 252..304) pet.release()
            confirmUntil = 0
            return
        }
        if (feedMenuUntil != 0L) {
            if (timeLeft(feedMenuUntil) > 0 && y in 288..352 && x in 101..365) {
                val item = ((x - 101) / 66).coerceAtMost(3)
                if (item == 3) pet.feedCandy() else pet.feedBerry(item)
                sfxPlay(Sfx.EAT)
            }
            feedMenuUntil = 0
            return
        }
        if (pet.isEgg()) {
            pet.eggTap()
            sfxPlay(Sfx.TAP)
            return
        }
        if (pet.wantEvolveButton() && x in EVO_BTN_X..EVO_BTN_X + EVO_BTN_W && y in EVO_BTN_Y..EVO_BTN_Y + EVO_BTN_H) {
            choiceKind = 1; choiceUntil = millis() + 12000
            return
        }
        if (x in FAR_BTN_X..FAR_BTN_X + FAR_BTN_W && y in FAR_BTN_Y..FAR_BTN_Y + FAR_BTN_H) {
            if (pet.canRunawayNow()) { pet.startRunaway(); return }
            if (pet.wantFarewellButton()) { choiceKind = 2; choiceUntil = millis() + 12000; return }
        }
        for (i in 0 until 4) {
            val dx = x - buttons[i].cx
            val dy = y - buttons[i].cy
            if (dx * dx + dy * dy <= BTN_HIT * BTN_HIT) {
                sfxPlay(Sfx.TAP)
                when (i) {
                    0 -> if (!pet.sleeping) feedMenuUntil = millis() + 6000
                    1 -> startGame()
                    2 -> pet.toggleLight()
                    else -> startBath()
                }
                return
            }
        }
        if (inPetZone(x, y)) {
            pet.caress()
            if (!pet.sleeping) sfxPlay(Sfx.HEART)
        }
    }

    // =====================================================================
    // scene
    // =====================================================================
    private fun inkColor() = if (gNight) Ui.INK_NIGHT else Ui.INK

    private fun sceneHour(): Int {
        val e = pet.lastSeenEpoch
        return if (e != 0L) ((e / 3600) % 24).toInt() else 13
    }

    private fun drawClouds(now: Long, col: Int) {
        for (k in 0 until 2) {
            val cx = ((now / 50 + k * 250) % 560).toInt() - 40
            val cy = 70 + k * 34
            g.fillCircle(cx, cy, 16, col)
            g.fillCircle(cx + 18, cy + 3, 13, col)
            g.fillCircle(cx - 15, cy + 4, 12, col)
        }
    }

    private fun skyColors(night: Boolean, h: Int): Pair<Int, Int> = when {
        night -> c565(0x0c, 0x12, 0x24) to c565(0x1e, 0x26, 0x46)
        h < 8 -> c565(0xd1, 0x6a, 0x86) to c565(0xf3, 0xb8, 0x7c)
        h < 18 -> c565(0x8f, 0xc8, 0xea) to c565(0xdc, 0xee, 0xe6)
        else -> c565(0xc7, 0x5a, 0x4a) to c565(0xf0, 0xae, 0x64)
    }

    private fun drawScene(biome: Int, now: Long, night: Boolean) {
        val h = sceneHour()
        val (top, bot) = skyColors(night, h)
        var y = 0
        while (y < HORIZON) {
            g.fillRect(0, y, 466, 8, lerpColor(top, bot, y, HORIZON))
            y += 8
        }
        if (night) {
            g.fillCircle(360, 78, 24, c565(0xe8, 0xee, 0xf5))
            g.fillCircle(370, 72, 22, lerpColor(top, bot, 78, HORIZON))
            for (st in STARS) g.fillRect(st[0], st[1], 4, 4, Ui.WHITE)
        } else if (h < 18) {
            g.fillCircle(360, 84, 26, if (h < 8) c565(0xff, 0xd9, 0x8a) else c565(0xff, 0xe7, 0x9f))
            drawClouds(now, c565(0xff, 0xff, 0xff))
        } else {
            g.fillCircle(233, HORIZON - 6, 34, c565(0xff, 0xf1, 0xc8))
        }

        var soil = BIOME_SOIL[if (biome < 6) biome else 0]
        if (night) soil = lerpColor(soil, c565(0x16, 0x1c, 0x30), 9, 16)
        if (biome == 1) {
            val sea = if (night) c565(0x1c, 0x34, 0x52) else c565(0x4f, 0x96, 0xc4)
            g.fillRect(0, HORIZON - 26, 466, 26, sea)
            for (i in 0 until 3) {
                val wy = HORIZON - 22 + i * 7
                val fc = if (night) c565(0x3a, 0x58, 0x78) else c565(0xbf, 0xe6, 0xf5)
                g.fillRect(60 + ((now / 60 + i * 30) % 60), wy, 26, 2, fc)
                g.fillRect(300 - ((now / 60 + i * 20) % 60), wy, 26, 2, fc)
            }
        }

        g.fillRect(0, HORIZON, 466, 466 - HORIZON, soil)
        val hill = lerpColor(soil, if (night) c565(0x0c, 0x12, 0x24) else c565(0xff, 0xff, 0xff), 3, 16)
        g.fillRoundRect(-60, HORIZON - 14, 586, 60, 30, hill)

        val dk = lerpColor(soil, c565(0x10, 0x18, 0x20), if (night) 11 else 7, 16)
        when (biome) {
            2 -> for (tx in intArrayOf(60, 150, 360, 416)) {
                g.fillTriangle(tx, HORIZON - 46, tx - 16, HORIZON, tx + 16, HORIZON, dk)
                g.fillTriangle(tx, HORIZON - 60, tx - 12, HORIZON - 28, tx + 12, HORIZON - 28, dk)
            }
            3 -> {
                g.fillTriangle(70, HORIZON, 40, HORIZON + 30, 100, HORIZON + 30, dk)
                g.fillTriangle(400, HORIZON + 4, 372, HORIZON + 30, 430, HORIZON + 30, dk)
                if (!night) for (e in 0 until 4)
                    g.fillRect(120 + e * 70, HORIZON + 8 + (e % 2) * 6, 4, 4, c565(0xff, 0x9b, 0x3a))
            }
            4 -> {
                g.fillTriangle(140, HORIZON - 50, 60, HORIZON, 220, HORIZON, dk)
                g.fillTriangle(330, HORIZON - 38, 250, HORIZON, 410, HORIZON, dk)
            }
            5 -> if (!night) for (f in 0 until 10) {
                val fx = (f * 53 + now / 40) % 466
                val fy = (f * 90 + now / 18) % HORIZON
                g.fillRect(fx, fy, 3, 3, Ui.WHITE)
            }
            0 -> for (gx in intArrayOf(80, 175, 300, 395)) for (b in -1..1)
                g.fillRect(gx + b * 5, HORIZON + 6, 2, 8 + if (b == 0) 4 else 0, dk)
        }
    }

    private fun roundBg() {
        g.fillScreen(0xFF000000.toInt())
        g.fillCircle(CX, CY, 231, Ui.BG_DAY)
    }

    // ---- starter choice: one starter at a time in its home biome ----
    private fun starterStep(dir: Int) {
        starterSel = (starterSel + dir + 3) % 3
        starterHopAt = millis()
        sfxPlay(Sfx.TAP)
    }

    private fun starterTap(x: Int, y: Int) {
        if (abs(y - STARTER_ARROW_Y) < 50 && x < STARTER_ARROW_X + 48) { starterStep(-1); return }
        if (abs(y - STARTER_ARROW_Y) < 50 && x > 466 - STARTER_ARROW_X - 48) { starterStep(1); return }
        if (abs(x - CX) < STARTER_BTN_W / 2 + 10 && y in STARTER_BTN_Y - 10..STARTER_BTN_Y + STARTER_BTN_H + 10) {
            pet.chooseStarter(STARTER_DEX[starterSel])
            starterPmd = null
            starterPmdFor = 0
            sfxPlay(Sfx.TAP)
            return
        }
        if (abs(x - CX) < 100 && y in 120..STARTER_GROUND + 10) starterHopAt = millis()
    }

    private fun renderStarterSelect() {
        val d = STARTER_DEX[starterSel]
        val acc = DexTables.ACCENT[d]
        val now = millis()
        val h = sceneHour()
        val night = h < 6 || h >= 20
        g.fillScreen(0xFF000000.toInt())
        drawScene(DexTables.BIOME[d], now, night)

        // title on a pill, page dots under it
        val t = T(S.CHOOSE_STARTER)
        val ts = if (g.textW(t, 2) <= 300) 2 else 1
        val tw = g.textW(t, ts) + 36
        g.fillRoundRect(CX - tw / 2, 40, tw, 40, 20, Ui.WHITE)
        g.textColor = Ui.INK
        g.setSize(ts); g.setCur(g.centerX(t, ts), if (ts == 2) 54 else 57); g.print(t)
        for (i in 0 until 3) {
            val dx = CX - 22 + i * 22
            g.fillCircle(dx, 98, if (i == starterSel) 8 else 6, if (i == starterSel) acc else Ui.INK)
            g.fillCircle(dx, 98, if (i == starterSel) 4 else 3, Ui.WHITE)
        }

        // the starter: a little hop when it comes on stage or is tapped
        val ht = now - starterHopAt
        val hop = if (ht in 0..359) (sin(ht * PI / 360) * 26).toInt() else 0
        val shadowW = 120 - hop * 2
        val soil = BIOME_SOIL[DexTables.BIOME[d]]
        g.fillRoundRect(CX - shadowW / 2, STARTER_GROUND - 8, shadowW, 16, 8,
            lerpColor(soil, 0xFF000000.toInt(), if (night) 10 else 5, 16))
        drawStarterMon(d, STARTER_GROUND - hop, now)

        // arrows
        for (side in intArrayOf(-1, 1)) {
            val ax = if (side < 0) STARTER_ARROW_X else 466 - STARTER_ARROW_X
            g.fillCircle(ax, STARTER_ARROW_Y, 26, Ui.WHITE)
            g.fillTriangle(ax + 9 * side, STARTER_ARROW_Y, ax - 7 * side, STARTER_ARROW_Y - 13,
                ax - 7 * side, STARTER_ARROW_Y + 13, acc)
        }

        // name on the starter's colour
        val nm = dexName(d)
        val ns = if (g.textW(nm, 3) <= 260) 3 else 2
        val nw = g.textW(nm, ns) + 44
        g.fillRoundRect(CX - nw / 2, 332, nw, 46, 23, acc)
        g.textColor = Ui.WHITE
        g.setSize(ns); g.setCur(g.centerX(nm, ns), if (ns == 3) 343 else 347); g.print(nm)

        // confirm: a white pill with a check
        val bx = CX - STARTER_BTN_W / 2
        g.fillRoundRect(bx, STARTER_BTN_Y + 4, STARTER_BTN_W, STARTER_BTN_H, 26, lerpColor(acc, 0xFF000000.toInt(), 5, 16))
        g.fillRoundRect(bx, STARTER_BTN_Y, STARTER_BTN_W, STARTER_BTN_H, 26, Ui.WHITE)
        drawCheck(CX, STARTER_BTN_Y + STARTER_BTN_H / 2, acc)
    }

    private fun drawStarterMon(d: Int, groundY: Int, now: Long) {
        if (starterPmdFor != d) {
            starterPmdFor = d
            starterPmd = loadMon(d, false)
        }
        val m = starterPmd
        val a = m?.mon?.acts?.get(PMD_IDLE)
        if (m != null && a != null) {
            // bigger than on the main screen: it's the star of this one
            val s = (240 / a.h).coerceIn(3, 7)
            g.drawBitmap(m.frame(PMD_IDLE, a.frameAt(now, true), false),
                CX - a.w * s / 2, groundY - a.base * s, a.w * s, a.h * s)
            return
        }
        val t = thumbs?.get(d)
        if (t != null) {
            g.drawBitmap(Art.thumb(t, false), CX - t.w * 2, groundY - t.h * 4, t.w * 4, t.h * 4)
            return
        }
        // no sprites installed: the built-in pixel art, blinking now and then
        val sp = SpriteTables.FLASH[d - 1]
        val x = CX - 16 * 5
        val y = groundY - 30 * 5
        drawMap(sp.sprite, x, y, 5, false)
        if (now % 3500 < 300) {
            overlayEye(sp, x, y, 5, sp.eyeL)
            overlayEye(sp, x, y, 5, sp.eyeR)
        }
    }

    private fun drawCheck(cx: Int, cy: Int, col: Int) {
        // two thick strokes: short down-right, long up-right
        g.fillTriangle(cx - 22, cy - 2, cx - 14, cy - 10, cx - 4, cy + 14, col)
        g.fillTriangle(cx - 14, cy - 10, cx + 4, cy + 4, cx - 4, cy + 14, col)
        g.fillTriangle(cx - 4, cy + 14, cx - 4, cy - 2, cx + 20, cy - 20, col)
        g.fillTriangle(cx - 4, cy + 14, cx + 20, cy - 20, cx + 26, cy - 12, col)
    }

    // =====================================================================
    // render
    // =====================================================================
    private fun render() {
        if (pet.awaitingStarter()) { renderStarterSelect(); return }
        if (galleryOpen) { renderGallery(); return }
        if (gameOpen) { renderGame(); return }
        if (sackOpen) { renderSack(); return }
        if (kbOpen) { renderKeyboard(); return }
        if (settingsOpen) { renderSettings(); return }
        if (cardOpen) { renderCard(); return }

        val h = sceneHour()
        gNight = pet.sleeping || h < 6 || h >= 20
        drawScene(if (pet.isEgg()) 0 else DexTables.BIOME[pet.speciesId], millis(), gNight)

        if (pet.ceremony != CER_NONE) {
            val msg = when (pet.ceremony) {
                CER_FAREWELL -> T(S.FAREWELL)
                CER_RUNAWAY -> T(S.RUNAWAY)
                else -> T(S.GOODBYE)
            }
            drawHeader(dexName(pet.speciesId), DexTables.ACCENT[pet.speciesId], msg)
            drawCeremony()
            return
        }

        if (pet.isEgg()) {
            drawHeader(T(S.EGG_HDR), inkColor(), eggMsg())
            val s = 5
            val x = CX - 16 * s
            val y = PET_CY - 16 * s
            drawMap(SpriteTables.SPR_EGG, x, y, s, false)
            if (pet.eggCracks() >= 1) for (c in CRACK1) g.fillRect(x + c[0] * s, y + c[1] * s, s, s, INK_K)
            if (pet.eggCracks() >= 2) for (c in CRACK2) g.fillRect(x + c[0] * s, y + c[1] * s, s, s, INK_K)
            if (pet.eggRarity() >= R_RARO) {
                val rar = if (pet.eggRarity() == R_LEGENDARIO) T(S.EGG_LEGEND) else T(S.EGG_RARE)
                g.textColor = if (pet.eggRarity() == R_LEGENDARIO) Ui.BAR_WARN else rgb565ToArgb(0x4C98)
                g.setSize(2); g.setCur(g.centerX(rar, 2), 316); g.print(rar)
            }
            val reg = Text.f(S.POKEDEX_FMT, pet.registeredCount())
            g.fillRect(0, 312, 466, 154, if (gNight) Ui.BG_NIGHT else Ui.BG_DAY)
            g.textColor = inkColor()
            g.setSize(2); g.setCur(g.centerX(reg, 2), 348); g.print(reg)
        } else {
            val base = pet.nick.ifEmpty { dexName(pet.speciesId) }
            val name = Text.f(S.NAME_FMT, if (pet.shiny) "*" else "", base, pet.level())
            drawHeader(name, if (gNight) Ui.INK_NIGHT else DexTables.ACCENT[pet.speciesId], statusMsg())
            drawStreakBadge()
            drawPet()
            drawBath()
            drawPoops()
            g.fillRect(0, 312, 466, 154, if (gNight) Ui.BG_NIGHT else Ui.BG_DAY)
            drawBars()
            drawButtons()
            drawCelebration()
            if (pet.wantEvolveButton()) drawEvolveButton()
            else if (pet.canRunawayNow()) drawRunawayButton()
            else if (pet.wantFarewellButton()) drawFarewellButton()
        }

        if (pet.sleeping) {
            g.textColor = Ui.INK_NIGHT
            g.setSize(3); g.setCur(320, 130); g.print("Zz")
        }

        if (feedMenuUntil != 0L) {
            if (timeLeft(feedMenuUntil) == 0L) {
                feedMenuUntil = 0
            } else {
                g.fillRoundRect(101, 288, 264, 64, 14, Ui.WHITE)
                g.drawRoundRect(101, 288, 264, 64, 14, inkColor())
                drawMap(SpriteTables.SPR_ICON_FOOD, 110, 296, 3, false)
                drawMap(SpriteTables.SPR_ICON_BERRY_B, 176, 296, 3, false)
                drawMap(SpriteTables.SPR_ICON_BERRY_G, 242, 296, 3, false)
                drawMap(SpriteTables.SPR_ICON_CANDY, 308, 296, 3, false)
            }
        }

        if (confirmUntil != 0L) {
            if (timeLeft(confirmUntil) == 0L) {
                confirmUntil = 0
            } else {
                g.fillRoundRect(94, 168, 278, 152, 16, Ui.WHITE)
                g.drawRoundRect(94, 168, 278, 152, 16, Ui.INK)
                val q = Text.f(S.RELEASE_FMT, dexName(pet.speciesId))
                g.textColor = Ui.INK
                g.setSize(2); g.setCur(g.centerX(q, 2), 196); g.print(q)
                g.fillRoundRect(118, 252, 100, 52, 12, Ui.BAR_OK)
                g.textColor = Ui.WHITE
                g.setCur(118 + (100 - g.textW(T(S.YES), 2)) / 2, 270); g.print(T(S.YES))
                g.fillRoundRect(248, 252, 100, 52, 12, Ui.BAR_BAD)
                g.setCur(248 + (100 - g.textW(T(S.NO), 2)) / 2, 270); g.print(T(S.NO))
            }
        }

        if (choiceKind != 0) {
            if (timeLeft(choiceUntil) == 0L) choiceKind = 0 else drawChoiceDialog()
        }
    }

    // =====================================================================
    // minigame: keep the ball in the air
    // =====================================================================
    private fun startGame() {
        if (pet.isEgg() || pet.sleeping || pet.ceremony != CER_NONE) return
        gameOpen = true
        gameOverUntil = 0
        gameScore = 0
        gameMisses = 0
        gameNewHi = false
        hitTime = 0
        gamePetX = 233f
        lastGameStep = millis()
        respawnBall()
    }

    private fun respawnBall() {
        ballX = (150 + random(166)).toFloat()
        ballY = 96f
        val sp = minOf(1.6f + gameScore * 0.05f, 4.0f)
        ballVX = if (random(2) == 1) sp else -sp
        ballVY = 0f
    }

    private fun gameTap(x: Int, y: Int) {
        if (gameOverUntil != 0L) return
        if (y < 72) { gameOpen = false; return }
        val dx = ballX - x
        val dy = ballY - y
        if (dx * dx + dy * dy < 74 * 74) {
            gameScore++
            sfxPlay(Sfx.PLAY)
            val lift = 6.6f + if (gameScore > 16) 3.5f else gameScore * 0.22f
            ballVY = -lift
            ballVX = (ballVX + dx * 0.12f).coerceIn(-6.5f, 6.5f)
            hitX = ballX
            hitY = ballY
            hitTime = millis()
        }
    }

    private fun stepGame() {
        val now = millis()
        val k = if (lastGameStep != 0L) minOf((now - lastGameStep) / 85f, 3f) else 1f
        lastGameStep = now

        val grav = minOf(0.40f + gameScore * 0.013f, 0.80f)
        ballVY += grav * k
        ballX += ballVX * k
        ballY += ballVY * k
        val dx = ballX - CX
        val dy = ballY - CY
        val d = sqrt(dx * dx + dy * dy)
        if (d > 205) {
            val nx = dx / d
            val ny = dy / d
            val dot = ballVX * nx + ballVY * ny
            if (dot > 0) {
                ballVX = (ballVX - 2 * dot * nx) * 0.85f
                ballVY = (ballVY - 2 * dot * ny) * 0.85f
            }
            ballX = CX + nx * 205
            ballY = CY + ny * 205
        }
        if (ballY > 384) {
            if (++gameMisses >= 3) {
                gameNewHi = gameScore > pet.gameHi
                pet.playResult(gameScore)
                sfxPlay(if (gameNewHi && gameScore > 0) Sfx.MEDAL else Sfx.LEVEL)
                gameOverUntil = millis() + 4000
            } else {
                respawnBall()
            }
        }
        val chase = ((ballX - gamePetX) * 0.12f).coerceIn(-7f, 7f)
        gamePetX += chase * k
    }

    private fun drawGameScene() {
        val hh = sceneHour()
        val night = hh < 6 || hh >= 20
        val (top, bot) = skyColors(night, hh)
        val hor = 376
        var y = 0
        while (y < hor) {
            g.fillRect(0, y, 466, 8, lerpColor(top, bot, y, hor))
            y += 8
        }
        if (night) for (st in STARS) g.fillRect(st[0], st[1], 4, 4, Ui.WHITE)
        val bio = if (pet.isEgg()) 0 else DexTables.BIOME[pet.speciesId]
        var soil = BIOME_SOIL[if (bio < 6) bio else 0]
        if (night) soil = lerpColor(soil, c565(0x16, 0x1c, 0x30), 9, 16)
        g.fillRect(0, hor, 466, 466 - hor, soil)
    }

    private fun renderGame() {
        val night = sceneHour() < 6 || sceneHour() >= 20
        val ink = if (night) Ui.INK_NIGHT else Ui.INK

        if (gameOverUntil != 0L) {
            drawGameScene()
            if (timeLeft(gameOverUntil) == 0L) { gameOpen = false; return }
            val buf = Text.f(S.SCORE_FMT, gameScore)
            g.textColor = ink
            g.setSize(4); g.setCur(g.centerX(buf, 4), 160); g.print(buf)
            g.setSize(2)
            if (gameNewHi && gameScore > 0) {
                g.textColor = Ui.BAR_WARN
                g.setCur(g.centerX(T(S.NEW_RECORD), 2), 214); g.print(T(S.NEW_RECORD))
            } else {
                val rec = Text.f(S.RECORD_FMT, pet.gameHi)
                g.textColor = ink
                g.setCur(g.centerX(rec, 2), 214); g.print(rec)
            }
            val msg = if (gameScore >= 10) T(S.GREAT_JOY) else T(S.PLUS_JOY)
            g.textColor = ink
            g.setCur(g.centerX(msg, 2), 250); g.print(msg)
            return
        }

        drawGameScene()
        stepGame()

        val buf = gameScore.toString()
        g.textColor = ink
        g.setSize(4); g.setCur(g.centerX(buf, 4), 30); g.print(buf)
        val rec = Text.f(S.REC_FMT, pet.gameHi)
        g.setSize(2); g.setCur(g.centerX(rec, 2), 76); g.print(rec)
        for (i in 0 until 3) {
            if (i < 3 - gameMisses) g.fillCircle(180 + i * 28, 104, 6, Ui.BAR_BAD)
            else g.drawCircle(180 + i * 28, 104, 6, Ui.TRACK)
        }

        val m = pmd
        if (m != null) {
            var act = if (ballX > gamePetX + 4) PMD_WALKR else if (ballX < gamePetX - 4) PMD_WALKL else PMD_IDLE
            if (!m.mon.has(act)) act = PMD_IDLE
            drawPmdAct(m, act, gamePetX.toInt(), 394, millis(), true, false, 3)
        } else {
            drawFlashPet(gamePetX.toInt(), 394 - 80, 2)
        }

        val ht = millis() - hitTime
        if (hitTime != 0L && ht < 260) {
            val rad = 22 + (ht / 6).toInt()
            g.drawCircle(hitX, hitY, rad, c565(0xff, 0xe7, 0x9f))
            g.drawCircle(hitX, hitY, rad - 2, c565(0xff, 0xd9, 0x8a))
        }

        drawMap(SpriteTables.SPR_ICON_PLAY, ballX.toInt() - 24, ballY.toInt() - 24, 3, false)
    }

    // =====================================================================
    // training bag
    // =====================================================================
    private fun startSack() {
        if (pet.isEgg() || pet.sleeping || pet.ceremony != CER_NONE) return
        sackOpen = true
        sackUntil = millis() + 10000
        sackOverUntil = 0
        sackHits = 0
        sackShake = 0f
        sackNewHi = false
    }

    private fun sackTap() {
        if (timeLeft(sackUntil) == 0L) return
        sackHits++
        sackShake = 16f
    }

    private fun renderSack() {
        val now = millis()
        drawGameScene()
        val night = sceneHour() < 6 || sceneHour() >= 20
        val ink = if (night) Ui.INK_NIGHT else Ui.INK

        if (sackOverUntil != 0L) {
            if (timeLeft(sackOverUntil) == 0L) { sackOpen = false; return }
            val b = Text.f(S.HITS_FMT, sackHits)
            g.textColor = ink
            g.setSize(4); g.setCur(g.centerX(b, 4), 150); g.print(b)
            val gs = Text.f(S.STR_GAIN_FMT, sackGain)
            g.textColor = Ui.BAR_BAD
            g.setSize(3); g.setCur(g.centerX(gs, 3), 210); g.print(gs)
            g.setSize(2)
            if (sackNewHi && sackHits > 0) {
                g.textColor = Ui.BAR_WARN
                g.setCur(g.centerX(T(S.NEW_RECORD), 2), 256); g.print(T(S.NEW_RECORD))
            } else {
                val r = Text.f(S.RECORD_FMT, pet.strHi)
                g.textColor = ink
                g.setCur(g.centerX(r, 2), 256); g.print(r)
            }
            return
        }

        if (timeLeft(sackUntil) == 0L) {
            sackNewHi = sackHits > pet.strHi
            sackGain = pet.trainStrength(sackHits)
            sfxPlay(if (sackNewHi) Sfx.MEDAL else Sfx.PLAY)
            sackOverUntil = now + 3500
            return
        }

        sackShake *= 0.84f
        val off = (sackShake * sin(now * 0.05f)).toInt()
        val sx = CX + off
        val top = 86
        g.fillRect(CX - 3, 56, 6, top - 56, ink)
        g.fillRect(sx - 4, top - 30, 8, 34, ink)
        g.fillRoundRect(sx - 42, top, 84, 150, 26, c565(0xb5, 0x3a, 0x3a))
        g.fillRoundRect(sx - 42, top, 84, 22, 18, c565(0x7e, 0x28, 0x28))
        g.drawRoundRect(sx - 42, top, 84, 150, 26, ink)
        g.fillRect(sx - 42, top + 70, 84, 4, c565(0x7e, 0x28, 0x28))

        val buf = sackHits.toString()
        g.textColor = ink
        g.setSize(6); g.setCur(g.centerX(buf, 6), 268); g.print(buf)
        g.setSize(2); g.setCur(g.centerX(T(S.HIT_FAST), 2), 322); g.print(T(S.HIT_FAST))

        val left = sackUntil - now
        val bw = 280
        val fw = (bw * left / 10000).toInt()
        g.fillRoundRect(CX - bw / 2, 350, bw, 16, 5, Ui.TRACK)
        if (fw > 2) g.fillRoundRect(CX - bw / 2, 350, fw, 16, 5, Ui.BAR_OK)
    }

    // =====================================================================
    // card (swipe up)
    // =====================================================================
    private fun statBarX(): Int {
        var w = 0
        for (id in arrayOf(S.STAT_ATK, S.STAT_DEF, S.STAT_SPE, S.STAT_WGT, S.VIN)) w = maxOf(w, g.textW(T(id), 2))
        return maxOf(150, 96 + w + 12)
    }

    private fun drawCardStat(y: Int, label: String, v: Int, maxBar: Int, color: Int) {
        g.textColor = Ui.INK
        g.setSize(2); g.setCur(96, y); g.print(label)
        g.setCur(330, y); g.print(v.toString())
        val bx = statBarX()
        val bw = 310 - bx
        val fw = minOf(v * bw / maxBar, bw)
        g.fillRoundRect(bx, y + 2, bw, 11, 3, Ui.TRACK)
        if (fw > 2) g.fillRoundRect(bx, y + 2, fw, 11, 3, color)
    }

    private fun drawStreakBadge() {
        if (pet.streak < 1) return
        val x = 26
        val y = 16
        g.fillTriangle(x + 8, y, x + 1, y + 17, x + 15, y + 17, Ui.BAR_BAD)
        g.fillTriangle(x + 8, y + 7, x + 4, y + 17, x + 12, y + 17, Ui.BAR_WARN)
        g.textColor = inkColor()
        g.setSize(2); g.setCur(x + 22, y + 2); g.print(pet.streak.toString())
    }

    private fun drawCelebration() {
        val l1: String
        val l2: String
        if (pet.showMedal()) {
            var name = ""
            for (i in 0 until MED_COUNT) if ((pet.newMedal and (1 shl i)) != 0) { name = Text.medalName(i); break }
            l1 = T(S.MEDAL_BANNER); l2 = name
        } else if (pet.showMilestone()) {
            l1 = T(S.GREAT); l2 = Text.f(S.STREAK_DAYS_FMT, pet.streak)
        } else return
        g.fillRoundRect(73, 150, 320, 96, 16, Ui.BAR_WARN)
        g.drawRoundRect(73, 150, 320, 96, 16, Ui.INK)
        g.textColor = Ui.INK
        g.setSize(3); g.setCur(g.centerX(l1, 3), 176); g.print(l1)
        g.setSize(2); g.setCur(g.centerX(l2, 2), 212); g.print(l2)
    }

    private fun renderCardProfile() {
        val nm = pet.nick.ifEmpty { dexName(pet.speciesId) }
        val head = Text.f(S.NAME_FMT, if (pet.shiny) "*" else "", nm, pet.level())
        g.textColor = DexTables.ACCENT[pet.speciesId]
        val hts = if (g.textW(head, 3) <= 198) 3 else 2
        g.setSize(hts); g.setCur(g.centerX(head, hts), if (hts == 3) 34 else 40); g.print(head)
        if (pet.nick.isNotEmpty()) {
            val par = "(${dexName(pet.speciesId)})"
            g.textColor = Ui.TRACK
            g.setSize(2); g.setCur(g.centerX(par, 2), 64); g.print(par)
        }
        pmd?.let { drawPmdAct(it, PMD_IDLE, CX, 206, millis(), true, false, 4) }

        val sx = 138
        val sy = 224
        g.fillTriangle(sx + 8, sy, sx + 1, sy + 18, sx + 15, sy + 18, Ui.BAR_BAD)
        g.fillTriangle(sx + 8, sy + 7, sx + 4, sy + 18, sx + 12, sy + 18, Ui.BAR_WARN)
        val rl = Text.f(S.STREAK_FMT, pet.streak, pet.bestStreak)
        g.textColor = Ui.INK
        g.setSize(2); g.setCur(sx + 24, sy + 2); g.print(rl)

        drawCardStat(258, T(S.VIN), pet.bond, 100, c565(0xd4, 0x52, 0x7e))

        val berry = when {
            !pet.berryKnown -> T(S.BERRY_UNK)
            pet.lovesBerry(0) -> T(S.BERRY_RED)
            pet.lovesBerry(1) -> T(S.BERRY_BLUE)
            else -> T(S.BERRY_GREEN)
        }
        val info = Text.f(S.INFO_FMT, berry, pet.ageMinutes / 1440)
        g.textColor = Ui.INK
        g.setSize(2); g.setCur(g.centerX(info, 2), 296); g.print(info)
        g.textColor = Ui.TRACK
        g.setCur(g.centerX(T(S.RENAME_HINT), 2), 332); g.print(T(S.RENAME_HINT))
    }

    private fun renderCardStats() {
        g.textColor = Ui.INK
        g.setSize(3); g.setCur(g.centerX(T(S.BATTLE), 3), 48); g.print(T(S.BATTLE))
        drawCardStat(118, T(S.STAT_ATK), pet.atkStat(), 260, Ui.BAR_BAD)
        drawCardStat(160, T(S.STAT_DEF), pet.defStat(), 260, rgb565ToArgb(0x4C98))
        drawCardStat(202, T(S.STAT_SPE), pet.speStat(), 260, Ui.BAR_WARN)
        drawCardStat(244, T(S.STAT_WGT), pet.weight, 100, rgb565ToArgb(0xB3C8))
        g.fillRoundRect(96, 300, 274, 40, 12, Ui.BAR_BAD)
        g.textColor = Ui.BG_DAY
        g.setSize(2); g.setCur(g.centerX(T(S.TRAIN_STR), 2), 311); g.print(T(S.TRAIN_STR))
    }

    private fun renderCardMedals() {
        val got = (0 until MED_COUNT).count { pet.hasMedal(1 shl it) }
        val head = Text.f(S.MEDALS_FMT, got, MED_COUNT)
        g.textColor = Ui.INK
        g.setSize(3); g.setCur(g.centerX(head, 3), 48); g.print(head)
        for (i in 0 until MED_COUNT) {
            val x = 28 + (i % 2) * 206
            val y = 104 + (i / 2) * 54
            val gm = pet.hasMedal(1 shl i)
            g.fillRoundRect(x, y, 196, 44, 10, if (gm) Ui.BAR_OK else Ui.TRACK)
            if (gm) {
                g.fillCircle(x + 22, y + 22, 11, Ui.BG_DAY)
                g.textColor = Ui.BAR_OK
                g.setSize(2); g.setCur(x + 16, y + 13); g.print("v")
            }
            g.textColor = if (gm) Ui.BG_DAY else rgb565ToArgb(0x8410)
            g.setSize(2); g.setCur(x + 44, y + 14); g.print(Text.medalDesc(i))
        }
    }

    private fun renderCardProgress() {
        val sp = pet.speciesId
        g.textColor = Ui.INK
        g.setSize(3); g.setCur(g.centerX(T(S.PROGRESS), 3), 44); g.print(T(S.PROGRESS))
        val lv = Text.f(S.LVL_FMT, pet.level())
        g.setSize(5); g.setCur(g.centerX(lv, 5), 86); g.print(lv)

        val into = (pet.ageMinutes % MINUTES_PER_LEVEL).toInt()
        val bx = 93; val bw = 280; val by = 158; val bh = 22
        g.fillRoundRect(bx, by, bw, bh, 6, Ui.TRACK)
        val fw = (bw - 4) * into / MINUTES_PER_LEVEL
        if (fw > 0) g.fillRoundRect(bx + 2, by + 2, fw, bh - 4, 5, Ui.BAR_OK)
        val nx = Text.f(S.NEXT_LVL_FMT, MINUTES_PER_LEVEL - into, pet.level() + 1)
        g.textColor = Ui.INK
        g.setSize(2); g.setCur(g.centerX(nx, 2), by + 32); g.print(nx)

        g.textColor = Ui.TRACK
        g.setCur(g.centerX(T(S.EVO_LABEL), 2), 230); g.print(T(S.EVO_LABEL))
        var evoCol = Ui.INK
        val evo = if (DexTables.EVOLVES_TO[sp] == 0) {
            T(S.FINAL_FORM)
        } else {
            val needed = DexTables.EVOLVE_LEVEL[sp] + pet.careMistakes
            if (pet.level() >= needed) {
                if (pet.lowestStat() >= 40) { evoCol = Ui.BAR_OK; T(S.EVO_READY) }
                else { evoCol = Ui.BAR_BAD; T(S.EVO_BLOCKED) }
            } else Text.f(S.EVO_IN_FMT, needed - pet.level())
        }
        g.textColor = evoCol
        g.setCur(g.centerX(evo, 2), 256); g.print(evo)
        val ms = Text.f(S.MISTAKES_FMT, pet.careMistakes)
        g.textColor = if (pet.careMistakes > 0) Ui.BAR_BAD else Ui.INK
        g.setCur(g.centerX(ms, 2), 312); g.print(ms)
    }

    private fun renderCard() {
        roundBg()
        when (cardPage) {
            0 -> renderCardProfile()
            1 -> renderCardStats()
            2 -> renderCardMedals()
            else -> renderCardProgress()
        }
        for (i in 0 until 4) {
            if (i == cardPage) g.fillCircle(194 + i * 26, 374, 5, Ui.INK)
            else g.drawCircle(194 + i * 26, 374, 4, Ui.INK)
        }
        g.textColor = Ui.TRACK
        g.setSize(2); g.setCur(g.centerX(T(S.BACK), 2), 398); g.print(T(S.BACK))
    }

    // =====================================================================
    // settings (swipe down). The firmware's "set time" screen: the watch
    // already knows the time, so only sound and language remain.
    // =====================================================================
    private fun renderSettings() {
        roundBg()
        g.textColor = Ui.INK
        val clock = "%02d:%02d".format(((pet.lastSeenEpoch / 3600) % 24).toInt(), ((pet.lastSeenEpoch / 60) % 60).toInt())
        g.setSize(7); g.setCur(g.centerX(clock, 7), 90); g.print(clock)

        val snd = sound.enabled
        val sl = if (snd) T(S.SND_ON) else T(S.SND_OFF)
        g.fillRoundRect(84, SET_PILL_Y, 140, SET_PILL_H, 10, if (snd) Ui.BAR_OK else Ui.WHITE)
        g.drawRoundRect(84, SET_PILL_Y, 140, SET_PILL_H, 10, Ui.INK)
        g.textColor = if (snd) Ui.BG_DAY else Ui.INK
        g.setSize(2); g.setCur(84 + (140 - g.textW(sl, 2)) / 2, SET_PILL_Y + 15); g.print(sl)

        g.fillRoundRect(242, SET_PILL_Y, 140, SET_PILL_H, 10, Ui.WHITE)
        g.drawRoundRect(242, SET_PILL_Y, 140, SET_PILL_H, 10, Ui.INK)
        val lp = "${T(S.LANG_LABEL)} ${StringTables.LANG_CODES[Text.lang]} >"
        g.textColor = Ui.INK
        g.setSize(2); g.setCur(242 + (140 - g.textW(lp, 2)) / 2, SET_PILL_Y + 15); g.print(lp)

        g.textColor = Ui.TRACK
        g.setSize(2)
        val back = T(S.CLOCK_CANCEL)
        g.setCur(g.centerX(back, 2), 330); g.print(back)
        g.setSize(1)
        val ver = "PokeWatch 1.0 - TamaPoke v1.18 port"
        g.setCur(g.centerX(ver, 1), 410); g.print(ver)
    }

    private fun settingsTap(x: Int, y: Int) {
        if (y in SET_PILL_Y..SET_PILL_Y + SET_PILL_H) {
            if (x in 84..224) {
                sound.enabled = !sound.enabled
                if (sound.enabled) sfxPlay(Sfx.TAP)
                return
            }
            if (x in 242..382) {
                Text.lang = (Text.lang + 1) % Text.LANG_COUNT
                context.getSharedPreferences("tamapoke", Context.MODE_PRIVATE).edit().putInt("lang", Text.lang).apply()
                sfxPlay(Sfx.TAP)
                return
            }
        }
        settingsOpen = false
    }

    // =====================================================================
    // rename keyboard
    // =====================================================================
    private fun openKeyboard() {
        kbOpen = true
        nameBuf = pet.nick
    }

    private fun renderKeyboard() {
        roundBg()
        g.textColor = Ui.INK
        g.setSize(2); g.setCur(g.centerX(T(S.NAME), 2), 56); g.print(T(S.NAME))
        g.fillRoundRect(83, 84, 300, 40, 8, Ui.WHITE)
        g.drawRoundRect(83, 84, 300, 40, 8, Ui.INK)
        g.setSize(3); g.setCur(95, 94); g.print(nameBuf.ifEmpty { "_" })
        for (i in 0 until 30) {
            val x = KB_X + (i % KB_COLS) * KB_W
            val y = KB_Y + (i / KB_COLS) * KB_H
            g.fillRoundRect(x, y, KB_W - 6, KB_H - 6, 6, if (i >= 28) Ui.BAR_WARN else Ui.WHITE)
            g.drawRoundRect(x, y, KB_W - 6, KB_H - 6, 6, Ui.INK)
            g.textColor = Ui.INK
            g.setSize(2)
            if (i < 28) {
                g.setCur(x + KB_W / 2 - 9, y + KB_H / 2 - 10); g.print(KB_KEYS[i].toString())
            } else {
                g.setCur(x + KB_W / 2 - 15, y + KB_H / 2 - 10); g.print(if (i == 28) "<-" else "OK")
            }
        }
    }

    private fun keyboardTap(x: Int, y: Int) {
        if (x < KB_X || y < KB_Y) return
        val col = (x - KB_X) / KB_W
        val row = (y - KB_Y) / KB_H
        if (col >= KB_COLS || row >= 5) return
        val i = row * KB_COLS + col
        when {
            i >= 30 -> return
            i == 28 -> if (nameBuf.isNotEmpty()) nameBuf = nameBuf.dropLast(1)
            i == 29 -> { pet.rename(nameBuf); kbOpen = false }
            nameBuf.length < 11 -> nameBuf += KB_KEYS[i]
        }
    }

    // =====================================================================
    // Pokédex gallery (swipe sideways)
    // =====================================================================
    private fun drawThumb(t: Thumb, x: Int, y: Int, s: Int, sil: Boolean) {
        val ox = x + (GAL_CELL - t.w * s) / 2
        val oy = y + (GAL_CELL - t.h * s) / 2
        g.drawBitmap(Art.thumb(t, sil), ox, oy, t.w * s, t.h * s)
    }

    private fun renderGallery() {
        roundBg()
        if (galleryDetail != 0) {
            val d = galleryDetail
            val reg = pet.isRegistered(d)
            val head = "N.%03d %s%s".format(d, if (pet.isShinyRegistered(d)) "*" else "", if (reg) dexName(d) else "???")
            g.textColor = if (reg) DexTables.ACCENT[d] else Ui.INK
            val gts = if (g.textW(head, 3) <= 234) 3 else 2
            g.setSize(gts); g.setCur(g.centerX(head, gts), if (gts == 3) 56 else 60); g.print(head)
            val gp = galleryPmd
            if (gp != null) {
                drawPmdAct(gp, PMD_IDLE, CX, 300, if (reg) millis() else 0, true, !reg, 6)
            } else {
                thumbs?.get(d)?.let { drawThumb(it, CX - GAL_CELL, 135, 4, !reg) }
            }
            g.textColor = Ui.INK
            g.setSize(2); g.setCur(g.centerX(T(S.DETAIL_BACK), 2), 408); g.print(T(S.DETAIL_BACK))
            return
        }

        val head = Text.f(S.POKEDEX_FMT, pet.registeredCount())
        g.textColor = Ui.INK
        g.setSize(3); g.setCur(g.centerX(head, 3), 36); g.print(head)
        for (r in 0 until 4) for (c in 0 until 4) {
            val dex = galleryPage * 16 + r * 4 + c + 1
            if (dex > 151) break
            val x = GAL_X + c * GAL_CELL
            val y = GAL_Y + r * GAL_CELL
            val t = thumbs?.get(dex)
            if (t != null) {
                drawThumb(t, x, y, 2, !pet.isRegistered(dex))
                if (pet.isShinyRegistered(dex)) {
                    g.textColor = Ui.BAR_WARN
                    g.setSize(2); g.setCur(x + 62, y + 4); g.print("*")
                }
            } else {
                g.textColor = if (pet.isRegistered(dex)) Ui.INK else Ui.TRACK
                g.setSize(2); g.setCur(x + 24, y + 32); g.print(dex.toString())
            }
        }
        for (i in 0 until 10) {
            if (i == galleryPage) g.fillCircle(170 + i * 14, 436, 4, Ui.INK)
            else g.drawCircle(170 + i * 14, 436, 3, Ui.INK)
        }
    }

    private fun galleryTap(x: Int, y: Int) {
        if (galleryDetail != 0) {
            galleryDetail = 0
            galleryPmd = null
            return
        }
        if (y < 72) {
            galleryOpen = false
            galleryPmd = null
            return
        }
        if (x < GAL_X || y < GAL_Y) return
        val c = (x - GAL_X) / GAL_CELL
        val r = (y - GAL_Y) / GAL_CELL
        if (c > 3 || r > 3) return
        val dex = galleryPage * 16 + r * 4 + c + 1
        if (dex > 151) return
        galleryDetail = dex
        galleryPmd = loadMon(dex, pet.isShinyRegistered(dex))
    }

    // =====================================================================
    // header, ceremonies, dialogs
    // =====================================================================
    private fun drawBattery() {
        val pc = battery.percent
        if (pc < 0) return
        val x = CX - 14; val y = 12; val w = 24; val h = 11
        val charging = battery.charging
        val col = when {
            charging -> Ui.BAR_OK
            pc >= 40 -> inkColor()
            pc >= 15 -> Ui.BAR_WARN
            else -> Ui.BAR_BAD
        }
        g.drawRoundRect(x, y, w, h, 2, col)
        g.fillRect(x + w, y + 3, 3, 5, col)
        if (charging) {
            val bolt = c565(0xff, 0xd9, 0x4a)
            val bx = x + w / 2
            g.fillTriangle(bx + 3, y + 1, bx - 4, y + 6, bx + 1, y + 6, bolt)
            g.fillTriangle(bx - 1, y + 5, bx + 4, y + 5, bx - 3, y + 10, bolt)
        } else {
            val fw = (w - 4) * pc / 100
            if (fw > 0) g.fillRect(x + 2, y + 2, fw, h - 4, col)
        }
    }

    private fun drawHeader(name: String, nameColor: Int, msg: String) {
        drawBattery()
        g.textColor = nameColor
        g.setSize(3); g.setCur(g.centerX(name, 3), 52); g.print(name)
        g.textColor = inkColor()
        g.setSize(2); g.setCur(g.centerX(msg, 2), 90); g.print(msg)
    }

    private fun drawCeremony() {
        val m = pmd
        if (m == null) { drawPet(); return }
        val now = millis()
        val t = pet.ceremonyT()
        var x = CX
        val y = PET_GROUND
        var act: Int

        if (pet.ceremony == CER_RUNAWAY) {
            for (i in 0 until 46) {
                val rx = ((i * 47 + now / 3) % 466).toInt()
                val ry = ((i * 91 + now / 2) % 470).toInt()
                g.drawLine(rx, ry, rx - 3, ry + 12, c565(0x6a, 0x84, 0xb0))
            }
            var fade = false
            if (t < 0.30f) {
                act = if (m.mon.has(PMD_HURT)) PMD_HURT else PMD_IDLE
                x = CX + (4 * sin(now * 0.04f)).toInt()
            } else {
                act = if (m.mon.has(PMD_WALKL)) PMD_WALKL else PMD_IDLE
                x = CX - (((t - 0.30f) / 0.70f) * (CX + 120)).toInt()
                fade = t > 0.6f && (now / 160) % 2 == 0L
            }
            drawPmdAct(m, act, x, y, now, true, fade, 5)
            if (t < 0.55f) {
                val ty = y - 150 + ((now / 6) % 40).toInt()
                g.fillRect(x + 6, ty, 3, 6, c565(0x9a, 0xc4, 0xe8))
            }
            return
        }

        val gcy = PET_GROUND - 96
        for (k in 0 until 4) {
            val r = 60 + k * 34 + (10 * sin(now * 0.02f)).toInt()
            g.drawCircle(CX, gcy, r, c565(0xff, 0xdf, 0x8a))
        }
        for (i in 0 until 16) {
            val px = (i * 71 + 28) % 466
            val py = 410 - ((now / 8 + i * 70) % 360).toInt()
            if (py < 30) continue
            if (i % 4 == 0) drawMap(SpriteTables.SPR_HEART, px - 8, py - 8, 1, false)
            else g.fillRect(px, py, 4, 4, if (i % 2 == 1) c565(0xff, 0xe7, 0x9f) else c565(0xff, 0x9a, 0xc0))
        }
        if (t < 0.45f) {
            act = if (m.mon.has(PMD_POSE)) PMD_POSE else if (m.mon.has(PMD_NOD)) PMD_NOD else PMD_IDLE
        } else {
            act = if (m.mon.has(PMD_WALKR)) PMD_WALKR else PMD_IDLE
            x = CX + (((t - 0.45f) / 0.55f) * (CX + 140)).toInt()
        }
        drawPmdAct(m, act, x, y, now, true, false, 5)
        if (pet.showHeart()) drawMap(SpriteTables.SPR_HEART, x + 50, y - 190, 2, false)
    }

    private fun drawChoiceDialog() {
        val q: String; val o1: String; val o2: String
        val c1: Int; val c2: Int; val t1: Int; val t2: Int
        if (choiceKind == 1) {
            q = T(S.EVO_Q); o1 = T(S.EVO_TAP); o2 = T(S.EVO_KEEP)
            c1 = Ui.BAR_BAD; t1 = Ui.WHITE; c2 = Ui.TRACK; t2 = Ui.INK
        } else {
            q = T(S.FAR_Q); o1 = T(S.FAR_GO); o2 = T(S.FAR_STAY)
            c1 = Ui.BAR_WARN; t1 = Ui.INK; c2 = Ui.BAR_OK; t2 = Ui.WHITE
        }
        g.fillRoundRect(73, 156, 320, 188, 16, Ui.WHITE)
        g.drawRoundRect(73, 156, 320, 188, 16, Ui.INK)
        g.textColor = Ui.INK
        g.setSize(2); g.setCur(g.centerX(q, 2), 176); g.print(q)
        g.fillRoundRect(93, 206, 280, 52, 12, c1)
        g.textColor = t1
        g.setCur(g.centerX(o1, 2), 224); g.print(o1)
        g.fillRoundRect(93, 268, 280, 52, 12, c2)
        g.textColor = t2
        g.setCur(g.centerX(o2, 2), 286); g.print(o2)
    }

    private fun drawEvolveButton() {
        val p = (5 * sin(millis() * 0.006f)).toInt()
        val x = EVO_BTN_X - p; val y = EVO_BTN_Y - p; val w = EVO_BTN_W + 2 * p; val h = EVO_BTN_H + 2 * p
        g.fillRoundRect(x, y, w, h, 18, Ui.BAR_BAD)
        g.drawRoundRect(x, y, w, h, 18, Ui.WHITE)
        g.drawRoundRect(x + 2, y + 2, w - 4, h - 4, 16, Ui.WHITE)
        g.textColor = Ui.WHITE
        val t = T(S.EVO_TAP)
        g.setSize(3); g.setCur(g.centerX(t, 3), y + h / 2 - 11); g.print(t)
    }

    private fun drawFarewellButton() {
        val p = (4 * sin(millis() * 0.005f)).toInt()
        val x = FAR_BTN_X - p; val y = FAR_BTN_Y - p; val w = FAR_BTN_W + 2 * p; val h = FAR_BTN_H + 2 * p
        g.fillRoundRect(x, y, w, h, 16, Ui.BAR_WARN)
        g.drawRoundRect(x, y, w, h, 16, Ui.INK)
        val buf = Text.f(S.FAREWELL_BTN, pet.nick.ifEmpty { dexName(pet.speciesId) })
        g.textColor = Ui.INK
        g.setSize(2); g.setCur(g.centerX(buf, 2), y + h / 2 - 8); g.print(buf)
    }

    private fun drawRunawayButton() {
        val p = (3 * sin(millis() * 0.003f)).toInt()
        val x = FAR_BTN_X - p; val y = FAR_BTN_Y - p; val w = FAR_BTN_W + 2 * p; val h = FAR_BTN_H + 2 * p
        g.fillRoundRect(x, y, w, h, 16, c565(0x3a, 0x44, 0x5a))
        g.drawRoundRect(x, y, w, h, 16, c565(0x70, 0x80, 0x98))
        val buf = Text.f(S.RUNAWAY_BTN, pet.nick.ifEmpty { dexName(pet.speciesId) })
        g.textColor = c565(0xc8, 0xd2, 0xe0)
        g.setSize(2); g.setCur(g.centerX(buf, 2), y + h / 2 - 8); g.print(buf)
    }

    // =====================================================================
    // the pet
    // =====================================================================
    private fun drawEvolveFX(now: Long) {
        val m = pmd ?: return
        val t = pet.evolveT()
        val cx = CX
        val cy = PET_GROUND - 96
        val halo = 36 + (t * 150).toInt() + (8 * sin(now * 0.02f)).toInt()
        for (k in 0 until 4) {
            val r = halo - k * 7
            if (r > 0) g.drawCircle(cx, cy, r, Ui.WHITE)
        }
        val base = now * 0.004f
        for (i in 0 until 12) {
            val a = base + i * (Math.PI / 6).toFloat()
            val len = 90 + (70 * (0.5f + 0.5f * sin(now * 0.012f + i))).toInt()
            g.drawLine(cx, cy, cx + (cos(a) * len).toInt(), cy + (sin(a) * len).toInt(), Ui.WHITE)
        }
        val period = 60 + (220 * (1f - t)).toInt()
        val old = evoPmd
        val showOld = t < 0.9f && old != null && (now / period) % 2 == 0L
        if (showOld) drawPmdAct(old!!, PMD_IDLE, cx, PET_GROUND, 0, true, true, 5)
        else drawPmdAct(m, PMD_IDLE, cx, PET_GROUND, 0, true, true, 5)
        for (i in 0 until 10) {
            val a = i * (Math.PI / 5).toFloat() + t * 4f
            val d = ((now / 14 + i * 33) % 200).toInt()
            val sx = cx + (cos(a) * d).toInt()
            val sy = cy + (sin(a) * d).toInt()
            g.fillRect(sx - 2, sy - 2, 5, 5, if ((i and 1) == 1) c565(0xff, 0xe0, 0x70) else Ui.WHITE)
        }
        if (t > 0.9f) g.fillCircle(cx, cy, (300 * (t - 0.9f) / 0.1f).toInt(), Ui.WHITE)
    }

    private fun drawPet() {
        if (pmd != null) { drawPetPMD(); return }
        val fi = if (pet.speciesId in 1..9) pet.speciesId - 1 else -1
        if (fi < 0) {
            g.textColor = inkColor()
            g.setSize(6); g.setCur(CX - 18, PET_CY - 80); g.print("?")
            g.setSize(2)
            val l1 = T(S.NO_SPRITES)
            g.setCur(g.centerX(l1, 2), PET_CY - 4); g.print(l1)
            val l2 = "run tools/fetch_sprites"
            g.setCur(g.centerX(l2, 2), PET_CY + 20); g.print(l2)
            return
        }
        val sp = SpriteTables.FLASH[fi]
        val s = sp.scale
        val x = CX - 16 * s
        var y = PET_CY - 16 * s

        if (pet.evolving()) {
            val flash = (millis() / 300) % 2 == 1L
            val show = if (flash && pet.prevSpeciesId >= 0) pet.prevSpeciesId else pet.speciesId
            if (show in 1..9) {
                val f = SpriteTables.FLASH[show - 1]
                drawMap(f.sprite, CX - 16 * f.scale, PET_CY - 16 * f.scale, f.scale, flash)
            }
            return
        }

        val m = pet.mood()
        if (m == Mood.HAPPY && (millis() / 500) % 2 == 1L) y -= 6
        drawMap(sp.sprite, x, y, s, false)
        val blink = millis() % 3500 < 300
        if (m == Mood.SLEEPING || blink) {
            overlayEye(sp, x, y, s, sp.eyeL)
            overlayEye(sp, x, y, s, sp.eyeR)
        }
        if (m == Mood.EATING) overlayMouth(sp, x, y, s, true)
        else if (m == Mood.SAD) overlayMouth(sp, x, y, s, false)
        if (pet.showHeart()) drawMap(SpriteTables.SPR_HEART, x + 20 * s, y - 2 * s, 2, false)
    }

    /** Built-in fallback sprite (dex 1-9 only) for the minigame when no sprites are installed. */
    private fun drawFlashPet(cx: Int, y: Int, s: Int) {
        if (pet.speciesId !in 1..9) return
        val sp = SpriteTables.FLASH[pet.speciesId - 1]
        drawMap(sp.sprite, cx - 16 * s, y, s, false)
    }

    private fun overlayEye(sp: SpriteTables.Flash, x: Int, y: Int, s: Int, col: Int) {
        g.fillRect(x + col * s, y + sp.eyeRow * s, 3 * s, 4 * s, sp.body)
        g.fillRect(x + col * s, y + (sp.eyeRow + 2) * s, 3 * s, s, INK_K)
    }

    private fun overlayMouth(sp: SpriteTables.Flash, x: Int, y: Int, s: Int, open: Boolean) {
        val mc = sp.mouthCol
        val mr = sp.mouthRow
        g.fillRect(x + (mc - 3) * s, y + mr * s, 7 * s, 2 * s, sp.body)
        if (open) {
            g.fillRect(x + (mc - 2) * s, y + mr * s, 5 * s, 2 * s, INK_K)
        } else {
            g.fillRect(x + (mc - 2) * s, y + mr * s, 5 * s, s, INK_K)
            g.fillRect(x + (mc - 3) * s, y + (mr + 1) * s, s, s, INK_K)
            g.fillRect(x + (mc + 3) * s, y + (mr + 1) * s, s, s, INK_K)
        }
    }

    private fun startBath() {
        if (pet.isEgg() || pet.sleeping || pet.ceremony != CER_NONE || bathUntil != 0L) return
        bathUntil = millis() + 3000
        bathPending = true
        val cx = behX.toInt()
        for (b in bubbles) {
            b.x = cx - 70 + random(140)
            b.y = PET_GROUND - random(150)
            b.r = 8 + random(16)
            b.ph = random(64)
        }
    }

    private fun drawBath() {
        val now = millis()
        if (timeLeft(bathUntil) == 0L) {
            bathUntil = 0
            if (bathPending) {
                bathPending = false
                pet.clean()
                val m = pmd
                if (m != null && m.mon.has(PMD_POSE)) {
                    behMode = 2
                    behAct = PMD_POSE
                    behT0 = now
                    behUntil = now + m.mon.acts[PMD_POSE]!!.totalMs() * 2
                }
            }
            return
        }
        val left = bathUntil - now
        if (left > 800) {
            val t = now / 220f
            for (b in bubbles) {
                val bx = b.x + (sin(t + b.ph) * 6).toInt()
                val by = b.y - ((3000 - left) / 90).toInt()
                g.fillCircle(bx, by, b.r, Ui.WHITE)
                g.drawCircle(bx, by, b.r, rgb565ToArgb(0x7E3D))
                g.fillCircle(bx - b.r / 3, by - b.r / 3, b.r / 4, Ui.BG_DAY)
            }
        } else {
            for (i in 0 until 8) {
                val b = bubbles[i]
                val sx = b.x + (i % 3) * 6 - 6
                val sy = b.y - 18
                val col = if (i % 2 == 1) Ui.BAR_WARN else Ui.WHITE
                g.fillRect(sx - 6, sy - 1, 13, 3, col)
                g.fillRect(sx - 1, sy - 6, 3, 13, col)
            }
        }
    }

    private fun drawPmdAct(m: Art.MonCache, actId: Int, cx: Int, groundY: Int, t: Long, loop: Boolean, sil: Boolean, maxS: Int) {
        val a = m.mon.acts[actId] ?: return
        val idleH = m.mon.acts[PMD_IDLE]?.h ?: 0
        var s = if (idleH != 0) 170 / idleH else 5
        s = s.coerceIn(2, maxOf(2, maxS))
        while (s > 2 && a.h * s > 250) s--
        val fi = a.frameAt(t, loop)
        val x0 = cx - a.w * s / 2
        val y0 = groundY - a.base * s
        g.drawBitmap(m.frame(actId, fi, sil), x0, y0, a.w * s, a.h * s)
    }

    private fun behNext() {
        val m = pmd ?: return
        val now = millis()
        behT0 = now
        val r = random(100)
        if (r < 35 && (m.mon.has(PMD_WALKL) || m.mon.has(PMD_WALKR))) {
            behMode = 1
            behTargetX = (150 + random(176)).toFloat()
            behUntil = now + 15000
        } else if (r < 60) {
            val pick = intArrayOf(PMD_POSE, PMD_NOD, PMD_BREATH).filter { m.mon.has(it) }
            if (pick.isNotEmpty()) {
                behMode = 2
                behAct = pick[random(pick.size)]
                behUntil = now + m.mon.acts[behAct]!!.totalMs()
                return
            }
            behMode = 0
            behUntil = now + 2000 + random(3000)
        } else {
            behMode = 0
            behUntil = now + 2000 + random(3000)
        }
    }

    private fun drawPetPMD() {
        val m = pmd ?: return
        val now = millis()
        if (pet.evolving()) { drawEvolveFX(now); return }
        evoPmd = null

        val mood = pet.mood()
        var act: Int
        var loop = true
        if (mood == Mood.SLEEPING && m.mon.has(PMD_SLEEP)) {
            act = PMD_SLEEP
            behMode = 0
        } else if (mood == Mood.EATING && m.mon.has(PMD_EAT)) {
            act = PMD_EAT
            behT0 = 0
        } else if (mood == Mood.SAD && m.mon.has(PMD_HURT)) {
            act = PMD_HURT
        } else {
            if (now > behUntil) behNext()
            if (behMode != 1) walkLast = 0
            if (behMode == 1) {
                val d = behTargetX - behX
                if (abs(d) < 4) {
                    behNext()
                    act = PMD_IDLE
                } else {
                    val dt = minOf(if (walkLast != 0L) now - walkLast else 100L, 200L)
                    walkLast = now
                    val step = minOf(30f * dt / 1000f, abs(d))
                    behX += if (d > 0) step else -step
                    act = if (d > 0) PMD_WALKR else PMD_WALKL
                }
            } else {
                act = if (behMode == 2) behAct else PMD_IDLE
                loop = false
            }
            if (!m.mon.has(act)) act = PMD_IDLE
        }
        drawPmdAct(m, act, behX.toInt(), PET_GROUND, now - behT0, loop || act == PMD_IDLE, false, 5)
        if (pet.showHeart()) drawMap(SpriteTables.SPR_HEART, behX.toInt() + 50, PET_GROUND - 190, 2, false)
    }

    private fun drawPoops() {
        for (i in 0 until pet.poops) drawMap(SpriteTables.SPR_POOP, 36 + i * 46, 244, 2, false)
    }

    private fun barLabelGap(): Int {
        var w = 0
        for (id in arrayOf(S.BAR_FOOD, S.BAR_JOY, S.BAR_ENE, S.BAR_HYG)) w = maxOf(w, g.textW(T(id), 2))
        return if (w <= 48) 48 else w + 8
    }

    private fun drawBars() {
        drawBar(78, 318, T(S.BAR_FOOD), pet.fullness)
        drawBar(244, 318, T(S.BAR_JOY), pet.joy)
        drawBar(78, 346, T(S.BAR_ENE), pet.energy)
        drawBar(244, 346, T(S.BAR_HYG), pet.hygiene)
    }

    private fun drawBar(x: Int, y: Int, label: String, v: Int) {
        g.textColor = inkColor()
        g.setSize(2); g.setCur(x, y); g.print(label)
        val gap = barLabelGap()
        val bw = minOf(232 - (78 + gap), 100)
        val bx = x + gap
        val bh = 15
        val fill = if (v >= 50) Ui.BAR_OK else if (v >= 25) Ui.BAR_WARN else Ui.BAR_BAD
        g.fillRoundRect(bx, y, bw, bh, 4, Ui.TRACK)
        val fw = (bw - 4) * v / 100
        if (fw > 0) g.fillRoundRect(bx + 2, y + 2, fw, bh - 4, 3, fill)
    }

    private fun drawButtons() {
        for (i in 0 until 4) {
            val off = pet.sleeping && i != 2
            val bx = buttons[i].cx - BTN_HALF
            val by = buttons[i].cy - BTN_HALF
            if (!pet.sleeping) g.fillRoundRect(bx, by, 2 * BTN_HALF, 2 * BTN_HALF, 14, Ui.WHITE)
            g.drawRoundRect(bx, by, 2 * BTN_HALF, 2 * BTN_HALF, 14, inkColor())
            if (!off) drawMap(buttons[i].icon, buttons[i].cx - 16, buttons[i].cy - 16, 2, false)
        }
    }

    private fun eggMsg() = when (pet.eggCracks()) {
        0 -> T(S.EGG_TOUCH)
        1 -> T(S.EGG_MOVES)
        else -> T(S.EGG_ALMOST)
    }

    private fun statusMsg(): String = when {
        pet.evolving() -> T(S.EVOLVING)
        bathUntil != 0L -> "Splish splash!"
        pet.sleeping -> "Zzz..."
        pet.eating() -> T(S.EATING)
        pet.showHeart() -> T(S.LIKES)
        pet.fullness < 25 -> T(S.HUNGRY)
        pet.hygiene < 25 -> T(S.NEEDS_BATH)
        pet.energy < 25 -> T(S.EXHAUSTED)
        pet.joy < 25 -> T(S.SAD)
        pet.weight > 60 -> T(S.CHUBBY)
        pet.shiny && pet.ageMinutes < 15 -> T(S.IS_SHINY)
        else -> T(S.HAPPY)
    }

    private fun drawMap(map: Array<String>, x: Int, y: Int, s: Int, sil: Boolean) {
        val n = map.size
        g.drawBitmap(Art.map(map, sil), x, y, map[0].length * s, n * s)
    }
}
