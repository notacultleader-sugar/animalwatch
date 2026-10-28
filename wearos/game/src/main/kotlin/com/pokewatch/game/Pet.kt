// Port of TamaPoke's pet.h / pet.cpp (MIT, (c) 2026 Quique Tortosa).
// Same rules and numbers as the firmware; only storage and timing are adapted.
package com.pokewatch.game

import kotlin.random.Random

const val PET_TICK_MS = 60_000L
const val MINUTES_PER_LEVEL = 60
const val EAT_ANIM_MS = 2500L
const val HEART_MS = 1500L
const val EVOLVE_ANIM_MS = 5200L
const val CEREMONY_MS = 10_000L
const val FAREWELL_AGE_MIN = 3L * 24 * 60
const val RUNAWAY_TICKS = 60

const val CER_NONE = 0
const val CER_FAREWELL = 1
const val CER_RUNAWAY = 2
const val CER_RELEASE = 3

const val R_EVO = 0
const val R_COMUN = 1
const val R_RARO = 2
const val R_LEGENDARIO = 3

const val DEX_COUNT = 151
const val DEX_EEVEE = 133
val CLASSIC_DEX = intArrayOf(1, 4, 7, 25, 133)

const val MED_LV10 = 1 shl 0
const val MED_LV25 = 1 shl 1
const val MED_LV50 = 1 shl 2
const val MED_BERRY = 1 shl 3
const val MED_STREAK7 = 1 shl 4
const val MED_BOND = 1 shl 5
const val MED_FINAL = 1 shl 6
const val MED_FIT = 1 shl 7
const val MED_COUNT = 8

enum class Mood { HAPPY, SAD, EATING, SLEEPING }

enum class Sfx { TAP, EAT, PLAY, HEART, HATCH, EVOLVE, MEDAL, DENY, BYE, LEVEL }

/** Key/value persistence, the role ESP32 Preferences (NVS) plays in the firmware. */
interface Store {
    fun getInt(key: String, def: Int): Int
    fun putInt(key: String, v: Int)
    fun getLong(key: String, def: Long): Long
    fun putLong(key: String, v: Long)
    fun getBool(key: String, def: Boolean): Boolean
    fun putBool(key: String, v: Boolean)
    fun getString(key: String, def: String): String
    fun putString(key: String, v: String)
    fun has(key: String): Boolean
    fun clear()
    /** Called once at the end of every save, so a store can batch the writes. */
    fun flush() {}
}

class Pet(
    private val prefs: Store,
    private val rng: Random = Random.Default,
    private val millis: () -> Long = { System.currentTimeMillis() },
    private val sfx: (Sfx) -> Unit = {},
) {
    var fullness = 80
    var joy = 80
    var energy = 80
    var hygiene = 100
    var poops = 0
    var weight = 0
    var geneAtk = 100; var geneDef = 100; var geneSpe = 100
    var trAtk = 0; var trDef = 0; var trSpe = 0
    var berryKnown = false
    var shiny = false
    var ageMinutes = 0L
    var speciesId = -1
    var prevSpeciesId = -1
    var careMistakes = 0
    var sleeping = false
    var lastSeenEpoch = 0L
    var ceremony = CER_NONE
    var lastEnd = CER_NONE
    val dexReg = ByteArray(19)
    val dexShinyReg = ByteArray(19)
    var streak = 0; var bestStreak = 0
    var lastCareDay = 0L
    var bond = 0
    var nick = ""
    var medals = 0; var totalMedals = 0
    var newMedal = 0
    var lastMilestone = 0
    var gameHi = 0
    var strHi = 0

    private var lastTick = 0L
    private var eatUntil = 0L
    private var heartUntil = 0L
    private var evolveUntil = 0L
    private var eggTarget = 1
    private var eggShiny = false
    private var eggTaps = 0
    private var mistakeCooldown = 0
    private var ticksSinceSave = 0
    var pendingSave = false
        private set
    private var evoDeclinedLv = 0
    private var farDeclinedAge = 0L
    private var starterPick = false
    private var neglectTicks = 0
    private var goodTicks = 0
    private var ceremonyUntil = 0L
    private var bondToday = 0
    private var medalUntil = 0L
    private var milestoneUntil = 0L

    private fun timeLeft(deadline: Long): Long {
        if (deadline == 0L) return 0
        val left = deadline - millis()
        return if (left > 0) left else 0
    }

    private fun random(n: Int) = rng.nextInt(n)

    fun begin() {
        if (!prefs.getBool("init", false)) {
            prefs.putBool("init", true)
            newEgg()
        } else {
            load()
        }
        lastTick = millis()
    }

    fun lovesBerry(color: Int) = !isEgg() && (speciesId % 3) == color
    fun isEgg() = speciesId < 0
    fun eggCracks() = eggTaps
    fun eating() = timeLeft(eatUntil) > 0
    fun showHeart() = timeLeft(heartUntil) > 0
    fun evolving() = timeLeft(evolveUntil) > 0
    fun evolveT() = 1f - timeLeft(evolveUntil).toFloat() / EVOLVE_ANIM_MS
    fun wantEvolveButton() = canEvolveNow() && level() > evoDeclinedLv
    fun wantFarewellButton() = canFarewellNow() && ageMinutes >= farDeclinedAge
    fun declineEvolve() { evoDeclinedLv = level() }
    fun declineFarewell() { farDeclinedAge = ageMinutes + 1440 }
    fun awaitingStarter() = starterPick
    fun chooseStarter(dex: Int) { eggTarget = dex; starterPick = false; save() }
    fun factoryReset() = prefs.clear()

    fun level(): Int {
        val lv = 1 + ageMinutes / MINUTES_PER_LEVEL
        return if (lv > 999) 999 else lv.toInt()
    }

    fun isRegistered(dex: Int) =
        dex in 1..151 && (dexReg[(dex - 1) shr 3].toInt() and (1 shl ((dex - 1) and 7))) != 0

    fun isShinyRegistered(dex: Int) =
        dex in 1..151 && (dexShinyReg[(dex - 1) shr 3].toInt() and (1 shl ((dex - 1) and 7))) != 0

    fun lowestStat() = minOf(minOf(fullness, joy), minOf(energy, hygiene))

    fun ceremonyT(): Float =
        if (ceremony == CER_NONE) 0f else 1f - timeLeft(ceremonyUntil).toFloat() / CEREMONY_MS

    fun hasMedal(m: Int) = (medals and m) != 0
    fun showMedal() = timeLeft(medalUntil) > 0
    fun showMilestone() = timeLeft(milestoneUntil) > 0
    fun savedEpoch() = prefs.getLong("seen", 0)

    fun newEgg() {
        ceremony = CER_NONE
        neglectTicks = 0
        weight = 0
        speciesId = -1
        prevSpeciesId = -1
        eggTarget = pickEggSpecies()
        starterPick = registeredCount() == 0
        var shinyBase = (if (lastEnd == CER_FAREWELL) 24 else 48) - careBonus()
        if (shinyBase < 8) shinyBase = 8
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

    fun setClock(nowEpoch: Long) {
        lastSeenEpoch = nowEpoch
        if (nowEpoch != 0L) save()
    }

    /** Applies the time that passed while the app was closed (gentle: floors, no slip-ups). */
    fun syncClock(nowEpoch: Long) {
        val seen = prefs.getLong("seen", 0)
        lastSeenEpoch = nowEpoch
        if (nowEpoch == 0L) return
        var mins = if (seen != 0L && nowEpoch > seen) (nowEpoch - seen) / 60 else 0
        if (mins < 2 || ceremony != CER_NONE || starterPick) {
            save()
            return
        }
        if (mins > 14L * 24 * 60) mins = 14L * 24 * 60
        // keep the live minute clock in step so these minutes aren't ticked twice
        lastTick = millis()

        for (i in 0 until mins) {
            ageMinutes++
            if (isEgg()) {
                if (ageMinutes >= 3) hatch()
                continue
            }
            if (sleeping) {
                energy = clamp100(energy + 6)
                if (ageMinutes % 2 == 0L) {
                    fullness = dropTo(fullness, 1, 30)
                    joy = dropTo(joy, 1, 35)
                }
                if (ageMinutes % 3 == 0L) hygiene = dropTo(hygiene, 1, 45)
                continue
            }
            fullness = dropTo(fullness, 2, 15)
            energy = dropTo(energy, 1, 15)
            hygiene = dropTo(hygiene, 1, 15)
            joy = dropTo(joy, 1, 15)
        }
        if (!isEgg() && !sleeping) {
            val p = poops + (mins / 240).toInt()
            poops = if (p > 3) 3 else p
        }
        save()
    }

    fun update(nowMs: Long) {
        if (ceremony != CER_NONE && timeLeft(ceremonyUntil) == 0L) {
            newEgg()
            return
        }
        while (nowMs - lastTick >= PET_TICK_MS) {
            lastTick += PET_TICK_MS
            tick()
        }
    }

    private fun tick() {
        if (ceremony != CER_NONE) return
        if (starterPick) return
        ageMinutes++

        if (isEgg()) {
            if (ageMinutes >= 3) hatch()
            return
        }

        if (sleeping) {
            energy = clamp100(energy + 6)
            if (weight > 0 && ageMinutes % 3 == 0L) weight--
            if (ageMinutes % 2 == 0L) {
                fullness = dropTo(fullness, 1, 30)
                joy = dropTo(joy, 1, 35)
            }
            if (ageMinutes % 3 == 0L) hygiene = dropTo(hygiene, 1, 45)
            checkMedals()
            if (++ticksSinceSave >= 5) pendingSave = true
            return
        }

        if (ageMinutes % MINUTES_PER_LEVEL == 0L) sfx(Sfx.LEVEL)

        fullness = clamp100(fullness - 2)
        energy = clamp100(energy - 1)
        if (fullness > 40 && poops < 3 && random(100) < 15) poops++

        hygiene = clamp100(hygiene - 1 - 4 * poops)
        if (weight > 50) energy = clamp100(energy - 1)
        if (weight > 0 && ageMinutes % 3 == 0L) weight--

        if (lowestStat() >= 40) {
            if (++goodTicks >= 720) {
                goodTicks = 0
                if (trDef < 100) trDef++
            }
        } else {
            goodTicks = 0
        }

        var dJoy = -1
        if (fullness < 30) dJoy -= 2
        if (hygiene < 30) dJoy -= 2
        joy = clamp100(joy + dJoy)

        if (mistakeCooldown > 0) mistakeCooldown--
        if (lowestStat() <= 10 && mistakeCooldown == 0) {
            careMistakes++
            mistakeCooldown = 60
            if (bond > 1) bond--
        }

        checkMedals()

        if (fullness == 0 && joy == 0 && energy == 0 && hygiene == 0) {
            if (neglectTicks < RUNAWAY_TICKS) neglectTicks++
        } else {
            neglectTicks = 0
        }

        if (++ticksSinceSave >= 5) pendingSave = true
    }

    fun flushSave() {
        if (pendingSave) save()
    }

    fun lineHasUnregistered(base: Int): Boolean {
        var cur = base
        var guard = 0
        while (cur in 1..151 && guard < 6) {
            if (!isRegistered(cur)) return true
            if (cur == DEX_EEVEE) {
                for (b in 134..136) if (!isRegistered(b)) return true
                return false
            }
            cur = DexTables.EVOLVES_TO[cur]
            guard++
        }
        return false
    }

    fun eggRarity() = if (eggTarget in 1..151) DexTables.RARITY[eggTarget] else R_COMUN

    fun pickEggSpecies(): Int {
        if (registeredCount() == 0) return CLASSIC_DEX[random(CLASSIC_DEX.size)]

        var tier = R_COMUN
        if (lastEnd != CER_RUNAWAY) {
            val blessed = lastEnd == CER_FAREWELL
            val rare = (if (blessed) 45 else 27) + careBonus()
            val leg = if (registeredCount() >= 25) (if (blessed) 10 else 3) + careBonus() / 3 else 0
            val r = random(100)
            if (r < leg) tier = R_LEGENDARIO
            else if (r < leg + rare) tier = R_RARO
        }

        for (pass in 0 until 2) {
            for (t in tier downTo R_COMUN) {
                val cand = ArrayList<Int>()
                for (d in 1..151) {
                    if (cand.size >= 80) break
                    if (DexTables.RARITY[d] != t) continue
                    if (pass == 0 && !lineHasUnregistered(d)) continue
                    cand.add(d)
                }
                if (cand.isNotEmpty()) return cand[random(cand.size)]
            }
        }
        return CLASSIC_DEX[random(CLASSIC_DEX.size)]
    }

    private fun registerSpecies(dex: Int) {
        if (dex < 1 || dex > 151) return
        val i = (dex - 1) shr 3
        val bit = 1 shl ((dex - 1) and 7)
        dexReg[i] = (dexReg[i].toInt() or bit).toByte()
        if (shiny) dexShinyReg[i] = (dexShinyReg[i].toInt() or bit).toByte()
    }

    fun careBonus(): Int {
        val s = if (streak > 30) 30 else streak
        return s / 3 + bond / 25
    }

    private fun today() = if (lastSeenEpoch != 0L) lastSeenEpoch / 86400 else 0

    private fun registerCare() {
        if (isEgg() || ceremony != CER_NONE) return
        val d = today()
        if (d == 0L || d == lastCareDay) return
        if (lastCareDay == 0L || d == lastCareDay + 1) {
            streak++
        } else {
            streak = 1
            lastMilestone = 0
        }
        lastCareDay = d
        bondToday = 0
        if (streak > bestStreak) bestStreak = streak
        bond = clamp100(bond + 4)
        val ms = when {
            streak >= 100 -> 100
            streak >= 30 -> 30
            streak >= 7 -> 7
            streak >= 3 -> 3
            else -> 0
        }
        if (ms > lastMilestone) {
            lastMilestone = ms
            milestoneUntil = millis() + 4500
        }
        checkMedals()
        save()
    }

    private fun addBond(amt: Int) {
        if (bondToday >= 20) return
        bond = clamp100(bond + amt)
        bondToday += amt
    }

    private fun checkMedals() {
        if (isEgg()) return
        val before = medals
        if (level() >= 10) medals = medals or MED_LV10
        if (level() >= 25) medals = medals or MED_LV25
        if (level() >= 50) medals = medals or MED_LV50
        if (berryKnown) medals = medals or MED_BERRY
        if (streak >= 7) medals = medals or MED_STREAK7
        if (bond >= 100) medals = medals or MED_BOND
        if (DexTables.EVOLVES_TO[speciesId] == 0) medals = medals or MED_FINAL
        if (weight == 0 && level() >= 5 && careMistakes == 0) medals = medals or MED_FIT
        val gained = medals and before.inv()
        if (gained != 0) {
            totalMedals += Integer.bitCount(gained)
            newMedal = gained
            medalUntil = millis() + 4000
            if (!sleeping) sfx(Sfx.MEDAL)
            save()
        }
    }

    fun rename(name: String) {
        nick = name.take(11)
        save()
    }

    private fun calcStat(base: Int, gene: Int, lvl: Int, tr: Int) = base * gene / 100 + lvl + tr

    fun atkStat() = if (isEgg()) 0 else calcStat(DexTables.B_ATK[speciesId], geneAtk, level(), trAtk)
    fun defStat() = if (isEgg()) 0 else calcStat(DexTables.B_DEF[speciesId], geneDef, level(), trDef)
    fun speStat() = if (isEgg()) 0 else calcStat(DexTables.B_SPE[speciesId], geneSpe, level(), trSpe)

    fun registeredCount() = (1..151).count { isRegistered(it) }

    fun canFarewellNow() = !isEgg() && !sleeping && ceremony == CER_NONE &&
        DexTables.EVOLVES_TO[speciesId] == 0 && ageMinutes >= FAREWELL_AGE_MIN

    fun canRunawayNow() = !isEgg() && !sleeping && ceremony == CER_NONE && neglectTicks >= RUNAWAY_TICKS

    fun startFarewell() {
        if (isEgg() || ceremony != CER_NONE) return
        lastEnd = CER_FAREWELL
        ceremony = CER_FAREWELL
        ceremonyUntil = millis() + CEREMONY_MS
        heartUntil = ceremonyUntil
        sfx(Sfx.BYE)
        save()
    }

    fun startRunaway() {
        if (isEgg() || ceremony != CER_NONE) return
        lastEnd = CER_RUNAWAY
        ceremony = CER_RUNAWAY
        ceremonyUntil = millis() + CEREMONY_MS
        sfx(Sfx.BYE)
        save()
    }

    fun release() {
        if (isEgg() || ceremony != CER_NONE) return
        lastEnd = CER_RELEASE
        ceremony = CER_RELEASE
        ceremonyUntil = millis() + CEREMONY_MS
        heartUntil = ceremonyUntil
        sfx(Sfx.BYE)
        save()
    }

    private fun hatch() {
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
        sfx(Sfx.HATCH)
        save()
    }

    fun canEvolveNow(): Boolean {
        if (isEgg() || sleeping || ceremony != CER_NONE) return false
        if (DexTables.EVOLVES_TO[speciesId] == 0) return false
        return level() >= DexTables.EVOLVE_LEVEL[speciesId] + careMistakes && lowestStat() >= 40
    }

    fun evolve() {
        if (!canEvolveNow()) return
        prevSpeciesId = speciesId
        var next = DexTables.EVOLVES_TO[speciesId]
        if (speciesId == DEX_EEVEE) {
            val opts = (134..136).filter { !isRegistered(it) }
            next = if (opts.isNotEmpty()) opts[random(opts.size)] else 134 + random(3)
        }
        speciesId = next
        registerSpecies(speciesId)
        sfx(Sfx.EVOLVE)
        evolveUntil = millis() + EVOLVE_ANIM_MS
        save()
    }

    fun feed() = feedBerry(0)

    fun feedBerry(color: Int) {
        if (ceremony != CER_NONE) return
        if (isEgg() || sleeping) return
        if (lovesBerry(color)) {
            fullness = clamp100(fullness + 35)
            joy = clamp100(joy + 10)
            heartUntil = millis() + HEART_MS
            berryKnown = true
            addBond(2)
        } else {
            fullness = clamp100(fullness + 25)
        }
        eatUntil = millis() + EAT_ANIM_MS
        registerCare()
        save()
    }

    fun feedCandy() {
        if (ceremony != CER_NONE) return
        if (isEgg() || sleeping) return
        fullness = clamp100(fullness + 10)
        joy = clamp100(joy + 12)
        weight = clamp100(weight + 12)
        eatUntil = millis() + EAT_ANIM_MS
        registerCare()
        save()
    }

    fun playResult(score: Int) {
        if (ceremony != CER_NONE || isEgg()) return
        val v = trSpe + score / 5
        trSpe = if (v > 100) 100 else v
        joy = clamp100(joy + 5 + if (score > 15) 30 else score * 2)
        energy = dropTo(energy, 10 + score / 2, 5)
        fullness = dropTo(fullness, 5, 5)
        val burn = weight - score * 2
        weight = if (burn > 0) burn else 0
        if (score >= 5) heartUntil = millis() + HEART_MS
        if (score > gameHi) gameHi = score
        addBond(2)
        registerCare()
        save()
    }

    fun trainStrength(hits: Int): Int {
        if (ceremony != CER_NONE || isEgg()) return 0
        var gain = hits / 4
        if (gain > 18) gain = 18
        val before = trAtk
        val v = trAtk + gain
        trAtk = if (v > 100) 100 else v
        gain = trAtk - before
        energy = dropTo(energy, 12, 5)
        fullness = dropTo(fullness, 5, 5)
        val burn = weight - hits / 3
        weight = if (burn > 0) burn else 0
        joy = clamp100(joy + 6)
        if (hits >= 20) heartUntil = millis() + HEART_MS
        if (hits > strHi) strHi = hits
        addBond(2)
        registerCare()
        save()
        return gain
    }

    fun play() {
        if (ceremony != CER_NONE) return
        if (isEgg() || sleeping) return
        joy = clamp100(joy + 25)
        energy = clamp100(energy - 10)
        fullness = clamp100(fullness - 5)
        heartUntil = millis() + HEART_MS
        addBond(2)
        registerCare()
        save()
    }

    fun toggleLight() {
        if (ceremony != CER_NONE) return
        if (isEgg()) return
        sleeping = !sleeping
        save()
    }

    fun clean() {
        if (ceremony != CER_NONE) return
        poops = 0
        hygiene = 100
        addBond(1)
        registerCare()
        save()
    }

    fun caress() {
        if (ceremony != CER_NONE) return
        if (isEgg() || sleeping) return
        joy = clamp100(joy + 5)
        heartUntil = millis() + HEART_MS
        addBond(1)
        registerCare()
    }

    fun eggTap() {
        if (!isEgg()) return
        if (++eggTaps >= 3) hatch() else save()
    }

    fun mood(): Mood = when {
        sleeping -> Mood.SLEEPING
        eating() -> Mood.EATING
        lowestStat() < 25 -> Mood.SAD
        else -> Mood.HAPPY
    }

    // test hooks (the firmware's serial console commands)
    fun dbgRunawayReady() {
        fullness = 0; joy = 0; energy = 0; hygiene = 0
        neglectTicks = RUNAWAY_TICKS
    }

    fun save() {
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
        prefs.putString("dexsh", hex(dexShinyReg))
        prefs.putLong("age", ageMinutes)
        prefs.putInt("dexn", speciesId)
        prefs.putInt("eggT2", eggTarget)
        prefs.putInt("crack", eggTaps)
        prefs.putInt("mist", careMistakes)
        prefs.putBool("sleep", sleeping)
        prefs.putInt("lend", lastEnd)
        if (lastSeenEpoch != 0L) prefs.putLong("seen", lastSeenEpoch)
        prefs.putString("dexreg", hex(dexReg))
        prefs.putInt("strk", streak)
        prefs.putInt("bstrk", bestStreak)
        prefs.putLong("cday", lastCareDay)
        prefs.putInt("bond", bond)
        prefs.putInt("medal", medals)
        prefs.putInt("tmedal", totalMedals)
        prefs.putInt("mstone", lastMilestone)
        prefs.putInt("ghi", gameHi)
        prefs.putInt("shi", strHi)
        prefs.putString("nick", nick)
        // the firmware keeps these two only in RAM; a phone-style app is killed
        // often, so they are persisted to keep "keep form"/"stay together" sticky
        prefs.putInt("evodl", evoDeclinedLv)
        prefs.putLong("fardl", farDeclinedAge)
        prefs.putInt("negl", neglectTicks)
        prefs.putInt("mcool", mistakeCooldown)
        prefs.putInt("good", goodTicks)
        prefs.putInt("bday", bondToday)
        prefs.flush()
    }

    private fun load() {
        fullness = prefs.getInt("full", 80)
        joy = prefs.getInt("joy", 80)
        energy = prefs.getInt("ene", 80)
        hygiene = prefs.getInt("hyg", 100)
        poops = prefs.getInt("poop", 0)
        weight = prefs.getInt("wgt", 0)
        geneAtk = prefs.getInt("gatk", 0)
        geneDef = prefs.getInt("gdef", 0)
        geneSpe = prefs.getInt("gspe", 0)
        if (geneAtk == 0) {
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
        unhex(prefs.getString("dexsh", ""), dexShinyReg)
        ageMinutes = prefs.getLong("age", 0)
        speciesId = prefs.getInt("dexn", -1)
        eggTarget = prefs.getInt("eggT2", 4)
        eggTaps = prefs.getInt("crack", 0)
        careMistakes = prefs.getInt("mist", 0)
        sleeping = prefs.getBool("sleep", false)
        lastEnd = prefs.getInt("lend", CER_NONE)
        unhex(prefs.getString("dexreg", ""), dexReg)
        streak = prefs.getInt("strk", 0)
        bestStreak = prefs.getInt("bstrk", 0)
        lastCareDay = prefs.getLong("cday", 0)
        bond = prefs.getInt("bond", 0)
        medals = prefs.getInt("medal", 0)
        totalMedals = prefs.getInt("tmedal", 0)
        lastMilestone = prefs.getInt("mstone", 0)
        gameHi = prefs.getInt("ghi", 0)
        strHi = prefs.getInt("shi", 0)
        nick = prefs.getString("nick", "")
        evoDeclinedLv = prefs.getInt("evodl", 0)
        farDeclinedAge = prefs.getLong("fardl", 0)
        neglectTicks = prefs.getInt("negl", 0)
        mistakeCooldown = prefs.getInt("mcool", 0)
        goodTicks = prefs.getInt("good", 0)
        bondToday = prefs.getInt("bday", 0)
        if (speciesId >= 1) registerSpecies(speciesId)
    }

    companion object {
        fun clamp100(v: Int) = if (v < 0) 0 else if (v > 100) 100 else v

        /** Offline decay with mercy: never below the floor (comes back hungry, not dead). */
        fun dropTo(v: Int, d: Int, fl: Int): Int {
            if (v <= fl) return v
            return if (v - fl > d) v - d else fl
        }

        private fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it.toInt() and 0xFF) }

        private fun unhex(s: String, out: ByteArray) {
            for (i in out.indices) {
                out[i] = if (s.length >= i * 2 + 2) s.substring(i * 2, i * 2 + 2).toInt(16).toByte() else 0
            }
        }
    }
}
