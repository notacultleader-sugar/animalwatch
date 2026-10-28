// Port of TamaPoke.ino's screens, touch handling and minigames (MIT,
// (c) 2026 Quique Tortosa), following the Wear OS port (GameView.kt).
// Coordinates are the firmware's 466x466 ones; Gfx scales them to the watch.
import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

const CX = 233;
const CY = 233;
const PET_CY = 202;
const PET_GROUND = 304;
const HORIZON = 232;
const BTN_HALF = 26;
const BTN_HIT = 36;
const STARTER_ROW_Y = 110;
const STARTER_ROW_H = 70;
const STARTER_ROW_GAP = 8;
const EVO_BTN_W = 256;
const EVO_BTN_H = 64;
const EVO_BTN_X = 105;
const EVO_BTN_Y = 172;
const FAR_BTN_W = 408;
const FAR_BTN_H = 58;
const FAR_BTN_X = 29;
const FAR_BTN_Y = 176;
const GAL_X = 73;
const GAL_Y = 84;
const GAL_CELL = 80;

class GameView extends WatchUi.View {
    var pet as Pet;
    private var g as Gfx;
    private var timer as Timer.Timer?;
    private var soundOn = true;

    private var strips as Array;
    private var thumbIds as Array;
    private var monId = null;       // strip resource of the current species
    private var monFor = -2;
    private var evoId = null;       // previous form, during the evolution flicker
    private var evoDex = 0;

    // behaviour of the pet on screen
    private var behMode = 0;
    private var behUntil = 0;
    private var behX = 233.0;
    private var behTargetX = 233.0;
    private var behT0 = 0;
    private var walkLast = 0;

    // screens / dialogs
    var galleryOpen = false;
    private var galleryPage = 0;
    private var galleryDetail = 0;
    var cardOpen = false;
    private var cardPage = 0;
    var settingsOpen = false;
    private var bathUntil = 0;
    private var bathPending = false;
    private var bubbles as Array;
    var feedMenuUntil = 0;
    private var feedSel = 0;
    var confirmUntil = 0;
    var choiceKind = 0;
    private var choiceUntil = 0;
    private var starterSel = 1;

    // minigame
    var gameOpen = false;
    private var gameOverUntil = 0;
    private var ballX = 0.0;
    private var ballY = 0.0;
    private var ballVX = 0.0;
    private var ballVY = 0.0;
    private var gamePetX = 233.0;
    private var lastGameStep = 0;
    private var gameScore = 0;
    private var gameMisses = 0;
    private var hitX = 0.0;
    private var hitY = 0.0;
    private var hitTime = 0;
    private var gameNewHi = false;

    // training bag
    var sackOpen = false;
    private var sackUntil = 0;
    private var sackOverUntil = 0;
    private var sackHits = 0;
    private var sackShake = 0.0;
    private var sackGain = 0;
    private var sackNewHi = false;

    // long press on the pet (release dialog)
    private var holdStart = 0;
    private var holdX = 0;
    private var holdY = 0;

    private var gNight = false;
    private var wasEvoReady = false;
    private var wasRunReady = false;
    private var lastClock = 0;

    private const STARTER_DEX = [1, 4, 7];
    private const STARS = [[120, 140], [330, 120], [370, 210], [95, 230], [280, 90], [160, 95]];
    private const BIOME_SOIL = [0x7EC07F, 0xDCCA94, 0x4F8A55, 0x8A5544, 0xA8906A, 0xE6EEF5];
    private const CRACK1 = [[15, 8], [16, 9], [15, 10]];
    private const CRACK2 = [[11, 13], [12, 14], [11, 15], [20, 12], [19, 13], [20, 14]];
    private const BUTTONS = [[140, 390], [202, 404], [264, 404], [326, 390]];

    function initialize() {
        View.initialize();
        g = new Gfx();
        Math.srand(Time.now().value());
        strips = SpriteIds.strips();
        thumbIds = SpriteIds.thumbs();
        bubbles = new [14];
        for (var i = 0; i < 14; i++) {
            bubbles[i] = [0, 0, 0, 0];
        }
        var snd = Application.Storage.getValue("snd");
        soundOn = snd == null ? true : snd as Boolean;
        pet = new Pet();
        pet.sfx = method(:sfxPlay);
        pet.begin();
        pet.syncClock(localEpoch());
    }

    // ------------------------------------------------------------------
    // platform
    // ------------------------------------------------------------------
    function localEpoch() as Number {
        return Time.now().value() + System.getClockTime().timeZoneOffset;
    }

    private const NOTES = [
        [[880, 35]],
        [[660, 45], [0, 12], [660, 45]],
        [[784, 45], [988, 60]],
        [[1047, 55], [1319, 90]],
        [[523, 80], [659, 80], [784, 110], [1047, 170]],
        [[523, 80], [659, 80], [784, 80], [1047, 90], [1319, 230]],
        [[784, 70], [0, 25], [784, 70], [0, 25], [1047, 200]],
        [[300, 110], [200, 170]],
        [[784, 150], [659, 150], [523, 280]],
        [[784, 70], [1047, 130]]
    ];

    function sfxPlay(id as Number) as Void {
        if (!soundOn || !(Attention has :playTone) || !(Attention has :ToneProfile)) {
            return;
        }
        var notes = NOTES[id];
        var prof = [];
        for (var i = 0; i < notes.size(); i++) {
            prof.add(new Attention.ToneProfile(notes[i][0], notes[i][1]));
        }
        try {
            Attention.playTone({:toneProfile => prof});
        } catch (e) {
        }
    }

    function onShow() as Void {
        pet.syncClock(localEpoch());
        timer = new Timer.Timer();
        timer.start(method(:onTick), 100, true);
    }

    function onHide() as Void {
        if (timer != null) {
            timer.stop();
            timer = null;
        }
        pet.lastSeenEpoch = localEpoch();
        pet.save();
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    private function T(id as Number) as String {
        return Tables.S[id];
    }

    private function F(id as Number, args as Array) as String {
        return Lang.format(Tables.S[id], args);
    }

    private function dexName(d as Number) as String {
        return (d >= 1 && d <= 151) ? Tables.NAME[d] : Tables.NAME[0];
    }

    private function timeLeft(deadline as Number) as Number {
        if (deadline == 0) {
            return 0;
        }
        var l = deadline - G.millis();
        return l > 0 ? l : 0;
    }

    private function ensureMon() as Void {
        if (pet.speciesId == monFor) {
            return;
        }
        g.forget(monId);
        monFor = pet.speciesId;
        monId = (monFor >= 1 && monFor <= 151) ? strips[monFor] : null;
        behX = 233.0;
        behTargetX = 233.0;
        behMode = 0;
        behUntil = 0;
    }

    // ------------------------------------------------------------------
    // frame
    // ------------------------------------------------------------------
    function onUpdate(dc as Dc) as Void {
        var now = G.millis();
        pet.update(now);
        var evoReady = pet.wantEvolveButton();
        if (evoReady && !wasEvoReady) {
            sfxPlay(G.SFX_MEDAL);
        }
        wasEvoReady = evoReady;
        var runReady = pet.canRunawayNow();
        if (runReady && !wasRunReady) {
            sfxPlay(G.SFX_DENY);
        }
        wasRunReady = runReady;
        ensureMon();
        if (now - lastClock > 30000) {
            lastClock = now;
            pet.lastSeenEpoch = localEpoch();
        }
        pet.flushSave();
        checkHold();

        g.begin(dc);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        render();
    }

    // ------------------------------------------------------------------
    // input (from GameDelegate): touch, in the firmware's 466 px space
    // ------------------------------------------------------------------
    function toGame(c as Array) as Array {
        return [(c[0] / g.s).toNumber(), (c[1] / g.s).toNumber()];
    }

    private function inPetZone(x as Number, y as Number) as Boolean {
        return x > 110 && x < 356 && y > 95 && y < 310;
    }

    function holdBegin(x as Number, y as Number) as Void {
        holdStart = G.millis();
        holdX = x;
        holdY = y;
    }

    function holdEnd() as Void {
        holdStart = 0;
    }

    private function checkHold() as Void {
        // the watch reports a hold ~0.5 s in; TamaPoke wants 3 s in total
        if (holdStart == 0 || G.millis() - holdStart < 2500) {
            return;
        }
        holdStart = 0;
        if (!galleryOpen && !cardOpen && !settingsOpen && inPetZone(holdX, holdY) &&
            !pet.isEgg() && confirmUntil == 0 && pet.ceremony == G.CER_NONE) {
            confirmUntil = G.millis() + 10000;
            if (Attention has :vibrate) {
                Attention.vibrate([new Attention.VibeProfile(50, 200)]);
            }
        }
    }

    function sackPress(y as Number) as Void {
        if (y < 72) {
            sackOpen = false;
        } else {
            sackTap();
        }
    }

    function swipeV(dir as Number) as Void {
        if (pet.awaitingStarter()) { return; }
        if (gameOpen || galleryOpen || sackOpen || pet.ceremony != G.CER_NONE) { return; }
        if (settingsOpen) { settingsOpen = false; return; }
        if (cardOpen) {
            if (dir < 0) { cardOpen = false; }
            return;
        }
        if (dir > 0) {
            if (confirmUntil == 0 && feedMenuUntil == 0) { settingsOpen = true; }
        } else if (!pet.isEgg() && confirmUntil == 0 && feedMenuUntil == 0) {
            cardOpen = true;
            cardPage = 0;
        }
    }

    function swipe(dir as Number) as Void {
        if (pet.awaitingStarter()) { return; }
        if (gameOpen || settingsOpen) { return; }
        if (cardOpen) {
            var p = cardPage + (dir > 0 ? -1 : 1);
            cardPage = p < 0 ? 0 : (p > 3 ? 3 : p);
            return;
        }
        if (!galleryOpen) {
            if (pet.ceremony == G.CER_NONE && confirmUntil == 0) {
                openGallery();
            }
            return;
        }
        if (galleryDetail != 0) {
            closeDetail();
            return;
        }
        var np = galleryPage - dir;
        if (np < 0) {
            galleryOpen = false;
            return;
        }
        galleryPage = np > 9 ? 9 : np;
    }

    function openGallery() as Void {
        galleryOpen = true;
        galleryPage = 0;
        galleryDetail = 0;
    }

    private function closeDetail() as Void {
        if (galleryDetail != 0) {
            g.forget(strips[galleryDetail]);
        }
        galleryDetail = 0;
    }

    function tap(x as Number, y as Number) as Void {
        if (pet.awaitingStarter()) {
            for (var i = 0; i < 3; i++) {
                var ry = STARTER_ROW_Y + i * (STARTER_ROW_H + STARTER_ROW_GAP);
                if (x >= 70 && x <= 396 && y >= ry && y <= ry + STARTER_ROW_H) {
                    pet.chooseStarter(STARTER_DEX[i]);
                    sfxPlay(G.SFX_TAP);
                    break;
                }
            }
            return;
        }
        if (galleryOpen) { galleryTap(x, y); return; }
        if (settingsOpen) { settingsTap(x, y); return; }
        if (pet.ceremony != G.CER_NONE) { return; }
        if (cardOpen) {
            if (cardPage == 1 && y >= 300 && y <= 340 && x >= 96 && x <= 370) {
                cardOpen = false;
                startSack();
            } else {
                cardOpen = false;
            }
            return;
        }
        if (gameOpen) { gameTap(x, y); return; }
        if (choiceKind != 0) {
            var b1 = x >= 93 && x <= 373 && y >= 206 && y <= 258;
            var b2 = x >= 93 && x <= 373 && y >= 268 && y <= 320;
            choiceAnswer(b1 ? 1 : (b2 ? 2 : 0));
            return;
        }
        if (confirmUntil != 0) {
            confirmAnswer(timeLeft(confirmUntil) > 0 && x >= 118 && x <= 218 && y >= 252 && y <= 304);
            return;
        }
        if (feedMenuUntil != 0) {
            if (timeLeft(feedMenuUntil) > 0 && y >= 288 && y <= 352 && x >= 101 && x <= 365) {
                var item = (x - 101) / 66;
                feed(item > 3 ? 3 : item);
            }
            feedMenuUntil = 0;
            return;
        }
        if (pet.isEgg()) {
            pet.eggTap();
            sfxPlay(G.SFX_TAP);
            return;
        }
        if (pet.wantEvolveButton() && x >= EVO_BTN_X && x <= EVO_BTN_X + EVO_BTN_W &&
            y >= EVO_BTN_Y && y <= EVO_BTN_Y + EVO_BTN_H) {
            openChoice(1);
            return;
        }
        if (x >= FAR_BTN_X && x <= FAR_BTN_X + FAR_BTN_W && y >= FAR_BTN_Y && y <= FAR_BTN_Y + FAR_BTN_H) {
            if (pet.canRunawayNow()) { pet.startRunaway(); return; }
            if (pet.wantFarewellButton()) { openChoice(2); return; }
        }
        for (var i = 0; i < 4; i++) {
            var dx = x - BUTTONS[i][0];
            var dy = y - BUTTONS[i][1];
            if (dx * dx + dy * dy <= BTN_HIT * BTN_HIT) {
                sfxPlay(G.SFX_TAP);
                if (i == 0) {
                    openFeedMenu();
                } else if (i == 1) {
                    startGame();
                } else if (i == 2) {
                    pet.toggleLight();
                } else {
                    startBath();
                }
                return;
            }
        }
        if (inPetZone(x, y)) {
            caress();
        }
    }

    // ---- actions shared by touch and the button menu ----
    function caress() as Void {
        pet.caress();
        if (!pet.sleeping) { sfxPlay(G.SFX_HEART); }
    }

    function feed(item as Number) as Void {
        if (item == 3) {
            pet.feedCandy();
        } else {
            pet.feedBerry(item);
        }
        sfxPlay(G.SFX_EAT);
    }

    function openFeedMenu() as Void {
        if (!pet.sleeping) {
            feedMenuUntil = G.millis() + 6000;
            feedSel = 0;
        }
    }

    function openChoice(kind as Number) as Void {
        choiceKind = kind;
        choiceUntil = G.millis() + 12000;
    }

    // 1 = action (evolve / say goodbye), 2 = keep form / stay together
    function choiceAnswer(b as Number) as Void {
        if (choiceKind == 1) {
            if (b == 1) {
                evoDex = pet.speciesId;
                pet.evolve();
                evoId = strips[evoDex];
            } else if (b == 2) {
                pet.declineEvolve();
            }
        } else if (choiceKind == 2) {
            if (b == 1) {
                pet.startFarewell();
            } else if (b == 2) {
                pet.declineFarewell();
            }
        }
        choiceKind = 0;
    }

    function confirmAnswer(yes as Boolean) as Void {
        if (yes) {
            pet.release();
        }
        confirmUntil = 0;
    }

    function askRelease() as Void {
        if (!pet.isEgg() && pet.ceremony == G.CER_NONE) {
            confirmUntil = G.millis() + 10000;
        }
    }

    function openCard() as Void { swipeV(-1); }
    function openSettings() as Void { swipeV(1); }

    // ---- physical buttons ----
    // SELECT: confirm / hit; returns false when the main menu should open
    function keySelect() as Boolean {
        if (pet.awaitingStarter()) {
            pet.chooseStarter(STARTER_DEX[starterSel]);
            sfxPlay(G.SFX_TAP);
            return true;
        }
        if (sackOpen) { sackTap(); return true; }
        if (gameOpen) {
            // no touch: kick when the ball is down by the pet
            if (gameOverUntil == 0 && ballY > 250) { gameTap(ballX.toNumber(), ballY.toNumber()); }
            return true;
        }
        if (choiceKind != 0) { choiceAnswer(1); return true; }
        if (confirmUntil != 0) { confirmAnswer(true); return true; }
        if (feedMenuUntil != 0) { feed(feedSel); feedMenuUntil = 0; return true; }
        if (galleryOpen) {
            if (galleryDetail != 0) { closeDetail(); } else { galleryOpen = false; }
            return true;
        }
        if (cardOpen) {
            if (cardPage == 1) { cardOpen = false; startSack(); } else { cardOpen = false; }
            return true;
        }
        if (settingsOpen) { toggleSound(); return true; }
        if (pet.ceremony != G.CER_NONE) { return true; }
        if (pet.isEgg()) { pet.eggTap(); sfxPlay(G.SFX_TAP); return true; }
        return false;
    }

    // BACK: close what's open; false = leave the app
    function keyBack() as Boolean {
        if (sackOpen) { sackOpen = false; return true; }
        if (gameOpen) { gameOpen = false; return true; }
        if (galleryOpen && galleryDetail != 0) { closeDetail(); return true; }
        if (galleryOpen) { galleryOpen = false; return true; }
        if (cardOpen) { cardOpen = false; return true; }
        if (settingsOpen) { settingsOpen = false; return true; }
        if (choiceKind != 0) { choiceAnswer(2); return true; }
        if (confirmUntil != 0) { confirmAnswer(false); return true; }
        if (feedMenuUntil != 0) { feedMenuUntil = 0; return true; }
        return false;
    }

    // UP / DOWN: dir -1 = up, +1 = down
    function keyPage(dir as Number) as Boolean {
        if (pet.awaitingStarter()) {
            starterSel = (starterSel + dir + 3) % 3;
            return true;
        }
        if (feedMenuUntil != 0) {
            feedSel = (feedSel + dir + 4) % 4;
            feedMenuUntil = G.millis() + 6000;
            return true;
        }
        if (cardOpen) { swipe(-dir); return true; }
        if (galleryOpen) {
            if (galleryDetail != 0) {
                var d = galleryDetail + dir;
                if (d >= 1 && d <= 151) { openDetail(d); }
            } else {
                swipe(-dir);
            }
            return true;
        }
        if (settingsOpen) { return true; }
        return false;
    }

    function blocked() as Boolean {
        return pet.awaitingStarter() || gameOpen || sackOpen || galleryOpen || cardOpen || settingsOpen ||
            choiceKind != 0 || confirmUntil != 0 || feedMenuUntil != 0;
    }

    // ------------------------------------------------------------------
    // scene
    // ------------------------------------------------------------------
    private function inkColor() as Number { return gNight ? Ui.INK_NIGHT : Ui.INK; }

    private function sceneHour() as Number {
        var e = pet.lastSeenEpoch;
        return e != 0 ? (e / 3600) % 24 : 13;
    }

    private function sky(night as Boolean, h as Number) as Array {
        if (night) { return [0x0C1224, 0x1E2646]; }
        if (h < 8) { return [0xD16A86, 0xF3B87C]; }
        if (h < 18) { return [0x8FC8EA, 0xDCEEE6]; }
        return [0xC75A4A, 0xF0AE64];
    }

    private function drawScene(biome as Number, now as Number, night as Boolean) as Void {
        var h = sceneHour();
        var c = sky(night, h);
        for (var y = 0; y < HORIZON; y += 8) {
            g.fillRect(0, y, 466, 8, Ui.lerp(c[0], c[1], y, HORIZON));
        }
        if (night) {
            g.fillCircle(360, 78, 24, 0xE8EEF5);
            g.fillCircle(370, 72, 22, Ui.lerp(c[0], c[1], 78, HORIZON));
            for (var i = 0; i < STARS.size(); i++) {
                g.fillRect(STARS[i][0], STARS[i][1], 4, 4, Ui.WHITE);
            }
        } else if (h < 18) {
            g.fillCircle(360, 84, 26, h < 8 ? 0xFFD98A : 0xFFE79F);
            for (var k = 0; k < 2; k++) {
                var cx = ((now / 50 + k * 250) % 560) - 40;
                var cy = 70 + k * 34;
                g.fillCircle(cx, cy, 16, 0xFFFFFF);
                g.fillCircle(cx + 18, cy + 3, 13, 0xFFFFFF);
                g.fillCircle(cx - 15, cy + 4, 12, 0xFFFFFF);
            }
        } else {
            g.fillCircle(233, HORIZON - 6, 34, 0xFFF1C8);
        }
        var soil = BIOME_SOIL[biome < 6 ? biome : 0];
        if (night) { soil = Ui.lerp(soil, 0x161C30, 9, 16); }
        if (biome == 1) {
            g.fillRect(0, HORIZON - 26, 466, 26, night ? 0x1C3452 : 0x4F96C4);
            var fc = night ? 0x3A5878 : 0xBFE6F5;
            for (var i = 0; i < 3; i++) {
                var wy = HORIZON - 22 + i * 7;
                g.fillRect(60 + ((now / 60 + i * 30) % 60), wy, 26, 2, fc);
                g.fillRect(300 - ((now / 60 + i * 20) % 60), wy, 26, 2, fc);
            }
        }
        g.fillRect(0, HORIZON, 466, 466 - HORIZON, soil);
        g.fillRoundRect(-60, HORIZON - 14, 586, 60, 30, Ui.lerp(soil, night ? 0x0C1224 : 0xFFFFFF, 3, 16));
        var dk = Ui.lerp(soil, 0x101820, night ? 11 : 7, 16);
        if (biome == 2) {
            var xs = [60, 150, 360, 416];
            for (var i = 0; i < 4; i++) {
                var tx = xs[i];
                g.fillTriangle(tx, HORIZON - 46, tx - 16, HORIZON, tx + 16, HORIZON, dk);
                g.fillTriangle(tx, HORIZON - 60, tx - 12, HORIZON - 28, tx + 12, HORIZON - 28, dk);
            }
        } else if (biome == 3) {
            g.fillTriangle(70, HORIZON, 40, HORIZON + 30, 100, HORIZON + 30, dk);
            g.fillTriangle(400, HORIZON + 4, 372, HORIZON + 30, 430, HORIZON + 30, dk);
            if (!night) {
                for (var e = 0; e < 4; e++) {
                    g.fillRect(120 + e * 70, HORIZON + 8 + (e % 2) * 6, 4, 4, 0xFF9B3A);
                }
            }
        } else if (biome == 4) {
            g.fillTriangle(140, HORIZON - 50, 60, HORIZON, 220, HORIZON, dk);
            g.fillTriangle(330, HORIZON - 38, 250, HORIZON, 410, HORIZON, dk);
        } else if (biome == 5 && !night) {
            for (var f = 0; f < 10; f++) {
                g.fillRect((f * 53 + now / 40) % 466, (f * 90 + now / 18) % HORIZON, 3, 3, Ui.WHITE);
            }
        } else if (biome == 0) {
            var gx = [80, 175, 300, 395];
            for (var i = 0; i < 4; i++) {
                for (var b = -1; b <= 1; b++) {
                    g.fillRect(gx[i] + b * 5, HORIZON + 6, 2, 8 + (b == 0 ? 4 : 0), dk);
                }
            }
        }
    }

    private function roundBg() as Void {
        g.fillCircle(CX, CY, 233, Ui.BG_DAY);
    }

    private function text(str as String, sz as Number, x, y, col as Number) as Void {
        g.textColor = col;
        g.setSize(sz);
        g.setCur(x, y);
        g.print(str);
    }

    private function centered(str as String, sz as Number, y, col as Number) as Void {
        text(str, sz, g.centerX(str, sz), y, col);
    }

    // ------------------------------------------------------------------
    // render
    // ------------------------------------------------------------------
    private function render() as Void {
        if (pet.awaitingStarter()) { renderStarterSelect(); return; }
        if (galleryOpen) { renderGallery(); return; }
        if (gameOpen) { renderGame(); return; }
        if (sackOpen) { renderSack(); return; }
        if (settingsOpen) { renderSettings(); return; }
        if (cardOpen) { renderCard(); return; }

        var h = sceneHour();
        gNight = pet.sleeping || h < 6 || h >= 20;
        drawScene(pet.isEgg() ? 0 : Tables.BIOME[pet.speciesId], G.millis(), gNight);

        if (pet.ceremony != G.CER_NONE) {
            var msg = pet.ceremony == G.CER_FAREWELL ? T(Str.FAREWELL)
                : (pet.ceremony == G.CER_RUNAWAY ? T(Str.RUNAWAY) : T(Str.GOODBYE));
            drawHeader(dexName(pet.speciesId), Tables.ACCENT[pet.speciesId], msg);
            drawCeremony();
            return;
        }

        if (pet.isEgg()) {
            drawHeader(T(Str.EGG_HDR), inkColor(), eggMsg());
            var s = 5;
            var x = CX - 16 * s;
            var y = PET_CY - 16 * s;
            g.drawBitmap(Rez.Drawables.Egg, x, y);
            if (pet.eggCracks() >= 1) {
                for (var i = 0; i < CRACK1.size(); i++) {
                    g.fillRect(x + CRACK1[i][0] * s, y + CRACK1[i][1] * s, s, s, Ui.INK_K);
                }
            }
            if (pet.eggCracks() >= 2) {
                for (var i = 0; i < CRACK2.size(); i++) {
                    g.fillRect(x + CRACK2[i][0] * s, y + CRACK2[i][1] * s, s, s, Ui.INK_K);
                }
            }
            if (pet.eggRarity() >= G.R_RARO) {
                var leg = pet.eggRarity() == G.R_LEGENDARIO;
                centered(leg ? T(Str.EGG_LEGEND) : T(Str.EGG_RARE), 2, 316, leg ? Ui.BAR_WARN : Ui.BLUE);
            }
            g.fillRect(0, 312, 466, 154, gNight ? Ui.BG_NIGHT : Ui.BG_DAY);
            centered(F(Str.POKEDEX_FMT, [pet.registeredCount()]), 2, 348, inkColor());
        } else {
            var base = pet.nick.length() > 0 ? pet.nick : dexName(pet.speciesId);
            var name = F(Str.NAME_FMT, [pet.shiny ? "*" : "", base, pet.level()]);
            drawHeader(name, gNight ? Ui.INK_NIGHT : Tables.ACCENT[pet.speciesId], statusMsg());
            drawStreakBadge();
            drawPet();
            drawBath();
            for (var i = 0; i < pet.poops; i++) {
                g.drawBitmap(Rez.Drawables.Poop, 36 + i * 46, 244);
            }
            g.fillRect(0, 312, 466, 154, gNight ? Ui.BG_NIGHT : Ui.BG_DAY);
            drawBars();
            drawButtons();
            drawCelebration();
            if (pet.wantEvolveButton()) {
                drawEvolveButton();
            } else if (pet.canRunawayNow()) {
                drawEndButton(Str.RUNAWAY_BTN, 0x3A445A, 0x708098, 0xC8D2E0, 3, 0.003);
            } else if (pet.wantFarewellButton()) {
                drawEndButton(Str.FAREWELL_BTN, Ui.BAR_WARN, Ui.INK, Ui.INK, 4, 0.005);
            }
        }

        if (pet.sleeping) {
            text("Zz", 3, 320, 130, Ui.INK_NIGHT);
        }

        if (feedMenuUntil != 0) {
            if (timeLeft(feedMenuUntil) == 0) {
                feedMenuUntil = 0;
            } else {
                g.fillRoundRect(101, 288, 264, 64, 14, Ui.WHITE);
                g.drawRoundRect(101, 288, 264, 64, 14, inkColor());
                g.drawBitmap(Rez.Drawables.MenuRed, 110, 296);
                g.drawBitmap(Rez.Drawables.MenuBlue, 176, 296);
                g.drawBitmap(Rez.Drawables.MenuGreen, 242, 296);
                g.drawBitmap(Rez.Drawables.MenuCandy, 308, 296);
                // button users: which item SELECT will feed
                g.drawRoundRect(104 + feedSel * 66, 291, 60, 58, 10, Ui.BAR_WARN);
            }
        }

        if (confirmUntil != 0) {
            if (timeLeft(confirmUntil) == 0) {
                confirmUntil = 0;
            } else {
                g.fillRoundRect(94, 168, 278, 152, 16, Ui.WHITE);
                g.drawRoundRect(94, 168, 278, 152, 16, Ui.INK);
                centered(F(Str.RELEASE_FMT, [dexName(pet.speciesId)]), 2, 196, Ui.INK);
                g.fillRoundRect(118, 252, 100, 52, 12, Ui.BAR_OK);
                text(T(Str.YES), 2, 118 + (100 - g.textW(T(Str.YES), 2)) / 2, 270, Ui.WHITE);
                g.fillRoundRect(248, 252, 100, 52, 12, Ui.BAR_BAD);
                text(T(Str.NO), 2, 248 + (100 - g.textW(T(Str.NO), 2)) / 2, 270, Ui.WHITE);
            }
        }

        if (choiceKind != 0) {
            if (timeLeft(choiceUntil) == 0) {
                choiceKind = 0;
            } else {
                drawChoiceDialog();
            }
        }
    }

    private function renderStarterSelect() as Void {
        roundBg();
        centered(T(Str.CHOOSE_STARTER), 2, 68, Ui.INK);
        for (var i = 0; i < 3; i++) {
            var d = STARTER_DEX[i];
            var acc = Tables.ACCENT[d];
            var ry = STARTER_ROW_Y + i * (STARTER_ROW_H + STARTER_ROW_GAP);
            g.fillRoundRect(70, ry, 326, STARTER_ROW_H, 14, Ui.lerp(acc, Ui.WHITE, 6, 8));
            g.drawRoundRect(70, ry, 326, STARTER_ROW_H, 14, acc);
            if (i == starterSel) {
                g.drawRoundRect(66, ry - 4, 334, STARTER_ROW_H + 8, 16, Ui.INK);
            }
            drawThumb(d, 76, ry - 5);
            text(dexName(d), 3, 178, ry + 24, Ui.INK);
        }
    }

    // ------------------------------------------------------------------
    // minigame
    // ------------------------------------------------------------------
    function startGame() as Void {
        if (pet.isEgg() || pet.sleeping || pet.ceremony != G.CER_NONE) {
            return;
        }
        gameOpen = true;
        gameOverUntil = 0;
        gameScore = 0;
        gameMisses = 0;
        gameNewHi = false;
        hitTime = 0;
        gamePetX = 233.0;
        lastGameStep = G.millis();
        respawnBall();
    }

    private function respawnBall() as Void {
        ballX = (150 + G.random(166)).toFloat();
        ballY = 96.0;
        var sp = 1.6 + gameScore * 0.05;
        if (sp > 4.0) { sp = 4.0; }
        ballVX = G.random(2) == 1 ? sp : -sp;
        ballVY = 0.0;
    }

    private function gameTap(x as Number, y as Number) as Void {
        if (gameOverUntil != 0) { return; }
        if (y < 72) { gameOpen = false; return; }
        var dx = ballX - x;
        var dy = ballY - y;
        if (dx * dx + dy * dy < 74 * 74) {
            gameScore++;
            sfxPlay(G.SFX_PLAY);
            ballVY = -(6.6 + (gameScore > 16 ? 3.5 : gameScore * 0.22));
            ballVX += dx * 0.12;
            if (ballVX > 6.5) { ballVX = 6.5; }
            if (ballVX < -6.5) { ballVX = -6.5; }
            hitX = ballX;
            hitY = ballY;
            hitTime = G.millis();
        }
    }

    private function stepGame() as Void {
        var now = G.millis();
        var k = lastGameStep != 0 ? (now - lastGameStep) / 85.0 : 1.0;
        if (k > 3.0) { k = 3.0; }
        lastGameStep = now;
        var grav = 0.40 + gameScore * 0.013;
        if (grav > 0.80) { grav = 0.80; }
        ballVY += grav * k;
        ballX += ballVX * k;
        ballY += ballVY * k;
        var dx = ballX - CX;
        var dy = ballY - CY;
        var d = Math.sqrt(dx * dx + dy * dy);
        if (d > 205) {
            var nx = dx / d;
            var ny = dy / d;
            var dot = ballVX * nx + ballVY * ny;
            if (dot > 0) {
                ballVX = (ballVX - 2 * dot * nx) * 0.85;
                ballVY = (ballVY - 2 * dot * ny) * 0.85;
            }
            ballX = CX + nx * 205;
            ballY = CY + ny * 205;
        }
        if (ballY > 384) {
            gameMisses++;
            if (gameMisses >= 3) {
                gameNewHi = gameScore > pet.gameHi;
                pet.playResult(gameScore);
                sfxPlay(gameNewHi && gameScore > 0 ? G.SFX_MEDAL : G.SFX_LEVEL);
                gameOverUntil = G.millis() + 4000;
            } else {
                respawnBall();
            }
        }
        var chase = (ballX - gamePetX) * 0.12;
        if (chase > 7) { chase = 7.0; }
        if (chase < -7) { chase = -7.0; }
        gamePetX += chase * k;
    }

    private function drawGameScene() as Void {
        var hh = sceneHour();
        var night = hh < 6 || hh >= 20;
        var c = sky(night, hh);
        var hor = 376;
        for (var y = 0; y < hor; y += 8) {
            g.fillRect(0, y, 466, 8, Ui.lerp(c[0], c[1], y, hor));
        }
        if (night) {
            for (var i = 0; i < STARS.size(); i++) {
                g.fillRect(STARS[i][0], STARS[i][1], 4, 4, Ui.WHITE);
            }
        }
        var bio = pet.isEgg() ? 0 : Tables.BIOME[pet.speciesId];
        var soil = BIOME_SOIL[bio < 6 ? bio : 0];
        if (night) { soil = Ui.lerp(soil, 0x161C30, 9, 16); }
        g.fillRect(0, hor, 466, 466 - hor, soil);
    }

    private function renderGame() as Void {
        var night = sceneHour() < 6 || sceneHour() >= 20;
        var ink = night ? Ui.INK_NIGHT : Ui.INK;
        drawGameScene();
        if (gameOverUntil != 0) {
            if (timeLeft(gameOverUntil) == 0) {
                gameOpen = false;
                return;
            }
            centered(F(Str.SCORE_FMT, [gameScore]), 4, 160, ink);
            if (gameNewHi && gameScore > 0) {
                centered(T(Str.NEW_RECORD), 2, 214, Ui.BAR_WARN);
            } else {
                centered(F(Str.RECORD_FMT, [pet.gameHi]), 2, 214, ink);
            }
            centered(gameScore >= 10 ? T(Str.GREAT_JOY) : T(Str.PLUS_JOY), 2, 250, ink);
            return;
        }
        stepGame();
        centered(gameScore.toString(), 4, 30, ink);
        centered(F(Str.REC_FMT, [pet.gameHi]), 2, 76, ink);
        for (var i = 0; i < 3; i++) {
            if (i < 3 - gameMisses) {
                g.fillCircle(180 + i * 28, 104, 6, Ui.BAR_BAD);
            } else {
                g.drawCircle(180 + i * 28, 104, 6, Ui.TRACK);
            }
        }
        // the pet follows the ball along the ground (x3 like the firmware: 3/5 of the main size)
        drawMon(monFor, gamePetX.toNumber(), 394, G.millis(), true);
        var ht = G.millis() - hitTime;
        if (hitTime != 0 && ht < 260) {
            var rad = 22 + ht / 6;
            g.drawCircle(hitX, hitY, rad, 0xFFE79F);
            g.drawCircle(hitX, hitY, rad - 2, 0xFFD98A);
        }
        g.drawBitmap(Rez.Drawables.Ball, ballX.toNumber() - 24, ballY.toNumber() - 24);
    }

    // ------------------------------------------------------------------
    // training bag
    // ------------------------------------------------------------------
    function startSack() as Void {
        if (pet.isEgg() || pet.sleeping || pet.ceremony != G.CER_NONE) {
            return;
        }
        sackOpen = true;
        sackUntil = G.millis() + 10000;
        sackOverUntil = 0;
        sackHits = 0;
        sackShake = 0.0;
        sackNewHi = false;
    }

    private function sackTap() as Void {
        if (timeLeft(sackUntil) == 0) {
            return;
        }
        sackHits++;
        sackShake = 16.0;
    }

    private function renderSack() as Void {
        var now = G.millis();
        drawGameScene();
        var night = sceneHour() < 6 || sceneHour() >= 20;
        var ink = night ? Ui.INK_NIGHT : Ui.INK;
        if (sackOverUntil != 0) {
            if (timeLeft(sackOverUntil) == 0) {
                sackOpen = false;
                return;
            }
            centered(F(Str.HITS_FMT, [sackHits]), 4, 150, ink);
            centered(F(Str.STR_GAIN_FMT, [sackGain]), 3, 210, Ui.BAR_BAD);
            if (sackNewHi && sackHits > 0) {
                centered(T(Str.NEW_RECORD), 2, 256, Ui.BAR_WARN);
            } else {
                centered(F(Str.RECORD_FMT, [pet.strHi]), 2, 256, ink);
            }
            return;
        }
        if (timeLeft(sackUntil) == 0) {
            sackNewHi = sackHits > pet.strHi;
            sackGain = pet.trainStrength(sackHits);
            sfxPlay(sackNewHi ? G.SFX_MEDAL : G.SFX_PLAY);
            sackOverUntil = now + 3500;
            return;
        }
        sackShake *= 0.84;
        var off = (sackShake * Math.sin(now * 0.05)).toNumber();
        var sx = CX + off;
        var top = 86;
        g.fillRect(CX - 3, 56, 6, top - 56, ink);
        g.fillRect(sx - 4, top - 30, 8, 34, ink);
        g.fillRoundRect(sx - 42, top, 84, 150, 26, 0xB53A3A);
        g.fillRoundRect(sx - 42, top, 84, 22, 18, 0x7E2828);
        g.drawRoundRect(sx - 42, top, 84, 150, 26, ink);
        g.fillRect(sx - 42, top + 70, 84, 4, 0x7E2828);
        centered(sackHits.toString(), 6, 268, ink);
        centered(T(Str.HIT_FAST), 2, 322, ink);
        var left = sackUntil - now;
        var bw = 280;
        var fw = bw * left / 10000;
        g.fillRoundRect(CX - bw / 2, 350, bw, 16, 5, Ui.TRACK);
        if (fw > 2) {
            g.fillRoundRect(CX - bw / 2, 350, fw, 16, 5, Ui.BAR_OK);
        }
    }

    // ------------------------------------------------------------------
    // card (swipe up / menu)
    // ------------------------------------------------------------------
    private function statBarX() as Number {
        var ids = [Str.STAT_ATK, Str.STAT_DEF, Str.STAT_SPE, Str.STAT_WGT, Str.VIN];
        var w = 0;
        for (var i = 0; i < ids.size(); i++) {
            w = G.max2(w, g.textW(T(ids[i]), 2));
        }
        return G.max2(150, 96 + w + 12);
    }

    private function drawCardStat(y as Number, label as String, v as Number, maxBar as Number, color as Number) as Void {
        text(label, 2, 96, y, Ui.INK);
        text(v.toString(), 2, 330, y, Ui.INK);
        var bx = statBarX();
        var bw = 310 - bx;
        var fw = G.min2(v * bw / maxBar, bw);
        g.fillRoundRect(bx, y + 2, bw, 11, 3, Ui.TRACK);
        if (fw > 2) {
            g.fillRoundRect(bx, y + 2, fw, 11, 3, color);
        }
    }

    private function drawFlame(x as Number, y as Number) as Void {
        g.fillTriangle(x + 8, y, x + 1, y + 17, x + 15, y + 17, Ui.BAR_BAD);
        g.fillTriangle(x + 8, y + 7, x + 4, y + 17, x + 12, y + 17, Ui.BAR_WARN);
    }

    private function drawStreakBadge() as Void {
        if (pet.streak < 1) {
            return;
        }
        drawFlame(26, 16);
        text(pet.streak.toString(), 2, 48, 18, inkColor());
    }

    private function drawCelebration() as Void {
        var l1;
        var l2;
        if (pet.showMedal()) {
            l2 = "";
            for (var i = 0; i < G.MED_COUNT; i++) {
                if ((pet.newMedal & (1 << i)) != 0) {
                    l2 = Tables.MED_NAME[i];
                    break;
                }
            }
            l1 = T(Str.MEDAL_BANNER);
        } else if (pet.showMilestone()) {
            l1 = T(Str.GREAT);
            l2 = F(Str.STREAK_DAYS_FMT, [pet.streak]);
        } else {
            return;
        }
        g.fillRoundRect(73, 150, 320, 96, 16, Ui.BAR_WARN);
        g.drawRoundRect(73, 150, 320, 96, 16, Ui.INK);
        centered(l1, 3, 176, Ui.INK);
        centered(l2, 2, 212, Ui.INK);
    }

    private function renderCard() as Void {
        roundBg();
        var sp = pet.speciesId;
        if (cardPage == 0) {
            var nm = pet.nick.length() > 0 ? pet.nick : dexName(sp);
            var head = F(Str.NAME_FMT, [pet.shiny ? "*" : "", nm, pet.level()]);
            var hts = g.textW(head, 3) <= 198 ? 3 : 2;
            centered(head, hts, hts == 3 ? 34 : 40, Tables.ACCENT[sp]);
            drawMon(sp, CX, 206, G.millis(), false);
            drawFlame(138, 224);
            text(F(Str.STREAK_FMT, [pet.streak, pet.bestStreak]), 2, 162, 226, Ui.INK);
            drawCardStat(258, T(Str.VIN), pet.bond, 100, 0xD4527E);
            var berry = !pet.berryKnown ? T(Str.BERRY_UNK)
                : (pet.lovesBerry(0) ? T(Str.BERRY_RED) : (pet.lovesBerry(1) ? T(Str.BERRY_BLUE) : T(Str.BERRY_GREEN)));
            centered(F(Str.INFO_FMT, [berry, pet.ageMinutes / 1440]), 2, 296, Ui.INK);
        } else if (cardPage == 1) {
            centered(T(Str.BATTLE), 3, 48, Ui.INK);
            drawCardStat(118, T(Str.STAT_ATK), pet.atkStat(), 260, Ui.BAR_BAD);
            drawCardStat(160, T(Str.STAT_DEF), pet.defStat(), 260, Ui.BLUE);
            drawCardStat(202, T(Str.STAT_SPE), pet.speStat(), 260, Ui.BAR_WARN);
            drawCardStat(244, T(Str.STAT_WGT), pet.weight, 100, 0xB07A45);
            g.fillRoundRect(96, 300, 274, 40, 12, Ui.BAR_BAD);
            centered(T(Str.TRAIN_STR), 2, 311, Ui.BG_DAY);
        } else if (cardPage == 2) {
            var got = 0;
            for (var i = 0; i < G.MED_COUNT; i++) {
                if (pet.hasMedal(1 << i)) { got++; }
            }
            centered(F(Str.MEDALS_FMT, [got, G.MED_COUNT]), 3, 48, Ui.INK);
            for (var i = 0; i < G.MED_COUNT; i++) {
                var x = 28 + (i % 2) * 206;
                var y = 104 + (i / 2) * 54;
                var gm = pet.hasMedal(1 << i);
                g.fillRoundRect(x, y, 196, 44, 10, gm ? Ui.BAR_OK : Ui.TRACK);
                if (gm) {
                    g.fillCircle(x + 22, y + 22, 11, Ui.BG_DAY);
                    text("v", 2, x + 16, y + 13, Ui.BAR_OK);
                }
                text(Tables.MED_DSC[i], 2, x + 44, y + 14, gm ? Ui.BG_DAY : 0x808080);
            }
        } else {
            centered(T(Str.PROGRESS), 3, 44, Ui.INK);
            centered(F(Str.LVL_FMT, [pet.level()]), 5, 86, Ui.INK);
            var into = pet.ageMinutes % G.MINUTES_PER_LEVEL;
            g.fillRoundRect(93, 158, 280, 22, 6, Ui.TRACK);
            var fw = 276 * into / G.MINUTES_PER_LEVEL;
            if (fw > 0) {
                g.fillRoundRect(95, 160, fw, 18, 5, Ui.BAR_OK);
            }
            centered(F(Str.NEXT_LVL_FMT, [G.MINUTES_PER_LEVEL - into, pet.level() + 1]), 2, 190, Ui.INK);
            centered(T(Str.EVO_LABEL), 2, 230, Ui.TRACK);
            var evo;
            var col = Ui.INK;
            if (Tables.EVOLVES_TO[sp] == 0) {
                evo = T(Str.FINAL_FORM);
            } else {
                var needed = Tables.EVOLVE_LEVEL[sp] + pet.careMistakes;
                if (pet.level() >= needed) {
                    if (pet.lowestStat() >= 40) {
                        evo = T(Str.EVO_READY);
                        col = Ui.BAR_OK;
                    } else {
                        evo = T(Str.EVO_BLOCKED);
                        col = Ui.BAR_BAD;
                    }
                } else {
                    evo = F(Str.EVO_IN_FMT, [needed - pet.level()]);
                }
            }
            centered(evo, 2, 256, col);
            centered(F(Str.MISTAKES_FMT, [pet.careMistakes]), 2, 312, pet.careMistakes > 0 ? Ui.BAR_BAD : Ui.INK);
        }
        for (var i = 0; i < 4; i++) {
            if (i == cardPage) {
                g.fillCircle(194 + i * 26, 374, 5, Ui.INK);
            } else {
                g.drawCircle(194 + i * 26, 374, 4, Ui.INK);
            }
        }
        centered(T(Str.BACK), 2, 398, Ui.TRACK);
    }

    // ------------------------------------------------------------------
    // settings (swipe down / menu): the watch keeps the time, so only sound
    // ------------------------------------------------------------------
    function toggleSound() as Void {
        soundOn = !soundOn;
        Application.Storage.setValue("snd", soundOn);
        if (soundOn) {
            sfxPlay(G.SFX_TAP);
        }
    }

    private function renderSettings() as Void {
        roundBg();
        var e = pet.lastSeenEpoch;
        var clock = ((e / 3600) % 24).format("%02d") + ":" + ((e / 60) % 60).format("%02d");
        centered(clock, 6, 90, Ui.INK);
        var sl = soundOn ? T(Str.SND_ON) : T(Str.SND_OFF);
        g.fillRoundRect(163, 200, 140, 44, 10, soundOn ? Ui.BAR_OK : Ui.WHITE);
        g.drawRoundRect(163, 200, 140, 44, 10, Ui.INK);
        centered(sl, 2, 215, soundOn ? Ui.BG_DAY : Ui.INK);
        centered(T(Str.CLOCK_CANCEL), 2, 330, Ui.TRACK);
        centered("PokeWatch 1.0 - TamaPoke v1.18 port", 1, 410, Ui.TRACK);
    }

    private function settingsTap(x as Number, y as Number) as Void {
        if (y >= 200 && y <= 244 && x >= 163 && x <= 303) {
            toggleSound();
            return;
        }
        settingsOpen = false;
    }

    // ------------------------------------------------------------------
    // Pokédex (swipe sideways / menu)
    // ------------------------------------------------------------------
    private function drawThumb(dex as Number, x as Number, y as Number) as Void {
        var id = thumbIds[dex];
        if (id == null) {
            return;
        }
        g.drawBitmap(id, x + (GAL_CELL - SpriteIds.TW[dex]) / 2, y + (GAL_CELL - SpriteIds.TH[dex]) / 2);
    }

    private function openDetail(d as Number) as Void {
        closeDetail();
        galleryDetail = d;
    }

    private function renderGallery() as Void {
        roundBg();
        if (galleryDetail != 0) {
            var d = galleryDetail;
            var reg = pet.isRegistered(d);
            var head = "N." + d.format("%03d") + " " + (pet.isShinyRegistered(d) ? "*" : "") + (reg ? dexName(d) : "???");
            var gts = g.textW(head, 3) <= 234 ? 3 : 2;
            centered(head, gts, gts == 3 ? 56 : 60, reg ? Tables.ACCENT[d] : Ui.INK);
            if (reg) {
                drawMon(d, CX, 300, G.millis(), false);
            } else {
                centered("?", 7, 180, Ui.TRACK);
            }
            centered(T(Str.DETAIL_BACK), 2, 408, Ui.INK);
            return;
        }
        centered(F(Str.POKEDEX_FMT, [pet.registeredCount()]), 3, 36, Ui.INK);
        for (var r = 0; r < 4; r++) {
            for (var c = 0; c < 4; c++) {
                var dex = galleryPage * 16 + r * 4 + c + 1;
                if (dex > 151) {
                    break;
                }
                var x = GAL_X + c * GAL_CELL;
                var y = GAL_Y + r * GAL_CELL;
                // no silhouettes on Garmin: unseen species show their number
                if (pet.isRegistered(dex) && thumbIds[dex] != null) {
                    drawThumb(dex, x, y);
                    if (pet.isShinyRegistered(dex)) {
                        text("*", 2, x + 62, y + 4, Ui.BAR_WARN);
                    }
                } else {
                    text(dex.toString(), 2, x + 24, y + 32, pet.isRegistered(dex) ? Ui.INK : Ui.TRACK);
                }
            }
        }
        for (var i = 0; i < 10; i++) {
            if (i == galleryPage) {
                g.fillCircle(170 + i * 14, 436, 4, Ui.INK);
            } else {
                g.drawCircle(170 + i * 14, 436, 3, Ui.INK);
            }
        }
    }

    private function galleryTap(x as Number, y as Number) as Void {
        if (galleryDetail != 0) {
            closeDetail();
            return;
        }
        if (y < 72) {
            galleryOpen = false;
            return;
        }
        if (x < GAL_X || y < GAL_Y) {
            return;
        }
        var c = (x - GAL_X) / GAL_CELL;
        var r = (y - GAL_Y) / GAL_CELL;
        if (c > 3 || r > 3) {
            return;
        }
        var dex = galleryPage * 16 + r * 4 + c + 1;
        if (dex <= 151) {
            openDetail(dex);
        }
    }

    // ------------------------------------------------------------------
    // header, ceremonies, dialogs
    // ------------------------------------------------------------------
    private function drawBattery() as Void {
        var st = System.getSystemStats();
        var pc = st.battery.toNumber();
        var charging = (st has :charging) ? st.charging : false;
        var x = CX - 14;
        var y = 12;
        var col = charging ? Ui.BAR_OK : (pc >= 40 ? inkColor() : (pc >= 15 ? Ui.BAR_WARN : Ui.BAR_BAD));
        g.drawRoundRect(x, y, 24, 11, 2, col);
        g.fillRect(x + 24, y + 3, 3, 5, col);
        var fw = 20 * pc / 100;
        if (fw > 0) {
            g.fillRect(x + 2, y + 2, fw, 7, col);
        }
    }

    private function drawHeader(name as String, nameColor as Number, msg as String) as Void {
        drawBattery();
        centered(name, 3, 52, nameColor);
        centered(msg, 2, 90, inkColor());
    }

    private function drawCeremony() as Void {
        var now = G.millis();
        var t = pet.ceremonyT();
        var x = CX;
        if (pet.ceremony == G.CER_RUNAWAY) {
            for (var i = 0; i < 46; i++) {
                var rx = (i * 47 + now / 3) % 466;
                var ry = (i * 91 + now / 2) % 470;
                g.drawLine(rx, ry, rx - 3, ry + 12, 0x6A84B0);
            }
            if (t < 0.30) {
                x = CX + (4 * Math.sin(now * 0.04)).toNumber();
            } else {
                x = CX - ((t - 0.30) / 0.70 * (CX + 120)).toNumber();
            }
            // fading: blink out instead of the firmware's silhouette
            if (!(t > 0.6 && (now / 160) % 2 == 0)) {
                drawMon(pet.speciesId, x, PET_GROUND, now, true);
            }
            if (t < 0.55) {
                g.fillRect(x + 6, PET_GROUND - 150 + (now / 6) % 40, 3, 6, 0x9AC4E8);
            }
            return;
        }
        var gcy = PET_GROUND - 96;
        for (var k = 0; k < 4; k++) {
            g.drawCircle(CX, gcy, 60 + k * 34 + (10 * Math.sin(now * 0.02)).toNumber(), 0xFFDF8A);
        }
        for (var i = 0; i < 16; i++) {
            var px = (i * 71 + 28) % 466;
            var py = 410 - (now / 8 + i * 70) % 360;
            if (py < 30) {
                continue;
            }
            if (i % 4 == 0) {
                g.drawBitmap(Rez.Drawables.HeartSmall, px - 8, py - 8);
            } else {
                g.fillRect(px, py, 4, 4, i % 2 == 1 ? 0xFFE79F : 0xFF9AC0);
            }
        }
        if (t >= 0.45) {
            x = CX + ((t - 0.45) / 0.55 * (CX + 140)).toNumber();
        }
        drawMon(pet.speciesId, x, PET_GROUND, now, true);
        if (pet.showHeart()) {
            g.drawBitmap(Rez.Drawables.Heart, x + 50, PET_GROUND - 190);
        }
    }

    private function drawChoiceDialog() as Void {
        var evo = choiceKind == 1;
        g.fillRoundRect(73, 156, 320, 188, 16, Ui.WHITE);
        g.drawRoundRect(73, 156, 320, 188, 16, Ui.INK);
        centered(evo ? T(Str.EVO_Q) : T(Str.FAR_Q), 2, 176, Ui.INK);
        g.fillRoundRect(93, 206, 280, 52, 12, evo ? Ui.BAR_BAD : Ui.BAR_WARN);
        centered(evo ? T(Str.EVO_TAP) : T(Str.FAR_GO), 2, 224, evo ? Ui.WHITE : Ui.INK);
        g.fillRoundRect(93, 268, 280, 52, 12, evo ? Ui.TRACK : Ui.BAR_OK);
        centered(evo ? T(Str.EVO_KEEP) : T(Str.FAR_STAY), 2, 286, evo ? Ui.INK : Ui.WHITE);
    }

    private function drawEvolveButton() as Void {
        var p = (5 * Math.sin(G.millis() * 0.006)).toNumber();
        var x = EVO_BTN_X - p;
        var y = EVO_BTN_Y - p;
        var w = EVO_BTN_W + 2 * p;
        var h = EVO_BTN_H + 2 * p;
        g.fillRoundRect(x, y, w, h, 18, Ui.BAR_BAD);
        g.drawRoundRect(x, y, w, h, 18, Ui.WHITE);
        g.drawRoundRect(x + 2, y + 2, w - 4, h - 4, 16, Ui.WHITE);
        centered(T(Str.EVO_TAP), 3, y + h / 2 - 11, Ui.WHITE);
    }

    private function drawEndButton(id as Number, fill as Number, edge as Number, ink as Number, amp as Number, speed as Float) as Void {
        var p = (amp * Math.sin(G.millis() * speed)).toNumber();
        var x = FAR_BTN_X - p;
        var y = FAR_BTN_Y - p;
        var w = FAR_BTN_W + 2 * p;
        var h = FAR_BTN_H + 2 * p;
        g.fillRoundRect(x, y, w, h, 16, fill);
        g.drawRoundRect(x, y, w, h, 16, edge);
        var nm = pet.nick.length() > 0 ? pet.nick : dexName(pet.speciesId);
        centered(F(id, [nm]), 2, y + h / 2 - 8, ink);
    }

    // ------------------------------------------------------------------
    // the pet
    // ------------------------------------------------------------------
    // idle animation of species `dex`, feet on groundY (sizes from SpriteIds)
    private function drawMon(dex as Number, cx as Number, groundY as Number, t as Number, loop as Boolean) as Void {
        if (dex < 1 || dex > 151) {
            return;
        }
        var id = strips[dex];
        var n = SpriteIds.FRAMES[dex];
        if (id == null || n == 0) {
            return;
        }
        var ms = SpriteIds.MS[dex];
        var fi = (t / (ms > 0 ? ms : 150)) % n;
        g.drawFrame(id, n, fi, cx - SpriteIds.FW[dex] / 2, groundY - SpriteIds.BASE[dex]);
    }

    private function drawPet() as Void {
        var now = G.millis();
        var dex = pet.speciesId;
        if (strips[dex] == null) {
            text("?", 6, CX - 18, PET_CY - 80, inkColor());
            centered(T(Str.NO_SPRITES), 2, PET_CY - 4, inkColor());
            centered("run tools/fetch_sprites", 2, PET_CY + 20, inkColor());
            return;
        }
        if (pet.evolving()) {
            drawEvolveFX(now);
            return;
        }
        if (evoId != null) {
            g.forget(evoId);
            evoId = null;
        }
        var mood = pet.mood();
        if (mood == G.MOOD_SLEEPING) {
            behMode = 0;
            drawMon(dex, behX.toNumber(), PET_GROUND, 0, false);
        } else {
            if (now > behUntil) {
                behNext();
            }
            if (behMode == 1 && mood == G.MOOD_HAPPY) {
                var d = behTargetX - behX;
                if (d.abs() < 4) {
                    behNext();
                } else {
                    var dt = walkLast != 0 ? now - walkLast : 100;
                    if (dt > 200) { dt = 200; }
                    var step = 30.0 * dt / 1000.0;
                    if (step > d.abs()) { step = d.abs(); }
                    behX += d > 0 ? step : -step;
                }
                walkLast = now;
            } else {
                walkLast = 0;
            }
            // eating / sad: a little shake instead of the PMD eat and hurt animations
            var jig = (mood == G.MOOD_EATING) ? (3 * Math.sin(now * 0.05)).toNumber() : 0;
            drawMon(dex, behX.toNumber() + jig, PET_GROUND, now - behT0, true);
        }
        if (pet.showHeart()) {
            g.drawBitmap(Rez.Drawables.Heart, behX.toNumber() + 50, PET_GROUND - 190);
        }
    }

    private function behNext() as Void {
        var now = G.millis();
        behT0 = now;
        if (G.random(100) < 35) {
            behMode = 1;
            behTargetX = (150 + G.random(176)).toFloat();
            behUntil = now + 15000;
        } else {
            behMode = 0;
            behUntil = now + 2000 + G.random(3000);
        }
    }

    private function drawEvolveFX(now as Number) as Void {
        var t = pet.evolveT();
        var cy = PET_GROUND - 96;
        var halo = 36 + (t * 150).toNumber() + (8 * Math.sin(now * 0.02)).toNumber();
        for (var k = 0; k < 4; k++) {
            var r = halo - k * 7;
            if (r > 0) {
                g.drawCircle(CX, cy, r, Ui.WHITE);
            }
        }
        var base = now * 0.004;
        for (var i = 0; i < 12; i++) {
            var a = base + i * Math.PI / 6;
            var len = 90 + (70 * (0.5 + 0.5 * Math.sin(now * 0.012 + i))).toNumber();
            g.drawLine(CX, cy, CX + (Math.cos(a) * len).toNumber(), cy + (Math.sin(a) * len).toNumber(), Ui.WHITE);
        }
        var period = 60 + (220 * (1.0 - t)).toNumber();
        var showOld = t < 0.9 && evoId != null && (now / period) % 2 == 0;
        drawMon(showOld ? evoDex : pet.speciesId, CX, PET_GROUND, 0, false);
        for (var i = 0; i < 10; i++) {
            var a = i * Math.PI / 5 + t * 4.0;
            var d = (now / 14 + i * 33) % 200;
            g.fillRect(CX + (Math.cos(a) * d).toNumber() - 2, cy + (Math.sin(a) * d).toNumber() - 2, 5, 5,
                (i & 1) == 1 ? 0xFFE070 : Ui.WHITE);
        }
        if (t > 0.9) {
            g.fillCircle(CX, cy, (300 * (t - 0.9) / 0.1).toNumber(), Ui.WHITE);
        }
    }

    function startBath() as Void {
        if (pet.isEgg() || pet.sleeping || pet.ceremony != G.CER_NONE || bathUntil != 0) {
            return;
        }
        bathUntil = G.millis() + 3000;
        bathPending = true;
        var cx = behX.toNumber();
        for (var i = 0; i < 14; i++) {
            bubbles[i] = [cx - 70 + G.random(140), PET_GROUND - G.random(150), 8 + G.random(16), G.random(64)];
        }
    }

    private function drawBath() as Void {
        var now = G.millis();
        if (timeLeft(bathUntil) == 0) {
            bathUntil = 0;
            if (bathPending) {
                bathPending = false;
                pet.clean();
            }
            return;
        }
        var left = bathUntil - now;
        if (left > 800) {
            var t = now / 220.0;
            for (var i = 0; i < 14; i++) {
                var b = bubbles[i];
                var bx = b[0] + (Math.sin(t + b[3]) * 6).toNumber();
                var by = b[1] - (3000 - left) / 90;
                g.fillCircle(bx, by, b[2], Ui.WHITE);
                g.drawCircle(bx, by, b[2], 0x7CC4EA);
                g.fillCircle(bx - b[2] / 3, by - b[2] / 3, b[2] / 4, Ui.BG_DAY);
            }
        } else {
            for (var i = 0; i < 8; i++) {
                var b = bubbles[i];
                var sx = b[0] + (i % 3) * 6 - 6;
                var sy = b[1] - 18;
                var col = i % 2 == 1 ? Ui.BAR_WARN : Ui.WHITE;
                g.fillRect(sx - 6, sy - 1, 13, 3, col);
                g.fillRect(sx - 1, sy - 6, 3, 13, col);
            }
        }
    }

    private function barLabelGap() as Number {
        var ids = [Str.BAR_FOOD, Str.BAR_JOY, Str.BAR_ENE, Str.BAR_HYG];
        var w = 0;
        for (var i = 0; i < ids.size(); i++) {
            w = G.max2(w, g.textW(T(ids[i]), 2));
        }
        return w <= 48 ? 48 : w + 8;
    }

    private function drawBars() as Void {
        var gap = barLabelGap();
        drawBar(78, 318, T(Str.BAR_FOOD), pet.fullness, gap);
        drawBar(244, 318, T(Str.BAR_JOY), pet.joy, gap);
        drawBar(78, 346, T(Str.BAR_ENE), pet.energy, gap);
        drawBar(244, 346, T(Str.BAR_HYG), pet.hygiene, gap);
    }

    private function drawBar(x as Number, y as Number, label as String, v as Number, gap as Number) as Void {
        text(label, 2, x, y, inkColor());
        var bw = G.min2(232 - (78 + gap), 100);
        var bx = x + gap;
        var fill = v >= 50 ? Ui.BAR_OK : (v >= 25 ? Ui.BAR_WARN : Ui.BAR_BAD);
        g.fillRoundRect(bx, y, bw, 15, 4, Ui.TRACK);
        var fw = (bw - 4) * v / 100;
        if (fw > 0) {
            g.fillRoundRect(bx + 2, y + 2, fw, 11, 3, fill);
        }
    }

    private function drawButtons() as Void {
        var icons = [Rez.Drawables.IcoFood, Rez.Drawables.IcoPlay, Rez.Drawables.IcoLight, Rez.Drawables.IcoClean];
        for (var i = 0; i < 4; i++) {
            var off = pet.sleeping && i != 2;
            var bx = BUTTONS[i][0] - BTN_HALF;
            var by = BUTTONS[i][1] - BTN_HALF;
            if (!pet.sleeping) {
                g.fillRoundRect(bx, by, 2 * BTN_HALF, 2 * BTN_HALF, 14, Ui.WHITE);
            }
            g.drawRoundRect(bx, by, 2 * BTN_HALF, 2 * BTN_HALF, 14, inkColor());
            if (!off) {
                g.drawBitmap(icons[i], BUTTONS[i][0] - 16, BUTTONS[i][1] - 16);
            }
        }
    }

    private function eggMsg() as String {
        var c = pet.eggCracks();
        return c == 0 ? T(Str.EGG_TOUCH) : (c == 1 ? T(Str.EGG_MOVES) : T(Str.EGG_ALMOST));
    }

    private function statusMsg() as String {
        if (pet.evolving()) { return T(Str.EVOLVING); }
        if (bathUntil != 0) { return "Splish splash!"; }
        if (pet.sleeping) { return "Zzz..."; }
        if (pet.eating()) { return T(Str.EATING); }
        if (pet.showHeart()) { return T(Str.LIKES); }
        if (pet.fullness < 25) { return T(Str.HUNGRY); }
        if (pet.hygiene < 25) { return T(Str.NEEDS_BATH); }
        if (pet.energy < 25) { return T(Str.EXHAUSTED); }
        if (pet.joy < 25) { return T(Str.SAD); }
        if (pet.weight > 60) { return T(Str.CHUBBY); }
        if (pet.shiny && pet.ageMinutes < 15) { return T(Str.IS_SHINY); }
        return T(Str.HAPPY);
    }
}
