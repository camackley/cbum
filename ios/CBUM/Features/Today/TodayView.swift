import SwiftUI

// Pantalla HOY (spec I3). Scroll de arriba a abajo: header, anillos + precisión,
// 2 stat cards (peso-tendencia, TDEE), card de sesión del día, toggle día completo.
struct TodayView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @State private var vm: TodayViewModel?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: CBSpace.s5) {
                    Color.clear.frame(height: 0).id("cb.today.top")
                    if let vm, let s = vm.summary {
                        triadaSection(vm, s)
                        precisionBar(s.precision)
                        statsSection(s)
                        sessionSection(s)
                        dayCompleteToggle(vm, s)
                        if vm.usingFallback { fallbackNote(vm) }
                    } else {
                        ProgressView().tint(CB.bone).frame(maxWidth: .infinity).padding(.top, 80)
                    }
                }
                .padding(.horizontal, CBSpace.gutterScreen)
                .padding(.bottom, CBSpace.s10)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                CBHeader(title: "Hoy", eyebrow: CBDate.shortLabel())
                    .background(CB.bgApp)
            }
            .background(CB.bgApp)
            .refreshable { await vm?.load() }
            .task {
                if vm == nil { vm = TodayViewModel(env: env) }
                await vm?.load()
            }
            // Fix: al reemplazar el loader por el contenido async, el ScrollView
            // quedaba con offset inicial que ocultaba los anillos. Anclar al top.
            .onChange(of: vm?.summary != nil) { _, loaded in
                if loaded { proxy.scrollTo("cb.today.top", anchor: .top) }
            }
        }
    }

    // MARK: HOY = tríada (I5 §2) — COMER · ENTRENAR · DORMIR + chip de recuperación.
    private func triadaSection(_ vm: TodayViewModel, _ s: SummaryToday) -> some View {
        let sleep = vm.recovery?.sleep
        let train: TodayTriad.Train? = s.session.map {
            .init(name: $0.name, isRest: $0.program_day_id == "rest",
                  completed: $0.completed_today, exerciseCount: $0.exercise_count)
        }
        return TodayTriad(
            eat: .init(kcalConsumed: s.intake.kcal, kcalTarget: s.targets.kcal),
            train: train,
            sleep: .init(hours: sleep?.hours ?? s.recovery?.sleep_hours,
                         deep: sleep?.deep_hours, rem: sleep?.rem_hours, core: sleep?.core_hours),
            recoveryState: vm.recoveryState,
            onEat: { router.tab = .nutricion },
            onTrain: { router.goToSession() },
            onSleep: { router.goToProgress("recuperacion") })
    }

    private func precisionBar(_ p: SummaryToday.Precision) -> some View {
        let low = p.weighed_pct < 0.5
        return HStack(spacing: CBSpace.s2) {
            CBIcon(name: .scale, size: 14, color: low ? CB.estimated : CB.textSecondary)
            Text("\(CBNumber.percent(p.weighed_pct)) PESADO")
                .font(CBFont.label)
                .tracking(CBFont.Size.label * CBFont.labelTrackFactor)
                .foregroundStyle(low ? CB.estimated : CB.textSecondary)
            if p.low_confidence_items > 0 {
                Text("· \(p.low_confidence_items) con baja confianza")
                    .font(CBFont.caption).foregroundStyle(CB.estimated)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CBSpace.s3).padding(.vertical, CBSpace.s2)
        .background(CB.surfaceRaised, in: RoundedRectangle(cornerRadius: CBRadius.sm))
    }

    // MARK: Stat cards
    private func statsSection(_ s: SummaryToday) -> some View {
        HStack(spacing: CBSpace.s3) {
            weightCard(s.weight)
            tdeeCard(s.tdee)
        }
    }

    private func weightCard(_ w: SummaryToday.Weight) -> some View {
        let delta: StatDelta? = w.delta_7d_kg.map { d in
            StatDelta(value: "\(CBNumber.format(abs(d), decimals: 2)) kg",
                      dir: d < 0 ? .down : (d > 0 ? .up : .flat),
                      period: "/sem", good: goalOnTrack(delta: d))
        }
        return StatCard(label: "Peso-tendencia",
                        value: w.trend_kg.map { CBNumber.format($0, decimals: 1) } ?? "—",
                        unit: "kg", delta: delta,
                        footnote: w.last_reading_kg.map { "última lectura \(CBNumber.format($0, decimals: 1)) kg" })
    }

    private func tdeeCard(_ t: SummaryToday.TDEE) -> some View {
        StatCard(label: "TDEE",
                 value: t.kcal > 0 ? CBNumber.format(t.kcal.rounded(), decimals: 0) : "—",
                 unit: "kcal",
                 calibrating: t.status == "calibrating",
                 footnote: t.status == "adaptive" ? "adaptativo" : "calibrando",
                 accent: t.status == "adaptive")
    }

    private func goalOnTrack(delta: Double) -> Bool? {
        // Sin rate objetivo en summary; heurística: perder peso (delta<0) = on-track.
        guard let rate = goalRate() else { return nil }
        if rate < 0 { return delta <= 0 }
        if rate > 0 { return delta >= 0 }
        return nil
    }
    private func goalRate() -> Double? { env.fetchGoal(key: "goal_rate_kg_per_week").flatMap { Double($0.value) } }

    // MARK: Sesión del día
    @ViewBuilder
    private func sessionSection(_ s: SummaryToday) -> some View {
        if let sess = s.session {
            if sess.program_day_id == "rest" {
                restCard
            } else if sess.completed_today {
                completedCard(sess)
            } else {
                VStack(spacing: CBSpace.s3) {
                    ExerciseDayCompact(name: sess.name, exerciseCount: sess.exercise_count)
                    CBButton(title: "Empezar entreno", style: .primary, size: .lg, icon: .dumbbell) {
                        router.goToSession(autostart: true)
                    }
                    CBButton(title: "Entreno libre", style: .secondary, size: .md) {
                        router.goToSession(free: true)
                    }
                }
            }
        }
    }

    private var restCard: some View {
        VStack(spacing: CBSpace.s2) {
            CBIcon(name: .today, size: 40, color: CB.textTertiary)
            Text("Día de descanso").cbDisplay(CBFont.Size.displaySM)
            Text("Recuperación · sin entreno programado")
                .font(CBFont.bodySM).foregroundStyle(CB.textSecondary)
        }
        .frame(maxWidth: .infinity).cbCard()
    }

    private func completedCard(_ sess: SummaryToday.Session) -> some View {
        HStack(spacing: CBSpace.s3) {
            CBIcon(name: .check, size: 28, color: CB.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(sess.name) completado").font(CBFont.bodySemibold).foregroundStyle(CB.textPrimary)
                Text("Buen trabajo hoy").font(CBFont.caption).foregroundStyle(CB.textSecondary)
            }
            Spacer()
        }
        .cbCard(stroke: CB.success)
    }

    // MARK: Toggle día completo
    private func dayCompleteToggle(_ vm: TodayViewModel, _ s: SummaryToday) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { s.logging_complete }, set: { vm.toggleDayComplete($0) })) {
                Text("Día logueado completo").font(CBFont.bodySemibold).foregroundStyle(CB.textPrimary)
            }
            .tint(CB.bone)
            Text("¿Registraste todo lo que comiste hoy? Alimenta tu TDEE adaptativo.")
                .font(CBFont.caption).foregroundStyle(CB.textSecondary)
        }
        .cbCard()
    }

    private func fallbackNote(_ vm: TodayViewModel) -> some View {
        HStack(spacing: CBSpace.s2) {
            CBIcon(name: .clock, size: 14, color: CB.textTertiary)
            Text(vm.lastKnownAt.map { "Sin conexión · datos de \(CBDate.hour(fromTs: CBDate.ts($0)))" } ?? "Sin conexión · datos locales")
                .font(CBFont.caption).foregroundStyle(CB.textTertiary)
            Spacer()
        }
    }
}

// Card compacta del día (nombre + N ejercicios) para HOY.
struct ExerciseDayCompact: View {
    let name: String
    let exerciseCount: Int
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).cbDisplay(CBFont.Size.displaySM)
                Text("\(exerciseCount) ejercicios").font(CBFont.bodyMedium).foregroundStyle(CB.textSecondary)
            }
            Spacer()
            CBIcon(name: .dumbbell, size: 32, color: CB.bone)
        }
        .cbCard()
    }
}
