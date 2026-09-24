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
                    grid
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

    /// **Las maletas, como están en el armario.**
    ///
    /// Una lista de nombres obliga a leer para elegir entre cuatro viajes que
    /// tú distingues de un vistazo por su forma y su color —que es justo para
    /// lo que les pusiste icono y color al crearlas—. La misma figura que en
    /// la balda, en rejilla.
    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: WK.Spacing.l)],
                spacing: WK.Spacing.l
            ) {
                ForEach(suitcases) { suitcase in
                    Button {
                        // Sin fechas no hay día que preguntar: entra como
                        // preparado.
                        if suitcase.tripDayCount == nil {
                            onPick(suitcase, nil)
                            dismiss()
                        } else {
                            chosen = suitcase
                        }
                    } label: {
                        VStack(spacing: WK.Spacing.xs) {
                            SuitcaseFigure(
                                symbolName: suitcase.symbolName,
                                tint: SuitcaseTint(rawValue: suitcase.colorRaw ?? ""),
                                width: 124
                            )
                            Text(suitcase.name)
                                .font(WK.Font.garmentName)
                                .foregroundStyle(WK.Palette.primaryText)
                                .lineLimit(1)
                            // Los días, en pequeño: es lo que dice si al
                            // tocarla va a preguntar algo más.
                            Text(suitcase.tripDayCount.map { "\($0) días" } ?? "Sin fechas")
                                .font(WK.Font.caption)
                                .foregroundStyle(WK.Palette.tertiaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                    }
                    .buttonStyle(WKPressStyle())
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.vertical, WK.Spacing.l)
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas)
    }
}

/// Los días de un viaje, **y el hueco de sin día**.
///
/// Sin día no es una excepción ni un caso raro: la mitad de lo que se mete en
/// una maleta se mete sin saber todavía qué día se va a llevar. Sin esa
/// opción, decidirlo era obligatorio, y lo obligatorio se contesta a boleo.
///
/// En tacos y no en renglones: un día de viaje es un número, y una lista de
/// "Día 1 / Día 2 / Día 3" obliga a leer tres palabras iguales para encontrar
/// el número que las distingue. Es el mismo taco de calendario que llevan los
/// outfits planeados, a tamaño de tocarlo.
struct SuitcaseDayList: View {
    let suitcase: Suitcase
    let onPick: (Int?) -> Void

    private var days: Int { max(1, suitcase.tripDayCount ?? 3) }

    var body: some View {
        ScrollView {
            VStack(spacing: WK.Spacing.l) {
                // Ancho entero y el primero: es la respuesta más común.
                Button { onPick(nil) } label: {
                    VStack(spacing: WK.Spacing.xs) {
                        Image(systemName: "tray")
                            .font(.title2)
                            .foregroundStyle(WK.Palette.secondaryText)
                        Text("Sin día")
                            .font(WK.Font.headline)
                            .foregroundStyle(WK.Palette.primaryText)
                        Text("Preparado en la maleta")
                            .font(WK.Font.caption)
                            .foregroundStyle(WK.Palette.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WK.Spacing.l)
                    .background(
                        WK.Palette.shelf,
                        in: .rect(cornerRadius: WK.Radius.large, style: .continuous)
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(WKPressStyle())

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: WK.Spacing.m), count: 3),
                    spacing: WK.Spacing.m
                ) {
                    ForEach(0..<days, id: \.self) { index in
                        Button { onPick(index) } label: {
                            TripDayPad(
                                index: index,
                                date: suitcase.date(forDayIndex: index)
                            )
                        }
                        .buttonStyle(WKPressStyle())
                    }
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.vertical, WK.Spacing.l)
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas)
        .navigationTitle(suitcase.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Un día del viaje, con la forma de un taco de calendario.
private struct TripDayPad: View {
    let index: Int
    let date: Date?

    var body: some View {
        VStack(spacing: 2) {
            // "DÍA" en pequeño arriba, como la banda de un taco, y el número
            // grande debajo: el número es lo que se busca.
            Text("DÍA")
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(WK.Palette.tertiaryText)
            Text("\(index + 1)")
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(WK.Palette.primaryText)
            if let date {
                Text(date.formatted(.dateTime.weekday(.abbreviated).day()))
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WK.Spacing.m)
        .background(
            WK.Palette.shelf,
            in: .rect(cornerRadius: WK.Radius.large, style: .continuous)
        )
        .contentShape(.rect)
    }
}
