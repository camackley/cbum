import Foundation

// Computación de recuperación (§R2) COMPARTIDA por el mock y el fallback local del
// ViewModel — MISMO algoritmo que el backend (recovery.ts) → la app y `get_recovery`
// del coach dan iguales números. `seriesForType` devuelve la serie {date,value} de un
// tipo (ya sin borrados, date ≤ hoy), ordenada ascendente por fecha.
enum RecoveryCompute {
    static func build(date: String, needHours: Double,
                      seriesForType: (String) -> [FormulasKit.DatedValue]) -> Recovery {
        func valueOn(_ rows: [FormulasKit.DatedValue]) -> Double? {
            var v: Double? = nil; for r in rows where r.date == date { v = r.value }; return v
        }

        let sleepRows = seriesForType("sleep_hours"), inbedRows = seriesForType("sleep_inbed_hours")
        let deepRows = seriesForType("sleep_deep_hours"), remRows = seriesForType("sleep_rem_hours")
        let coreRows = seriesForType("sleep_core_hours"), awakeRows = seriesForType("sleep_awake_hours")
        let midRows = seriesForType("sleep_midpoint_hour")
        let rhrRows = seriesForType("resting_hr"), hrvRows = seriesForType("hrv_ms")

        // Sueño
        let sleepHours = valueOn(sleepRows), inbed = valueOn(inbedRows), midpoint = valueOn(midRows)
        let midBaseline = FormulasKit.baseline28(midRows, endExclusive: date)
        let midpointDriftHours: Double? = (midpoint != nil && midBaseline != nil)
            ? FormulasKit.midpointDrift(todayMidpoint: midpoint!, baselineMidpoint: midBaseline!.value) : nil
        let sevenStart = FormulasKit.addDays(to: date, days: -6) ?? date
        let last7 = sleepRows.filter { $0.date >= sevenStart && $0.date <= date }.map { $0.value }
        let avg7 = last7.isEmpty ? nil : FormulasKit.round1(last7.reduce(0, +) / Double(last7.count))
        let sSt: FormulasKit.SleepStatus = sleepHours == nil ? .noData : FormulasKit.sleepStatus(hours: sleepHours!, needHours: needHours)
        let sleep = Recovery.Sleep(
            hours: sleepHours, inbed_hours: inbed,
            efficiency: (sleepHours != nil && inbed != nil && inbed! > 0) ? round3(sleepHours! / inbed!) : nil,
            deep_hours: valueOn(deepRows), rem_hours: valueOn(remRows), core_hours: valueOn(coreRows),
            awake_hours: valueOn(awakeRows), midpoint_hour: midpoint, midpoint_drift_hours: midpointDriftHours,
            avg_7d_hours: avg7, status: sSt.rawValue)

        // RHR
        let rhrToday = valueOn(rhrRows), rhrBase = FormulasKit.baseline28(rhrRows, endExclusive: date)
        let rhrDev: Double? = (rhrToday != nil && rhrBase != nil) ? FormulasKit.deviationPct(today: rhrToday!, baseline: rhrBase!.value) : nil
        let rhrSt: FormulasKit.RhrStatus = rhrDev == nil ? .noData : FormulasKit.rhrStatus(deviation: rhrDev!)
        let rhr = Recovery.Rhr(today: rhrToday, baseline_28d: rhrBase.map { FormulasKit.round1($0.value) },
                               deviation_pct: rhrDev, status: rhrSt.rawValue)

        // HRV
        let hrvToday = valueOn(hrvRows), hrvBase = FormulasKit.baseline28(hrvRows, endExclusive: date)
        let hrvDev: Double? = (hrvToday != nil && hrvBase != nil) ? FormulasKit.deviationPct(today: hrvToday!, baseline: hrvBase!.value) : nil
        let hrvSt: FormulasKit.HrvStatus = hrvDev == nil ? .noData : FormulasKit.hrvStatus(deviation: hrvDev!)
        let hrv = Recovery.Hrv(today_ms: hrvToday, baseline_28d_ms: hrvBase.map { FormulasKit.round1($0.value) },
                               deviation_pct: hrvDev, status: hrvSt.rawValue)

        let state = FormulasKit.recoveryState(.init(
            sleepHours: sleepHours, rhrDeviationPct: rhrDev, rhrStatus: rhrSt,
            hrvDeviationPct: hrvDev, hrvStatus: hrvSt, midpointDriftHours: midpointDriftHours))

        // data_gaps: tipos sin registro en los últimos 3 días [date-2, date].
        let gapCutoff = FormulasKit.addDays(to: date, days: -2) ?? date
        var gaps: [String] = []
        for (type, label) in [("sleep_hours", "sleep"), ("resting_hr", "rhr"), ("hrv_ms", "hrv")] {
            let last = seriesForType(type).last?.date
            let fresh = last != nil && last! >= gapCutoff
            if !fresh { gaps.append(last != nil ? "\(label) desde \(last!)" : "\(label) sin registros") }
        }

        return Recovery(date: date, sleep: sleep, rhr: rhr, hrv: hrv,
                        recovery_state: state.rawValue, data_gaps: gaps,
                        basis: "reglas R5; baselines = mediana 28d propios")
    }

    static func round3(_ x: Double) -> Double { (x * 1000).rounded() / 1000 + 0 }
}
