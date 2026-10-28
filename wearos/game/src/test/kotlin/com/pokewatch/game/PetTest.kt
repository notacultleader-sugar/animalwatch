// Port of TamaPoke's test/test_pet.cpp (MIT, (c) 2026 Quique Tortosa):
// the same cases, so the Kotlin rules are checked against the firmware's.
package com.pokewatch.game

import kotlin.random.Random
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MemStore : Store {
    val m = HashMap<String, Any>()
    override fun getInt(key: String, def: Int) = m[key] as? Int ?: def
    override fun putInt(key: String, v: Int) { m[key] = v }
    override fun getLong(key: String, def: Long) = m[key] as? Long ?: def
    override fun putLong(key: String, v: Long) { m[key] = v }
    override fun getBool(key: String, def: Boolean) = m[key] as? Boolean ?: def
    override fun putBool(key: String, v: Boolean) { m[key] = v }
    override fun getString(key: String, def: String) = m[key] as? String ?: def
    override fun putString(key: String, v: String) { m[key] = v }
    override fun has(key: String) = key in m
    override fun clear() = m.clear()
}

/** Arduino random() shim: seedable, and can be forced to a fixed value. */
class TestRandom(seed: Int = 1) : Random() {
    var inner: Random = Random(seed)
    var forced: Int? = null
    fun seed(s: Int) { inner = Random(s) }
    override fun nextBits(bitCount: Int) = inner.nextBits(bitCount)
    override fun nextInt(until: Int): Int = forced?.let { minOf(it, until - 1) } ?: inner.nextInt(until)
}

class PetTest {
    private var now = 0L
    private var nvs = MemStore()
    private val rng = TestRandom()

    private fun newPet() = Pet(nvs, rng, { now })

    @BeforeTest
    fun reset() {
        nvs = MemStore()
        now = 0
        rng.forced = null
        rng.seed(1)
    }

    private fun advance(p: Pet, minutes: Int) {
        repeat(minutes) {
            now += PET_TICK_MS
            p.update(now)
        }
    }

    /** Freshly hatched pet of the given species, on a clean store. */
    private fun makePet(dex: Int): Pet {
        nvs = MemStore()
        now = 0
        val p = newPet()
        p.begin()
        if (p.awaitingStarter()) p.chooseStarter(dex)
        p.eggTap(); p.eggTap(); p.eggTap()
        return p
    }

    private fun Pet.stats(f: Int, j: Int, e: Int, h: Int) {
        fullness = f; joy = j; energy = e; hygiene = h
    }

    private fun Pet.reg(d: Int) {
        dexReg[(d - 1) shr 3] = (dexReg[(d - 1) shr 3].toInt() or (1 shl ((d - 1) and 7))).toByte()
    }

    // ---------------------------------------------------------------- egg
    @Test fun firstGameAsksForStarter() {
        val p = newPet(); p.begin()
        assertTrue(p.isEgg()); assertTrue(p.awaitingStarter())
        assertEquals(0, p.eggCracks()); assertEquals(0, p.registeredCount()); assertEquals(0L, p.ageMinutes)
    }

    @Test fun eggDoesNotHatchWhileChoosingStarter() {
        val p = newPet(); p.begin()
        advance(p, 600)
        assertTrue(p.isEgg()); assertEquals(0L, p.ageMinutes)
        p.chooseStarter(7)
        advance(p, 3)
        assertFalse(p.isEgg()); assertEquals(7, p.speciesId)
    }

    @Test fun eggHatchesAfter3Minutes() {
        val p = newPet(); p.begin(); p.chooseStarter(1)
        advance(p, 2); assertTrue(p.isEgg())
        advance(p, 1); assertFalse(p.isEgg()); assertEquals(1, p.speciesId)
    }

    @Test fun threeTapsHatch() {
        val p = newPet(); p.begin(); p.chooseStarter(4)
        p.eggTap(); assertEquals(1, p.eggCracks()); assertTrue(p.isEgg())
        p.eggTap(); assertEquals(2, p.eggCracks()); assertTrue(p.isEgg())
        p.eggTap(); assertFalse(p.isEgg()); assertEquals(4, p.speciesId)
    }

    @Test fun hatchRollsGenesAndResetsIndividual() {
        val p = makePet(4)
        assertTrue(p.geneAtk in 90..110); assertTrue(p.geneDef in 90..110); assertTrue(p.geneSpe in 90..110)
        assertEquals(0, p.trAtk); assertEquals(0, p.trDef); assertEquals(0, p.trSpe)
        assertEquals(0, p.bond); assertFalse(p.berryKnown); assertEquals("", p.nick)
        assertTrue(p.isRegistered(4)); assertEquals(1, p.registeredCount())
    }

    @Test fun tappingAfterHatchDoesNothing() {
        val p = makePet(4)
        val c = p.eggCracks(); p.eggTap()
        assertEquals(c, p.eggCracks()); assertEquals(4, p.speciesId)
    }

    @Test fun eggRarityIsValid() {
        val p = newPet(); p.begin()
        assertTrue(p.eggRarity() in R_COMUN..R_LEGENDARIO)
    }

    // ---------------------------------------------------------------- feed
    @Test fun normalBerryAdds25CappedAt100() {
        val p = makePet(4); p.fullness = 50
        val notLoved = (p.speciesId + 1) % 3
        p.feedBerry(notLoved); assertEquals(75, p.fullness)
        p.feedBerry(notLoved); assertEquals(100, p.fullness)
    }

    @Test fun favouriteBerryGivesMoreAndHeart() {
        val p = makePet(4)
        assertTrue(p.lovesBerry(1)); assertFalse(p.lovesBerry(0)); assertFalse(p.lovesBerry(2))
        p.fullness = 10; p.joy = 10
        p.feedBerry(1)
        assertEquals(45, p.fullness); assertEquals(20, p.joy)
        assertTrue(p.berryKnown); assertTrue(p.showHeart()); assertTrue(p.eating())
    }

    @Test fun candyFattens() {
        val p = makePet(4); p.fullness = 50; p.joy = 50
        p.feedCandy()
        assertEquals(60, p.fullness); assertEquals(62, p.joy); assertEquals(12, p.weight)
    }

    @Test fun asleepOrEggDoesNotEat() {
        val p = makePet(4); p.fullness = 40
        p.toggleLight(); assertTrue(p.sleeping)
        p.feedBerry(1); p.feedCandy()
        assertEquals(40, p.fullness)
        nvs = MemStore()
        val e = newPet(); e.begin(); e.chooseStarter(4); e.fullness = 40
        e.feedBerry(0)
        assertEquals(40, e.fullness)
    }

    // ---------------------------------------------------------------- tick
    @Test fun awakeDrainsPerMinute() {
        val p = makePet(4); p.stats(100, 100, 100, 100); p.poops = 0
        rng.forced = 99
        advance(p, 10)
        rng.forced = null
        assertEquals(80, p.fullness); assertEquals(90, p.energy); assertEquals(90, p.hygiene)
        assertEquals(90, p.joy); assertEquals(10L, p.ageMinutes); assertEquals(0, p.poops)
    }

    @Test fun barsNeverBelowZero() {
        val p = makePet(4); p.stats(5, 3, 2, 1)
        advance(p, 30)
        assertEquals(0, p.fullness); assertEquals(0, p.joy); assertEquals(0, p.energy); assertEquals(0, p.hygiene)
    }

    @Test fun sleepRestoresEnergyWithFloors() {
        val p = makePet(4); p.stats(100, 100, 10, 100)
        p.toggleLight()
        advance(p, 20)
        assertEquals(100, p.energy); assertTrue(p.fullness > 80)
        advance(p, 2000)
        assertTrue(p.fullness >= 30); assertTrue(p.joy >= 35); assertTrue(p.hygiene >= 45)
        assertEquals(0, p.careMistakes)
    }

    @Test fun weightBurnsOff() {
        val p = makePet(4); p.weight = 30
        advance(p, 30)
        assertEquals(20, p.weight)
    }

    @Test fun slipUpCountsOncePerHour() {
        val p = makePet(4); p.stats(0, 0, 0, 0)
        advance(p, 1); assertEquals(1, p.careMistakes)
        advance(p, 50); assertEquals(1, p.careMistakes)
        advance(p, 11); assertEquals(2, p.careMistakes)
    }

    @Test fun slipUpCoolsBondGently() {
        val p = makePet(4); p.bond = 50; p.stats(0, 0, 0, 0)
        advance(p, 1); assertEquals(49, p.bond)
        p.bond = 1
        advance(p, 61); assertEquals(1, p.bond)
    }

    @Test fun twelveHoursOfGoodCareForgesDefense() {
        val p = makePet(4)
        assertEquals(0, p.trDef)
        repeat(720) { p.stats(100, 100, 100, 100); advance(p, 1) }
        assertEquals(1, p.trDef)
    }

    // ---------------------------------------------------------------- level
    @Test fun oneLevelPerHour() {
        val p = makePet(4)
        assertEquals(1, p.level())
        p.ageMinutes = 59; assertEquals(1, p.level())
        p.ageMinutes = 60; assertEquals(2, p.level())
        p.ageMinutes = 24 * 60; assertEquals(25, p.level())
    }

    @Test fun levelDoesNotOverflow() {
        val p = makePet(4)
        p.ageMinutes = 254L * 60
        val before = p.level(); assertEquals(255, before)
        p.ageMinutes = 255L * 60
        assertTrue(p.level() >= before)
    }

    // ---------------------------------------------------------------- evolve
    @Test fun evolveNeedsLevelAndCare() {
        val p = makePet(4)
        p.ageMinutes = 14L * 60; assertFalse(p.canEvolveNow())
        p.ageMinutes = 15L * 60; assertTrue(p.canEvolveNow())
        p.fullness = 39; assertFalse(p.canEvolveNow())
        p.fullness = 40; assertTrue(p.canEvolveNow())
    }

    @Test fun eachSlipUpDelaysOneLevel() {
        val p = makePet(4)
        p.ageMinutes = 15L * 60; p.careMistakes = 1; assertFalse(p.canEvolveNow())
        p.ageMinutes = 16L * 60; assertTrue(p.canEvolveNow())
    }

    @Test fun manySlipUpsNeverAdvanceEvolution() {
        val p = makePet(4)
        p.careMistakes = 250; p.ageMinutes = 9L * 60
        assertFalse(p.canEvolveNow())
    }

    @Test fun noEvolveAsleepEggOrCeremony() {
        val p = makePet(4); p.ageMinutes = 20L * 60
        assertTrue(p.canEvolveNow())
        p.toggleLight(); assertFalse(p.canEvolveNow())
        p.toggleLight(); p.startFarewell(); assertFalse(p.canEvolveNow())
        nvs = MemStore()
        val e = newPet(); e.begin(); assertFalse(e.canEvolveNow())
    }

    @Test fun evolveTransformsRegistersAndAnimates() {
        val p = makePet(4); p.ageMinutes = 20L * 60
        p.evolve()
        assertEquals(5, p.speciesId); assertEquals(4, p.prevSpeciesId)
        assertTrue(p.isRegistered(5)); assertTrue(p.evolving()); assertTrue(p.evolveT() in 0f..1f)
        now += EVOLVE_ANIM_MS + 1
        assertFalse(p.evolving())
    }

    @Test fun finalFormDoesNotEvolve() {
        val p = makePet(6); p.ageMinutes = 200L * 60
        assertFalse(p.canEvolveNow()); p.evolve(); assertEquals(6, p.speciesId)
    }

    @Test fun eeveeBranches() {
        for (seed in 1..12) {
            rng.seed(seed)
            val p = makePet(DEX_EEVEE); p.ageMinutes = 40L * 60
            assertTrue(p.canEvolveNow())
            p.evolve()
            assertTrue(p.speciesId in 134..136); assertTrue(p.isRegistered(p.speciesId))
        }
    }

    @Test fun declineEvolvePostponesButton() {
        val p = makePet(4); p.ageMinutes = 15L * 60
        assertTrue(p.wantEvolveButton())
        p.declineEvolve()
        assertFalse(p.wantEvolveButton()); assertTrue(p.canEvolveNow())
        p.ageMinutes = 16L * 60; assertTrue(p.wantEvolveButton())
    }

    // ---------------------------------------------------------------- stats
    @Test fun statFormula() {
        val p = makePet(4)
        p.geneAtk = 100; p.geneDef = 100; p.geneSpe = 100
        p.trAtk = 0; p.trDef = 0; p.trSpe = 0; p.ageMinutes = 0
        assertEquals(52 + 1, p.atkStat()); assertEquals(43 + 1, p.defStat()); assertEquals(65 + 1, p.speStat())
        p.ageMinutes = 9L * 60; p.trAtk = 20
        assertEquals(52 + 10 + 20, p.atkStat())
        p.geneAtk = 110
        assertEquals(52 * 110 / 100 + 10 + 20, p.atkStat())
    }

    @Test fun eggHasNoStats() {
        val p = newPet(); p.begin()
        assertEquals(0, p.atkStat()); assertEquals(0, p.defStat()); assertEquals(0, p.speStat())
    }

    // ---------------------------------------------------------------- train / play
    @Test fun bagGivesOnePointPer4HitsCapped() {
        val p = makePet(4)
        assertEquals(0, p.trainStrength(0))
        assertEquals(10, p.trainStrength(40)); assertEquals(10, p.trAtk)
        assertEquals(18, p.trainStrength(1000)); assertEquals(1000, p.strHi)
    }

    @Test fun bagReportsRealGain() {
        val p = makePet(4); p.trAtk = 95
        val before = p.trAtk
        assertEquals(p.trainStrength(72), p.trAtk - before)
    }

    @Test fun trainingCapsAt100() {
        val p = makePet(4)
        repeat(20) { p.trainStrength(80) }
        assertEquals(100, p.trAtk)
    }

    @Test fun bagTiresAndBurns() {
        val p = makePet(4); p.weight = 40; p.energy = 80; p.fullness = 80
        p.trainStrength(30)
        assertEquals(68, p.energy); assertEquals(75, p.fullness); assertEquals(30, p.weight)
        p.energy = 3; p.trainStrength(30); assertEquals(3, p.energy)
    }

    @Test fun minigameTrainsSpeedAndKeepsRecord() {
        val p = makePet(4); p.joy = 10; p.weight = 50
        p.playResult(20)
        assertEquals(4, p.trSpe); assertEquals(45, p.joy); assertEquals(10, p.weight); assertEquals(20, p.gameHi)
        p.playResult(5); assertEquals(20, p.gameHi)
    }

    @Test fun playRaisesJoyAndTires() {
        val p = makePet(4); p.stats(50, 50, 50, 50)
        p.play()
        assertEquals(75, p.joy); assertEquals(40, p.energy); assertEquals(45, p.fullness); assertTrue(p.showHeart())
    }

    // ---------------------------------------------------------------- care
    @Test fun cleanRemovesPoops() {
        val p = makePet(4); p.poops = 3; p.hygiene = 10
        p.clean()
        assertEquals(0, p.poops); assertEquals(100, p.hygiene)
    }

    @Test fun pettingRaisesJoyAndBond() {
        val p = makePet(4); p.joy = 50
        p.caress()
        assertEquals(55, p.joy); assertEquals(1, p.bond); assertTrue(p.showHeart())
    }

    @Test fun bondHasDailyCap() {
        val p = makePet(4)
        repeat(50) { p.play() }
        assertEquals(20, p.bond)
    }

    @Test fun moodReflectsState() {
        val p = makePet(4); p.stats(80, 80, 80, 80)
        assertEquals(Mood.HAPPY, p.mood())
        p.joy = 20; assertEquals(Mood.SAD, p.mood())
        p.joy = 80; p.feedBerry(0); assertEquals(Mood.EATING, p.mood())
        now += EAT_ANIM_MS + 1
        p.toggleLight(); assertEquals(Mood.SLEEPING, p.mood())
    }

    // ---------------------------------------------------------------- dex
    @Test fun bitmapCovers1To151() {
        val p = makePet(4)
        p.dexReg.fill(0)
        assertEquals(0, p.registeredCount())
        for (d in 1..151) { p.reg(d); assertTrue(p.isRegistered(d)) }
        assertEquals(151, p.registeredCount())
    }

    @Test fun outOfRangeIsNotRegistered() {
        val p = makePet(4)
        p.dexReg.fill(0xFF.toByte())
        assertFalse(p.isRegistered(0)); assertFalse(p.isRegistered(-1))
        assertFalse(p.isRegistered(152)); assertFalse(p.isRegistered(32767))
        assertEquals(151, p.registeredCount())
    }

    @Test fun incompleteLineDetected() {
        val p = makePet(1)
        assertTrue(p.lineHasUnregistered(1))
        p.reg(2); p.reg(3)
        assertFalse(p.lineHasUnregistered(1))
    }

    @Test fun eeveeBranchCountsAllThree() {
        val p = makePet(DEX_EEVEE)
        assertTrue(p.lineHasUnregistered(DEX_EEVEE))
        for (d in 134..136) p.reg(d)
        assertFalse(p.lineHasUnregistered(DEX_EEVEE))
    }

    @Test fun eggRollAlwaysValid() {
        val p = makePet(4)
        for (i in 0 until 400) {
            rng.seed(i * 7919 + 1)
            val d = p.pickEggSpecies()
            assertTrue(d in 1..151); assertTrue(DexTables.RARITY[d] != R_EVO)
        }
    }

    @Test fun firstEggIsClassicStarter() {
        for (seed in 1..20) {
            rng.seed(seed); nvs = MemStore()
            val p = newPet(); p.begin()
            assertTrue(p.pickEggSpecies() in CLASSIC_DEX)
        }
    }

    @Test fun runawayCursesRarity() {
        val p = makePet(4); p.lastEnd = CER_RUNAWAY
        for (seed in 1..60) {
            rng.seed(seed)
            assertEquals(R_COMUN, DexTables.RARITY[p.pickEggSpecies()])
        }
    }

    // ---------------------------------------------------------------- streak / bonus / medals
    @Test fun firstCareOfDayCounts() {
        val p = makePet(4)
        p.setClock(100L * 86400); p.caress()
        assertEquals(1, p.streak); assertEquals(1, p.bestStreak)
        p.caress(); assertEquals(1, p.streak)
        p.setClock(101L * 86400); p.caress(); assertEquals(2, p.streak)
    }

    @Test fun missedDayResetsStreak() {
        val p = makePet(4)
        p.setClock(100L * 86400); p.caress()
        p.setClock(101L * 86400); p.caress()
        p.setClock(105L * 86400); p.caress()
        assertEquals(1, p.streak); assertEquals(2, p.bestStreak)
    }

    @Test fun noClockNoStreak() {
        val p = makePet(4); p.caress(); assertEquals(0, p.streak)
    }

    @Test fun milestonesCelebrated() {
        val p = makePet(4)
        for (d in 100L until 103L) { p.setClock(d * 86400); p.caress() }
        assertEquals(3, p.streak); assertTrue(p.showMilestone()); assertEquals(3, p.lastMilestone)
    }

    @Test fun streakAndBondImproveEgg() {
        val p = makePet(4)
        assertEquals(0, p.careBonus())
        p.streak = 30; p.bond = 100; assertEquals(14, p.careBonus())
        p.streak = 300; assertEquals(14, p.careBonus())
    }

    @Test fun level10Medal() {
        val p = makePet(4)
        assertFalse(p.hasMedal(MED_LV10))
        p.ageMinutes = 9L * 60 - 1; advance(p, 1)
        assertTrue(p.hasMedal(MED_LV10)); assertTrue(p.showMedal())
    }

    @Test fun fitMedalAtLevel5() {
        val p = makePet(4); p.weight = 0; p.ageMinutes = 4L * 60 - 1; advance(p, 1)
        assertTrue(p.hasMedal(MED_FIT)); assertEquals(1, p.totalMedals)
        val q = makePet(4); q.careMistakes = 1; q.ageMinutes = 4L * 60 - 1; advance(q, 1)
        assertFalse(q.hasMedal(MED_FIT))
    }

    @Test fun eachNewMedalAddsToTotal() {
        val p = makePet(4); p.weight = 0; p.ageMinutes = 9L * 60 - 1; advance(p, 1)
        assertTrue(p.hasMedal(MED_LV10)); assertTrue(p.hasMedal(MED_FIT)); assertEquals(2, p.totalMedals)
    }

    @Test fun finalFormAtBirth() {
        val p = makePet(143)
        assertTrue(p.hasMedal(MED_FINAL)); assertEquals(1, p.totalMedals)
    }

    @Test fun favouriteBerryMedal() {
        val p = makePet(4); p.feedBerry(1)
        assertTrue(p.berryKnown); advance(p, 1); assertTrue(p.hasMedal(MED_BERRY))
    }

    @Test fun totalAccumulatesAcrossPets() {
        val p = makePet(143)
        assertEquals(1, p.totalMedals)
        p.newEgg(); p.chooseStarter(144)
        p.eggTap(); p.eggTap(); p.eggTap()
        assertEquals(MED_FINAL, p.medals); assertEquals(2, p.totalMedals)
    }

    // ---------------------------------------------------------------- ceremonies
    @Test fun farewellOnlyFinalFormAfter3Days() {
        val p = makePet(6)
        p.ageMinutes = FAREWELL_AGE_MIN - 1; assertFalse(p.canFarewellNow())
        p.ageMinutes = FAREWELL_AGE_MIN; assertTrue(p.canFarewellNow())
        val q = makePet(4); q.ageMinutes = FAREWELL_AGE_MIN * 3; assertFalse(q.canFarewellNow())
    }

    @Test fun farewellLeavesNewEgg() {
        val p = makePet(6); p.ageMinutes = FAREWELL_AGE_MIN
        p.startFarewell()
        assertEquals(CER_FAREWELL, p.ceremony); assertTrue(p.ceremonyT() in 0f..1f)
        now += CEREMONY_MS + 1; p.update(now)
        assertTrue(p.isEgg()); assertEquals(CER_NONE, p.ceremony)
        assertEquals(CER_FAREWELL, p.lastEnd); assertEquals(0L, p.ageMinutes)
    }

    @Test fun runawayNeedsAnHourOfTotalNeglect() {
        val p = makePet(4); p.stats(0, 0, 0, 0)
        assertFalse(p.canRunawayNow())
        advance(p, RUNAWAY_TICKS - 1); assertFalse(p.canRunawayNow())
        advance(p, 1); assertTrue(p.canRunawayNow())
    }

    @Test fun oneCareSavesFromRunaway() {
        val p = makePet(4); p.dbgRunawayReady()
        assertTrue(p.canRunawayNow())
        p.feedBerry(0); advance(p, 1)
        assertFalse(p.canRunawayNow())
    }

    @Test fun noInteractionDuringCeremony() {
        val p = makePet(4); p.stats(50, 50, 50, 50); p.poops = 2
        p.startRunaway()
        p.feedBerry(0); p.feedCandy(); p.play(); p.clean(); p.caress(); p.toggleLight()
        assertEquals(50, p.fullness); assertEquals(50, p.joy); assertEquals(2, p.poops); assertFalse(p.sleeping)
    }

    @Test fun releaseMarksEnding() {
        val p = makePet(4); p.release()
        assertEquals(CER_RELEASE, p.ceremony); assertEquals(CER_RELEASE, p.lastEnd)
        now += CEREMONY_MS + 1; p.update(now)
        assertTrue(p.isEgg())
    }

    @Test fun eggCannotLeave() {
        val p = newPet(); p.begin()
        p.startFarewell(); p.release(); p.startRunaway()
        assertEquals(CER_NONE, p.ceremony)
    }

    // ---------------------------------------------------------------- offline
    @Test fun offlineTimeHasFloorOf15() {
        val p = makePet(4); p.stats(80, 80, 80, 100)
        p.setClock(1000L * 86400)
        p.syncClock(1000L * 86400 + 600 * 60)
        assertEquals(600L, p.ageMinutes)
        assertEquals(15, p.fullness); assertEquals(15, p.energy); assertEquals(15, p.joy); assertEquals(15, p.hygiene)
        assertEquals(0, p.careMistakes); assertEquals(2, p.poops)
    }

    @Test fun offlineCapsAtTwoWeeks() {
        val p = makePet(4)
        p.setClock(1000L * 86400); p.syncClock(1000L * 86400 + 90L * 86400)
        assertEquals(14L * 24 * 60, p.ageMinutes)
    }

    @Test fun underTwoMinutesDoesNothing() {
        val p = makePet(4); p.stats(80, 80, 80, 100)
        p.setClock(1000L * 86400); p.syncClock(1000L * 86400 + 90)
        assertEquals(0L, p.ageMinutes); assertEquals(80, p.fullness)
    }

    @Test fun eggHatchesWhileAway() {
        val p = makePet(4); p.newEgg()
        assertFalse(p.awaitingStarter())
        p.setClock(1000L * 86400); p.syncClock(1000L * 86400 + 600)
        assertFalse(p.isEgg()); assertTrue(p.speciesId in 1..151)
    }

    @Test fun sleepingRestsOffline() {
        val p = makePet(4); p.stats(90, 90, 20, 90); p.toggleLight()
        p.setClock(1000L * 86400); p.syncClock(1000L * 86400 + 120 * 60)
        assertEquals(100, p.energy); assertTrue(p.fullness >= 30); assertEquals(0, p.poops)
    }

    @Test fun noClockNoOffline() {
        val p = makePet(4); p.stats(80, 80, 80, 100)
        p.syncClock(0)
        assertEquals(0L, p.ageMinutes); assertEquals(80, p.fullness)
    }

    // ---------------------------------------------------------------- save
    @Test fun stateSurvivesRestart() {
        val a = makePet(25)
        a.ageMinutes = 1234; a.streak = 9; a.bestStreak = 11; a.bond = 44; a.trAtk = 17
        a.weight = 33; a.gameHi = 21
        a.rename("SPARKY")
        val b = newPet(); b.begin()
        assertEquals(25, b.speciesId); assertEquals(1234L, b.ageMinutes); assertEquals(9, b.streak)
        assertEquals(11, b.bestStreak); assertEquals(44, b.bond); assertEquals(17, b.trAtk)
        assertEquals(33, b.weight); assertEquals(21, b.gameHi); assertEquals("SPARKY", b.nick)
        assertTrue(b.isRegistered(25)); assertFalse(b.awaitingStarter())
    }

    @Test fun nicknameTrimmedTo11() {
        val p = makePet(4); p.rename("NOMBRE-LARGUISIMO-QUE-NO-CABE")
        assertEquals("NOMBRE-LARG", p.nick)
    }

    @Test fun factoryResetStartsOver() {
        val a = makePet(4); a.factoryReset()
        val b = newPet(); b.begin()
        assertTrue(b.isEgg()); assertTrue(b.awaitingStarter()); assertEquals(0, b.registeredCount())
    }

    @Test fun autosaveMarkedAndFlushed() {
        val p = makePet(4)
        assertFalse(p.pendingSave)
        advance(p, 5); assertTrue(p.pendingSave)
        p.flushSave(); assertFalse(p.pendingSave)
    }

    // ---------------------------------------------------------------- tables / text
    @Test fun tablesMatchFirmware() {
        assertEquals("CHARMANDER", DexTables.NAME[4]); assertEquals(5, DexTables.EVOLVES_TO[4])
        assertEquals(16, DexTables.EVOLVE_LEVEL[4]); assertEquals(152, DexTables.NAME.size)
        Text.lang = Text.LANG_EN
        assertEquals("POKEDEX 3/151", Text.f(S.POKEDEX_FMT, 3))
        assertEquals("*PIKACHU Lv.12", Text.f(S.NAME_FMT, "*", "PIKACHU", 12))
        Text.lang = Text.LANG_FR
        assertEquals("SALAMECHE", Text.dexName(4))
        Text.lang = Text.LANG_EN
    }
}
