// Port of TamaPoke's pet.h / pet.cpp (MIT, (c) 2026 Quique Tortosa), by way of
// the Wear OS port's Pet.kt. Same rules and numbers as the firmware; only
// storage and timing are adapted. Kept free of UIKit/SwiftUI so it can be tested.
import Foundation

let PET_TICK_MS = 60_000
let MINUTES_PER_LEVEL = 60
let EAT_ANIM_MS = 2500
let HEART_MS = 1500
let EVOLVE_ANIM_MS = 5200
let CEREMONY_MS = 10_000
let FAREWELL_AGE_MIN = 3 * 24 * 60
let RUNAWAY_TICKS = 60

let CER_NONE = 0
let CER_FAREWELL = 1
let CER_RUNAWAY = 2
let CER_RELEASE = 3

let R_EVO = 0
let R_COMUN = 1
let R_RARO = 2
let R_LEGENDARIO = 3

let DEX_COUNT = 151
let DEX_EEVEE = 133
let CLASSIC_DEX = [1, 4, 7, 25, 133]

let MED_LV10 = 1 << 0
let MED_LV25 = 1 << 1
let MED_LV50 = 1 << 2
let MED_BERRY = 1 << 3
let MED_STREAK7 = 1 << 4
let MED_BOND = 1 << 5
let MED_FINAL = 1 << 6
let MED_FIT = 1 << 7
let MED_COUNT = 8

enum Mood { case happy, sad, eating, sleeping }

enum Sfx: CaseIterable { case tap, eat, play, heart, hatch, evolve, medal, deny, bye, level }

/// Key/value persistence, the role ESP32 Preferences (NVS) plays in the firmware.
protocol Store: AnyObject {
    func getInt(_ key: String, _ def: Int) -> Int
    func putInt(_ key: String, _ v: Int)
    func getBool(_ key: String, _ def: Bool) -> Bool
    func putBool(_ key: String, _ v: Bool)
    func getString(_ key: String, _ def: String) -> String
    func putString(_ key: String, _ v: String)
    func has(_ key: String) -> Bool
    func clear()
    /// Called once at the end of every save, so a store can batch the writes.
    func flush()
}

/// Arduino random(n): 0..<n. A protocol so tests can force values.
protocol Rng: AnyObject {
    func next(_ n: Int) -> Int
}

final class SystemRng: Rng {
    func next(_ n: Int) -> Int { n <= 1 ? 0 : Int.random(in: 0..<n) }
}

final class Pet {
    private let prefs: Store
    private let rng: Rng
    private let millis: () -> Int
    private let sfx: (Sfx) -> Void

    var fullness = 80
    var joy = 80
    var energy = 80
    var hygiene = 100
    var poops = 0
    var weight = 0
    var geneAtk = 100, geneDef = 100, geneSpe = 100
    var trAtk = 0, trDef = 0, trSpe = 0
    var berryKnown = false
    var shiny = false
    var ageMinutes = 0
    var speciesId = -1
    var prevSpeciesId = -1
    var careMistakes = 0
    var sleeping = false
    var lastSeenEpoch = 0
    var ceremony = CER_NONE
    var lastEnd = CER_NONE
    var dexReg = [UInt8](repeating: 0, count: 19)
    var dexShinyReg = [UInt8](repeating: 0, count: 19)
    var streak = 0, bestStreak = 0
    var lastCareDay = 0
    var bond = 0
    var nick = ""
    var medals = 0, totalMedals = 0
    var newMedal = 0
    var lastMilestone = 0
    var gameHi = 0
    var strHi = 0

    private var lastTick = 0
    private var eatUntil = 0
    private var heartUntil = 0
    private var evolveUntil = 0
    private var eggTarget = 1
    private var eggShiny = false
    private var eggTaps = 0
    private var mistakeCooldown = 0
    private var ticksSinceSave = 0
    private(set) var pendingSave = false
    private var evoDeclinedLv = 0
    private var farDeclinedAge = 0
    private var starterPick = false
    private var neglectTicks = 0
    private var goodTicks = 0
    private var ceremonyUntil = 0
    private var bondToday = 0
    private var medalUntil = 0
    private var milestoneUntil = 0

    init(prefs: Store, rng: Rng = SystemRng(),
         millis: @escaping () -> Int = { Int(Date().timeIntervalSince1970 * 1000) },
         sfx: @escaping (Sfx) -> Void = { _ in }) {
        self.prefs = prefs
        self.rng = rng
        self.millis = millis
        self.sfx = sfx
    }

    private func timeLeft(_ deadline: Int) -> Int {
        if deadline == 0 { return 0 }
        let left = deadline - millis()
        return left > 0 ? left : 0
    }

    private func random(_ n: Int) -> Int { rng.next(n) }

    func begin() {
        if !prefs.getBool("init", false) {
            prefs.putBool("init", true)
            newEgg()
        } else {
            load()
        }
        lastTick = millis()
    }

    func lovesBerry(_ color: Int) -> Bool { !isEgg() && (speciesId % 3) == color }
    func isEgg() -> Bool { speciesId < 0 }
    func eggCracks() -> Int { eggTaps }
    func eating() -> Bool { timeLeft(eatUntil) > 0 }
    func showHeart() -> Bool { timeLeft(heartUntil) > 0 }
    func evolving() -> Bool { timeLeft(evolveUntil) > 0 }
    func evolveT() -> Double { 1 - Double(timeLeft(evolveUntil)) / Double(EVOLVE_ANIM_MS) }
    func wantEvolveButton() -> Bool { canEvolveNow() && level() > evoDeclinedLv }
    func wantFarewellButton() -> Bool { canFarewellNow() && ageMinutes >= farDeclinedAge }
    func declineEvolve() { evoDeclinedLv = level() }
    func declineFarewell() { farDeclinedAge = ageMinutes + 1440 }
    func awaitingStarter() -> Bool { starterPick }
    func chooseStarter(_ dex: Int) { eggTarget = dex; starterPick = false; save() }
    func factoryReset() { prefs.clear() }

    func level() -> Int {
        let lv = 1 + ageMinutes / MINUTES_PER_LEVEL
        return lv > 999 ? 999 : lv
    }

    func isRegistered(_ dex: Int) -> Bool {
        (1...151).contains(dex) && (Int(dexReg[(dex - 1) >> 3]) & (1 << ((dex - 1) & 7))) != 0
    }

    func isShinyRegistered(_ dex: Int) -> Bool {
        (1...151).contains(dex) && (Int(dexShinyReg[(dex - 1) >> 3]) & (1 << ((dex - 1) & 7))) != 0
    }

    func lowestStat() -> Int { min(min(fullness, joy), min(energy, hygiene)) }

    func ceremonyT() -> Double {
        ceremony == CER_NONE ? 0 : 1 - Double(timeLeft(ceremonyUntil)) / Double(CEREMONY_MS)
    }

    func hasMedal(_ m: Int) -> Bool { (medals & m) != 0 }
    func showMedal() -> Bool { timeLeft(medalUntil) > 0 }
    func showMilestone() -> Bool { timeLeft(milestoneUntil) > 0 }
    func savedEpoch() -> Int { prefs.getInt("seen", 0) }

    func newEgg() {
        ceremony = CER_NONE
        neglectTicks = 0
        weight = 0
        speciesId = -1
        prevSpeciesId = -1
        eggTarget = pickEggSpecies()
        starterPick = registeredCount() == 0
        var shinyBase = (lastEnd == CER_FAREWELL ? 24 : 48) - careBonus()
        if shinyBase < 8 { shinyBase = 8 }
        eggShiny = random(shinyBase) == 0
        eggTaps = 0
        fullness = 80
        joy = 80
        energy = 80
        hygiene = 100
        poops = 0
        ageMinutes = 0
        careMistakes = 0
        mistakeCooldown = 0
        sleeping = false
        save()
    }

    func setClock(_ nowEpoch: Int) {
        lastSeenEpoch = nowEpoch
        if nowEpoch != 0 { save() }
    }

    /// Applies the time that passed while the app was closed (gentle: floors, no slip-ups).
    func syncClock(_ nowEpoch: Int) {
        let seen = prefs.getInt("seen", 0)
        lastSeenEpoch = nowEpoch
        if nowEpoch == 0 { return }
        var mins = (seen != 0 && nowEpoch > seen) ? (nowEpoch - seen) / 60 : 0
        if mins < 2 || ceremony != CER_NONE || starterPick {
            save()
            return
        }
        if mins > 14 * 24 * 60 { mins = 14 * 24 * 60 }
        // keep the live minute clock in step so these minutes aren't ticked twice
        lastTick = millis()

        for _ in 0..<mins {
            ageMinutes += 1
            if isEgg() {
                if ageMinutes >= 3 { hatch() }
                continue
            }
            if sleeping {
                energy = Pet.clamp100(energy + 6)
                if ageMinutes % 2 == 0 {
                    fullness = Pet.dropTo(fullness, 1, 30)
                    joy = Pet.dropTo(joy, 1, 35)
                }
                if ageMinutes % 3 == 0 { hygiene = Pet.dropTo(hygiene, 1, 45) }
                continue
            }
            fullness = Pet.dropTo(fullness, 2, 15)
            energy = Pet.dropTo(energy, 1, 15)
            hygiene = Pet.dropTo(hygiene, 1, 15)
            joy = Pet.dropTo(joy, 1, 15)
        }
        if !isEgg() && !sleeping {
            let p = poops + mins / 240
            poops = p > 3 ? 3 : p
        }
        save()
    }

    func update(_ nowMs: Int) {
        if ceremony != CER_NONE && timeLeft(ceremonyUntil) == 0 {
            newEgg()
            return
        }
        while nowMs - lastTick >= PET_TICK_MS {
            lastTick += PET_TICK_MS
            tick()
        }
    }

    private func tick() {
        if ceremony != CER_NONE { return }
        if starterPick { return }
        ageMinutes += 1

        if isEgg() {
            if ageMinutes >= 3 { hatch() }
            return
        }

        if sleeping {
            energy = Pet.clamp100(energy + 6)
            if weight > 0 && ageMinutes % 3 == 0 { weight -= 1 }
            if ageMinutes % 2 == 0 {
                fullness = Pet.dropTo(fullness, 1, 30)
                joy = Pet.dropTo(joy, 1, 35)
            }
            if ageMinutes % 3 == 0 { hygiene = Pet.dropTo(hygiene, 1, 45) }
            checkMedals()
            ticksSinceSave += 1
            if ticksSinceSave >= 5 { pendingSave = true }
            return
        }

        if ageMinutes % MINUTES_PER_LEVEL == 0 { sfx(.level) }

        fullness = Pet.clamp100(fullness - 2)
        energy = Pet.clamp100(energy - 1)
        if fullness > 40 && poops < 3 && random(100) < 15 { poops += 1 }

        hygiene = Pet.clamp100(hygiene - 1 - 4 * poops)
        if weight > 50 { energy = Pet.clamp100(energy - 1) }
        if weight > 0 && ageMinutes % 3 == 0 { weight -= 1 }

        if lowestStat() >= 40 {
            goodTicks += 1
            if goodTicks >= 720 {
                goodTicks = 0
                if trDef < 100 { trDef += 1 }
            }
        } else {
            goodTicks = 0
        }

        var dJoy = -1
        if fullness < 30 { dJoy -= 2 }
        if hygiene < 30 { dJoy -= 2 }
        joy = Pet.clamp100(joy + dJoy)

        if mistakeCooldown > 0 { mistakeCooldown -= 1 }
        if lowestStat() <= 10 && mistakeCooldown == 0 {
            careMistakes += 1
            mistakeCooldown = 60
            if bond > 1 { bond -= 1 }
        }

        checkMedals()

        if fullness == 0 && joy == 0 && energy == 0 && hygiene == 0 {
            if neglectTicks < RUNAWAY_TICKS { neglectTicks += 1 }
        } else {
            neglectTicks = 0
        }

        ticksSinceSave += 1
        if ticksSinceSave >= 5 { pendingSave = true }
    }

    func flushSave() {
        if pendingSave { save() }
    }

    func lineHasUnregistered(_ base: Int) -> Bool {
        var cur = base
        var guardN = 0
        while (1...151).contains(cur) && guardN < 6 {
            if !isRegistered(cur) { return true }
            if cur == DEX_EEVEE {
                for b in 134...136 where !isRegistered(b) { return true }
                return false
            }
            cur = DexTables.EVOLVES_TO[cur]
            guardN += 1
        }
        return false
    }

    func eggRarity() -> Int { (1...151).contains(eggTarget) ? DexTables.RARITY[eggTarget] : R_COMUN }

    func pickEggSpecies() -> Int {
        if registeredCount() == 0 { return CLASSIC_DEX[random(CLASSIC_DEX.count)] }

        var tier = R_COMUN
        if lastEnd != CER_RUNAWAY {
            let blessed = lastEnd == CER_FAREWELL
            let rare = (blessed ? 45 : 27) + careBonus()
            let leg = registeredCount() >= 25 ? (blessed ? 10 : 3) + careBonus() / 3 : 0
            let r = random(100)
            if r < leg { tier = R_LEGENDARIO } else if r < leg + rare { tier = R_RARO }
        }

        for pass in 0..<2 {
            for t in stride(from: tier, through: R_COMUN, by: -1) {
                var cand: [Int] = []
                for d in 1...151 {
                    if cand.count >= 80 { break }
                    if DexTables.RARITY[d] != t { continue }
                    if pass == 0 && !lineHasUnregistered(d) { continue }
                    cand.append(d)
                }
                if !cand.isEmpty { return cand[random(cand.count)] }
            }
        }
        return CLASSIC_DEX[random(CLASSIC_DEX.count)]
    }

    private func registerSpecies(_ dex: Int) {
        if dex < 1 || dex > 151 { return }
        let i = (dex - 1) >> 3
        let bit = UInt8(1 << ((dex - 1) & 7))
        dexReg[i] |= bit
        if shiny { dexShinyReg[i] |= bit }
    }

    func careBonus() -> Int {
        let s = streak > 30 ? 30 : streak
        return s / 3 + bond / 25
    }

    private func today() -> Int { lastSeenEpoch != 0 ? lastSeenEpoch / 86400 : 0 }

    private func registerCare() {
        if isEgg() || ceremony != CER_NONE { return }
        let d = today()
        if d == 0 || d == lastCareDay { return }
        if lastCareDay == 0 || d == lastCareDay + 1 {
            streak += 1
        } else {
            streak = 1
            lastMilestone = 0
        }
        lastCareDay = d
        bondToday = 0
        if streak > bestStreak { bestStreak = streak }
        bond = Pet.clamp100(bond + 4)
        let ms: Int
        if streak >= 100 { ms = 100 } else if streak >= 30 { ms = 30 } else if streak >= 7 { ms = 7 } else if streak >= 3 { ms = 3 } else { ms = 0 }
        if ms > lastMilestone {
            lastMilestone = ms
            milestoneUntil = millis() + 4500
        }
        checkMedals()
        save()
    }

    private func addBond(_ amt: Int) {
        if bondToday >= 20 { return }
        bond = Pet.clamp100(bond + amt)
        bondToday += amt
    }

    private func checkMedals() {
        if isEgg() { return }
        let before = medals
        if level() >= 10 { medals |= MED_LV10 }
        if level() >= 25 { medals |= MED_LV25 }
        if level() >= 50 { medals |= MED_LV50 }
        if berryKnown { medals |= MED_BERRY }
        if streak >= 7 { medals |= MED_STREAK7 }
        if bond >= 100 { medals |= MED_BOND }
        if DexTables.EVOLVES_TO[speciesId] == 0 { medals |= MED_FINAL }
        if weight == 0 && level() >= 5 && careMistakes == 0 { medals |= MED_FIT }
        let gained = medals & ~before
        if gained != 0 {
            totalMedals += gained.nonzeroBitCount
            newMedal = gained
            medalUntil = millis() + 4000
            if !sleeping { sfx(.medal) }
            save()
        }
    }

    func rename(_ name: String) {
        nick = String(name.prefix(11))
        save()
    }

    private func calcStat(_ base: Int, _ gene: Int, _ lvl: Int, _ tr: Int) -> Int { base * gene / 100 + lvl + tr }

    func atkStat() -> Int { isEgg() ? 0 : calcStat(DexTables.B_ATK[speciesId], geneAtk, level(), trAtk) }
    func defStat() -> Int { isEgg() ? 0 : calcStat(DexTables.B_DEF[speciesId], geneDef, level(), trDef) }
    func speStat() -> Int { isEgg() ? 0 : calcStat(DexTables.B_SPE[speciesId], geneSpe, level(), trSpe) }

    func registeredCount() -> Int { (1...151).filter { isRegistered($0) }.count }

    func canFarewellNow() -> Bool {
        !isEgg() && !sleeping && ceremony == CER_NONE &&
            DexTables.EVOLVES_TO[speciesId] == 0 && ageMinutes >= FAREWELL_AGE_MIN
    }

    func canRunawayNow() -> Bool { !isEgg() && !sleeping && ceremony == CER_NONE && neglectTicks >= RUNAWAY_TICKS }

    func startFarewell() {
        if isEgg() || ceremony != CER_NONE { return }
        lastEnd = CER_FAREWELL
        ceremony = CER_FAREWELL
        ceremonyUntil = millis() + CEREMONY_MS
        heartUntil = ceremonyUntil
        sfx(.bye)
        save()
    }

    func startRunaway() {
        if isEgg() || ceremony != CER_NONE { return }
        lastEnd = CER_RUNAWAY
        ceremony = CER_RUNAWAY
        ceremonyUntil = millis() + CEREMONY_MS
        sfx(.bye)
        save()
    }

    func release() {
        if isEgg() || ceremony != CER_NONE { return }
        lastEnd = CER_RELEASE
        ceremony = CER_RELEASE
        ceremonyUntil = millis() + CEREMONY_MS
        heartUntil = ceremonyUntil
        sfx(.bye)
        save()
    }

    private func hatch() {
        speciesId = eggTarget
        shiny = eggShiny
        geneAtk = 90 + random(21)
        geneDef = 90 + random(21)
        geneSpe = 90 + random(21)
        trAtk = 0; trDef = 0; trSpe = 0
        berryKnown = false
        bond = 0
        bondToday = 0
        medals = 0
        newMedal = 0
        nick = ""
        registerSpecies(speciesId)
        checkMedals()
        sfx(.hatch)
        save()
    }

    func canEvolveNow() -> Bool {
        if isEgg() || sleeping || ceremony != CER_NONE { return false }
        if DexTables.EVOLVES_TO[speciesId] == 0 { return false }
        return level() >= DexTables.EVOLVE_LEVEL[speciesId] + careMistakes && lowestStat() >= 40
    }

    func evolve() {
        if !canEvolveNow() { return }
        prevSpeciesId = speciesId
        var next = DexTables.EVOLVES_TO[speciesId]
        if speciesId == DEX_EEVEE {
            let opts = (134...136).filter { !isRegistered($0) }
            next = !opts.isEmpty ? opts[random(opts.count)] : 134 + random(3)
        }
        speciesId = next
        registerSpecies(speciesId)
        sfx(.evolve)
        evolveUntil = millis() + EVOLVE_ANIM_MS
        save()
    }

    func feed() { feedBerry(0) }

    func feedBerry(_ color: Int) {
        if ceremony != CER_NONE { return }
        if isEgg() || sleeping { return }
        if lovesBerry(color) {
            fullness = Pet.clamp100(fullness + 35)
            joy = Pet.clamp100(joy + 10)
            heartUntil = millis() + HEART_MS
            berryKnown = true
            addBond(2)
        } else {
            fullness = Pet.clamp100(fullness + 25)
        }
        eatUntil = millis() + EAT_ANIM_MS
        registerCare()
        save()
    }

    func feedCandy() {
        if ceremony != CER_NONE { return }
        if isEgg() || sleeping { return }
        fullness = Pet.clamp100(fullness + 10)
        joy = Pet.clamp100(joy + 12)
        weight = Pet.clamp100(weight + 12)
        eatUntil = millis() + EAT_ANIM_MS
        registerCare()
        save()
    }

    func playResult(_ score: Int) {
        if ceremony != CER_NONE || isEgg() { return }
        let v = trSpe + score / 5
        trSpe = v > 100 ? 100 : v
        joy = Pet.clamp100(joy + 5 + (score > 15 ? 30 : score * 2))
        energy = Pet.dropTo(energy, 10 + score / 2, 5)
        fullness = Pet.dropTo(fullness, 5, 5)
        let burn = weight - score * 2
        weight = burn > 0 ? burn : 0
        if score >= 5 { heartUntil = millis() + HEART_MS }
        if score > gameHi { gameHi = score }
        addBond(2)
        registerCare()
        save()
    }

    @discardableResult
    func trainStrength(_ hits: Int) -> Int {
        if ceremony != CER_NONE || isEgg() { return 0 }
        var gain = hits / 4
        if gain > 18 { gain = 18 }
        let before = trAtk
        let v = trAtk + gain
        trAtk = v > 100 ? 100 : v
        gain = trAtk - before
        energy = Pet.dropTo(energy, 12, 5)
        fullness = Pet.dropTo(fullness, 5, 5)
        let burn = weight - hits / 3
        weight = burn > 0 ? burn : 0
        joy = Pet.clamp100(joy + 6)
        if hits >= 20 { heartUntil = millis() + HEART_MS }
        if hits > strHi { strHi = hits }
        addBond(2)
        registerCare()
        save()
        return gain
    }

    func play() {
        if ceremony != CER_NONE { return }
        if isEgg() || sleeping { return }
        joy = Pet.clamp100(joy + 25)
        energy = Pet.clamp100(energy - 10)
        fullness = Pet.clamp100(fullness - 5)
        heartUntil = millis() + HEART_MS
        addBond(2)
        registerCare()
        save()
    }

    func toggleLight() {
        if ceremony != CER_NONE { return }
        if isEgg() { return }
        sleeping.toggle()
        save()
    }

    func clean() {
        if ceremony != CER_NONE { return }
        poops = 0
        hygiene = 100
        addBond(1)
        registerCare()
        save()
    }

    func caress() {
        if ceremony != CER_NONE { return }
        if isEgg() || sleeping { return }
        joy = Pet.clamp100(joy + 5)
        heartUntil = millis() + HEART_MS
        addBond(1)
        registerCare()
    }

    func eggTap() {
        if !isEgg() { return }
        eggTaps += 1
        if eggTaps >= 3 { hatch() } else { save() }
    }

    func mood() -> Mood {
        if sleeping { return .sleeping }
        if eating() { return .eating }
        if lowestStat() < 25 { return .sad }
        return .happy
    }

    // test hooks (the firmware's serial console commands)
    func dbgRunawayReady() {
        fullness = 0; joy = 0; energy = 0; hygiene = 0
        neglectTicks = RUNAWAY_TICKS
    }

    func save() {
        ticksSinceSave = 0
        pendingSave = false
        prefs.putInt("full", fullness)
        prefs.putInt("joy", joy)
        prefs.putInt("ene", energy)
        prefs.putInt("hyg", hygiene)
        prefs.putInt("poop", poops)
        prefs.putInt("wgt", weight)
        prefs.putInt("gatk", geneAtk)
        prefs.putInt("gdef", geneDef)
        prefs.putInt("gspe", geneSpe)
        prefs.putInt("tatk", trAtk)
        prefs.putInt("tdef", trDef)
        prefs.putInt("tspe", trSpe)
        prefs.putBool("bk", berryKnown)
        prefs.putBool("shy", shiny)
        prefs.putBool("eshy", eggShiny)
        prefs.putBool("stpk", starterPick)
        prefs.putString("dexsh", Pet.hex(dexShinyReg))
        prefs.putInt("age", ageMinutes)
        prefs.putInt("dexn", speciesId)
        prefs.putInt("eggT2", eggTarget)
        prefs.putInt("crack", eggTaps)
        prefs.putInt("mist", careMistakes)
        prefs.putBool("sleep", sleeping)
        prefs.putInt("lend", lastEnd)
        if lastSeenEpoch != 0 { prefs.putInt("seen", lastSeenEpoch) }
        prefs.putString("dexreg", Pet.hex(dexReg))
        prefs.putInt("strk", streak)
        prefs.putInt("bstrk", bestStreak)
        prefs.putInt("cday", lastCareDay)
        prefs.putInt("bond", bond)
        prefs.putInt("medal", medals)
        prefs.putInt("tmedal", totalMedals)
        prefs.putInt("mstone", lastMilestone)
        prefs.putInt("ghi", gameHi)
        prefs.putInt("shi", strHi)
        prefs.putString("nick", nick)
        // the firmware keeps these two only in RAM; a watch app is suspended
        // often, so they are persisted to keep "keep form"/"stay together" sticky
        prefs.putInt("evodl", evoDeclinedLv)
        prefs.putInt("fardl", farDeclinedAge)
        prefs.putInt("negl", neglectTicks)
        prefs.putInt("mcool", mistakeCooldown)
        prefs.putInt("good", goodTicks)
        prefs.putInt("bday", bondToday)
        prefs.flush()
    }

    private func load() {
        fullness = prefs.getInt("full", 80)
        joy = prefs.getInt("joy", 80)
        energy = prefs.getInt("ene", 80)
        hygiene = prefs.getInt("hyg", 100)
        poops = prefs.getInt("poop", 0)
        weight = prefs.getInt("wgt", 0)
        geneAtk = prefs.getInt("gatk", 0)
        geneDef = prefs.getInt("gdef", 0)
        geneSpe = prefs.getInt("gspe", 0)
        if geneAtk == 0 {
            geneAtk = 90 + random(21)
            geneDef = 90 + random(21)
            geneSpe = 90 + random(21)
        }
        trAtk = prefs.getInt("tatk", 0)
        trDef = prefs.getInt("tdef", 0)
        trSpe = prefs.getInt("tspe", 0)
        berryKnown = prefs.getBool("bk", false)
        shiny = prefs.getBool("shy", false)
        eggShiny = prefs.getBool("eshy", false)
        starterPick = prefs.getBool("stpk", false)
        Pet.unhex(prefs.getString("dexsh", ""), &dexShinyReg)
        ageMinutes = prefs.getInt("age", 0)
        speciesId = prefs.getInt("dexn", -1)
        eggTarget = prefs.getInt("eggT2", 4)
        eggTaps = prefs.getInt("crack", 0)
        careMistakes = prefs.getInt("mist", 0)
        sleeping = prefs.getBool("sleep", false)
        lastEnd = prefs.getInt("lend", CER_NONE)
        Pet.unhex(prefs.getString("dexreg", ""), &dexReg)
        streak = prefs.getInt("strk", 0)
        bestStreak = prefs.getInt("bstrk", 0)
        lastCareDay = prefs.getInt("cday", 0)
        bond = prefs.getInt("bond", 0)
        medals = prefs.getInt("medal", 0)
        totalMedals = prefs.getInt("tmedal", 0)
        lastMilestone = prefs.getInt("mstone", 0)
        gameHi = prefs.getInt("ghi", 0)
        strHi = prefs.getInt("shi", 0)
        nick = prefs.getString("nick", "")
        evoDeclinedLv = prefs.getInt("evodl", 0)
        farDeclinedAge = prefs.getInt("fardl", 0)
        neglectTicks = prefs.getInt("negl", 0)
        mistakeCooldown = prefs.getInt("mcool", 0)
        goodTicks = prefs.getInt("good", 0)
        bondToday = prefs.getInt("bday", 0)
        if speciesId >= 1 { registerSpecies(speciesId) }
    }

    static func clamp100(_ v: Int) -> Int { v < 0 ? 0 : (v > 100 ? 100 : v) }

    /// Offline decay with mercy: never below the floor (comes back hungry, not dead).
    static func dropTo(_ v: Int, _ d: Int, _ fl: Int) -> Int {
        if v <= fl { return v }
        return v - fl > d ? v - d : fl
    }

    private static func hex(_ b: [UInt8]) -> String {
        b.map { v -> String in let h = String(v, radix: 16); return h.count == 1 ? "0" + h : h }.joined()
    }

    private static func unhex(_ s: String, _ out: inout [UInt8]) {
        let chars = Array(s.utf8)
        for i in out.indices {
            if chars.count >= i * 2 + 2, let v = UInt8(String(decoding: chars[(i * 2)..<(i * 2 + 2)], as: UTF8.self), radix: 16) {
                out[i] = v
            } else {
                out[i] = 0
            }
        }
    }
}
