import SwiftUI

// Vista read-only del programa activo (spec I4): días, ejercicios, prescripciones,
// start_date y qué día toca mañana. Nota "se edita con el coach".
struct ProgramView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let model = env.activeProgram(), let prog = model.program {
                    VStack(alignment: .leading, spacing: CBSpace.s5) {
                        header(model, prog)
                        ForEach(prog.days) { day in
                            dayCard(day)
                        }
                        Text("Se edita con el coach.").font(CBFont.caption).foregroundStyle(CB.textTertiary)
                    }
                    .padding(CBSpace.gutterScreen)
                } else {
                    Text("Sin programa activo").font(CBFont.body).foregroundStyle(CB.textSecondary).padding(40)
                }
            }
            .background(CB.bgApp)
            .navigationTitle("Programa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func header(_ model: ProgramModel, _ prog: ProgramJSON) -> some View {
        VStack(alignment: .leading, spacing: CBSpace.s2) {
            Text(prog.name).cbDisplay(CBFont.Size.displaySM)
            HStack {
                Text("Inicio").cbLabel(); Spacer()
                Text(model.startDate).font(CBFont.mono(12)).foregroundStyle(CB.textSecondary)
            }
            HStack {
                Text("Mañana toca").cbLabel(); Spacer()
                Text(tomorrowLabel(model, prog)).font(CBFont.bodySemibold).foregroundStyle(CB.bone)
            }
        }.cbCard()
    }

    private func dayCard(_ day: ProgramDay) -> some View {
        VStack(alignment: .leading, spacing: CBSpace.s2) {
            Text(day.name).cbDisplay(CBFont.Size.displaySM)
            ForEach(Array(day.exercises.enumerated()), id: \.offset) { _, ex in
                HStack {
                    Text(env.allExercises().first { $0.id == ex.exercise_id }?.name ?? ex.exercise_id)
                        .font(CBFont.body).foregroundStyle(CB.textPrimary)
                    Spacer()
                    Text(scheme(ex)).font(CBFont.caption).foregroundStyle(CB.textSecondary)
                }
            }
        }.cbCard()
    }

    private func scheme(_ ex: ProgramExercise) -> String {
        let rr = ex.rep_range.count >= 2 && ex.rep_range[0] != ex.rep_range[1] ? "\(ex.rep_range[0])–\(ex.rep_range[1])" : "\(ex.rep_range.last ?? 0)"
        return "\(ex.sets)×\(rr) @ RIR \(ex.target_rir)"
    }
    private func tomorrowLabel(_ model: ProgramModel, _ prog: ProgramJSON) -> String {
        guard let start = CBDate.date(fromDay: model.startDate),
              let tomorrow = Calendar.bogota.date(byAdding: .day, value: 1, to: Date()),
              let dayId = FormulasKit.scheduledDayId(schedule: prog.schedule, startDate: start, date: tomorrow) else { return "—" }
        if dayId == "rest" { return "Descanso" }
        return prog.day(id: dayId)?.name ?? dayId
    }
}
