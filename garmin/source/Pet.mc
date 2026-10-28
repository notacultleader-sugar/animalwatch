// Port of TamaPoke's pet.h / pet.cpp (MIT, (c) 2026 Quique Tortosa).
// Same rules and numbers as the firmware and the Wear OS port (Pet.kt).
import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

module G {
    const PET_TICK_MS = 60000;
    const MINUTES_PER_LEVEL = 60;
    const EAT_ANIM_MS = 2500;
    const HEART_MS = 1500;
    const EVOLVE_ANIM_MS = 5200;
    const CEREMONY_MS = 10000;
    const FAREWELL_AGE_MIN = 4320; // 3 days
    const RUNAWAY_TICKS = 60;

    const CER_NONE = 0;
    const CER_FAREWELL = 1;
    const CER_RUNAWAY = 2;
    const CER_RELEASE = 3;

    const R_EVO = 0;
    const R_COMUN = 1;
    const R_RARO = 2;
    const R_LEGENDARIO = 3;

    const DEX_EEVEE = 133;
    const CLASSIC_DEX = [1, 4, 7, 25, 133] as Array<Number>;

    const MED_LV10 = 1;
    const MED_LV25 = 2;
    const MED_LV50 = 4;
    const MED_BERRY = 8;
    const MED_STREAK7 = 16;
    const MED_BOND = 32;
    const MED_FINAL = 64;
    const MED_FIT = 128;
    const MED_COUNT = 8;

    const MOOD_HAPPY = 0;
    const MOOD_SAD = 1;
    const MOOD_EATING = 2;
    const MOOD_SLEEPING = 3;

    const SFX_TAP = 0;
    const SFX_EAT = 1;
    const SFX_PLAY = 2;
    const SFX_HEART = 3;
    const SFX_HATCH = 4;
    const SFX_EVOLVE = 5;
    const SFX_MEDAL = 6;
    const SFX_DENY = 7;
    const SFX_BYE = 8;
    const SFX_LEVEL = 9;

    function millis() as Number {
        return System.getTimer();
    }

    function random(n as Number) as Number {
        return (Math.rand() & 0x7FFFFFFF) % n;
    }

    function min2(a as Number, b as Number) as Number {
        return a < b ? a : b;
    }

    function max2(a as Number, b as Number) as Number {
        return a > b ? a : b;
    }

    function clamp100(v as Number) as Number {
        return v < 0 ? 0 : (v > 100 ? 100 : v);
    }

    // offline decay with mercy: never below the floor
    function dropTo(v as Number, d as Number, fl as Number) as Number {
        if (v <= fl) {
            return v;
        }
        return (v - fl > d) ? v - d : fl;
    }

    function bitCount(v as Number) as Number {
        var n = 0;
        while (v != 0) {
            v = v & (v - 1);
            n++;
        }
        return n;
    }
}

class Pet {
    var fullness = 80;
    var joy = 80;
    var energy = 80;
    var hygiene = 100;
    var poops = 0;
    var weight = 0;
    var geneAtk = 100;
    var geneDef = 100;
    var geneSpe = 100;
    var trAtk = 0;
    var trDef = 0;
    var trSpe = 0;
    var berryKnown = false;
    var shiny = false;
    var ageMinutes = 0;
    var speciesId = -1;
    var prevSpeciesId = -1;
    var careMistakes = 0;
    var sleeping = false;
    var lastSeenEpoch = 0;
    var ceremony = 0;
    var lastEnd = 0;
    var dexReg as Array<Number>;
    var dexShinyReg as Array<Number>;
    var streak = 0;
    var bestStreak = 0;
    var lastCareDay = 0;
    var bond = 0;
    var nick = "";
    var medals = 0;
    var totalMedals = 0;
    var newMedal = 0;
    var lastMilestone = 0;
    var gameHi = 0;
    var strHi = 0;
    var pendingSave = false;

    private var lastTick = 0;
    private var eatUntil = 0;
    private var heartUntil = 0;
    private var evolveUntil = 0;
    private var eggTarget = 1;
    private var eggShiny = false;
    private var eggTaps = 0;
    private var mistakeCooldown = 0;
    private var ticksSinceSave = 0;
    private var evoDeclinedLv = 0;
    private var farDeclinedAge = 0;
    private var starterPick = false;
    private var neglectTicks = 0;
    private var goodTicks = 0;
    private var ceremonyUntil = 0;
    private var bondToday = 0;
    private var medalUntil = 0;
    private var milestoneUntil = 0;

    var sfx as Method?;  // (id as Number) -> Void

    function initialize() {
        dexReg = new [19] as Array<Number>;
        dexShinyReg = new [19] as Array<Number>;
        for (var i = 0; i < 19; i++) {
            dexReg[i] = 0;
            dexShinyReg[i] = 0;
        }
    }

    private function play(id as Number) as Void {
        if (sfx != null) {
            sfx.invoke(id);
        }
    }

    private function timeLeft(deadline as Number) as Number {
        if (deadline == 0) {
            return 0;
        }
        var left = deadline - G.millis();
        return left > 0 ? left : 0;
    }

    function begin() as Void {
        var d = Application.Storage.getValue("pet");
        if (d == null) {
            newEgg();
        } else {
            load(d as Dictionary);
        }
        lastTick = G.millis();
    }

    function lovesBerry(color as Number) as Boolean { return !isEgg() && (speciesId % 3) == color; }
    function isEgg() as Boolean { return speciesId < 0; }
    function eggCracks() as Number { return eggTaps; }
    function eating() as Boolean { return timeLeft(eatUntil) > 0; }
    function showHeart() as Boolean { return timeLeft(heartUntil) > 0; }
    function evolving() as Boolean { return timeLeft(evolveUntil) > 0; }
    function evolveT() as Float { return 1.0 - timeLeft(evolveUntil).toFloat() / G.EVOLVE_ANIM_MS; }
    function wantEvolveButton() as Boolean { return canEvolveNow() && level() > evoDeclinedLv; }
    function wantFarewellButton() as Boolean { return canFarewellNow() && ageMinutes >= farDeclinedAge; }
    function declineEvolve() as Void { evoDeclinedLv = level(); save(); }
    function declineFarewell() as Void { farDeclinedAge = ageMinutes + 1440; save(); }
    function awaitingStarter() as Boolean { return starterPick; }
    function chooseStarter(dex as Number) as Void { eggTarget = dex; starterPick = false; save(); }

    function level() as Number {
        var lv = 1 + ageMinutes / G.MINUTES_PER_LEVEL;
        return lv > 999 ? 999 : lv;
    }

    function isRegistered(dex as Number) as Boolean {
        return dex >= 1 && dex <= 151 && (dexReg[(dex - 1) >> 3] & (1 << ((dex - 1) & 7))) != 0;
    }

    function isShinyRegistered(dex as Number) as Boolean {
        return dex >= 1 && dex <= 151 && (dexShinyReg[(dex - 1) >> 3] & (1 << ((dex - 1) & 7))) != 0;
    }

    function lowestStat() as Number {
        return G.min2(G.min2(fullness, joy), G.min2(energy, hygiene));
    }

    function ceremonyT() as Float {
        return ceremony == G.CER_NONE ? 0.0 : 1.0 - timeLeft(ceremonyUntil).toFloat() / G.CEREMONY_MS;
    }

    function hasMedal(m as Number) as Boolean { return (medals & m) != 0; }
    function showMedal() as Boolean { return timeLeft(medalUntil) > 0; }
    function showMilestone() as Boolean { return timeLeft(milestoneUntil) > 0; }

    function newEgg() as Void {
        ceremony = G.CER_NONE;
        neglectTicks = 0;
        weight = 0;
        speciesId = -1;
        prevSpeciesId = -1;
        eggTarget = pickEggSpecies();
        starterPick = registeredCount() == 0;
        var shinyBase = (lastEnd == G.CER_FAREWELL ? 24 : 48) - careBonus();
        if (shinyBase < 8) {
            shinyBase = 8;
        }
        eggShiny = G.random(shinyBase) == 0;
        eggTaps = 0;
        fullness = 80;
        joy = 80;
        energy = 80;
        hygiene = 100;
        poops = 0;
        ageMinutes = 0;
        careMistakes = 0;
        mistakeCooldown = 0;
        sleeping = false;
        save();
    }

    // applies the time that passed while the app was closed (gentle: floors, no slip-ups)
    function syncClock(nowEpoch as Number) as Void {
        var seen = lastSeenEpoch;
        lastSeenEpoch = nowEpoch;
        if (nowEpoch == 0) {
            return;
        }
        var mins = (seen != 0 && nowEpoch > seen) ? (nowEpoch - seen) / 60 : 0;
        if (mins < 2 || ceremony != G.CER_NONE || starterPick) {
            save();
            return;
        }
        if (mins > 14 * 24 * 60) {
            mins = 14 * 24 * 60;
        }
        lastTick = G.millis();
        for (var i = 0; i < mins; i++) {
            ageMinutes++;
            if (isEgg()) {
                if (ageMinutes >= 3) {
                    hatch();
                }
                continue;
            }
            if (sleeping) {
                energy = G.clamp100(energy + 6);
                if (ageMinutes % 2 == 0) {
                    fullness = G.dropTo(fullness, 1, 30);
                    joy = G.dropTo(joy, 1, 35);
                }
                if (ageMinutes % 3 == 0) {
                    hygiene = G.dropTo(hygiene, 1, 45);
                }
                continue;
            }
            fullness = G.dropTo(fullness, 2, 15);
            energy = G.dropTo(energy, 1, 15);
            hygiene = G.dropTo(hygiene, 1, 15);
            joy = G.dropTo(joy, 1, 15);
        }
        if (!isEgg() && !sleeping) {
            var p = poops + mins / 240;
            poops = p > 3 ? 3 : p;
        }
        save();
    }

    function update(nowMs as Number) as Void {
        if (ceremony != G.CER_NONE && timeLeft(ceremonyUntil) == 0) {
            newEgg();
            return;
        }
        while (nowMs - lastTick >= G.PET_TICK_MS) {
            lastTick += G.PET_TICK_MS;
            tick();
        }
    }

    private function tick() as Void {
        if (ceremony != G.CER_NONE || starterPick) {
            return;
        }
        ageMinutes++;
        if (isEgg()) {
            if (ageMinutes >= 3) {
                hatch();
            }
            return;
        }
        if (sleeping) {
            energy = G.clamp100(energy + 6);
            if (weight > 0 && ageMinutes % 3 == 0) {
                weight--;
            }
            if (ageMinutes % 2 == 0) {
                fullness = G.dropTo(fullness, 1, 30);
                joy = G.dropTo(joy, 1, 35);
            }
            if (ageMinutes % 3 == 0) {
                hygiene = G.dropTo(hygiene, 1, 45);
            }
            checkMedals();
            ticksSinceSave++;
            if (ticksSinceSave >= 5) {
                pendingSave = true;
            }
            return;
        }
        if (ageMinutes % G.MINUTES_PER_LEVEL == 0) {
            play(G.SFX_LEVEL);
        }
        fullness = G.clamp100(fullness - 2);
        energy = G.clamp100(energy - 1);
        if (fullness > 40 && poops < 3 && G.random(100) < 15) {
            poops++;
        }
        hygiene = G.clamp100(hygiene - 1 - 4 * poops);
        if (weight > 50) {
            energy = G.clamp100(energy - 1);
        }
        if (weight > 0 && ageMinutes % 3 == 0) {
            weight--;
        }
        if (lowestStat() >= 40) {
            goodTicks++;
            if (goodTicks >= 720) {
                goodTicks = 0;
                if (trDef < 100) {
                    trDef++;
                }
            }
        } else {
            goodTicks = 0;
        }
        var dJoy = -1;
        if (fullness < 30) {
            dJoy -= 2;
        }
        if (hygiene < 30) {
            dJoy -= 2;
        }
        joy = G.clamp100(joy + dJoy);

        if (mistakeCooldown > 0) {
            mistakeCooldown--;
        }
        if (lowestStat() <= 10 && mistakeCooldown == 0) {
            careMistakes++;
            mistakeCooldown = 60;
            if (bond > 1) {
                bond--;
            }
        }
        checkMedals();
        if (fullness == 0 && joy == 0 && energy == 0 && hygiene == 0) {
            if (neglectTicks < G.RUNAWAY_TICKS) {
                neglectTicks++;
            }
        } else {
            neglectTicks = 0;
        }
        ticksSinceSave++;
        if (ticksSinceSave >= 5) {
            pendingSave = true;
        }
    }

    function flushSave() as Void {
        if (pendingSave) {
            save();
        }
    }

    function lineHasUnregistered(base as Number) as Boolean {
        var cur = base;
        for (var guard = 0; cur >= 1 && cur <= 151 && guard < 6; guard++) {
            if (!isRegistered(cur)) {
                return true;
            }
            if (cur == G.DEX_EEVEE) {
                for (var b = 134; b <= 136; b++) {
                    if (!isRegistered(b)) {
                        return true;
                    }
                }
                return false;
            }
            cur = Tables.EVOLVES_TO[cur];
        }
        return false;
    }

    function eggRarity() as Number {
        return (eggTarget >= 1 && eggTarget <= 151) ? Tables.RARITY[eggTarget] : G.R_COMUN;
    }

    function pickEggSpecies() as Number {
        if (registeredCount() == 0) {
            return G.CLASSIC_DEX[G.random(G.CLASSIC_DEX.size())];
        }
        var tier = G.R_COMUN;
        if (lastEnd != G.CER_RUNAWAY) {
            var blessed = lastEnd == G.CER_FAREWELL;
            var rare = (blessed ? 45 : 27) + careBonus();
            var leg = registeredCount() >= 25 ? (blessed ? 10 : 3) + careBonus() / 3 : 0;
            var r = G.random(100);
            if (r < leg) {
                tier = G.R_LEGENDARIO;
            } else if (r < leg + rare) {
                tier = G.R_RARO;
            }
        }
        for (var pass = 0; pass < 2; pass++) {
            for (var t = tier; t >= G.R_COMUN; t--) {
                var cand = [] as Array<Number>;
                for (var d = 1; d <= 151 && cand.size() < 80; d++) {
                    if (Tables.RARITY[d] != t) {
                        continue;
                    }
                    if (pass == 0 && !lineHasUnregistered(d)) {
                        continue;
                    }
                    cand.add(d);
                }
                if (cand.size() > 0) {
                    return cand[G.random(cand.size())];
                }
            }
        }
        return G.CLASSIC_DEX[G.random(G.CLASSIC_DEX.size())];
    }

    private function registerSpecies(dex as Number) as Void {
        if (dex < 1 || dex > 151) {
            return;
        }
        var i = (dex - 1) >> 3;
        var bit = 1 << ((dex - 1) & 7);
        dexReg[i] = dexReg[i] | bit;
        if (shiny) {
            dexShinyReg[i] = dexShinyReg[i] | bit;
        }
    }

    function careBonus() as Number {
        var s = streak > 30 ? 30 : streak;
        return s / 3 + bond / 25;
    }

    private function today() as Number {
        return lastSeenEpoch != 0 ? lastSeenEpoch / 86400 : 0;
    }

    private function registerCare() as Void {
        if (isEgg() || ceremony != G.CER_NONE) {
            return;
        }
        var d = today();
        if (d == 0 || d == lastCareDay) {
            return;
        }
        if (lastCareDay == 0 || d == lastCareDay + 1) {
            streak++;
        } else {
            streak = 1;
            lastMilestone = 0;
        }
        lastCareDay = d;
        bondToday = 0;
        if (streak > bestStreak) {
            bestStreak = streak;
        }
        bond = G.clamp100(bond + 4);
        var ms = streak >= 100 ? 100 : (streak >= 30 ? 30 : (streak >= 7 ? 7 : (streak >= 3 ? 3 : 0)));
        if (ms > lastMilestone) {
            lastMilestone = ms;
            milestoneUntil = G.millis() + 4500;
        }
        checkMedals();
        save();
    }

    private function addBond(amt as Number) as Void {
        if (bondToday >= 20) {
            return;
        }
        bond = G.clamp100(bond + amt);
        bondToday += amt;
    }

    private function checkMedals() as Void {
        if (isEgg()) {
            return;
        }
        var before = medals;
        if (level() >= 10) { medals = medals | G.MED_LV10; }
        if (level() >= 25) { medals = medals | G.MED_LV25; }
        if (level() >= 50) { medals = medals | G.MED_LV50; }
        if (berryKnown) { medals = medals | G.MED_BERRY; }
        if (streak >= 7) { medals = medals | G.MED_STREAK7; }
        if (bond >= 100) { medals = medals | G.MED_BOND; }
        if (Tables.EVOLVES_TO[speciesId] == 0) { medals = medals | G.MED_FINAL; }
        if (weight == 0 && level() >= 5 && careMistakes == 0) { medals = medals | G.MED_FIT; }
        var gained = medals & ~before;
        if (gained != 0) {
            totalMedals += G.bitCount(gained);
            newMedal = gained;
            medalUntil = G.millis() + 4000;
            if (!sleeping) {
                play(G.SFX_MEDAL);
            }
            save();
        }
    }

    function rename(name as String) as Void {
        nick = name.length() > 11 ? name.substring(0, 11) : name;
        save();
    }

    private function calcStat(base as Number, gene as Number, lvl as Number, tr as Number) as Number {
        return base * gene / 100 + lvl + tr;
    }

    function atkStat() as Number { return isEgg() ? 0 : calcStat(Tables.B_ATK[speciesId], geneAtk, level(), trAtk); }
    function defStat() as Number { return isEgg() ? 0 : calcStat(Tables.B_DEF[speciesId], geneDef, level(), trDef); }
    function speStat() as Number { return isEgg() ? 0 : calcStat(Tables.B_SPE[speciesId], geneSpe, level(), trSpe); }

    function registeredCount() as Number {
        var n = 0;
        for (var i = 0; i < 19; i++) {
            n += G.bitCount(dexReg[i] & 0xFF);
        }
        // bits past #151 in the last byte are never set
        return n;
    }

    function canFarewellNow() as Boolean {
        return !isEgg() && !sleeping && ceremony == G.CER_NONE &&
            Tables.EVOLVES_TO[speciesId] == 0 && ageMinutes >= G.FAREWELL_AGE_MIN;
    }

    function canRunawayNow() as Boolean {
        return !isEgg() && !sleeping && ceremony == G.CER_NONE && neglectTicks >= G.RUNAWAY_TICKS;
    }

    private function startEnding(kind as Number, hearts as Boolean) as Void {
        if (isEgg() || ceremony != G.CER_NONE) {
            return;
        }
        lastEnd = kind;
        ceremony = kind;
        ceremonyUntil = G.millis() + G.CEREMONY_MS;
        if (hearts) {
            heartUntil = ceremonyUntil;
        }
        play(G.SFX_BYE);
        save();
    }

    function startFarewell() as Void { startEnding(G.CER_FAREWELL, true); }
    function startRunaway() as Void { startEnding(G.CER_RUNAWAY, false); }
    function release() as Void { startEnding(G.CER_RELEASE, true); }

    private function hatch() as Void {
        speciesId = eggTarget;
        shiny = eggShiny;
        geneAtk = 90 + G.random(21);
        geneDef = 90 + G.random(21);
        geneSpe = 90 + G.random(21);
        trAtk = 0;
        trDef = 0;
        trSpe = 0;
        berryKnown = false;
        bond = 0;
        bondToday = 0;
        medals = 0;
        newMedal = 0;
        nick = "";
        registerSpecies(speciesId);
        checkMedals();
        play(G.SFX_HATCH);
        save();
    }

    function canEvolveNow() as Boolean {
        if (isEgg() || sleeping || ceremony != G.CER_NONE) {
            return false;
        }
        if (Tables.EVOLVES_TO[speciesId] == 0) {
            return false;
        }
        return level() >= Tables.EVOLVE_LEVEL[speciesId] + careMistakes && lowestStat() >= 40;
    }

    function evolve() as Void {
        if (!canEvolveNow()) {
            return;
        }
        prevSpeciesId = speciesId;
        var next = Tables.EVOLVES_TO[speciesId];
        if (speciesId == G.DEX_EEVEE) {
            var opts = [] as Array<Number>;
            for (var b = 134; b <= 136; b++) {
                if (!isRegistered(b)) {
                    opts.add(b);
                }
            }
            next = opts.size() > 0 ? opts[G.random(opts.size())] : 134 + G.random(3);
        }
        speciesId = next;
        registerSpecies(speciesId);
        play(G.SFX_EVOLVE);
        evolveUntil = G.millis() + G.EVOLVE_ANIM_MS;
        save();
    }

    function feedBerry(color as Number) as Void {
        if (ceremony != G.CER_NONE || isEgg() || sleeping) {
            return;
        }
        if (lovesBerry(color)) {
            fullness = G.clamp100(fullness + 35);
            joy = G.clamp100(joy + 10);
            heartUntil = G.millis() + G.HEART_MS;
            berryKnown = true;
            addBond(2);
        } else {
            fullness = G.clamp100(fullness + 25);
        }
        eatUntil = G.millis() + G.EAT_ANIM_MS;
        registerCare();
        save();
    }

    function feedCandy() as Void {
        if (ceremony != G.CER_NONE || isEgg() || sleeping) {
            return;
        }
        fullness = G.clamp100(fullness + 10);
        joy = G.clamp100(joy + 12);
        weight = G.clamp100(weight + 12);
        eatUntil = G.millis() + G.EAT_ANIM_MS;
        registerCare();
        save();
    }

    function playResult(score as Number) as Void {
        if (ceremony != G.CER_NONE || isEgg()) {
            return;
        }
        var v = trSpe + score / 5;
        trSpe = v > 100 ? 100 : v;
        joy = G.clamp100(joy + 5 + (score > 15 ? 30 : score * 2));
        energy = G.dropTo(energy, 10 + score / 2, 5);
        fullness = G.dropTo(fullness, 5, 5);
        var burn = weight - score * 2;
        weight = burn > 0 ? burn : 0;
        if (score >= 5) {
            heartUntil = G.millis() + G.HEART_MS;
        }
        if (score > gameHi) {
            gameHi = score;
        }
        addBond(2);
        registerCare();
        save();
    }

    function trainStrength(hits as Number) as Number {
        if (ceremony != G.CER_NONE || isEgg()) {
            return 0;
        }
        var gain = hits / 4;
        if (gain > 18) {
            gain = 18;
        }
        var before = trAtk;
        var v = trAtk + gain;
        trAtk = v > 100 ? 100 : v;
        gain = trAtk - before;
        energy = G.dropTo(energy, 12, 5);
        fullness = G.dropTo(fullness, 5, 5);
        var burn = weight - hits / 3;
        weight = burn > 0 ? burn : 0;
        joy = G.clamp100(joy + 6);
        if (hits >= 20) {
            heartUntil = G.millis() + G.HEART_MS;
        }
        if (hits > strHi) {
            strHi = hits;
        }
        addBond(2);
        registerCare();
        save();
        return gain;
    }

    function toggleLight() as Void {
        if (ceremony != G.CER_NONE || isEgg()) {
            return;
        }
        sleeping = !sleeping;
        save();
    }

    function clean() as Void {
        if (ceremony != G.CER_NONE) {
            return;
        }
        poops = 0;
        hygiene = 100;
        addBond(1);
        registerCare();
        save();
    }

    function caress() as Void {
        if (ceremony != G.CER_NONE || isEgg() || sleeping) {
            return;
        }
        joy = G.clamp100(joy + 5);
        heartUntil = G.millis() + G.HEART_MS;
        addBond(1);
        registerCare();
    }

    function eggTap() as Void {
        if (!isEgg()) {
            return;
        }
        eggTaps++;
        if (eggTaps >= 3) {
            hatch();
        } else {
            save();
        }
    }

    function mood() as Number {
        if (sleeping) {
            return G.MOOD_SLEEPING;
        }
        if (eating()) {
            return G.MOOD_EATING;
        }
        if (lowestStat() < 25) {
            return G.MOOD_SAD;
        }
        return G.MOOD_HAPPY;
    }

    // the whole pet is one Storage value: one write per save
    function save() as Void {
        ticksSinceSave = 0;
        pendingSave = false;
        Application.Storage.setValue("pet", {
            "full" => fullness, "joy" => joy, "ene" => energy, "hyg" => hygiene,
            "poop" => poops, "wgt" => weight,
            "gatk" => geneAtk, "gdef" => geneDef, "gspe" => geneSpe,
            "tatk" => trAtk, "tdef" => trDef, "tspe" => trSpe,
            "bk" => berryKnown, "shy" => shiny, "eshy" => eggShiny, "stpk" => starterPick,
            "dexsh" => dexShinyReg, "age" => ageMinutes, "dexn" => speciesId, "eggT2" => eggTarget,
            "crack" => eggTaps, "mist" => careMistakes, "sleep" => sleeping, "lend" => lastEnd,
            "seen" => lastSeenEpoch, "dexreg" => dexReg,
            "strk" => streak, "bstrk" => bestStreak, "cday" => lastCareDay, "bond" => bond,
            "medal" => medals, "tmedal" => totalMedals, "mstone" => lastMilestone,
            "ghi" => gameHi, "shi" => strHi, "nick" => nick,
            "evodl" => evoDeclinedLv, "fardl" => farDeclinedAge, "negl" => neglectTicks,
            "mcool" => mistakeCooldown, "good" => goodTicks, "bday" => bondToday
        });
    }

    private function gi(d as Dictionary, k as String, def) {
        var v = d.get(k);
        return v == null ? def : v;
    }

    private function load(d as Dictionary) as Void {
        fullness = gi(d, "full", 80);
        joy = gi(d, "joy", 80);
        energy = gi(d, "ene", 80);
        hygiene = gi(d, "hyg", 100);
        poops = gi(d, "poop", 0);
        weight = gi(d, "wgt", 0);
        geneAtk = gi(d, "gatk", 100);
        geneDef = gi(d, "gdef", 100);
        geneSpe = gi(d, "gspe", 100);
        trAtk = gi(d, "tatk", 0);
        trDef = gi(d, "tdef", 0);
        trSpe = gi(d, "tspe", 0);
        berryKnown = gi(d, "bk", false);
        shiny = gi(d, "shy", false);
        eggShiny = gi(d, "eshy", false);
        starterPick = gi(d, "stpk", false);
        var sh = d.get("dexsh");
        if (sh != null) {
            dexShinyReg = sh as Array<Number>;
        }
        ageMinutes = gi(d, "age", 0);
        speciesId = gi(d, "dexn", -1);
        eggTarget = gi(d, "eggT2", 4);
        eggTaps = gi(d, "crack", 0);
        careMistakes = gi(d, "mist", 0);
        sleeping = gi(d, "sleep", false);
        lastEnd = gi(d, "lend", 0);
        lastSeenEpoch = gi(d, "seen", 0);
        var rg = d.get("dexreg");
        if (rg != null) {
            dexReg = rg as Array<Number>;
        }
        streak = gi(d, "strk", 0);
        bestStreak = gi(d, "bstrk", 0);
        lastCareDay = gi(d, "cday", 0);
        bond = gi(d, "bond", 0);
        medals = gi(d, "medal", 0);
        totalMedals = gi(d, "tmedal", 0);
        lastMilestone = gi(d, "mstone", 0);
        gameHi = gi(d, "ghi", 0);
        strHi = gi(d, "shi", 0);
        nick = gi(d, "nick", "");
        evoDeclinedLv = gi(d, "evodl", 0);
        farDeclinedAge = gi(d, "fardl", 0);
        neglectTicks = gi(d, "negl", 0);
        mistakeCooldown = gi(d, "mcool", 0);
        goodTicks = gi(d, "good", 0);
        bondToday = gi(d, "bday", 0);
        if (speciesId >= 1) {
            registerSpecies(speciesId);
        }
    }
}
