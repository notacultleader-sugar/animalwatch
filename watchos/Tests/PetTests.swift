// Port of TamaPoke's test/test_pet.cpp (MIT, (c) 2026 Quique Tortosa), by way
// of the Wear OS port's PetTest.kt: the same cases, so the Swift rules are
// checked against the firmware's.
import XCTest

final class MemStore: Store {
    var m: [String: Any] = [:]
    func getInt(_ key: String, _ def: Int) -> Int { m[key] as? Int ?? def }
    func putInt(_ key: String, _ v: Int) { m[key] = v }
    func getBool(_ key: String, _ def: Bool) -> Bool { m[key] as? Bool ?? def }
    func putBool(_ key: String, _ v: Bool) { m[key] = v }
    func getString(_ key: String, _ def: String) -> String { m[key] as? String ?? def }
    func putString(_ key: String, _ v: String) { m[key] = v }
    func has(_ key: String) -> Bool { m[key] != nil }
    func clear() { m.removeAll() }
    func flush() {}
}

/// Arduino random() shim: seedable (SplitMix64), and can be forced to a fixed value.
final class TestRandom: Rng {
    private var state: UInt64 = 1
    var forced: Int?
    func seed(_ s: Int) { state = UInt64(truncatingIfNeeded: s) &* 0x9E37_79B9_7F4A_7C15 | 1 }
    private func nextU64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    func next(_ n: Int) -> Int {
        if let f = forced { return min(f, n - 1) }
        return n <= 1 ? 0 : Int(nextU64() % UInt64(n))
    }
}

final class PetTests: XCTestCase {
    private var now = 0
    private var nvs = MemStore()
    private let rng = TestRandom()

    private func newPet() -> Pet { Pet(prefs: nvs, rng: rng, millis: { [unowned self] in self.now }) }

    override func setUp() {
        nvs = MemStore()
        now = 0
        rng.forced = nil
        rng.seed(1)
    }

    private func advance(_ p: Pet, _ minutes: Int) {
        for _ in 0..<minutes {
            now += PET_TICK_MS
            p.update(now)
        }
    }

    /// Freshly hatched pet of the given species, on a clean store.
    private func makePet(_ dex: Int) -> Pet {
        nvs = MemStore()
        now = 0
        let p = newPet()
        p.begin()
        if p.awaitingStarter() { p.chooseStarter(dex) }
        p.eggTap(); p.eggTap(); p.eggTap()
        return p
    }

    private func stats(_ p: Pet, _ f: Int, _ j: Int, _ e: Int, _ h: Int) {
        p.fullness = f; p.joy = j; p.energy = e; p.hygiene = h
    }

    private func reg(_ p: Pet, _ d: Int) { p.dexReg[(d - 1) >> 3] |= UInt8(1 << ((d - 1) & 7)) }

    // ---------------------------------------------------------------- egg
    func testFirstGameAsksForStarter() {
        let p = newPet(); p.begin()
        XCTAssertTrue(p.isEgg()); XCTAssertTrue(p.awaitingStarter())
        XCTAssertEqual(0, p.eggCracks()); XCTAssertEqual(0, p.registeredCount()); XCTAssertEqual(0, p.ageMinutes)
    }

    func testEggDoesNotHatchWhileChoosingStarter() {
        let p = newPet(); p.begin()
        advance(p, 600)
        XCTAssertTrue(p.isEgg()); XCTAssertEqual(0, p.ageMinutes)
        p.chooseStarter(7)
        advance(p, 3)
        XCTAssertFalse(p.isEgg()); XCTAssertEqual(7, p.speciesId)
    }

    func testEggHatchesAfter3Minutes() {
        let p = newPet(); p.begin(); p.chooseStarter(1)
        advance(p, 2); XCTAssertTrue(p.isEgg())
        advance(p, 1); XCTAssertFalse(p.isEgg()); XCTAssertEqual(1, p.speciesId)
    }

    func testThreeTapsHatch() {
        let p = newPet(); p.begin(); p.chooseStarter(4)
        p.eggTap(); XCTAssertEqual(1, p.eggCracks()); XCTAssertTrue(p.isEgg())
        p.eggTap(); XCTAssertEqual(2, p.eggCracks()); XCTAssertTrue(p.isEgg())
        p.eggTap(); XCTAssertFalse(p.isEgg()); XCTAssertEqual(4, p.speciesId)
    }

    func testHatchRollsGenesAndResetsIndividual() {
        let p = makePet(4)
        XCTAssertTrue((90...110).contains(p.geneAtk)); XCTAssertTrue((90...110).contains(p.geneDef))
        XCTAssertTrue((90...110).contains(p.geneSpe))
        XCTAssertEqual(0, p.trAtk); XCTAssertEqual(0, p.trDef); XCTAssertEqual(0, p.trSpe)
        XCTAssertEqual(0, p.bond); XCTAssertFalse(p.berryKnown); XCTAssertEqual("", p.nick)
        XCTAssertTrue(p.isRegistered(4)); XCTAssertEqual(1, p.registeredCount())
    }

    func testTappingAfterHatchDoesNothing() {
        let p = makePet(4)
        let c = p.eggCracks(); p.eggTap()
        XCTAssertEqual(c, p.eggCracks()); XCTAssertEqual(4, p.speciesId)
    }

    func testEggRarityIsValid() {
        let p = newPet(); p.begin()
        XCTAssertTrue((R_COMUN...R_LEGENDARIO).contains(p.eggRarity()))
    }

    // ---------------------------------------------------------------- feed
    func testNormalBerryAdds25CappedAt100() {
        let p = makePet(4); p.fullness = 50
        let notLoved = (p.speciesId + 1) % 3
        p.feedBerry(notLoved); XCTAssertEqual(75, p.fullness)
        p.feedBerry(notLoved); XCTAssertEqual(100, p.fullness)
    }

    func testFavouriteBerryGivesMoreAndHeart() {
        let p = makePet(4)
        XCTAssertTrue(p.lovesBerry(1)); XCTAssertFalse(p.lovesBerry(0)); XCTAssertFalse(p.lovesBerry(2))
        p.fullness = 10; p.joy = 10
        p.feedBerry(1)
        XCTAssertEqual(45, p.fullness); XCTAssertEqual(20, p.joy)
        XCTAssertTrue(p.berryKnown); XCTAssertTrue(p.showHeart()); XCTAssertTrue(p.eating())
    }

    func testCandyFattens() {
        let p = makePet(4); p.fullness = 50; p.joy = 50
        p.feedCandy()
        XCTAssertEqual(60, p.fullness); XCTAssertEqual(62, p.joy); XCTAssertEqual(12, p.weight)
    }

    func testAsleepOrEggDoesNotEat() {
        let p = makePet(4); p.fullness = 40
        p.toggleLight(); XCTAssertTrue(p.sleeping)
        p.feedBerry(1); p.feedCandy()
        XCTAssertEqual(40, p.fullness)
        nvs = MemStore()
        let e = newPet(); e.begin(); e.chooseStarter(4); e.fullness = 40
        e.feedBerry(0)
        XCTAssertEqual(40, e.fullness)
    }

    // ---------------------------------------------------------------- tick
    func testAwakeDrainsPerMinute() {
        let p = makePet(4); stats(p, 100, 100, 100, 100); p.poops = 0
        rng.forced = 99
        advance(p, 10)
        rng.forced = nil
        XCTAssertEqual(80, p.fullness); XCTAssertEqual(90, p.energy); XCTAssertEqual(90, p.hygiene)
        XCTAssertEqual(90, p.joy); XCTAssertEqual(10, p.ageMinutes); XCTAssertEqual(0, p.poops)
    }

    func testBarsNeverBelowZero() {
        let p = makePet(4); stats(p, 5, 3, 2, 1)
        advance(p, 30)
        XCTAssertEqual(0, p.fullness); XCTAssertEqual(0, p.joy); XCTAssertEqual(0, p.energy); XCTAssertEqual(0, p.hygiene)
    }

    func testSleepRestoresEnergyWithFloors() {
        let p = makePet(4); stats(p, 100, 100, 10, 100)
        p.toggleLight()
        advance(p, 20)
        XCTAssertEqual(100, p.energy); XCTAssertTrue(p.fullness > 80)
        advance(p, 2000)
        XCTAssertTrue(p.fullness >= 30); XCTAssertTrue(p.joy >= 35); XCTAssertTrue(p.hygiene >= 45)
        XCTAssertEqual(0, p.careMistakes)
    }

    func testWeightBurnsOff() {
        let p = makePet(4); p.weight = 30
        advance(p, 30)
        XCTAssertEqual(20, p.weight)
    }

    func testSlipUpCountsOncePerHour() {
        let p = makePet(4); stats(p, 0, 0, 0, 0)
        advance(p, 1); XCTAssertEqual(1, p.careMistakes)
        advance(p, 50); XCTAssertEqual(1, p.careMistakes)
        advance(p, 11); XCTAssertEqual(2, p.careMistakes)
    }

    func testSlipUpCoolsBondGently() {
        let p = makePet(4); p.bond = 50; stats(p, 0, 0, 0, 0)
        advance(p, 1); XCTAssertEqual(49, p.bond)
        p.bond = 1
        advance(p, 61); XCTAssertEqual(1, p.bond)
    }

    func testTwelveHoursOfGoodCareForgesDefense() {
        let p = makePet(4)
        XCTAssertEqual(0, p.trDef)
        for _ in 0..<720 { stats(p, 100, 100, 100, 100); advance(p, 1) }
        XCTAssertEqual(1, p.trDef)
    }

    // ---------------------------------------------------------------- level
    func testOneLevelPerHour() {
        let p = makePet(4)
        XCTAssertEqual(1, p.level())
        p.ageMinutes = 59; XCTAssertEqual(1, p.level())
        p.ageMinutes = 60; XCTAssertEqual(2, p.level())
        p.ageMinutes = 24 * 60; XCTAssertEqual(25, p.level())
    }

    func testLevelDoesNotOverflow() {
        let p = makePet(4)
        p.ageMinutes = 254 * 60
        let before = p.level(); XCTAssertEqual(255, before)
        p.ageMinutes = 255 * 60
        XCTAssertTrue(p.level() >= before)
    }

    // ---------------------------------------------------------------- evolve
    func testEvolveNeedsLevelAndCare() {
        let p = makePet(4)
        p.ageMinutes = 14 * 60; XCTAssertFalse(p.canEvolveNow())
        p.ageMinutes = 15 * 60; XCTAssertTrue(p.canEvolveNow())
        p.fullness = 39; XCTAssertFalse(p.canEvolveNow())
        p.fullness = 40; XCTAssertTrue(p.canEvolveNow())
    }

    func testEachSlipUpDelaysOneLevel() {
        let p = makePet(4)
        p.ageMinutes = 15 * 60; p.careMistakes = 1; XCTAssertFalse(p.canEvolveNow())
        p.ageMinutes = 16 * 60; XCTAssertTrue(p.canEvolveNow())
    }

    func testManySlipUpsNeverAdvanceEvolution() {
        let p = makePet(4)
        p.careMistakes = 250; p.ageMinutes = 9 * 60
        XCTAssertFalse(p.canEvolveNow())
    }

    func testNoEvolveAsleepEggOrCeremony() {
        let p = makePet(4); p.ageMinutes = 20 * 60
        XCTAssertTrue(p.canEvolveNow())
        p.toggleLight(); XCTAssertFalse(p.canEvolveNow())
        p.toggleLight(); p.startFarewell(); XCTAssertFalse(p.canEvolveNow())
        nvs = MemStore()
        let e = newPet(); e.begin(); XCTAssertFalse(e.canEvolveNow())
    }

    func testEvolveTransformsRegistersAndAnimates() {
        let p = makePet(4); p.ageMinutes = 20 * 60
        p.evolve()
        XCTAssertEqual(5, p.speciesId); XCTAssertEqual(4, p.prevSpeciesId)
        XCTAssertTrue(p.isRegistered(5)); XCTAssertTrue(p.evolving()); XCTAssertTrue((0...1).contains(p.evolveT()))
        now += EVOLVE_ANIM_MS + 1
        XCTAssertFalse(p.evolving())
    }

    func testFinalFormDoesNotEvolve() {
        let p = makePet(6); p.ageMinutes = 200 * 60
        XCTAssertFalse(p.canEvolveNow()); p.evolve(); XCTAssertEqual(6, p.speciesId)
    }

    func testEeveeBranches() {
        for seed in 1...12 {
            rng.seed(seed)
            let p = makePet(DEX_EEVEE); p.ageMinutes = 40 * 60
            XCTAssertTrue(p.canEvolveNow())
            p.evolve()
            XCTAssertTrue((134...136).contains(p.speciesId)); XCTAssertTrue(p.isRegistered(p.speciesId))
        }
    }

    func testDeclineEvolvePostponesButton() {
        let p = makePet(4); p.ageMinutes = 15 * 60
        XCTAssertTrue(p.wantEvolveButton())
        p.declineEvolve()
        XCTAssertFalse(p.wantEvolveButton()); XCTAssertTrue(p.canEvolveNow())
        p.ageMinutes = 16 * 60; XCTAssertTrue(p.wantEvolveButton())
    }

    // ---------------------------------------------------------------- stats
    func testStatFormula() {
        let p = makePet(4)
        p.geneAtk = 100; p.geneDef = 100; p.geneSpe = 100
        p.trAtk = 0; p.trDef = 0; p.trSpe = 0; p.ageMinutes = 0
        XCTAssertEqual(52 + 1, p.atkStat()); XCTAssertEqual(43 + 1, p.defStat()); XCTAssertEqual(65 + 1, p.speStat())
        p.ageMinutes = 9 * 60; p.trAtk = 20
        XCTAssertEqual(52 + 10 + 20, p.atkStat())
        p.geneAtk = 110
        XCTAssertEqual(52 * 110 / 100 + 10 + 20, p.atkStat())
    }

    func testEggHasNoStats() {
        let p = newPet(); p.begin()
        XCTAssertEqual(0, p.atkStat()); XCTAssertEqual(0, p.defStat()); XCTAssertEqual(0, p.speStat())
    }

    // ---------------------------------------------------------------- train / play
    func testBagGivesOnePointPer4HitsCapped() {
        let p = makePet(4)
        XCTAssertEqual(0, p.trainStrength(0))
        XCTAssertEqual(10, p.trainStrength(40)); XCTAssertEqual(10, p.trAtk)
        XCTAssertEqual(18, p.trainStrength(1000)); XCTAssertEqual(1000, p.strHi)
    }

    func testBagReportsRealGain() {
        let p = makePet(4); p.trAtk = 95
        let before = p.trAtk
        XCTAssertEqual(p.trainStrength(72), p.trAtk - before)
    }

    func testTrainingCapsAt100() {
        let p = makePet(4)
        for _ in 0..<20 { p.trainStrength(80) }
        XCTAssertEqual(100, p.trAtk)
    }

    func testBagTiresAndBurns() {
        let p = makePet(4); p.weight = 40; p.energy = 80; p.fullness = 80
        p.trainStrength(30)
        XCTAssertEqual(68, p.energy); XCTAssertEqual(75, p.fullness); XCTAssertEqual(30, p.weight)
        p.energy = 3; p.trainStrength(30); XCTAssertEqual(3, p.energy)
    }

    func testMinigameTrainsSpeedAndKeepsRecord() {
        let p = makePet(4); p.joy = 10; p.weight = 50
        p.playResult(20)
        XCTAssertEqual(4, p.trSpe); XCTAssertEqual(45, p.joy); XCTAssertEqual(10, p.weight); XCTAssertEqual(20, p.gameHi)
        p.playResult(5); XCTAssertEqual(20, p.gameHi)
    }

    func testPlayRaisesJoyAndTires() {
        let p = makePet(4); stats(p, 50, 50, 50, 50)
        p.play()
        XCTAssertEqual(75, p.joy); XCTAssertEqual(40, p.energy); XCTAssertEqual(45, p.fullness); XCTAssertTrue(p.showHeart())
    }

    // ---------------------------------------------------------------- care
    func testCleanRemovesPoops() {
        let p = makePet(4); p.poops = 3; p.hygiene = 10
        p.clean()
        XCTAssertEqual(0, p.poops); XCTAssertEqual(100, p.hygiene)
    }

    func testPettingRaisesJoyAndBond() {
        let p = makePet(4); p.joy = 50
        p.caress()
        XCTAssertEqual(55, p.joy); XCTAssertEqual(1, p.bond); XCTAssertTrue(p.showHeart())
    }

    func testBondHasDailyCap() {
        let p = makePet(4)
        for _ in 0..<50 { p.play() }
        XCTAssertEqual(20, p.bond)
    }

    func testMoodReflectsState() {
        let p = makePet(4); stats(p, 80, 80, 80, 80)
        XCTAssertEqual(.happy, p.mood())
        p.joy = 20; XCTAssertEqual(.sad, p.mood())
        p.joy = 80; p.feedBerry(0); XCTAssertEqual(.eating, p.mood())
        now += EAT_ANIM_MS + 1
        p.toggleLight(); XCTAssertEqual(.sleeping, p.mood())
    }

    // ---------------------------------------------------------------- dex
    func testBitmapCovers1To151() {
        let p = makePet(4)
        p.dexReg = [UInt8](repeating: 0, count: 19)
        XCTAssertEqual(0, p.registeredCount())
        for d in 1...151 { reg(p, d); XCTAssertTrue(p.isRegistered(d)) }
        XCTAssertEqual(151, p.registeredCount())
    }

    func testOutOfRangeIsNotRegistered() {
        let p = makePet(4)
        p.dexReg = [UInt8](repeating: 0xFF, count: 19)
        XCTAssertFalse(p.isRegistered(0)); XCTAssertFalse(p.isRegistered(-1))
        XCTAssertFalse(p.isRegistered(152)); XCTAssertFalse(p.isRegistered(32767))
        XCTAssertEqual(151, p.registeredCount())
    }

    func testIncompleteLineDetected() {
        let p = makePet(1)
        XCTAssertTrue(p.lineHasUnregistered(1))
        reg(p, 2); reg(p, 3)
        XCTAssertFalse(p.lineHasUnregistered(1))
    }

    func testEeveeBranchCountsAllThree() {
        let p = makePet(DEX_EEVEE)
        XCTAssertTrue(p.lineHasUnregistered(DEX_EEVEE))
        for d in 134...136 { reg(p, d) }
        XCTAssertFalse(p.lineHasUnregistered(DEX_EEVEE))
    }

    func testEggRollAlwaysValid() {
        let p = makePet(4)
        for i in 0..<400 {
            rng.seed(i * 7919 + 1)
            let d = p.pickEggSpecies()
            XCTAssertTrue((1...151).contains(d)); XCTAssertNotEqual(R_EVO, DexTables.RARITY[d])
        }
    }

    func testFirstEggIsClassicStarter() {
        for seed in 1...20 {
            rng.seed(seed); nvs = MemStore()
            let p = newPet(); p.begin()
            XCTAssertTrue(CLASSIC_DEX.contains(p.pickEggSpecies()))
        }
    }

    func testRunawayCursesRarity() {
        let p = makePet(4); p.lastEnd = CER_RUNAWAY
        for seed in 1...60 {
            rng.seed(seed)
            XCTAssertEqual(R_COMUN, DexTables.RARITY[p.pickEggSpecies()])
        }
    }

    // ---------------------------------------------------------------- streak / bonus / medals
    func testFirstCareOfDayCounts() {
        let p = makePet(4)
        p.setClock(100 * 86400); p.caress()
        XCTAssertEqual(1, p.streak); XCTAssertEqual(1, p.bestStreak)
        p.caress(); XCTAssertEqual(1, p.streak)
        p.setClock(101 * 86400); p.caress(); XCTAssertEqual(2, p.streak)
    }

    func testMissedDayResetsStreak() {
        let p = makePet(4)
        p.setClock(100 * 86400); p.caress()
        p.setClock(101 * 86400); p.caress()
        p.setClock(105 * 86400); p.caress()
        XCTAssertEqual(1, p.streak); XCTAssertEqual(2, p.bestStreak)
    }

    func testNoClockNoStreak() {
        let p = makePet(4); p.caress(); XCTAssertEqual(0, p.streak)
    }

    func testMilestonesCelebrated() {
        let p = makePet(4)
        for d in 100..<103 { p.setClock(d * 86400); p.caress() }
        XCTAssertEqual(3, p.streak); XCTAssertTrue(p.showMilestone()); XCTAssertEqual(3, p.lastMilestone)
    }

    func testStreakAndBondImproveEgg() {
        let p = makePet(4)
        XCTAssertEqual(0, p.careBonus())
        p.streak = 30; p.bond = 100; XCTAssertEqual(14, p.careBonus())
        p.streak = 300; XCTAssertEqual(14, p.careBonus())
    }

    func testLevel10Medal() {
        let p = makePet(4)
        XCTAssertFalse(p.hasMedal(MED_LV10))
        p.ageMinutes = 9 * 60 - 1; advance(p, 1)
        XCTAssertTrue(p.hasMedal(MED_LV10)); XCTAssertTrue(p.showMedal())
    }

    func testFitMedalAtLevel5() {
        let p = makePet(4); p.weight = 0; p.ageMinutes = 4 * 60 - 1; advance(p, 1)
        XCTAssertTrue(p.hasMedal(MED_FIT)); XCTAssertEqual(1, p.totalMedals)
        let q = makePet(4); q.careMistakes = 1; q.ageMinutes = 4 * 60 - 1; advance(q, 1)
        XCTAssertFalse(q.hasMedal(MED_FIT))
    }

    func testEachNewMedalAddsToTotal() {
        let p = makePet(4); p.weight = 0; p.ageMinutes = 9 * 60 - 1; advance(p, 1)
        XCTAssertTrue(p.hasMedal(MED_LV10)); XCTAssertTrue(p.hasMedal(MED_FIT)); XCTAssertEqual(2, p.totalMedals)
    }

    func testFinalFormAtBirth() {
        let p = makePet(143)
        XCTAssertTrue(p.hasMedal(MED_FINAL)); XCTAssertEqual(1, p.totalMedals)
    }

    func testFavouriteBerryMedal() {
        let p = makePet(4); p.feedBerry(1)
        XCTAssertTrue(p.berryKnown); advance(p, 1); XCTAssertTrue(p.hasMedal(MED_BERRY))
    }

    func testTotalAccumulatesAcrossPets() {
        let p = makePet(143)
        XCTAssertEqual(1, p.totalMedals)
        p.newEgg(); p.chooseStarter(144)
        p.eggTap(); p.eggTap(); p.eggTap()
        XCTAssertEqual(MED_FINAL, p.medals); XCTAssertEqual(2, p.totalMedals)
    }

    // ---------------------------------------------------------------- ceremonies
    func testFarewellOnlyFinalFormAfter3Days() {
        let p = makePet(6)
        p.ageMinutes = FAREWELL_AGE_MIN - 1; XCTAssertFalse(p.canFarewellNow())
        p.ageMinutes = FAREWELL_AGE_MIN; XCTAssertTrue(p.canFarewellNow())
        let q = makePet(4); q.ageMinutes = FAREWELL_AGE_MIN * 3; XCTAssertFalse(q.canFarewellNow())
    }

    func testFarewellLeavesNewEgg() {
        let p = makePet(6); p.ageMinutes = FAREWELL_AGE_MIN
        p.startFarewell()
        XCTAssertEqual(CER_FAREWELL, p.ceremony); XCTAssertTrue((0...1).contains(p.ceremonyT()))
        now += CEREMONY_MS + 1; p.update(now)
        XCTAssertTrue(p.isEgg()); XCTAssertEqual(CER_NONE, p.ceremony)
        XCTAssertEqual(CER_FAREWELL, p.lastEnd); XCTAssertEqual(0, p.ageMinutes)
    }

    func testRunawayNeedsAnHourOfTotalNeglect() {
        let p = makePet(4); stats(p, 0, 0, 0, 0)
        XCTAssertFalse(p.canRunawayNow())
        advance(p, RUNAWAY_TICKS - 1); XCTAssertFalse(p.canRunawayNow())
        advance(p, 1); XCTAssertTrue(p.canRunawayNow())
    }

    func testOneCareSavesFromRunaway() {
        let p = makePet(4); p.dbgRunawayReady()
        XCTAssertTrue(p.canRunawayNow())
        p.feedBerry(0); advance(p, 1)
        XCTAssertFalse(p.canRunawayNow())
    }

    func testNoInteractionDuringCeremony() {
        let p = makePet(4); stats(p, 50, 50, 50, 50); p.poops = 2
        p.startRunaway()
        p.feedBerry(0); p.feedCandy(); p.play(); p.clean(); p.caress(); p.toggleLight()
        XCTAssertEqual(50, p.fullness); XCTAssertEqual(50, p.joy); XCTAssertEqual(2, p.poops); XCTAssertFalse(p.sleeping)
    }

    func testReleaseMarksEnding() {
        let p = makePet(4); p.release()
        XCTAssertEqual(CER_RELEASE, p.ceremony); XCTAssertEqual(CER_RELEASE, p.lastEnd)
        now += CEREMONY_MS + 1; p.update(now)
        XCTAssertTrue(p.isEgg())
    }

    func testEggCannotLeave() {
        let p = newPet(); p.begin()
        p.startFarewell(); p.release(); p.startRunaway()
        XCTAssertEqual(CER_NONE, p.ceremony)
    }

    // ---------------------------------------------------------------- offline
    func testOfflineTimeHasFloorOf15() {
        let p = makePet(4); stats(p, 80, 80, 80, 100)
        p.setClock(1000 * 86400)
        p.syncClock(1000 * 86400 + 600 * 60)
        XCTAssertEqual(600, p.ageMinutes)
        XCTAssertEqual(15, p.fullness); XCTAssertEqual(15, p.energy); XCTAssertEqual(15, p.joy); XCTAssertEqual(15, p.hygiene)
        XCTAssertEqual(0, p.careMistakes); XCTAssertEqual(2, p.poops)
    }

    func testOfflineCapsAtTwoWeeks() {
        let p = makePet(4)
        p.setClock(1000 * 86400); p.syncClock(1000 * 86400 + 90 * 86400)
        XCTAssertEqual(14 * 24 * 60, p.ageMinutes)
    }

    func testUnderTwoMinutesDoesNothing() {
        let p = makePet(4); stats(p, 80, 80, 80, 100)
        p.setClock(1000 * 86400); p.syncClock(1000 * 86400 + 90)
        XCTAssertEqual(0, p.ageMinutes); XCTAssertEqual(80, p.fullness)
    }

    func testEggHatchesWhileAway() {
        let p = makePet(4); p.newEgg()
        XCTAssertFalse(p.awaitingStarter())
        p.setClock(1000 * 86400); p.syncClock(1000 * 86400 + 600)
        XCTAssertFalse(p.isEgg()); XCTAssertTrue((1...151).contains(p.speciesId))
    }

    func testSleepingRestsOffline() {
        let p = makePet(4); stats(p, 90, 90, 20, 90); p.toggleLight()
        p.setClock(1000 * 86400); p.syncClock(1000 * 86400 + 120 * 60)
        XCTAssertEqual(100, p.energy); XCTAssertTrue(p.fullness >= 30); XCTAssertEqual(0, p.poops)
    }

    func testNoClockNoOffline() {
        let p = makePet(4); stats(p, 80, 80, 80, 100)
        p.syncClock(0)
        XCTAssertEqual(0, p.ageMinutes); XCTAssertEqual(80, p.fullness)
    }

    // ---------------------------------------------------------------- save
    func testStateSurvivesRestart() {
        let a = makePet(25)
        a.ageMinutes = 1234; a.streak = 9; a.bestStreak = 11; a.bond = 44; a.trAtk = 17
        a.weight = 33; a.gameHi = 21
        a.rename("SPARKY")
        let b = newPet(); b.begin()
        XCTAssertEqual(25, b.speciesId); XCTAssertEqual(1234, b.ageMinutes); XCTAssertEqual(9, b.streak)
        XCTAssertEqual(11, b.bestStreak); XCTAssertEqual(44, b.bond); XCTAssertEqual(17, b.trAtk)
        XCTAssertEqual(33, b.weight); XCTAssertEqual(21, b.gameHi); XCTAssertEqual("SPARKY", b.nick)
        XCTAssertTrue(b.isRegistered(25)); XCTAssertFalse(b.awaitingStarter())
    }

    func testNicknameTrimmedTo11() {
        let p = makePet(4); p.rename("NOMBRE-LARGUISIMO-QUE-NO-CABE")
        XCTAssertEqual("NOMBRE-LARG", p.nick)
    }

    func testFactoryResetStartsOver() {
        let a = makePet(4); a.factoryReset()
        let b = newPet(); b.begin()
        XCTAssertTrue(b.isEgg()); XCTAssertTrue(b.awaitingStarter()); XCTAssertEqual(0, b.registeredCount())
    }

    func testAutosaveMarkedAndFlushed() {
        let p = makePet(4)
        XCTAssertFalse(p.pendingSave)
        advance(p, 5); XCTAssertTrue(p.pendingSave)
        p.flushSave(); XCTAssertFalse(p.pendingSave)
    }

    // ---------------------------------------------------------------- tables / text
    func testTablesMatchFirmware() {
        XCTAssertEqual("CHARMANDER", DexTables.NAME[4]); XCTAssertEqual(5, DexTables.EVOLVES_TO[4])
        XCTAssertEqual(16, DexTables.EVOLVE_LEVEL[4]); XCTAssertEqual(152, DexTables.NAME.count)
        I18n.lang = I18n.LANG_EN
        XCTAssertEqual("POKEDEX 3/151", I18n.f(.POKEDEX_FMT, 3))
        XCTAssertEqual("*PIKACHU Lv.12", I18n.f(.NAME_FMT, "*", "PIKACHU", 12))
        I18n.lang = I18n.LANG_FR
        XCTAssertEqual("SALAMECHE", I18n.dexName(4))
        I18n.lang = I18n.LANG_EN
    }
}
