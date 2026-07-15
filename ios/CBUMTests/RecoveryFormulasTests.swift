import XCTest
@testable import CBUM

// Tests de las fórmulas de recuperación V2 contra los test vectors OBLIGATORIOS del
// delta §R5 (specs/v2/01-contracts-delta.md). Paridad EXACTA con el backend
// (test/recovery.test.ts): mismos números, incluido el vector-trampa.
final class RecoveryFormulasTests: XCTestCase {

    // n días consecutivos terminando en `end` (YYYY-MM-DD), todos con `value`.
    private func daysEnding(_ end: String, _ n: Int, _ value: Double) -> [FormulasKit.DatedValue] {
        var out: [FormulasKit.DatedValue] = []
        for i in stride(from: n - 1, through: 0, by: -1) {
            let d = FormulasKit.addDays(to: end, days: -i)!
            out.append(.init(date: d, value: value))
        }
        return out
    }

    // MARK: §R5 median
    func testMedian() {
        XCTAssertEqual(FormulasKit.median([3, 1, 2])!, 2, accuracy: 0.0001)          // impar → central
        XCTAssertEqual(FormulasKit.median([1, 2, 3, 4])!, 2.5, accuracy: 0.0001)     // par → promedio centrales
        XCTAssertNil(FormulasKit.median([]))                                          // vacío → nil
    }

    // MARK: §R5 baseline28 (ventana termina AYER, mín 14 datos)
    func testBaseline28() {
        // 13 datos consecutivos terminando ayer (2026-07-13) → nil.
        XCTAssertNil(FormulasKit.baseline28(daysEnding("2026-07-13", 13, 58), endExclusive: "2026-07-14"))
        // 14 datos → valor 58, n 14.
        let b = FormulasKit.baseline28(daysEnding("2026-07-13", 14, 58), endExclusive: "2026-07-14")
        XCTAssertNotNil(b); XCTAssertEqual(b!.value, 58, accuracy: 0.0001); XCTAssertEqual(b!.n, 14)
        // El baseline NO incluye el valor de hoy: 28×58 + hoy 70 → 58, n 28.
        let withToday = daysEnding("2026-07-13", 28, 58) + [.init(date: "2026-07-14", value: 70)]
        let b2 = FormulasKit.baseline28(withToday, endExclusive: "2026-07-14")
        XCTAssertEqual(b2!.value, 58, accuracy: 0.0001); XCTAssertEqual(b2!.n, 28)
    }

    // MARK: §R5 deviationPct + status
    func testDeviationsAndStatus() {
        let rhrDev = FormulasKit.deviationPct(today: 61, baseline: 58)
        XCTAssertEqual(rhrDev, 5.2, accuracy: 0.0001)                    // 3/58 = 5.17 → 5.2
        XCTAssertEqual(FormulasKit.rhrStatus(deviation: rhrDev), .elevated)

        let hrvDev = FormulasKit.deviationPct(today: 48, baseline: 62)
        XCTAssertEqual(hrvDev, -22.6, accuracy: 0.0001)                  // −14/62 = −22.58 → −22.6
        XCTAssertEqual(FormulasKit.hrvStatus(deviation: hrvDev), .suppressed)

        XCTAssertEqual(FormulasKit.rhrStatus(deviation: 1), .normal)
        XCTAssertEqual(FormulasKit.hrvStatus(deviation: -5), .normal)

        XCTAssertEqual(FormulasKit.sleepStatus(hours: 6.95), .belowNeed) // 6.95 < 7.0
        XCTAssertEqual(FormulasKit.sleepStatus(hours: 7.5), .ok)
        XCTAssertEqual(FormulasKit.sleepStatus(hours: 7.5, needHours: 8.0), .belowNeed) // goal configurable

        XCTAssertEqual(FormulasKit.midpointDrift(todayMidpoint: 3.4, baselineMidpoint: 2.8), 0.6, accuracy: 0.0001)
    }

    // MARK: §R5 recoveryState (reglas en orden, gana la primera)
    func testRecoveryState() {
        let none = FormulasKit.RecoveryStateInput(
            sleepHours: nil, rhrDeviationPct: nil, rhrStatus: .noData,
            hrvDeviationPct: nil, hrvStatus: .noData, midpointDriftHours: nil)

        // {sleep 5.8, rhr elevated} → low (regla 2)
        XCTAssertEqual(FormulasKit.recoveryState(.init(
            sleepHours: 5.8, rhrDeviationPct: 4, rhrStatus: .elevated,
            hrvDeviationPct: nil, hrvStatus: .noData, midpointDriftHours: nil)), .low)

        // VECTOR-TRAMPA: {sleep 6.95, rhr +5.2 elevated, hrv −22.6 suppressed} → caution
        // (NO low: 6.95 no <6.0, hrv −22.6 no ≤−25, rhr +5.2 no ≥+7 → cae en regla 3).
        XCTAssertEqual(FormulasKit.recoveryState(.init(
            sleepHours: 6.95, rhrDeviationPct: 5.2, rhrStatus: .elevated,
            hrvDeviationPct: -22.6, hrvStatus: .suppressed, midpointDriftHours: 0.6)), .caution)

        // {sleep 7.5, rhr +1, hrv −5} → good
        XCTAssertEqual(FormulasKit.recoveryState(.init(
            sleepHours: 7.5, rhrDeviationPct: 1, rhrStatus: .normal,
            hrvDeviationPct: -5, hrvStatus: .normal, midpointDriftHours: 0.3)), .good)

        // {todo null} → no_data
        XCTAssertEqual(FormulasKit.recoveryState(none), .noData)

        // {hrv −26 solo} → low (regla 2 por HRV ≤ −25%)
        XCTAssertEqual(FormulasKit.recoveryState(.init(
            sleepHours: nil, rhrDeviationPct: nil, rhrStatus: .noData,
            hrvDeviationPct: -26, hrvStatus: .suppressed, midpointDriftHours: nil)), .low)

        // {rhr +7 solo} → low (regla 2 por RHR ≥ +7%)
        XCTAssertEqual(FormulasKit.recoveryState(.init(
            sleepHours: nil, rhrDeviationPct: 7, rhrStatus: .elevated,
            hrvDeviationPct: nil, hrvStatus: .noData, midpointDriftHours: nil)), .low)

        // {midpoint_drift 1.6, resto normal} → caution (regla 3)
        XCTAssertEqual(FormulasKit.recoveryState(.init(
            sleepHours: 7.5, rhrDeviationPct: 0, rhrStatus: .normal,
            hrvDeviationPct: 0, hrvStatus: .normal, midpointDriftHours: 1.6)), .caution)
    }

    // MARK: §R2 eficiencia
    func testEfficiency() {
        XCTAssertEqual((6.95 / 7.75 * 1000).rounded() / 1000, 0.897, accuracy: 0.0001)
    }
}
