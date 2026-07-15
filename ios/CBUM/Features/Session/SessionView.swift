import SwiftUI

// Pantalla SESIÓN (spec I3). idle → active → summary.
struct SessionView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(Router.self) private var router
    @State private var vm: SessionViewModel?
    @State private var showFinishConfirm = false
    @State private var showDiscardConfirm = false
    @State private var substituteFor: Int?
    @State private var showAddExercise = false

    var body: some View {
        Group {
            if let vm {
                switch vm.phase {
                case .idle: idleView(vm)
                case .active: activeView(vm)
                case .summary: summaryView(vm)
                }
            } else { Color.clear }
        }
        .background(CB.bgApp)
        .task { await bootstrap() }
    }

    private func bootstrap() async {
        if vm == nil { vm = SessionViewModel(env: env) }
        guard let vm else { return }
        vm.resumeIfNeeded()
        if router.autostartSession && vm.phase == .idle {
            router.autostartSession = false
            await vm.start(free: false)
        } else if router.startFreeWorkout && vm.phase == .idle {
            router.startFreeWorkout = false
            await vm.start(free: true)
        }
    }

    // MARK: Idle
    private func idleView(_ vm: SessionViewModel) -> some View {
        VStack(spacing: 0) {
            CBHeader(title: "Entreno")
            ScrollView {
                VStack(spacing: CBSpace.s4) {
                    if vm.isRest {
                        VStack(spacing: CBSpace.s2) {
                            CBIcon(name: .today, size: 44, color: CB.textTertiary)
                            Text("Día de descanso").cbDisplay(CBFont.Size.displaySM)
                            Text("Hoy no toca entrenar según tu programa")
                                .font(CBFont.bodySM).foregroundStyle(CB.textSecondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).cbCard()
                        CBButton(title: "Entreno libre", style: .secondary, size: .md) {
                            Task { await vm.start(free: true) }
                        }
                    } else {
                        if !vm.dayName.isEmpty {
                            ExerciseDayCompact(name: vm.dayName, exerciseCount: vm.exercises.count)
                        }
                        CBButton(title: "Empezar entreno", style: .primary, size: .lg, icon: .dumbbell) {
                            Task { await vm.start(free: false) }
                        }
                        CBButton(title: "Entreno libre", style: .secondary, size: .md) {
                            Task { await vm.start(free: true) }
                        }
                    }
                    if let err = vm.loadError {
                        Text(err).font(CBFont.caption).foregroundStyle(CB.alert)
                    }
                }
                .padding(CBSpace.gutterScreen)
            }
        }
    }

    // MARK: Active
    private func activeView(_ vm: SessionViewModel) -> some View {
        VStack(spacing: 0) {
            sessionHeader(vm)
            ScrollView {
                LazyVStack(spacing: CBSpace.s3) {
                    ForEach(Array(vm.exercises.enumerated()), id: \.element.id) { idx, ex in
                        exerciseBlock(vm, index: idx, ex: ex)
                    }
                    if vm.programDayId == nil {
                        CBButton(title: "Agregar ejercicio", style: .secondary, size: .md, icon: .plus) {
                            showAddExercise = true
                        }
                    }
                    CBButton(title: "Finalizar entreno", style: .primary, size: .lg, icon: .check) {
                        showFinishConfirm = true
                    }
                    CBButton(title: "Descartar sesión", style: .destructive, size: .sm, fullWidth: false) {
                        showDiscardConfirm = true
                    }
                    Color.clear.frame(height: vm.restRemaining != nil ? 80 : 20)
                }
                .padding(CBSpace.gutterScreen)
            }
        }
        .overlay(alignment: .bottom) { restBar(vm) }
        .prToast(item: Binding(get: { vm.prToast }, set: { vm.prToast = $0 }))
        .confirmationDialog("¿Finalizar el entreno?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Finalizar y guardar") { vm.finish() }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("¿Descartar esta sesión?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Descartar", role: .destructive) { vm.discard() }
            Button("Cancelar", role: .cancel) {}
        }
        .sheet(item: Binding(get: { substituteFor.map { IdxWrap(id: $0) } }, set: { substituteFor = $0?.id })) { wrap in
            SubstituteSheet(options: vm.substitutionOptions(for: wrap.id)) { chosen in
                vm.substitute(exerciseIndex: wrap.id, with: chosen); substituteFor = nil
            }
        }
        .sheet(isPresented: $showAddExercise) {
            SubstituteSheet(options: env.allExercises(), title: "Agregar ejercicio") { chosen in
                vm.addExercise(chosen); showAddExercise = false
            }
        }
    }

    private func sessionHeader(_ vm: SessionViewModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.dayName.isEmpty ? "Entreno" : vm.dayName).cbDisplay(CBFont.Size.displaySM)
                HStack(spacing: 6) {
                    Circle().fill(CB.alert).frame(width: 7, height: 7)
                    Text("SESIÓN EN CURSO · \(vm.elapsedLabel)")
                        .font(CBFont.mono(11)).foregroundStyle(CB.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, CBSpace.gutterScreen).padding(.vertical, CBSpace.s3)
        .background(CB.bgApp)
    }

    @ViewBuilder
    private func exerciseBlock(_ vm: SessionViewModel, index: Int, ex: SessionExercise) -> some View {
        let isActive = index == vm.activeExerciseIndex
        VStack(alignment: .leading, spacing: CBSpace.s3) {
            Button {
                withAnimation(CBMotion.easeOut) { vm.activeExerciseIndex = isActive ? -1 : index }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name).cbDisplay(CBFont.Size.displaySM)
                        Text(scheme(ex)).font(CBFont.bodyMedium).foregroundStyle(CB.textSecondary)
                    }
                    Spacer()
                    Text("\(ex.completedSets)/\(ex.prescribedSets)").cbNumber(20, color: ex.completedSets >= ex.prescribedSets ? CB.success : CB.textTertiary)
                    CBIcon(name: isActive ? .chevronD : .chevronR, size: 20, color: CB.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isActive {
                suggestionRow(ex)
                ForEach(ex.rows) { row in
                    setRow(vm, index: index, ex: ex, row: row)
                }
                HStack(spacing: CBSpace.s3) {
                    CBButton(title: "+ Set", style: .secondary, size: .sm, fullWidth: false) { vm.addExtraSet(exerciseIndex: index) }
                    CBButton(title: "Sustituir", style: .secondary, size: .sm, iconRight: .swap, fullWidth: false) { substituteFor = index }
                }
            }
        }
        .cbCard(stroke: isActive ? CB.borderAccent : CB.borderDefault)
    }

    private func suggestionRow(_ ex: SessionExercise) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            if let kg = ex.suggestedKg {
                Text("\(fmt(kg)) kg").cbNumber(24, color: CB.bone)
                Text(reasonLabel(ex)).font(CBFont.caption).foregroundStyle(CB.textTertiary)
            } else {
                Text("Sin historial · elige peso").font(CBFont.bodySM).foregroundStyle(CB.estimated)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func setRow(_ vm: SessionViewModel, index: Int, ex: SessionExercise, row: SetRow) -> some View {
        let state: SetLoggerRow.State = row.isPR ? .pr : (row.saved ? .saved : .active)
        SetLoggerRow(
            setNumber: row.setNumber,
            isWarmup: row.isWarmup,
            weight: bindWeight(vm, index, row.id),
            reps: bindReps(vm, index, row.id),
            rir: bindRir(vm, index, row.id),
            incrementKg: ex.incrementKg,
            state: state,
            e1rm: row.e1rm,
            onSave: { vm.saveSet(exerciseIndex: index, rowId: row.id) },
            onEdit: { unsave(vm, index, row.id) },
            onToggleWarmup: { vm.toggleWarmup(exerciseIndex: index, rowId: row.id) })
    }

    @ViewBuilder
    private func restBar(_ vm: SessionViewModel) -> some View {
        if let remaining = vm.restRemaining {
            RestTimer(duration: vm.restDuration, remaining: Binding(get: { remaining }, set: { vm.restRemaining = $0 }),
                      compact: true, onAddThirty: { vm.addThirtyToRest() }, onSkip: { vm.skipRest() })
            .padding(.horizontal, CBSpace.gutterScreen)
            .padding(.bottom, CBSpace.s2)
        }
    }

    // MARK: Summary
    private func summaryView(_ vm: SessionViewModel) -> some View {
        let data = vm.summaryData()
        return VStack(spacing: 0) {
            CBHeader(title: "Resumen")
            ScrollView {
                VStack(alignment: .leading, spacing: CBSpace.s5) {
                    if !data.prs.isEmpty {
                        ForEach(Array(data.prs.enumerated()), id: \.offset) { _, pr in
                            PRToast(exercise: pr.0, detail: "e1RM \(fmt(pr.1)) kg")
                        }
                    }
                    SessionSummaryView(
                        duration: data.duration, totalSets: data.totalSets, volumeKg: data.volumeKg,
                        prCount: data.prs.count,
                        byMuscle: data.byMuscle.sorted { $0.value > $1.value }.map { ($0.key, $0.value) },
                        exercises: data.exercises.map { ($0.name, $0.sets, $0.topSet, $0.isPR) })
                    CBButton(title: "Preguntarle al coach", style: .secondary, size: .md, icon: .zap) { openCoach() }
                    CBButton(title: "Listo", style: .primary, size: .lg) {
                        vm.reset(); router.tab = .hoy
                    }
                }
                .padding(CBSpace.gutterScreen)
            }
        }
    }

    // MARK: - Bindings helpers
    private func bindWeight(_ vm: SessionViewModel, _ idx: Int, _ rowId: String) -> Binding<Double> {
        Binding(get: { row(vm, idx, rowId)?.weight ?? 0 }, set: { v in setRowField(vm, idx, rowId) { $0.weight = v } })
    }
    private func bindReps(_ vm: SessionViewModel, _ idx: Int, _ rowId: String) -> Binding<Int> {
        Binding(get: { row(vm, idx, rowId)?.reps ?? 0 }, set: { v in setRowField(vm, idx, rowId) { $0.reps = v } })
    }
    private func bindRir(_ vm: SessionViewModel, _ idx: Int, _ rowId: String) -> Binding<Int?> {
        Binding(get: { row(vm, idx, rowId)?.rir }, set: { v in setRowField(vm, idx, rowId) { $0.rir = v } })
    }
    private func row(_ vm: SessionViewModel, _ idx: Int, _ rowId: String) -> SetRow? {
        guard vm.exercises.indices.contains(idx) else { return nil }
        return vm.exercises[idx].rows.first { $0.id == rowId }
    }
    private func setRowField(_ vm: SessionViewModel, _ idx: Int, _ rowId: String, _ f: (inout SetRow) -> Void) {
        guard vm.exercises.indices.contains(idx), let ri = vm.exercises[idx].rows.firstIndex(where: { $0.id == rowId }) else { return }
        f(&vm.exercises[idx].rows[ri])
    }
    private func unsave(_ vm: SessionViewModel, _ idx: Int, _ rowId: String) {
        setRowField(vm, idx, rowId) { $0.saved = false; $0.isPR = false }
    }

    private func openCoach() {
        #if canImport(UIKit)
        if let url = URL(string: "claude://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let web = URL(string: "https://claude.ai") {
            UIApplication.shared.open(web)
        }
        #endif
    }

    private func scheme(_ ex: SessionExercise) -> String {
        let rr = ex.repRange.count >= 2 && ex.repRange[0] != ex.repRange[1] ? "\(ex.repRange[0])–\(ex.repRange[1])" : "\(ex.repMax)"
        return "\(ex.prescribedSets)×\(rr) @ RIR \(ex.targetRir)"
    }
    private func reasonLabel(_ ex: SessionExercise) -> String {
        switch ex.suggestionReason {
        case "double_progression_increase": return "subiste · \(ex.lastSessionLabel ?? "")"
        case "repeat_weight": return "repite · \(ex.lastSessionLabel ?? "")"
        default: return ex.lastSessionLabel ?? ""
        }
    }
    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}

private struct IdxWrap: Identifiable { let id: Int }

// Sheet de sustitución / agregar ejercicio.
struct SubstituteSheet: View {
    let options: [Exercise]
    var title: String = "Sustituir ejercicio"
    let onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Exercise] {
        query.isEmpty ? options : options.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered, id: \.id) { ex in
                    Button { onPick(ex) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name).font(CBFont.bodySemibold).foregroundStyle(CB.textPrimary)
                                Text("\(ex.muscleGroup.displayName) · \(ex.equipment.rawValue)")
                                    .font(CBFont.caption).foregroundStyle(CB.textSecondary)
                            }
                            Spacer()
                            CBIcon(name: .chevronR, size: 16, color: CB.textTertiary)
                        }
                    }
                    .listRowBackground(CB.surfaceCard)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CB.bgApp)
            .searchable(text: $query, prompt: "Buscar ejercicio")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
