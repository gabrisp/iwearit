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
    @State private var flow = WKFlowStack(Step.suitcase)
    @State private var chosen: Suitcase?

    enum Step: Int, WKFlowStep {
        case suitcase, day
        var flowDepth: Int { rawValue }
    }

    var body: some View {
        // **Sin pila de navegación y del alto de lo que lleva dentro.**
        //
        // Una `NavigationStack` aquí es una barra que nadie pidió para dos
        // pantallas que no son navegación, son una pregunta con una
        // repregunta. El chrome —cerrar o volver, y el título— lo pone la
        // hoja en su barra, así que no se mueve: lo único que cambia es el
        // medio, y el título se funde. Ver `WKSheetChrome`.
        Group {
            switch flow.step {
            case .suitcase:
                grid
                    .transition(flow.transition)
                    .id(Step.suitcase)
            case .day:
                Group {
                    if let chosen {
                        SuitcaseDayList(suitcase: chosen) { pick($0) }
                    }
                }
                .transition(flow.transition)
                .id(Step.day)
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        // Con muchas maletas la rejilla puede pasarse de alto: ahí, y solo
        // ahí, se desplaza. Ver `wkScrollWhenTooTall`.
        .wkScrollWhenTooTall()
        .adaptiveSafeAreaBar(edge: .top, spacing: 0) {
            WKSheetChrome(
                title: title,
                isAtRoot: flow.isAtRoot,
                onLeading: {
                    if flow.isAtRoot {
                        dismiss()
                    } else {
                        flow.move(to: .suitcase)
                    }
                }
            )
        }
        .wkDynamicSheet()
    }

    private var title: String {
        switch flow.step {
        case .suitcase: "¿A qué maleta?"
        case .day: chosen?.name ?? "¿Qué día?"
        }
    }

    private func pick(_ dayIndex: Int?) {
        guard let chosen else { return }
        onPick(chosen, dayIndex)
        dismiss()
    }

    /// **Las maletas, como están en el armario.**
    ///
    /// Una lista de nombres obliga a leer para elegir entre cuatro viajes que
    /// tú distingues de un vistazo por su forma y su color —que es justo para
    /// lo que les pusiste icono y color al crearlas—.
    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: WK.Spacing.m), count: 3),
            spacing: WK.Spacing.l
        ) {
            ForEach(suitcases) { suitcase in
                Button {
                    // Sin fechas no hay día que preguntar: entra como
                    // preparado y se cierra.
                    if suitcase.tripDayCount == nil {
                        onPick(suitcase, nil)
                        dismiss()
                    } else {
                        chosen = suitcase
                        flow.move(to: .day)
                    }
                } label: {
                    VStack(spacing: WK.Spacing.xs) {
                        SuitcaseFigure(
                            symbolName: suitcase.symbolName,
                            tint: SuitcaseTint(rawValue: suitcase.colorRaw ?? ""),
                            width: 88
                        )
                        Text(suitcase.name)
                            .font(WK.Font.garmentName)
                            .foregroundStyle(WK.Palette.primaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(WKPressStyle())
            }
        }
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
    /// Si enseña el hueco de "sin día". Apagado cuando quien la enseña ya lo
    /// ofrece por su cuenta —el flujo de elegir maleta lo lleva en su botón—,
    /// para no dar dos veces la misma salida.
    var showsNoDay = true
    let onPick: (Int?) -> Void

    private var days: Int { max(1, suitcase.tripDayCount ?? 3) }

    var body: some View {
        VStack(spacing: WK.Spacing.l) {
                if showsNoDay {
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
                }

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
        .padding(.vertical, WK.Spacing.xs)
        // **Sin alto a mano y sin scroll propio.** Tenía los dos —un tope de
        // 320 puntos y un `ScrollView` dentro—, que es pelearse con la hoja:
        // la hoja mide lo que hay para decidir cuánto abrir, y un scroll le
        // devuelve el alto que ella misma le dio. Si un viaje es tan largo que
        // no cabe, de eso se encarga `wkScrollWhenTooTall`.
        .wkScrollWhenTooTall()
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
