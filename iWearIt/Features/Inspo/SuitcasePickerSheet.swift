import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// A qué maleta va esto, y a qué día del viaje.
///
/// ## Por qué en dos pasos y no en una lista larga
///
/// Porque son dos preguntas distintas y la segunda solo existe a veces: una
/// maleta sin fechas no tiene días que ofrecer. Con todo mezclado en una lista
/// —"Lisboa · día 1", "Lisboa · día 2"…— tres viajes de una semana son
/// veintiún renglones para elegir una cosa.
///
/// Primero el viaje; después, **si lo tiene**, el día. Sin fechas se resuelve
/// en un toque.
struct SuitcasePickerSheet: View {
    /// La maleta elegida y el día del viaje, o `nil` para dejarlo preparado
    /// sin día.
    let onPick: (Suitcase, Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Suitcase.createdAt, order: .reverse) private var suitcases: [Suitcase]
    @State private var chosen: Suitcase?

    var body: some View {
        NavigationStack {
            Group {
                if suitcases.isEmpty {
                    ContentUnavailableView(
                        "Todavía no hay maletas",
                        systemImage: "suitcase",
                        description: Text("Créala desde el armario y este conjunto tendrá dónde ir.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("¿A qué maleta?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(WK.Palette.primaryText)
                }
            }
            .navigationDestination(item: $chosen) { suitcase in
                SuitcaseDayList(suitcase: suitcase) { index in
                    onPick(suitcase, index)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var list: some View {
        List(suitcases) { suitcase in
            Button {
                // Sin fechas no hay día que preguntar: entra como preparado.
                if suitcase.tripDayCount == nil {
                    onPick(suitcase, nil)
                    dismiss()
                } else {
                    chosen = suitcase
                }
            } label: {
                HStack(spacing: WK.Spacing.m) {
                    Text(suitcase.name)
                        .font(WK.Font.rowTitle)
                        .foregroundStyle(WK.Palette.primaryText)
                    Spacer(minLength: 0)
                    if let days = suitcase.tripDayCount {
                        Text("\(days) días")
                            .font(WK.Font.caption)
                            .foregroundStyle(WK.Palette.secondaryText)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(WK.Palette.tertiaryText)
                    }
                }
            }
        }
    }
}

/// Los días de un viaje, **y el hueco de sin día**.
///
/// Sin día no es una excepción ni un caso raro: la mitad de lo que se mete en
/// una maleta se mete sin saber todavía qué día se va a llevar. Sin esa
/// opción, decidirlo era obligatorio, y lo obligatorio se contesta a boleo.
struct SuitcaseDayList: View {
    let suitcase: Suitcase
    let onPick: (Int?) -> Void

    var body: some View {
        List {
            Section {
                Button { onPick(nil) } label: {
                    HStack {
                        Text("Sin día")
                            .foregroundStyle(WK.Palette.primaryText)
                        Spacer()
                        Text("Preparado")
                            .font(WK.Font.caption)
                            .foregroundStyle(WK.Palette.secondaryText)
                    }
                }
            }

            Section {
                ForEach(0..<max(1, suitcase.tripDayCount ?? 3), id: \.self) { index in
                    Button { onPick(index) } label: {
                        HStack {
                            Text("Día \(index + 1)")
                                .foregroundStyle(WK.Palette.primaryText)
                            Spacer()
                            if let date = suitcase.date(forDayIndex: index) {
                                Text(date.formatted(.dateTime.weekday(.abbreviated).day().month()))
                                    .font(WK.Font.caption)
                                    .foregroundStyle(WK.Palette.secondaryText)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(suitcase.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
