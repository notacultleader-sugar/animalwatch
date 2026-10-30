// Port of TamaPoke.ino's screens, touch handling and minigames (MIT,
// (c) 2026 Quique Tortosa), by way of the Wear OS port's GameView.kt.
// Coordinates are the firmware's 466x466 ones; the view scales them to the
// watch. Function names follow the original so the files can be read side by side.
import Foundation
import SwiftUI

private let CX = 233
private let CY = 233
private let PET_CY = 202
private let PET_GROUND = 304
private let HORIZON = 232

private let BTN_HALF = 26
private let BTN_HIT = 36

private let STARTER_GROUND = 318
private let STARTER_ARROW_X = 52
private let STARTER_ARROW_Y = 250
private let STARTER_BTN_W = 120
private let STARTER_BTN_H = 52
private let STARTER_BTN_Y = 392
private let EVO_BTN_W = 256
private let EVO_BTN_H = 64
private let EVO_BTN_X = CX - EVO_BTN_W / 2
private let EVO_BTN_Y = 172
private let FAR_BTN_W = 408
private let FAR_BTN_H = 58
private let FAR_BTN_X = CX - FAR_BTN_W / 2
private let FAR_BTN_Y = 176

private let GAL_X = 73
private let GAL_Y = 84
private let GAL_CELL = 80
private let KB_COLS = 6
private let KB_X = 40
private let KB_Y = 150
private let KB_W = 64
private let KB_H = 52
private let KB_KEYS = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ.-")
private let SET_PILL_Y = 200
private let SET_PILL_H = 44

private let BLACK: UInt32 = 0xFF00_0000
private let INK_K: UInt32 = 0xFF1B_1B25
private let STARTER_DEX = [1, 4, 7]
private let CRACK1 = [(15, 8), (16, 9), (15, 10)]
private let CRACK2 = [(11, 13), (12, 14), (11, 15), (20, 12), (19, 13), (20, 14)]
private let STARS = [(120, 140), (330, 120), (370, 210), (95, 230), (280, 90), (160, 95)]
private let BIOME_SOIL: [UInt32] = [
    c565(0x7E, 0xC0, 0x7F), c565(0xDC, 0xCA, 0x94), c565(0x4F, 0x8A, 0x55),
    c565(0x8A, 0x55, 0x44), c565(0xA8, 0x90, 0x6A), c565(0xE6, 0xEE, 0xF5),
]

private struct Btn { let cx: Int; let cy: Int; let icon: [String] }

private final class Bubble { var x = 0, y = 0, r = 0, ph = 0 }

private func inRange(_ v: Int, _ lo: Int, _ hi: Int) -> Bool { v >= lo && v <= hi }
private func clampI(_ v: Int, _ lo: Int, _ hi: Int) -> Int { max(lo, min(hi, v)) }
private func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, v)) }

final class Game {
    private func random(_ n: Int) -> Int { n <= 1 ? 0 : Int.random(in: 0..<n) }
    private func millis() -> Int { Int(ProcessInfo.processInfo.systemUptime * 1000) }
    private func timeLeft(_ deadline: Int) -> Int { deadline == 0 ? 0 : max(0, deadline - millis()) }
    private func sfxPlay(_ s: Sfx) { sound.play(s) }

    private let sound: Sound
    private let battery: Battery
    private(set) var pet: Pet!
    private let g = Gfx()

    private let buttons = [
        Btn(cx: 140, cy: 390, icon: SpriteTables.SPR_ICON_FOOD),
        Btn(cx: 202, cy: 404, icon: SpriteTables.SPR_ICON_PLAY),
        Btn(cx: 264, cy: 404, icon: SpriteTables.SPR_ICON_LIGHT),
        Btn(cx: 326, cy: 390, icon: SpriteTables.SPR_ICON_CLEAN),
    ]

    // ---- sprites ----
    private var pmd: Art.MonCache?
    private var evoPmd: Art.MonCache?
    private var galleryPmd: Art.MonCache?
    private var monFor = -2
    private var monShinyFor = false
    private let thumbs: Thumbs?

    // ---- behaviour of the pet on screen ----
    private var behMode = 0
    private var behAct = PMD_IDLE
    private var behT0 = 0
    private var behUntil = 0
    private var behX: Double = 233
    private var behTargetX: Double = 233
    private var walkLast = 0

    // ---- screens / dialogs ----
    private var galleryOpen = false
    private var galleryPage = 0
    private var galleryDetail = 0
    private var cardOpen = false
    private var cardPage = 0
    private var kbOpen = false
    private var nameBuf = ""
    private var settingsOpen = false
    private var bathUntil = 0
    private var bathPending = false
    private let bubbles = (0..<14).map { _ in Bubble() }
    private var feedMenuUntil = 0
    private var confirmUntil = 0
    private var choiceKind = 0
    private var choiceUntil = 0

    // ---- minigame ----
    private var gameOpen = false
    private var gameOverUntil = 0
    private var ballX: Double = 0, ballY: Double = 0, ballVX: Double = 0, ballVY: Double = 0
    private var gamePetX: Double = 233
    private var lastGameStep = 0
    private var gameScore = 0
    private var gameMisses = 0
    private var hitX: Double = 0, hitY: Double = 0
    private var hitTime = 0
    private var gameNewHi = false

    // ---- training bag ----
    private var sackOpen = false
    private var sackUntil = 0
    private var sackOverUntil = 0
    private var sackHits = 0
    private var sackShake: Double = 0
    private var sackGain = 0
    private var sackNewHi = false

    // ---- touch ----
    private var wasPressed = false
    private var tX0 = 0, tY0 = 0, tXl = 0, tYl = 0
    private var tStart = 0
    private var holdFired = false

    private var gNight = false
    private var starterSel = 0
    private var starterHopAt = 0
    private var starterPmd: Art.MonCache?
    private var starterPmdFor = 0
    private var wasEvoReady = false
    private var wasRunReady = false
    private var lastClock = 0

    /// Sprites ship inside the app as the "mons" folder, made by tools/fetch_sprites.py.
    private static func readAsset(_ name: String) -> [UInt8]? {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("mons"),
              let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return [UInt8](data)
    }

    init(sound: Sound, battery: Battery) {
        self.sound = sound
        self.battery = battery
        thumbs = Game.readAsset("thumbs.bin").map { Thumbs($0) }
        let store = DefaultsStore()
        I18n.lang = clampI(store.getInt("lang", I18n.LANG_EN), 0, I18n.LANG_COUNT - 1)
        pet = Pet(prefs: store, millis: { [unowned self] in self.millis() }, sfx: { [unowned self] in self.sound.play($0) })
        pet.begin()
        pet.syncClock(localEpoch())
    }

    /// Local wall-clock seconds: the firmware's RTC holds local time, not UTC.
    func localEpoch() -> Int {
        let now = Date()
        return Int(now.timeIntervalSince1970) + TimeZone.current.secondsFromGMT(for: now)
    }

    func onResumeGame() {
        pet.syncClock(localEpoch())
    }

    func onPauseGame() {
        pet.lastSeenEpoch = localEpoch()
        pet.save()
    }

    private func loadMon(_ dex: Int, _ shiny: Bool) -> Art.MonCache? {
        let blob = (shiny ? Game.readAsset(String(format: "ps%03ld.bin", dex)) : nil)
            ?? Game.readAsset(String(format: "p%03ld.bin", dex))
        guard let blob, let mon = PmdMon.parse(blob) else { return nil }
        return Art.MonCache(mon)
    }

    private func ensureMon() {
        if pet.speciesId == monFor && monShinyFor == pet.shiny { return }
        monFor = pet.speciesId
        monShinyFor = pet.shiny
        pmd = nil
        behX = 233; behTargetX = 233
        behMode = 0
        behUntil = 0
        if inRange(pet.speciesId, 1, DEX_COUNT) { pmd = loadMon(pet.speciesId, pet.shiny) }
    }

    private func T(_ id: S) -> String { I18n.t(id) }
    private func dexName(_ d: Int) -> String { I18n.dexName(d) }

    // =====================================================================
    // frame loop
    // =====================================================================
    func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        viewSize = size
        let now = millis()
        pet.update(now)

        let evoReady = pet.wantEvolveButton()
        if evoReady && !wasEvoReady { sfxPlay(.medal) }
        wasEvoReady = evoReady
        let runReady = pet.canRunawayNow()
        if runReady && !wasRunReady { sfxPlay(.deny) }
        wasRunReady = runReady

        ensureMon()
        battery.poll(now)
        if now - lastClock > 30_000 {
            lastClock = now
            pet.lastSeenEpoch = localEpoch()
        }
        if pet.pendingSave { pet.flushSave() }
        holdCheck()

        var c = ctx
        let s = min(size.width, size.height) / SCREEN
        c.translateBy(x: (size.width - SCREEN * s) / 2, y: (size.height - SCREEN * s) / 2)
        c.scaleBy(x: s, y: s)
        g.c = c
        render()
        g.c = nil
    }

    // =====================================================================
    // touch (the view hands over points in its own coordinates)
    // =====================================================================
    private var viewSize = CGSize(width: SCREEN, height: SCREEN)

    private func toScreen(_ p: CGPoint) -> (Int, Int) {
        let s = min(viewSize.width, viewSize.height) / SCREEN
        let ox = (viewSize.width - SCREEN * s) / 2
        let oy = (viewSize.height - SCREEN * s) / 2
        return (Int((p.x - ox) / s), Int((p.y - oy) / s))
    }

    private func inPetZone(_ x: Int, _ y: Int) -> Bool { inRange(x, 111, 355) && inRange(y, 96, 309) }

    /// The Wear OS port polls this every 100 ms while a finger is down; here
    /// every frame does it.
    private func holdCheck() {
        if !wasPressed || holdFired { return }
        if !galleryOpen && !cardOpen && !kbOpen && !settingsOpen && millis() - tStart > 3000 &&
            abs(tXl - tX0) < 30 && abs(tYl - tY0) < 30 && inPetZone(tX0, tY0) &&
            !pet.isEgg() && confirmUntil == 0 && pet.ceremony == CER_NONE {
            confirmUntil = millis() + 10000
            holdFired = true
            Haptics.longPress()
        }
    }

    func touchDown(_ p: CGPoint) {
        let (x, y) = toScreen(p)
        if sackOpen {
            if y < 72 { sackOpen = false } else { sackTap() }
            wasPressed = true
            return
        }
        tX0 = x; tXl = x; tY0 = y; tYl = y
        tStart = millis()
        holdFired = false
        wasPressed = true
    }

    func touchMove(_ p: CGPoint) {
        let (x, y) = toScreen(p)
        tXl = x; tYl = y
    }

    func touchUp() {
        let was = wasPressed
        wasPressed = false
        if sackOpen || !was { return }
        let dx = tXl - tX0
        let dy = tYl - tY0
        let dt = millis() - tStart
        if !holdFired {
            if abs(dx) > 80 && abs(dy) < 70 && dt < 800 { onSwipe(dx > 0 ? 1 : -1) }
            else if abs(dy) > 80 && abs(dx) < 70 && dt < 800 { onSwipeV(dy > 0 ? 1 : -1) }
            else if dt < 1500 && abs(dx) < 40 && abs(dy) < 40 { onTap(tX0, tY0) }
        }
    }

    /// Digital Crown: page through the Pokédex, the card and the starters.
    /// dir -1 = forward (crown rolled up), like the Wear OS bezel.
    func onCrown(_ dir: Int) {
        if (galleryOpen && galleryDetail == 0) || cardOpen || pet.awaitingStarter() { onSwipe(dir) }
    }

    private func onSwipeV(_ dir: Int) {
        if pet.awaitingStarter() { return }
        if gameOpen || galleryOpen || kbOpen || sackOpen || pet.ceremony != CER_NONE { return }
        if settingsOpen { settingsOpen = false; return }
        if cardOpen {
            if dir < 0 { cardOpen = false }
            return
        }
        if dir > 0 {
            if confirmUntil == 0 && feedMenuUntil == 0 { settingsOpen = true }
        } else if !pet.isEgg() && confirmUntil == 0 && feedMenuUntil == 0 {
            cardOpen = true
            cardPage = 0
        }
    }

    private func onSwipe(_ dir: Int) {
        if pet.awaitingStarter() { starterStep(-dir); return }
        if gameOpen || kbOpen || settingsOpen { return }
        if cardOpen {
            cardPage = clampI(cardPage + (dir > 0 ? -1 : 1), 0, 3)
            return
        }
        if !galleryOpen {
            if pet.ceremony == CER_NONE && confirmUntil == 0 {
                galleryOpen = true
                galleryPage = 0
                galleryDetail = 0
            }
            return
        }
        if galleryDetail != 0 {
            galleryDetail = 0
            galleryPmd = nil
            return
        }
        let np = galleryPage - dir
        if np < 0 {
            galleryOpen = false
            galleryPmd = nil
            return
        }
        galleryPage = min(np, 9)
    }

    private func onTap(_ x: Int, _ y: Int) {
        if pet.awaitingStarter() { starterTap(x, y); return }
        if galleryOpen { galleryTap(x, y); return }
        if kbOpen { keyboardTap(x, y); return }
        if settingsOpen { settingsTap(x, y); return }
        if pet.ceremony != CER_NONE { return }
        if cardOpen {
            if cardPage == 0 && y < 84 { openKeyboard() }
            else if cardPage == 1 && inRange(y, 300, 340) && inRange(x, 96, 370) {
                cardOpen = false
                startSack()
            } else {
                cardOpen = false
            }
            return
        }
        if gameOpen { gameTap(x, y); return }
        if choiceKind != 0 {
            let b1 = inRange(x, 93, 373) && inRange(y, 206, 258)
            let b2 = inRange(x, 93, 373) && inRange(y, 268, 320)
            if choiceKind == 1 {
                if b1 {
                    let old = pet.speciesId
                    pet.evolve()
                    evoPmd = loadMon(old, pet.shiny)
                    monFor = -2 // load the new form
                } else if b2 { pet.declineEvolve() }
            } else if choiceKind == 2 {
                if b1 { pet.startFarewell() } else if b2 { pet.declineFarewell() }
            }
            choiceKind = 0
            return
        }
        if confirmUntil != 0 {
            if timeLeft(confirmUntil) > 0 && inRange(x, 118, 218) && inRange(y, 252, 304) { pet.release() }
            confirmUntil = 0
            return
        }
        if feedMenuUntil != 0 {
            if timeLeft(feedMenuUntil) > 0 && inRange(y, 288, 352) && inRange(x, 101, 365) {
                let item = min((x - 101) / 66, 3)
                if item == 3 { pet.feedCandy() } else { pet.feedBerry(item) }
                sfxPlay(.eat)
            }
            feedMenuUntil = 0
            return
        }
        if pet.isEgg() {
            pet.eggTap()
            sfxPlay(.tap)
            return
        }
        if pet.wantEvolveButton() && inRange(x, EVO_BTN_X, EVO_BTN_X + EVO_BTN_W) && inRange(y, EVO_BTN_Y, EVO_BTN_Y + EVO_BTN_H) {
            choiceKind = 1; choiceUntil = millis() + 12000
            return
        }
        if inRange(x, FAR_BTN_X, FAR_BTN_X + FAR_BTN_W) && inRange(y, FAR_BTN_Y, FAR_BTN_Y + FAR_BTN_H) {
            if pet.canRunawayNow() { pet.startRunaway(); return }
            if pet.wantFarewellButton() { choiceKind = 2; choiceUntil = millis() + 12000; return }
        }
        for i in 0..<4 {
            let dx = x - buttons[i].cx
            let dy = y - buttons[i].cy
            if dx * dx + dy * dy <= BTN_HIT * BTN_HIT {
                sfxPlay(.tap)
                switch i {
                case 0: if !pet.sleeping { feedMenuUntil = millis() + 6000 }
                case 1: startGame()
                case 2: pet.toggleLight()
                default: startBath()
                }
                return
            }
        }
        if inPetZone(x, y) {
            pet.caress()
            if !pet.sleeping { sfxPlay(.heart) }
        }
    }

    // =====================================================================
    // scene
    // =====================================================================
    private func inkColor() -> UInt32 { gNight ? Ui.INK_NIGHT : Ui.INK }

    private func sceneHour() -> Int {
        let e = pet.lastSeenEpoch
        return e != 0 ? (e / 3600) % 24 : 13
    }

    private func drawClouds(_ now: Int, _ col: UInt32) {
        for k in 0..<2 {
            let cx = (now / 50 + k * 250) % 560 - 40
            let cy = 70 + k * 34
            g.fillCircle(cx, cy, 16, col)
            g.fillCircle(cx + 18, cy + 3, 13, col)
            g.fillCircle(cx - 15, cy + 4, 12, col)
        }
    }

    private func skyColors(_ night: Bool, _ h: Int) -> (UInt32, UInt32) {
        if night { return (c565(0x0C, 0x12, 0x24), c565(0x1E, 0x26, 0x46)) }
        if h < 8 { return (c565(0xD1, 0x6A, 0x86), c565(0xF3, 0xB8, 0x7C)) }
        if h < 18 { return (c565(0x8F, 0xC8, 0xEA), c565(0xDC, 0xEE, 0xE6)) }
        return (c565(0xC7, 0x5A, 0x4A), c565(0xF0, 0xAE, 0x64))
    }

    /// Sky bands 8 px apart, drawn 9 tall so the scaled edges don't show seams.
    private func drawSky(_ top: UInt32, _ bot: UInt32, _ hor: Int) {
        var y = 0
        while y < hor {
            g.fillRect(0, y, 466, min(9, hor - y), lerpColor(top, bot, y, hor))
            y += 8
        }
    }

    private func drawScene(_ biome: Int, _ now: Int, _ night: Bool) {
        let h = sceneHour()
        let (top, bot) = skyColors(night, h)
        drawSky(top, bot, HORIZON)
        if night {
            g.fillCircle(360, 78, 24, c565(0xE8, 0xEE, 0xF5))
            g.fillCircle(370, 72, 22, lerpColor(top, bot, 78, HORIZON))
            for st in STARS { g.fillRect(st.0, st.1, 4, 4, Ui.WHITE) }
        } else if h < 18 {
            g.fillCircle(360, 84, 26, h < 8 ? c565(0xFF, 0xD9, 0x8A) : c565(0xFF, 0xE7, 0x9F))
            drawClouds(now, c565(0xFF, 0xFF, 0xFF))
        } else {
            g.fillCircle(233, HORIZON - 6, 34, c565(0xFF, 0xF1, 0xC8))
        }

        var soil = BIOME_SOIL[biome < 6 ? biome : 0]
        if night { soil = lerpColor(soil, c565(0x16, 0x1C, 0x30), 9, 16) }
        if biome == 1 {
            let sea = night ? c565(0x1C, 0x34, 0x52) : c565(0x4F, 0x96, 0xC4)
            g.fillRect(0, HORIZON - 26, 466, 26, sea)
            for i in 0..<3 {
                let wy = HORIZON - 22 + i * 7
                let fc = night ? c565(0x3A, 0x58, 0x78) : c565(0xBF, 0xE6, 0xF5)
                g.fillRect(60 + (now / 60 + i * 30) % 60, wy, 26, 2, fc)
                g.fillRect(300 - (now / 60 + i * 20) % 60, wy, 26, 2, fc)
            }
        }

        g.fillRect(0, HORIZON, 466, 466 - HORIZON, soil)
        let hill = lerpColor(soil, night ? c565(0x0C, 0x12, 0x24) : c565(0xFF, 0xFF, 0xFF), 3, 16)
        g.fillRoundRect(-60, HORIZON - 14, 586, 60, 30, hill)

        let dk = lerpColor(soil, c565(0x10, 0x18, 0x20), night ? 11 : 7, 16)
        switch biome {
        case 2:
            for tx in [60, 150, 360, 416] {
                g.fillTriangle(tx, HORIZON - 46, tx - 16, HORIZON, tx + 16, HORIZON, dk)
                g.fillTriangle(tx, HORIZON - 60, tx - 12, HORIZON - 28, tx + 12, HORIZON - 28, dk)
            }
        case 3:
            g.fillTriangle(70, HORIZON, 40, HORIZON + 30, 100, HORIZON + 30, dk)
            g.fillTriangle(400, HORIZON + 4, 372, HORIZON + 30, 430, HORIZON + 30, dk)
            if !night {
                for e in 0..<4 { g.fillRect(120 + e * 70, HORIZON + 8 + (e % 2) * 6, 4, 4, c565(0xFF, 0x9B, 0x3A)) }
            }
        case 4:
            g.fillTriangle(140, HORIZON - 50, 60, HORIZON, 220, HORIZON, dk)
            g.fillTriangle(330, HORIZON - 38, 250, HORIZON, 410, HORIZON, dk)
        case 5:
            if !night {
                for f in 0..<10 {
                    let fx = (f * 53 + now / 40) % 466
                    let fy = (f * 90 + now / 18) % HORIZON
                    g.fillRect(fx, fy, 3, 3, Ui.WHITE)
                }
            }
        case 0:
            for gx in [80, 175, 300, 395] {
                for b in -1...1 { g.fillRect(gx + b * 5, HORIZON + 6, 2, 8 + (b == 0 ? 4 : 0), dk) }
            }
        default:
            break
        }
    }

    private func roundBg() {
        g.fillScreen(BLACK)
        g.fillCircle(CX, CY, 231, Ui.BG_DAY)
    }

    // ---- starter choice: one starter at a time in its home biome ----
    private func starterStep(_ dir: Int) {
        starterSel = (starterSel + dir + 3) % 3
        starterHopAt = millis()
        sfxPlay(.tap)
    }

    private func starterTap(_ x: Int, _ y: Int) {
        if abs(y - STARTER_ARROW_Y) < 50 && x < STARTER_ARROW_X + 48 { starterStep(-1); return }
        if abs(y - STARTER_ARROW_Y) < 50 && x > 466 - STARTER_ARROW_X - 48 { starterStep(1); return }
        if abs(x - CX) < STARTER_BTN_W / 2 + 10 && inRange(y, STARTER_BTN_Y - 10, STARTER_BTN_Y + STARTER_BTN_H + 10) {
            pet.chooseStarter(STARTER_DEX[starterSel])
            starterPmd = nil
            starterPmdFor = 0
            sfxPlay(.tap)
            return
        }
        if abs(x - CX) < 100 && inRange(y, 120, STARTER_GROUND + 10) { starterHopAt = millis() }
    }

    private func renderStarterSelect() {
        let d = STARTER_DEX[starterSel]
        let acc = DexTables.ACCENT[d]
        let now = millis()
        let h = sceneHour()
        let night = h < 6 || h >= 20
        g.fillScreen(BLACK)
        drawScene(DexTables.BIOME[d], now, night)

        // title on a pill, page dots under it
        let t = T(.CHOOSE_STARTER)
        let ts = g.textW(t, 2) <= 300 ? 2 : 1
        let tw = g.textW(t, ts) + 36
        g.fillRoundRect(CX - tw / 2, 40, tw, 40, 20, Ui.WHITE)
        g.textColor = Ui.INK
        g.setSize(ts); g.setCur(g.centerX(t, ts), ts == 2 ? 54 : 57); g.print(t)
        for i in 0..<3 {
            let dx = CX - 22 + i * 22
            g.fillCircle(dx, 98, i == starterSel ? 8 : 6, i == starterSel ? acc : Ui.INK)
            g.fillCircle(dx, 98, i == starterSel ? 4 : 3, Ui.WHITE)
        }

        // the starter: a little hop when it comes on stage or is tapped
        let ht = now - starterHopAt
        let hop = inRange(ht, 0, 359) ? Int(sin(Double(ht) * Double.pi / 360) * 26) : 0
        let shadowW = 120 - hop * 2
        let soil = BIOME_SOIL[DexTables.BIOME[d]]
        g.fillRoundRect(CX - shadowW / 2, STARTER_GROUND - 8, shadowW, 16, 8, lerpColor(soil, BLACK, night ? 10 : 5, 16))
        drawStarterMon(d, STARTER_GROUND - hop, now)

        // arrows
        for side in [-1, 1] {
            let ax = side < 0 ? STARTER_ARROW_X : 466 - STARTER_ARROW_X
            g.fillCircle(ax, STARTER_ARROW_Y, 26, Ui.WHITE)
            g.fillTriangle(ax + 9 * side, STARTER_ARROW_Y, ax - 7 * side, STARTER_ARROW_Y - 13,
                           ax - 7 * side, STARTER_ARROW_Y + 13, acc)
        }

        // name on the starter's colour
        let nm = dexName(d)
        let ns = g.textW(nm, 3) <= 260 ? 3 : 2
        let nw = g.textW(nm, ns) + 44
        g.fillRoundRect(CX - nw / 2, 332, nw, 46, 23, acc)
        g.textColor = Ui.WHITE
        g.setSize(ns); g.setCur(g.centerX(nm, ns), ns == 3 ? 343 : 347); g.print(nm)

        // confirm: a white pill with a check
        let bx = CX - STARTER_BTN_W / 2
        g.fillRoundRect(bx, STARTER_BTN_Y + 4, STARTER_BTN_W, STARTER_BTN_H, 26, lerpColor(acc, BLACK, 5, 16))
        g.fillRoundRect(bx, STARTER_BTN_Y, STARTER_BTN_W, STARTER_BTN_H, 26, Ui.WHITE)
        drawCheck(CX, STARTER_BTN_Y + STARTER_BTN_H / 2, acc)
    }

    private func drawStarterMon(_ d: Int, _ groundY: Int, _ now: Int) {
        if starterPmdFor != d {
            starterPmdFor = d
            starterPmd = loadMon(d, false)
        }
        if let m = starterPmd, let a = m.mon.acts[PMD_IDLE] {
            // bigger than on the main screen: it's the star of this one
            let s = clampI(240 / a.h, 3, 7)
            g.drawBitmap(m.frame(PMD_IDLE, a.frameAt(now, loop: true), false),
                         CX - a.w * s / 2, groundY - a.base * s, a.w * s, a.h * s)
            return
        }
        if let t = thumbs?.get(d) {
            g.drawBitmap(Art.thumb(t, false), CX - t.w * 2, groundY - t.h * 4, t.w * 4, t.h * 4)
            return
        }
        // no sprites installed: the built-in pixel art, blinking now and then
        let sp = SpriteTables.FLASH[d - 1]
        let x = CX - 16 * 5
        let y = groundY - 30 * 5
        drawMap(sp.sprite, x, y, 5, false)
        if now % 3500 < 300 {
            overlayEye(sp, x, y, 5, sp.eyeL)
            overlayEye(sp, x, y, 5, sp.eyeR)
        }
    }

    private func drawCheck(_ cx: Int, _ cy: Int, _ col: UInt32) {
        // two thick strokes: short down-right, long up-right
        g.fillTriangle(cx - 22, cy - 2, cx - 14, cy - 10, cx - 4, cy + 14, col)
        g.fillTriangle(cx - 14, cy - 10, cx + 4, cy + 4, cx - 4, cy + 14, col)
        g.fillTriangle(cx - 4, cy + 14, cx - 4, cy - 2, cx + 20, cy - 20, col)
        g.fillTriangle(cx - 4, cy + 14, cx + 20, cy - 20, cx + 26, cy - 12, col)
    }

    // =====================================================================
    // render
    // =====================================================================
    private func render() {
        if pet.awaitingStarter() { renderStarterSelect(); return }
        if galleryOpen { renderGallery(); return }
        if gameOpen { renderGame(); return }
        if sackOpen { renderSack(); return }
        if kbOpen { renderKeyboard(); return }
        if settingsOpen { renderSettings(); return }
        if cardOpen { renderCard(); return }

        let h = sceneHour()
        gNight = pet.sleeping || h < 6 || h >= 20
        g.fillScreen(BLACK)
        drawScene(pet.isEgg() ? 0 : DexTables.BIOME[pet.speciesId], millis(), gNight)

        if pet.ceremony != CER_NONE {
            let msg: String
            switch pet.ceremony {
            case CER_FAREWELL: msg = T(.FAREWELL)
            case CER_RUNAWAY: msg = T(.RUNAWAY)
            default: msg = T(.GOODBYE)
            }
            drawHeader(dexName(pet.speciesId), DexTables.ACCENT[pet.speciesId], msg)
            drawCeremony()
            return
        }

        if pet.isEgg() {
            drawHeader(T(.EGG_HDR), inkColor(), eggMsg())
            let s = 5
            let x = CX - 16 * s
            let y = PET_CY - 16 * s
            drawMap(SpriteTables.SPR_EGG, x, y, s, false)
            if pet.eggCracks() >= 1 { for c in CRACK1 { g.fillRect(x + c.0 * s, y + c.1 * s, s, s, INK_K) } }
            if pet.eggCracks() >= 2 { for c in CRACK2 { g.fillRect(x + c.0 * s, y + c.1 * s, s, s, INK_K) } }
            if pet.eggRarity() >= R_RARO {
                let rar = pet.eggRarity() == R_LEGENDARIO ? T(.EGG_LEGEND) : T(.EGG_RARE)
                g.textColor = pet.eggRarity() == R_LEGENDARIO ? Ui.BAR_WARN : rgb565ToArgb(0x4C98)
                g.setSize(2); g.setCur(g.centerX(rar, 2), 316); g.print(rar)
            }
            let reg = I18n.f(.POKEDEX_FMT, pet.registeredCount())
            g.fillRect(0, 312, 466, 154, gNight ? Ui.BG_NIGHT : Ui.BG_DAY)
            g.textColor = inkColor()
            g.setSize(2); g.setCur(g.centerX(reg, 2), 348); g.print(reg)
        } else {
            let base = pet.nick.isEmpty ? dexName(pet.speciesId) : pet.nick
            let name = I18n.f(.NAME_FMT, pet.shiny ? "*" : "", base, pet.level())
            drawHeader(name, gNight ? Ui.INK_NIGHT : DexTables.ACCENT[pet.speciesId], statusMsg())
            drawStreakBadge()
            drawPet()
            drawBath()
            drawPoops()
            g.fillRect(0, 312, 466, 154, gNight ? Ui.BG_NIGHT : Ui.BG_DAY)
            drawBars()
            drawButtons()
            drawCelebration()
            if pet.wantEvolveButton() { drawEvolveButton() }
            else if pet.canRunawayNow() { drawRunawayButton() }
            else if pet.wantFarewellButton() { drawFarewellButton() }
        }

        if pet.sleeping {
            g.textColor = Ui.INK_NIGHT
            g.setSize(3); g.setCur(320, 130); g.print("Zz")
        }

        if feedMenuUntil != 0 {
            if timeLeft(feedMenuUntil) == 0 {
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

        if confirmUntil != 0 {
            if timeLeft(confirmUntil) == 0 {
                confirmUntil = 0
            } else {
                g.fillRoundRect(94, 168, 278, 152, 16, Ui.WHITE)
                g.drawRoundRect(94, 168, 278, 152, 16, Ui.INK)
                let q = I18n.f(.RELEASE_FMT, dexName(pet.speciesId))
                g.textColor = Ui.INK
                g.setSize(2); g.setCur(g.centerX(q, 2), 196); g.print(q)
                g.fillRoundRect(118, 252, 100, 52, 12, Ui.BAR_OK)
                g.textColor = Ui.WHITE
                g.setCur(118 + (100 - g.textW(T(.YES), 2)) / 2, 270); g.print(T(.YES))
                g.fillRoundRect(248, 252, 100, 52, 12, Ui.BAR_BAD)
                g.setCur(248 + (100 - g.textW(T(.NO), 2)) / 2, 270); g.print(T(.NO))
            }
        }

        if choiceKind != 0 {
            if timeLeft(choiceUntil) == 0 { choiceKind = 0 } else { drawChoiceDialog() }
        }
    }

    // =====================================================================
    // minigame: keep the ball in the air
    // =====================================================================
    private func startGame() {
        if pet.isEgg() || pet.sleeping || pet.ceremony != CER_NONE { return }
        gameOpen = true
        gameOverUntil = 0
        gameScore = 0
        gameMisses = 0
        gameNewHi = false
        hitTime = 0
        gamePetX = 233
        lastGameStep = millis()
        respawnBall()
    }

    private func respawnBall() {
        ballX = Double(150 + random(166))
        ballY = 96
        let sp = min(1.6 + Double(gameScore) * 0.05, 4.0)
        ballVX = random(2) == 1 ? sp : -sp
        ballVY = 0
    }

    private func gameTap(_ x: Int, _ y: Int) {
        if gameOverUntil != 0 { return }
        if y < 72 { gameOpen = false; return }
        let dx = ballX - Double(x)
        let dy = ballY - Double(y)
        if dx * dx + dy * dy < 74 * 74 {
            gameScore += 1
            sfxPlay(.play)
            let lift = 6.6 + (gameScore > 16 ? 3.5 : Double(gameScore) * 0.22)
            ballVY = -lift
            ballVX = clampD(ballVX + dx * 0.12, -6.5, 6.5)
            hitX = ballX
            hitY = ballY
            hitTime = millis()
        }
    }

    private func stepGame() {
        let now = millis()
        let k = lastGameStep != 0 ? min(Double(now - lastGameStep) / 85, 3) : 1
        lastGameStep = now

        let grav = min(0.40 + Double(gameScore) * 0.013, 0.80)
        ballVY += grav * k
        ballX += ballVX * k
        ballY += ballVY * k
        let dx = ballX - Double(CX)
        let dy = ballY - Double(CY)
        let d = (dx * dx + dy * dy).squareRoot()
        if d > 205 {
            let nx = dx / d
            let ny = dy / d
            let dot = ballVX * nx + ballVY * ny
            if dot > 0 {
                ballVX = (ballVX - 2 * dot * nx) * 0.85
                ballVY = (ballVY - 2 * dot * ny) * 0.85
            }
            ballX = Double(CX) + nx * 205
            ballY = Double(CY) + ny * 205
        }
        if ballY > 384 {
            gameMisses += 1
            if gameMisses >= 3 {
                gameNewHi = gameScore > pet.gameHi
                pet.playResult(gameScore)
                sfxPlay(gameNewHi && gameScore > 0 ? .medal : .level)
                gameOverUntil = millis() + 4000
            } else {
                respawnBall()
            }
        }
        let chase = clampD((ballX - gamePetX) * 0.12, -7, 7)
        gamePetX += chase * k
    }

    private func drawGameScene() {
        let hh = sceneHour()
        let night = hh < 6 || hh >= 20
        let (top, bot) = skyColors(night, hh)
        let hor = 376
        g.fillScreen(BLACK)
        drawSky(top, bot, hor)
        if night { for st in STARS { g.fillRect(st.0, st.1, 4, 4, Ui.WHITE) } }
        let bio = pet.isEgg() ? 0 : DexTables.BIOME[pet.speciesId]
        var soil = BIOME_SOIL[bio < 6 ? bio : 0]
        if night { soil = lerpColor(soil, c565(0x16, 0x1C, 0x30), 9, 16) }
        g.fillRect(0, hor, 466, 466 - hor, soil)
    }

    private func renderGame() {
        let night = sceneHour() < 6 || sceneHour() >= 20
        let ink = night ? Ui.INK_NIGHT : Ui.INK

        if gameOverUntil != 0 {
            drawGameScene()
            if timeLeft(gameOverUntil) == 0 { gameOpen = false; return }
            let buf = I18n.f(.SCORE_FMT, gameScore)
            g.textColor = ink
            g.setSize(4); g.setCur(g.centerX(buf, 4), 160); g.print(buf)
            g.setSize(2)
            if gameNewHi && gameScore > 0 {
                g.textColor = Ui.BAR_WARN
                g.setCur(g.centerX(T(.NEW_RECORD), 2), 214); g.print(T(.NEW_RECORD))
            } else {
                let rec = I18n.f(.RECORD_FMT, pet.gameHi)
                g.textColor = ink
                g.setCur(g.centerX(rec, 2), 214); g.print(rec)
            }
            let msg = gameScore >= 10 ? T(.GREAT_JOY) : T(.PLUS_JOY)
            g.textColor = ink
            g.setCur(g.centerX(msg, 2), 250); g.print(msg)
            return
        }

        drawGameScene()
        stepGame()

        let buf = String(gameScore)
        g.textColor = ink
        g.setSize(4); g.setCur(g.centerX(buf, 4), 30); g.print(buf)
        let rec = I18n.f(.REC_FMT, pet.gameHi)
        g.setSize(2); g.setCur(g.centerX(rec, 2), 76); g.print(rec)
        for i in 0..<3 {
            if i < 3 - gameMisses { g.fillCircle(180 + i * 28, 104, 6, Ui.BAR_BAD) }
            else { g.drawCircle(180 + i * 28, 104, 6, Ui.TRACK) }
        }

        if let m = pmd {
            var act = ballX > gamePetX + 4 ? PMD_WALKR : (ballX < gamePetX - 4 ? PMD_WALKL : PMD_IDLE)
            if !m.mon.has(act) { act = PMD_IDLE }
            drawPmdAct(m, act, Int(gamePetX), 394, millis(), true, false, 3)
        } else {
            drawFlashPet(Int(gamePetX), 394 - 80, 2)
        }

        let ht = millis() - hitTime
        if hitTime != 0 && ht < 260 {
            let rad = 22 + ht / 6
            g.drawCircle(Int(hitX), Int(hitY), rad, c565(0xFF, 0xE7, 0x9F))
            g.drawCircle(Int(hitX), Int(hitY), rad - 2, c565(0xFF, 0xD9, 0x8A))
        }

        drawMap(SpriteTables.SPR_ICON_PLAY, Int(ballX) - 24, Int(ballY) - 24, 3, false)
    }

    // =====================================================================
    // training bag
    // =====================================================================
    private func startSack() {
        if pet.isEgg() || pet.sleeping || pet.ceremony != CER_NONE { return }
        sackOpen = true
        sackUntil = millis() + 10000
        sackOverUntil = 0
        sackHits = 0
        sackShake = 0
        sackNewHi = false
    }

    private func sackTap() {
        if timeLeft(sackUntil) == 0 { return }
        sackHits += 1
        sackShake = 16
    }

    private func renderSack() {
        let now = millis()
        drawGameScene()
        let night = sceneHour() < 6 || sceneHour() >= 20
        let ink = night ? Ui.INK_NIGHT : Ui.INK

        if sackOverUntil != 0 {
            if timeLeft(sackOverUntil) == 0 { sackOpen = false; return }
            let b = I18n.f(.HITS_FMT, sackHits)
            g.textColor = ink
            g.setSize(4); g.setCur(g.centerX(b, 4), 150); g.print(b)
            let gs = I18n.f(.STR_GAIN_FMT, sackGain)
            g.textColor = Ui.BAR_BAD
            g.setSize(3); g.setCur(g.centerX(gs, 3), 210); g.print(gs)
            g.setSize(2)
            if sackNewHi && sackHits > 0 {
                g.textColor = Ui.BAR_WARN
                g.setCur(g.centerX(T(.NEW_RECORD), 2), 256); g.print(T(.NEW_RECORD))
            } else {
                let r = I18n.f(.RECORD_FMT, pet.strHi)
                g.textColor = ink
                g.setCur(g.centerX(r, 2), 256); g.print(r)
            }
            return
        }

        if timeLeft(sackUntil) == 0 {
            sackNewHi = sackHits > pet.strHi
            sackGain = pet.trainStrength(sackHits)
            sfxPlay(sackNewHi ? .medal : .play)
            sackOverUntil = now + 3500
            return
        }

        sackShake *= 0.84
        let off = Int(sackShake * sin(Double(now) * 0.05))
        let sx = CX + off
        let top = 86
        g.fillRect(CX - 3, 56, 6, top - 56, ink)
        g.fillRect(sx - 4, top - 30, 8, 34, ink)
        g.fillRoundRect(sx - 42, top, 84, 150, 26, c565(0xB5, 0x3A, 0x3A))
        g.fillRoundRect(sx - 42, top, 84, 22, 18, c565(0x7E, 0x28, 0x28))
        g.drawRoundRect(sx - 42, top, 84, 150, 26, ink)
        g.fillRect(sx - 42, top + 70, 84, 4, c565(0x7E, 0x28, 0x28))

        let buf = String(sackHits)
        g.textColor = ink
        g.setSize(6); g.setCur(g.centerX(buf, 6), 268); g.print(buf)
        g.setSize(2); g.setCur(g.centerX(T(.HIT_FAST), 2), 322); g.print(T(.HIT_FAST))

        let left = sackUntil - now
        let bw = 280
        let fw = bw * left / 10000
        g.fillRoundRect(CX - bw / 2, 350, bw, 16, 5, Ui.TRACK)
        if fw > 2 { g.fillRoundRect(CX - bw / 2, 350, fw, 16, 5, Ui.BAR_OK) }
    }

    // =====================================================================
    // card (swipe up)
    // =====================================================================
    private func statBarX() -> Int {
        var w = 0
        for id in [S.STAT_ATK, S.STAT_DEF, S.STAT_SPE, S.STAT_WGT, S.VIN] { w = max(w, g.textW(T(id), 2)) }
        return max(150, 96 + w + 12)
    }

    private func drawCardStat(_ y: Int, _ label: String, _ v: Int, _ maxBar: Int, _ color: UInt32) {
        g.textColor = Ui.INK
        g.setSize(2); g.setCur(96, y); g.print(label)
        g.setCur(330, y); g.print(String(v))
        let bx = statBarX()
        let bw = 310 - bx
        let fw = min(v * bw / maxBar, bw)
        g.fillRoundRect(bx, y + 2, bw, 11, 3, Ui.TRACK)
        if fw > 2 { g.fillRoundRect(bx, y + 2, fw, 11, 3, color) }
    }

    private func drawStreakBadge() {
        if pet.streak < 1 { return }
        let x = 26
        let y = 16
        g.fillTriangle(x + 8, y, x + 1, y + 17, x + 15, y + 17, Ui.BAR_BAD)
        g.fillTriangle(x + 8, y + 7, x + 4, y + 17, x + 12, y + 17, Ui.BAR_WARN)
        g.textColor = inkColor()
        g.setSize(2); g.setCur(x + 22, y + 2); g.print(String(pet.streak))
    }

    private func drawCelebration() {
        let l1: String
        let l2: String
        if pet.showMedal() {
            var name = ""
            for i in 0..<MED_COUNT where (pet.newMedal & (1 << i)) != 0 { name = I18n.medalName(i); break }
            l1 = T(.MEDAL_BANNER); l2 = name
        } else if pet.showMilestone() {
            l1 = T(.GREAT); l2 = I18n.f(.STREAK_DAYS_FMT, pet.streak)
        } else { return }
        g.fillRoundRect(73, 150, 320, 96, 16, Ui.BAR_WARN)
        g.drawRoundRect(73, 150, 320, 96, 16, Ui.INK)
        g.textColor = Ui.INK
        g.setSize(3); g.setCur(g.centerX(l1, 3), 176); g.print(l1)
        g.setSize(2); g.setCur(g.centerX(l2, 2), 212); g.print(l2)
    }

    private func renderCardProfile() {
        let nm = pet.nick.isEmpty ? dexName(pet.speciesId) : pet.nick
        let head = I18n.f(.NAME_FMT, pet.shiny ? "*" : "", nm, pet.level())
        g.textColor = DexTables.ACCENT[pet.speciesId]
        let hts = g.textW(head, 3) <= 198 ? 3 : 2
        g.setSize(hts); g.setCur(g.centerX(head, hts), hts == 3 ? 34 : 40); g.print(head)
        if !pet.nick.isEmpty {
            let par = "(\(dexName(pet.speciesId)))"
            g.textColor = Ui.TRACK
            g.setSize(2); g.setCur(g.centerX(par, 2), 64); g.print(par)
        }
        if let p = pmd { drawPmdAct(p, PMD_IDLE, CX, 206, millis(), true, false, 4) }

        let sx = 138
        let sy = 224
        g.fillTriangle(sx + 8, sy, sx + 1, sy + 18, sx + 15, sy + 18, Ui.BAR_BAD)
        g.fillTriangle(sx + 8, sy + 7, sx + 4, sy + 18, sx + 12, sy + 18, Ui.BAR_WARN)
        let rl = I18n.f(.STREAK_FMT, pet.streak, pet.bestStreak)
        g.textColor = Ui.INK
        g.setSize(2); g.setCur(sx + 24, sy + 2); g.print(rl)

        drawCardStat(258, T(.VIN), pet.bond, 100, c565(0xD4, 0x52, 0x7E))

        let berry: String
        if !pet.berryKnown { berry = T(.BERRY_UNK) }
        else if pet.lovesBerry(0) { berry = T(.BERRY_RED) }
        else if pet.lovesBerry(1) { berry = T(.BERRY_BLUE) }
        else { berry = T(.BERRY_GREEN) }
        let info = I18n.f(.INFO_FMT, berry, pet.ageMinutes / 1440)
        g.textColor = Ui.INK
        g.setSize(2); g.setCur(g.centerX(info, 2), 296); g.print(info)
        g.textColor = Ui.TRACK
        g.setCur(g.centerX(T(.RENAME_HINT), 2), 332); g.print(T(.RENAME_HINT))
    }

    private func renderCardStats() {
        g.textColor = Ui.INK
        g.setSize(3); g.setCur(g.centerX(T(.BATTLE), 3), 48); g.print(T(.BATTLE))
        drawCardStat(118, T(.STAT_ATK), pet.atkStat(), 260, Ui.BAR_BAD)
        drawCardStat(160, T(.STAT_DEF), pet.defStat(), 260, rgb565ToArgb(0x4C98))
        drawCardStat(202, T(.STAT_SPE), pet.speStat(), 260, Ui.BAR_WARN)
        drawCardStat(244, T(.STAT_WGT), pet.weight, 100, rgb565ToArgb(0xB3C8))
        g.fillRoundRect(96, 300, 274, 40, 12, Ui.BAR_BAD)
        g.textColor = Ui.BG_DAY
        g.setSize(2); g.setCur(g.centerX(T(.TRAIN_STR), 2), 311); g.print(T(.TRAIN_STR))
    }

    private func renderCardMedals() {
        let got = (0..<MED_COUNT).filter { pet.hasMedal(1 << $0) }.count
        let head = I18n.f(.MEDALS_FMT, got, MED_COUNT)
        g.textColor = Ui.INK
        g.setSize(3); g.setCur(g.centerX(head, 3), 48); g.print(head)
        for i in 0..<MED_COUNT {
            let x = 28 + (i % 2) * 206
            let y = 104 + (i / 2) * 54
            let gm = pet.hasMedal(1 << i)
            g.fillRoundRect(x, y, 196, 44, 10, gm ? Ui.BAR_OK : Ui.TRACK)
            if gm {
                g.fillCircle(x + 22, y + 22, 11, Ui.BG_DAY)
                g.textColor = Ui.BAR_OK
                g.setSize(2); g.setCur(x + 16, y + 13); g.print("v")
            }
            g.textColor = gm ? Ui.BG_DAY : rgb565ToArgb(0x8410)
            g.setSize(2); g.setCur(x + 44, y + 14); g.print(I18n.medalDesc(i))
        }
    }

    private func renderCardProgress() {
        let sp = pet.speciesId
        g.textColor = Ui.INK
        g.setSize(3); g.setCur(g.centerX(T(.PROGRESS), 3), 44); g.print(T(.PROGRESS))
        let lv = I18n.f(.LVL_FMT, pet.level())
        g.setSize(5); g.setCur(g.centerX(lv, 5), 86); g.print(lv)

        let into = pet.ageMinutes % MINUTES_PER_LEVEL
        let bx = 93, bw = 280, by = 158, bh = 22
        g.fillRoundRect(bx, by, bw, bh, 6, Ui.TRACK)
        let fw = (bw - 4) * into / MINUTES_PER_LEVEL
        if fw > 0 { g.fillRoundRect(bx + 2, by + 2, fw, bh - 4, 5, Ui.BAR_OK) }
        let nx = I18n.f(.NEXT_LVL_FMT, MINUTES_PER_LEVEL - into, pet.level() + 1)
        g.textColor = Ui.INK
        g.setSize(2); g.setCur(g.centerX(nx, 2), by + 32); g.print(nx)

        g.textColor = Ui.TRACK
        g.setCur(g.centerX(T(.EVO_LABEL), 2), 230); g.print(T(.EVO_LABEL))
        var evoCol = Ui.INK
        let evo: String
        if DexTables.EVOLVES_TO[sp] == 0 {
            evo = T(.FINAL_FORM)
        } else {
            let needed = DexTables.EVOLVE_LEVEL[sp] + pet.careMistakes
            if pet.level() >= needed {
                if pet.lowestStat() >= 40 { evoCol = Ui.BAR_OK; evo = T(.EVO_READY) }
                else { evoCol = Ui.BAR_BAD; evo = T(.EVO_BLOCKED) }
            } else { evo = I18n.f(.EVO_IN_FMT, needed - pet.level()) }
        }
        g.textColor = evoCol
        g.setCur(g.centerX(evo, 2), 256); g.print(evo)
        let ms = I18n.f(.MISTAKES_FMT, pet.careMistakes)
        g.textColor = pet.careMistakes > 0 ? Ui.BAR_BAD : Ui.INK
        g.setCur(g.centerX(ms, 2), 312); g.print(ms)
    }

    private func renderCard() {
        roundBg()
        switch cardPage {
        case 0: renderCardProfile()
        case 1: renderCardStats()
        case 2: renderCardMedals()
        default: renderCardProgress()
        }
        for i in 0..<4 {
            if i == cardPage { g.fillCircle(194 + i * 26, 374, 5, Ui.INK) }
            else { g.drawCircle(194 + i * 26, 374, 4, Ui.INK) }
        }
        g.textColor = Ui.TRACK
        g.setSize(2); g.setCur(g.centerX(T(.BACK), 2), 398); g.print(T(.BACK))
    }

    // =====================================================================
    // settings (swipe down). The firmware's "set time" screen: the watch
    // already knows the time, so only sound and language remain.
    // =====================================================================
    private func renderSettings() {
        roundBg()
        g.textColor = Ui.INK
        let clock = String(format: "%02ld:%02ld", (pet.lastSeenEpoch / 3600) % 24, (pet.lastSeenEpoch / 60) % 60)
        g.setSize(7); g.setCur(g.centerX(clock, 7), 90); g.print(clock)

        let snd = sound.enabled
        let sl = snd ? T(.SND_ON) : T(.SND_OFF)
        g.fillRoundRect(84, SET_PILL_Y, 140, SET_PILL_H, 10, snd ? Ui.BAR_OK : Ui.WHITE)
        g.drawRoundRect(84, SET_PILL_Y, 140, SET_PILL_H, 10, Ui.INK)
        g.textColor = snd ? Ui.BG_DAY : Ui.INK
        g.setSize(2); g.setCur(84 + (140 - g.textW(sl, 2)) / 2, SET_PILL_Y + 15); g.print(sl)

        g.fillRoundRect(242, SET_PILL_Y, 140, SET_PILL_H, 10, Ui.WHITE)
        g.drawRoundRect(242, SET_PILL_Y, 140, SET_PILL_H, 10, Ui.INK)
        let lp = "\(T(.LANG_LABEL)) \(StringTables.LANG_CODES[I18n.lang]) >"
        g.textColor = Ui.INK
        g.setSize(2); g.setCur(242 + (140 - g.textW(lp, 2)) / 2, SET_PILL_Y + 15); g.print(lp)

        g.textColor = Ui.TRACK
        g.setSize(2)
        let back = T(.CLOCK_CANCEL)
        g.setCur(g.centerX(back, 2), 330); g.print(back)
        g.setSize(1)
        let ver = "PokeWatch 1.0 - TamaPoke v1.18 port"
        g.setCur(g.centerX(ver, 1), 410); g.print(ver)
    }

    private func settingsTap(_ x: Int, _ y: Int) {
        if inRange(y, SET_PILL_Y, SET_PILL_Y + SET_PILL_H) {
            if inRange(x, 84, 224) {
                sound.enabled.toggle()
                if sound.enabled { sfxPlay(.tap) }
                return
            }
            if inRange(x, 242, 382) {
                I18n.lang = (I18n.lang + 1) % I18n.LANG_COUNT
                UserDefaults(suiteName: PREFS_SUITE)?.set(I18n.lang, forKey: "lang")
                sfxPlay(.tap)
                return
            }
        }
        settingsOpen = false
    }

    // =====================================================================
    // rename keyboard
    // =====================================================================
    private func openKeyboard() {
        kbOpen = true
        nameBuf = pet.nick
    }

    private func renderKeyboard() {
        roundBg()
        g.textColor = Ui.INK
        g.setSize(2); g.setCur(g.centerX(T(.NAME), 2), 56); g.print(T(.NAME))
        g.fillRoundRect(83, 84, 300, 40, 8, Ui.WHITE)
        g.drawRoundRect(83, 84, 300, 40, 8, Ui.INK)
        g.setSize(3); g.setCur(95, 94); g.print(nameBuf.isEmpty ? "_" : nameBuf)
        for i in 0..<30 {
            let x = KB_X + (i % KB_COLS) * KB_W
            let y = KB_Y + (i / KB_COLS) * KB_H
            g.fillRoundRect(x, y, KB_W - 6, KB_H - 6, 6, i >= 28 ? Ui.BAR_WARN : Ui.WHITE)
            g.drawRoundRect(x, y, KB_W - 6, KB_H - 6, 6, Ui.INK)
            g.textColor = Ui.INK
            g.setSize(2)
            if i < 28 {
                g.setCur(x + KB_W / 2 - 9, y + KB_H / 2 - 10); g.print(String(KB_KEYS[i]))
            } else {
                g.setCur(x + KB_W / 2 - 15, y + KB_H / 2 - 10); g.print(i == 28 ? "<-" : "OK")
            }
        }
    }

    private func keyboardTap(_ x: Int, _ y: Int) {
        if x < KB_X || y < KB_Y { return }
        let col = (x - KB_X) / KB_W
        let row = (y - KB_Y) / KB_H
        if col >= KB_COLS || row >= 5 { return }
        let i = row * KB_COLS + col
        if i >= 30 { return }
        if i == 28 { if !nameBuf.isEmpty { nameBuf.removeLast() } }
        else if i == 29 { pet.rename(nameBuf); kbOpen = false }
        else if nameBuf.count < 11 { nameBuf.append(KB_KEYS[i]) }
    }

    // =====================================================================
    // Pokédex gallery (swipe sideways)
    // =====================================================================
    private func drawThumb(_ t: Thumb, _ x: Int, _ y: Int, _ s: Int, _ sil: Bool) {
        let ox = x + (GAL_CELL - t.w * s) / 2
        let oy = y + (GAL_CELL - t.h * s) / 2
        g.drawBitmap(Art.thumb(t, sil), ox, oy, t.w * s, t.h * s)
    }

    private func renderGallery() {
        roundBg()
        if galleryDetail != 0 {
            let d = galleryDetail
            let reg = pet.isRegistered(d)
            let head = String(format: "N.%03ld ", d) + (pet.isShinyRegistered(d) ? "*" : "") + (reg ? dexName(d) : "???")
            g.textColor = reg ? DexTables.ACCENT[d] : Ui.INK
            let gts = g.textW(head, 3) <= 234 ? 3 : 2
            g.setSize(gts); g.setCur(g.centerX(head, gts), gts == 3 ? 56 : 60); g.print(head)
            if let gp = galleryPmd {
                drawPmdAct(gp, PMD_IDLE, CX, 300, reg ? millis() : 0, true, !reg, 6)
            } else if let t = thumbs?.get(d) {
                drawThumb(t, CX - GAL_CELL, 135, 4, !reg)
            }
            g.textColor = Ui.INK
            g.setSize(2); g.setCur(g.centerX(T(.DETAIL_BACK), 2), 408); g.print(T(.DETAIL_BACK))
            return
        }

        let head = I18n.f(.POKEDEX_FMT, pet.registeredCount())
        g.textColor = Ui.INK
        g.setSize(3); g.setCur(g.centerX(head, 3), 36); g.print(head)
        outer: for r in 0..<4 {
            for c in 0..<4 {
                let dex = galleryPage * 16 + r * 4 + c + 1
                if dex > 151 { break outer }
                let x = GAL_X + c * GAL_CELL
                let y = GAL_Y + r * GAL_CELL
                if let t = thumbs?.get(dex) {
                    drawThumb(t, x, y, 2, !pet.isRegistered(dex))
                    if pet.isShinyRegistered(dex) {
                        g.textColor = Ui.BAR_WARN
                        g.setSize(2); g.setCur(x + 62, y + 4); g.print("*")
                    }
                } else {
                    g.textColor = pet.isRegistered(dex) ? Ui.INK : Ui.TRACK
                    g.setSize(2); g.setCur(x + 24, y + 32); g.print(String(dex))
                }
            }
        }
        for i in 0..<10 {
            if i == galleryPage { g.fillCircle(170 + i * 14, 436, 4, Ui.INK) }
            else { g.drawCircle(170 + i * 14, 436, 3, Ui.INK) }
        }
    }

    private func galleryTap(_ x: Int, _ y: Int) {
        if galleryDetail != 0 {
            galleryDetail = 0
            galleryPmd = nil
            return
        }
        if y < 72 {
            galleryOpen = false
            galleryPmd = nil
            return
        }
        if x < GAL_X || y < GAL_Y { return }
        let c = (x - GAL_X) / GAL_CELL
        let r = (y - GAL_Y) / GAL_CELL
        if c > 3 || r > 3 { return }
        let dex = galleryPage * 16 + r * 4 + c + 1
        if dex > 151 { return }
        galleryDetail = dex
        galleryPmd = loadMon(dex, pet.isShinyRegistered(dex))
    }

    // =====================================================================
    // header, ceremonies, dialogs
    // =====================================================================
    private func drawBattery() {
        let pc = battery.percent
        if pc < 0 { return }
        let x = CX - 14, y = 12, w = 24, h = 11
        let charging = battery.charging
        let col: UInt32
        if charging { col = Ui.BAR_OK }
        else if pc >= 40 { col = inkColor() }
        else if pc >= 15 { col = Ui.BAR_WARN }
        else { col = Ui.BAR_BAD }
        g.drawRoundRect(x, y, w, h, 2, col)
        g.fillRect(x + w, y + 3, 3, 5, col)
        if charging {
            let bolt = c565(0xFF, 0xD9, 0x4A)
            let bx = x + w / 2
            g.fillTriangle(bx + 3, y + 1, bx - 4, y + 6, bx + 1, y + 6, bolt)
            g.fillTriangle(bx - 1, y + 5, bx + 4, y + 5, bx - 3, y + 10, bolt)
        } else {
            let fw = (w - 4) * pc / 100
            if fw > 0 { g.fillRect(x + 2, y + 2, fw, h - 4, col) }
        }
    }

    private func drawHeader(_ name: String, _ nameColor: UInt32, _ msg: String) {
        drawBattery()
        g.textColor = nameColor
        g.setSize(3); g.setCur(g.centerX(name, 3), 52); g.print(name)
        g.textColor = inkColor()
        g.setSize(2); g.setCur(g.centerX(msg, 2), 90); g.print(msg)
    }

    private func drawCeremony() {
        guard let m = pmd else { drawPet(); return }
        let now = millis()
        let t = pet.ceremonyT()
        var x = CX
        let y = PET_GROUND
        var act: Int

        if pet.ceremony == CER_RUNAWAY {
            for i in 0..<46 {
                let rx = (i * 47 + now / 3) % 466
                let ry = (i * 91 + now / 2) % 470
                g.drawLine(rx, ry, rx - 3, ry + 12, c565(0x6A, 0x84, 0xB0))
            }
            var fade = false
            if t < 0.30 {
                act = m.mon.has(PMD_HURT) ? PMD_HURT : PMD_IDLE
                x = CX + Int(4 * sin(Double(now) * 0.04))
            } else {
                act = m.mon.has(PMD_WALKL) ? PMD_WALKL : PMD_IDLE
                x = CX - Int(((t - 0.30) / 0.70) * Double(CX + 120))
                fade = t > 0.6 && (now / 160) % 2 == 0
            }
            drawPmdAct(m, act, x, y, now, true, fade, 5)
            if t < 0.55 {
                let ty = y - 150 + (now / 6) % 40
                g.fillRect(x + 6, ty, 3, 6, c565(0x9A, 0xC4, 0xE8))
            }
            return
        }

        let gcy = PET_GROUND - 96
        for k in 0..<4 {
            let r = 60 + k * 34 + Int(10 * sin(Double(now) * 0.02))
            g.drawCircle(CX, gcy, r, c565(0xFF, 0xDF, 0x8A))
        }
        for i in 0..<16 {
            let px = (i * 71 + 28) % 466
            let py = 410 - (now / 8 + i * 70) % 360
            if py < 30 { continue }
            if i % 4 == 0 { drawMap(SpriteTables.SPR_HEART, px - 8, py - 8, 1, false) }
            else { g.fillRect(px, py, 4, 4, i % 2 == 1 ? c565(0xFF, 0xE7, 0x9F) : c565(0xFF, 0x9A, 0xC0)) }
        }
        if t < 0.45 {
            act = m.mon.has(PMD_POSE) ? PMD_POSE : (m.mon.has(PMD_NOD) ? PMD_NOD : PMD_IDLE)
        } else {
            act = m.mon.has(PMD_WALKR) ? PMD_WALKR : PMD_IDLE
            x = CX + Int(((t - 0.45) / 0.55) * Double(CX + 140))
        }
        drawPmdAct(m, act, x, y, now, true, false, 5)
        if pet.showHeart() { drawMap(SpriteTables.SPR_HEART, x + 50, y - 190, 2, false) }
    }

    private func drawChoiceDialog() {
        let q: String, o1: String, o2: String
        let c1: UInt32, c2: UInt32, t1: UInt32, t2: UInt32
        if choiceKind == 1 {
            q = T(.EVO_Q); o1 = T(.EVO_TAP); o2 = T(.EVO_KEEP)
            c1 = Ui.BAR_BAD; t1 = Ui.WHITE; c2 = Ui.TRACK; t2 = Ui.INK
        } else {
            q = T(.FAR_Q); o1 = T(.FAR_GO); o2 = T(.FAR_STAY)
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

    private func drawEvolveButton() {
        let p = Int(5 * sin(Double(millis()) * 0.006))
        let x = EVO_BTN_X - p, y = EVO_BTN_Y - p, w = EVO_BTN_W + 2 * p, h = EVO_BTN_H + 2 * p
        g.fillRoundRect(x, y, w, h, 18, Ui.BAR_BAD)
        g.drawRoundRect(x, y, w, h, 18, Ui.WHITE)
        g.drawRoundRect(x + 2, y + 2, w - 4, h - 4, 16, Ui.WHITE)
        g.textColor = Ui.WHITE
        let t = T(.EVO_TAP)
        g.setSize(3); g.setCur(g.centerX(t, 3), y + h / 2 - 11); g.print(t)
    }

    private func drawFarewellButton() {
        let p = Int(4 * sin(Double(millis()) * 0.005))
        let x = FAR_BTN_X - p, y = FAR_BTN_Y - p, w = FAR_BTN_W + 2 * p, h = FAR_BTN_H + 2 * p
        g.fillRoundRect(x, y, w, h, 16, Ui.BAR_WARN)
        g.drawRoundRect(x, y, w, h, 16, Ui.INK)
        let buf = I18n.f(.FAREWELL_BTN, pet.nick.isEmpty ? dexName(pet.speciesId) : pet.nick)
        g.textColor = Ui.INK
        g.setSize(2); g.setCur(g.centerX(buf, 2), y + h / 2 - 8); g.print(buf)
    }

    private func drawRunawayButton() {
        let p = Int(3 * sin(Double(millis()) * 0.003))
        let x = FAR_BTN_X - p, y = FAR_BTN_Y - p, w = FAR_BTN_W + 2 * p, h = FAR_BTN_H + 2 * p
        g.fillRoundRect(x, y, w, h, 16, c565(0x3A, 0x44, 0x5A))
        g.drawRoundRect(x, y, w, h, 16, c565(0x70, 0x80, 0x98))
        let buf = I18n.f(.RUNAWAY_BTN, pet.nick.isEmpty ? dexName(pet.speciesId) : pet.nick)
        g.textColor = c565(0xC8, 0xD2, 0xE0)
        g.setSize(2); g.setCur(g.centerX(buf, 2), y + h / 2 - 8); g.print(buf)
    }

    // =====================================================================
    // the pet
    // =====================================================================
    private func drawEvolveFX(_ now: Int) {
        guard let m = pmd else { return }
        let t = pet.evolveT()
        let cx = CX
        let cy = PET_GROUND - 96
        let halo = 36 + Int(t * 150) + Int(8 * sin(Double(now) * 0.02))
        for k in 0..<4 {
            let r = halo - k * 7
            if r > 0 { g.drawCircle(cx, cy, r, Ui.WHITE) }
        }
        let base = Double(now) * 0.004
        for i in 0..<12 {
            let a = base + Double(i) * (Double.pi / 6)
            let len = 90 + Int(70 * (0.5 + 0.5 * sin(Double(now) * 0.012 + Double(i))))
            g.drawLine(cx, cy, cx + Int(cos(a) * Double(len)), cy + Int(sin(a) * Double(len)), Ui.WHITE)
        }
        let period = 60 + Int(220 * (1 - t))
        if t < 0.9, let old = evoPmd, (now / period) % 2 == 0 {
            drawPmdAct(old, PMD_IDLE, cx, PET_GROUND, 0, true, true, 5)
        } else {
            drawPmdAct(m, PMD_IDLE, cx, PET_GROUND, 0, true, true, 5)
        }
        for i in 0..<10 {
            let a = Double(i) * (Double.pi / 5) + t * 4
            let d = (now / 14 + i * 33) % 200
            let sx = cx + Int(cos(a) * Double(d))
            let sy = cy + Int(sin(a) * Double(d))
            g.fillRect(sx - 2, sy - 2, 5, 5, (i & 1) == 1 ? c565(0xFF, 0xE0, 0x70) : Ui.WHITE)
        }
        if t > 0.9 { g.fillCircle(cx, cy, Int(300 * (t - 0.9) / 0.1), Ui.WHITE) }
    }

    private func drawPet() {
        if pmd != nil { drawPetPMD(); return }
        let fi = inRange(pet.speciesId, 1, 9) ? pet.speciesId - 1 : -1
        if fi < 0 {
            g.textColor = inkColor()
            g.setSize(6); g.setCur(CX - 18, PET_CY - 80); g.print("?")
            g.setSize(2)
            let l1 = T(.NO_SPRITES)
            g.setCur(g.centerX(l1, 2), PET_CY - 4); g.print(l1)
            let l2 = "run tools/fetch_sprites"
            g.setCur(g.centerX(l2, 2), PET_CY + 20); g.print(l2)
            return
        }
        let sp = SpriteTables.FLASH[fi]
        let s = sp.scale
        let x = CX - 16 * s
        var y = PET_CY - 16 * s

        if pet.evolving() {
            let flash = (millis() / 300) % 2 == 1
            let show = flash && pet.prevSpeciesId >= 0 ? pet.prevSpeciesId : pet.speciesId
            if inRange(show, 1, 9) {
                let f = SpriteTables.FLASH[show - 1]
                drawMap(f.sprite, CX - 16 * f.scale, PET_CY - 16 * f.scale, f.scale, flash)
            }
            return
        }

        let m = pet.mood()
        if m == .happy && (millis() / 500) % 2 == 1 { y -= 6 }
        drawMap(sp.sprite, x, y, s, false)
        let blink = millis() % 3500 < 300
        if m == .sleeping || blink {
            overlayEye(sp, x, y, s, sp.eyeL)
            overlayEye(sp, x, y, s, sp.eyeR)
        }
        if m == .eating { overlayMouth(sp, x, y, s, true) }
        else if m == .sad { overlayMouth(sp, x, y, s, false) }
        if pet.showHeart() { drawMap(SpriteTables.SPR_HEART, x + 20 * s, y - 2 * s, 2, false) }
    }

    /// Built-in fallback sprite (dex 1-9 only) for the minigame when no sprites are installed.
    private func drawFlashPet(_ cx: Int, _ y: Int, _ s: Int) {
        if !inRange(pet.speciesId, 1, 9) { return }
        let sp = SpriteTables.FLASH[pet.speciesId - 1]
        drawMap(sp.sprite, cx - 16 * s, y, s, false)
    }

    private func overlayEye(_ sp: Flash, _ x: Int, _ y: Int, _ s: Int, _ col: Int) {
        g.fillRect(x + col * s, y + sp.eyeRow * s, 3 * s, 4 * s, sp.body)
        g.fillRect(x + col * s, y + (sp.eyeRow + 2) * s, 3 * s, s, INK_K)
    }

    private func overlayMouth(_ sp: Flash, _ x: Int, _ y: Int, _ s: Int, _ open: Bool) {
        let mc = sp.mouthCol
        let mr = sp.mouthRow
        g.fillRect(x + (mc - 3) * s, y + mr * s, 7 * s, 2 * s, sp.body)
        if open {
            g.fillRect(x + (mc - 2) * s, y + mr * s, 5 * s, 2 * s, INK_K)
        } else {
            g.fillRect(x + (mc - 2) * s, y + mr * s, 5 * s, s, INK_K)
            g.fillRect(x + (mc - 3) * s, y + (mr + 1) * s, s, s, INK_K)
            g.fillRect(x + (mc + 3) * s, y + (mr + 1) * s, s, s, INK_K)
        }
    }

    private func startBath() {
        if pet.isEgg() || pet.sleeping || pet.ceremony != CER_NONE || bathUntil != 0 { return }
        bathUntil = millis() + 3000
        bathPending = true
        let cx = Int(behX)
        for b in bubbles {
            b.x = cx - 70 + random(140)
            b.y = PET_GROUND - random(150)
            b.r = 8 + random(16)
            b.ph = random(64)
        }
    }

    private func drawBath() {
        let now = millis()
        if timeLeft(bathUntil) == 0 {
            bathUntil = 0
            if bathPending {
                bathPending = false
                pet.clean()
                if let m = pmd, let pose = m.mon.acts[PMD_POSE] {
                    behMode = 2
                    behAct = PMD_POSE
                    behT0 = now
                    behUntil = now + pose.totalMs() * 2
                }
            }
            return
        }
        let left = bathUntil - now
        if left > 800 {
            let t = Double(now) / 220
            for b in bubbles {
                let bx = b.x + Int(sin(t + Double(b.ph)) * 6)
                let by = b.y - (3000 - left) / 90
                g.fillCircle(bx, by, b.r, Ui.WHITE)
                g.drawCircle(bx, by, b.r, rgb565ToArgb(0x7E3D))
                g.fillCircle(bx - b.r / 3, by - b.r / 3, b.r / 4, Ui.BG_DAY)
            }
        } else {
            for i in 0..<8 {
                let b = bubbles[i]
                let sx = b.x + (i % 3) * 6 - 6
                let sy = b.y - 18
                let col = i % 2 == 1 ? Ui.BAR_WARN : Ui.WHITE
                g.fillRect(sx - 6, sy - 1, 13, 3, col)
                g.fillRect(sx - 1, sy - 6, 3, 13, col)
            }
        }
    }

    private func drawPmdAct(_ m: Art.MonCache, _ actId: Int, _ cx: Int, _ groundY: Int, _ t: Int,
                            _ loop: Bool, _ sil: Bool, _ maxS: Int) {
        guard let a = m.mon.acts[actId] else { return }
        let idleH = m.mon.acts[PMD_IDLE]?.h ?? 0
        var s = idleH != 0 ? 170 / idleH : 5
        s = clampI(s, 2, max(2, maxS))
        while s > 2 && a.h * s > 250 { s -= 1 }
        let fi = a.frameAt(t, loop: loop)
        let x0 = cx - a.w * s / 2
        let y0 = groundY - a.base * s
        g.drawBitmap(m.frame(actId, fi, sil), x0, y0, a.w * s, a.h * s)
    }

    private func behNext() {
        guard let m = pmd else { return }
        let now = millis()
        behT0 = now
        let r = random(100)
        if r < 35 && (m.mon.has(PMD_WALKL) || m.mon.has(PMD_WALKR)) {
            behMode = 1
            behTargetX = Double(150 + random(176))
            behUntil = now + 15000
        } else if r < 60 {
            let pick = [PMD_POSE, PMD_NOD, PMD_BREATH].filter { m.mon.has($0) }
            if !pick.isEmpty {
                behMode = 2
                behAct = pick[random(pick.count)]
                behUntil = now + m.mon.acts[behAct]!.totalMs()
                return
            }
            behMode = 0
            behUntil = now + 2000 + random(3000)
        } else {
            behMode = 0
            behUntil = now + 2000 + random(3000)
        }
    }

    private func drawPetPMD() {
        guard let m = pmd else { return }
        let now = millis()
        if pet.evolving() { drawEvolveFX(now); return }
        evoPmd = nil

        let mood = pet.mood()
        var act: Int
        var loop = true
        if mood == .sleeping && m.mon.has(PMD_SLEEP) {
            act = PMD_SLEEP
            behMode = 0
        } else if mood == .eating && m.mon.has(PMD_EAT) {
            act = PMD_EAT
            behT0 = 0
        } else if mood == .sad && m.mon.has(PMD_HURT) {
            act = PMD_HURT
        } else {
            if now > behUntil { behNext() }
            if behMode != 1 { walkLast = 0 }
            if behMode == 1 {
                let d = behTargetX - behX
                if abs(d) < 4 {
                    behNext()
                    act = PMD_IDLE
                } else {
                    let dt = min(walkLast != 0 ? now - walkLast : 100, 200)
                    walkLast = now
                    let step = min(30 * Double(dt) / 1000, abs(d))
                    behX += d > 0 ? step : -step
                    act = d > 0 ? PMD_WALKR : PMD_WALKL
                }
            } else {
                act = behMode == 2 ? behAct : PMD_IDLE
                loop = false
            }
            if !m.mon.has(act) { act = PMD_IDLE }
        }
        drawPmdAct(m, act, Int(behX), PET_GROUND, now - behT0, loop || act == PMD_IDLE, false, 5)
        if pet.showHeart() { drawMap(SpriteTables.SPR_HEART, Int(behX) + 50, PET_GROUND - 190, 2, false) }
    }

    private func drawPoops() {
        for i in 0..<pet.poops { drawMap(SpriteTables.SPR_POOP, 36 + i * 46, 244, 2, false) }
    }

    private func barLabelGap() -> Int {
        var w = 0
        for id in [S.BAR_FOOD, S.BAR_JOY, S.BAR_ENE, S.BAR_HYG] { w = max(w, g.textW(T(id), 2)) }
        return w <= 48 ? 48 : w + 8
    }

    private func drawBars() {
        drawBar(78, 318, T(.BAR_FOOD), pet.fullness)
        drawBar(244, 318, T(.BAR_JOY), pet.joy)
        drawBar(78, 346, T(.BAR_ENE), pet.energy)
        drawBar(244, 346, T(.BAR_HYG), pet.hygiene)
    }

    private func drawBar(_ x: Int, _ y: Int, _ label: String, _ v: Int) {
        g.textColor = inkColor()
        g.setSize(2); g.setCur(x, y); g.print(label)
        let gap = barLabelGap()
        let bw = min(232 - (78 + gap), 100)
        let bx = x + gap
        let bh = 15
        let fill = v >= 50 ? Ui.BAR_OK : (v >= 25 ? Ui.BAR_WARN : Ui.BAR_BAD)
        g.fillRoundRect(bx, y, bw, bh, 4, Ui.TRACK)
        let fw = (bw - 4) * v / 100
        if fw > 0 { g.fillRoundRect(bx + 2, y + 2, fw, bh - 4, 3, fill) }
    }

    private func drawButtons() {
        for i in 0..<4 {
            let off = pet.sleeping && i != 2
            let bx = buttons[i].cx - BTN_HALF
            let by = buttons[i].cy - BTN_HALF
            if !pet.sleeping { g.fillRoundRect(bx, by, 2 * BTN_HALF, 2 * BTN_HALF, 14, Ui.WHITE) }
            g.drawRoundRect(bx, by, 2 * BTN_HALF, 2 * BTN_HALF, 14, inkColor())
            if !off { drawMap(buttons[i].icon, buttons[i].cx - 16, buttons[i].cy - 16, 2, false) }
        }
    }

    private func eggMsg() -> String {
        switch pet.eggCracks() {
        case 0: return T(.EGG_TOUCH)
        case 1: return T(.EGG_MOVES)
        default: return T(.EGG_ALMOST)
        }
    }

    private func statusMsg() -> String {
        if pet.evolving() { return T(.EVOLVING) }
        if bathUntil != 0 { return "Splish splash!" }
        if pet.sleeping { return "Zzz..." }
        if pet.eating() { return T(.EATING) }
        if pet.showHeart() { return T(.LIKES) }
        if pet.fullness < 25 { return T(.HUNGRY) }
        if pet.hygiene < 25 { return T(.NEEDS_BATH) }
        if pet.energy < 25 { return T(.EXHAUSTED) }
        if pet.joy < 25 { return T(.SAD) }
        if pet.weight > 60 { return T(.CHUBBY) }
        if pet.shiny && pet.ageMinutes < 15 { return T(.IS_SHINY) }
        return T(.HAPPY)
    }

    private func drawMap(_ map: [String], _ x: Int, _ y: Int, _ s: Int, _ sil: Bool) {
        g.drawBitmap(Art.map(map, sil), x, y, map[0].count * s, map.count * s)
    }
}
