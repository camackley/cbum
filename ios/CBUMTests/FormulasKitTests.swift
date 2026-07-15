import XCTest
@testable import CBUM

// Tests de FormulasKit contra los test vectors EXACTOS de contracts §5.
// (Verificados también de forma standalone; ver DECISIONS.md.)
final class FormulasKitTests: XCTestCase {

    // §5.1 EMA: [80.0, 81.0, —, 80.5] → [80.0, 80.1, 80.1, 80.14]
    func testEMASeries() {
        let out = FormulasKit.ema(dailyWeights: [80.0, 81.0, nil, 80.5])
        let rounded = out.map { $0.map { ($0 * 100).rounded() / 100 } }
        XCTAssertEqual(rounded, [80.0, 80.1, 80.1, 80.14])
        XCTAssertEqual(out.last!!, 80.14, accuracy: 0.0001)
    }

    // §5.3 e1RM: 100×8@2 → 133.3 ; 60×12@3 → nil
    func testE1RM() {
        XCTAssertEqual(FormulasKit.e1rm(weightKg: 100, reps: 8, rir: 2, isWarmup: false)!, 133.3, accuracy: 0.0001)
        XCTAssertNil(FormulasKit.e1rm(weightKg: 60, reps: 12, rir: 3, isWarmup: false))       // 15 > 12
        XCTAssertNil(FormulasKit.e1rm(weightKg: 100, reps: 5, rir: 0, isWarmup: true))         // warmup
        XCTAssertNotNil(FormulasKit.e1rm(weightKg: 100, reps: 10, rir: 2, isWarmup: false))    // borde 12 válido
    }

    // §5.4 sugerencia: 4×[6,8] RIR2 inc2.5 ; 4 sets 80×8@2 → 82.5 ; un set 80×7@2 → 80
    func testSuggestion() {
        let allGood = (0..<4).map { _ in FormulasKit.WorkingSet(weightKg: 80, reps: 8, rir: 2, isWarmup: false) }
        let s1 = FormulasKit.suggestWeight(lastSessionSets: allGood, prescribedSets: 4, repRangeMax: 8, targetRIR: 2, incrementKg: 2.5)
        XCTAssertEqual(s1.weightKg!, 82.5, accuracy: 0.0001)
        XCTAssertEqual(s1.reason, .doubleProgressionIncrease)

        var oneShort = allGood
        oneShort[1] = FormulasKit.WorkingSet(weightKg: 80, reps: 7, rir: 2, isWarmup: false)
        let s2 = FormulasKit.suggestWeight(lastSessionSets: oneShort, prescribedSets: 4, repRangeMax: 8, targetRIR: 2, incrementKg: 2.5)
        XCTAssertEqual(s2.weightKg!, 80, accuracy: 0.0001)
        XCTAssertEqual(s2.reason, .repeatWeight)

        // §5.4: solo 2 de 4 sets prescritos (aunque al tope) → NO subir.
        let twoOfFour = (0..<2).map { _ in FormulasKit.WorkingSet(weightKg: 80, reps: 8, rir: 2, isWarmup: false) }
        let s2b = FormulasKit.suggestWeight(lastSessionSets: twoOfFour, prescribedSets: 4, repRangeMax: 8, targetRIR: 2, incrementKg: 2.5)
        XCTAssertEqual(s2b.weightKg!, 80, accuracy: 0.0001)
        XCTAssertEqual(s2b.reason, .repeatWeight)

        let s3 = FormulasKit.suggestWeight(lastSessionSets: [], prescribedSets: 4, repRangeMax: 8, targetRIR: 2, incrementKg: 2.5)
        XCTAssertNil(s3.weightKg)
        XCTAssertEqual(s3.reason, .noHistory)
    }

    // §5.2 TDEE: avg 2500, ΔEMA -0.6/21 → 2720 ; Mifflin ; status
    func testTDEE() {
        XCTAssertEqual(FormulasKit.tdeeAdaptive(avgIntakeCompleteDays: 2500, deltaEMA: -0.6, windowDays: 21), 2720, accuracy: 0.0001)
        XCTAssertEqual(FormulasKit.mifflinStJeor(weightKg: 82, heightCm: 178, age: 30, sex: "m", activityFactor: 1.5), 2681.25, accuracy: 0.0001)
        let adaptive = FormulasKit.tdee(completeDays: 16, weighins: 19, avgIntakeCompleteDays: 2500, deltaEMA: -0.6, mifflin: 2000)
        XCTAssertEqual(adaptive.status, .adaptive)
        XCTAssertEqual(adaptive.kcal, 2720, accuracy: 0.0001)
        let calibrating = FormulasKit.tdee(completeDays: 5, weighins: 3, avgIntakeCompleteDays: 2500, deltaEMA: -0.6, mifflin: 2000)
        XCTAssertEqual(calibrating.status, .calibrating)
        XCTAssertEqual(calibrating.kcal, 2000, accuracy: 0.0001)
    }

    // §5.5 set efectivo y PR
    func testEffectiveAndPR() {
        XCTAssertTrue(FormulasKit.isEffectiveSet(rir: 4, isWarmup: false))
        XCTAssertFalse(FormulasKit.isEffectiveSet(rir: 5, isWarmup: false))
        XCTAssertFalse(FormulasKit.isEffectiveSet(rir: 0, isWarmup: true))
        XCTAssertTrue(FormulasKit.isPR(candidateE1RM: 100, previousBestE1RM: nil))
        XCTAssertTrue(FormulasKit.isPR(candidateE1RM: 101, previousBestE1RM: 100))
        XCTAssertFalse(FormulasKit.isPR(candidateE1RM: 100, previousBestE1RM: 100))
        XCTAssertFalse(FormulasKit.isPR(candidateE1RM: nil, previousBestE1RM: 50))
    }
}
