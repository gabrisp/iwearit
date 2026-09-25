import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Crear una maleta, paso a paso.
///
/// Un formulario con todo a la vez obliga a leerlo entero antes de empezar. Por
/// pasos, cada pantalla hace una sola pregunta y el botón siempre dice qué va a
/// pasar. El chrome —salir, volver, continuar— es del contenedor y no se mueve:
/// solo cambia el medio.
struct NewSuitcaseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var flow = WKFlowStack(Step.name)
    /// El teclado del nombre: sale al llegar y se va antes de seguir.
    @FocusState private var isNameFocused: Bool
    @State private var name = ""
    @State private var hasDates = false
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(60 * 60 * 24 * 5)
    @State private var destination: GeoPlace?
    @State private var symbol: SuitcaseEmoji = .suitcase
    @State private var tint: SuitcaseTint = .sand
    @State private var isPickingPlace = false

    enum Step: Int, WKFlowStep {
        case name, place, look, dates, when
        var flowDepth: Int { rawValue }
    }

    var body: some View {
        Group {
            switch flow.step {
            case .name: nameStep
            case .place: placeStep
            case .look: lookStep
            case .dates: datesStep
            case .when: whenStep
            }
        }
        .wkDynamicSheet()
        .sheet(isPresented: $isPickingPlace) {
            PlaceSearchSheet(title: String(localized: "common.whereAreYouGoing", defaultValue: "Where are you going?")) { destination = $0 }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var nameStep: some View {
        WKFlowScreen(
            title: String(localized: "common.whereAreYouGoing", defaultValue: "Where are you going?"),
            subtitle: String(localized: "suitcases.newsuitcasesheet.weLlNameTheSuitcase", defaultValue: "We'll name the suitcase after it."),
            stepID: Step.name,
            transition: flow.transition,
            primaryTitle: String(localized: "common.next", defaultValue: "Next"),
            isPrimaryEnabled: !trimmedName.isEmpty,
            isAtRoot: flow.isAtRoot,
            onLeading: { resignFocus($isNameFocused) { dismiss() } },
            onPrimary: { resignFocus($isNameFocused) { flow.move(to: .place) } }
        ) {
            TextField(String(localized: "suitcases.newsuitcasesheet.lisbonWeekendInTheMountains", defaultValue: "Lisbon, weekend in the mountains…"), text: $name)
                .font(WK.Font.title)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .padding(WK.Spacing.m)
                .background(WK.Palette.shelf, in: .rect(cornerRadius: WK.Radius.medium, style: .continuous))
                .focused($isNameFocused)
                .wkFocusOnAppear($isNameFocused)
        }
    }

    /// El destino, en su propio paso.
    ///
    /// Se pregunta **al crear** y no después, escondido en la edición, porque
    /// es lo que hace que la maleta sepa el tiempo que va a hacer — y ese es el
    /// dato sobre el que se decide qué meter dentro. Preguntarlo cuando ya has
    /// preparado tres días llega tarde.
    private var placeStep: some View {
        WKFlowScreen(
            title: String(localized: "suitcases.newsuitcasesheet.whichPlace", defaultValue: "Which place?"),
            subtitle: String(localized: "suitcases.newsuitcasesheet.withTheDestinationSetEach", defaultValue: "With the destination set, each day of the trip brings the weather forecast."),
            stepID: Step.place,
            transition: flow.transition,
            primaryTitle: destination == nil ? String(localized: "common.notNow", defaultValue: "Not now") : String(localized: "common.next", defaultValue: "Next"),
            isAtRoot: false,
            onLeading: { flow.move(to: .name) },
            onPrimary: { flow.move(to: .look) }
        ) {
            // **El buscador aquí mismo**, dentro del paso: antes era un botón
            // que abría otra hoja con el buscador, dos pasos para lo mismo.
            // Elegir un sitio lo apunta y pasa al siguiente.
            VStack(alignment: .leading, spacing: WK.Spacing.m) {
                if let destination {
                    Label(destination.name, systemImage: "mappin.and.ellipse")
                        .font(WK.Font.rowTitle)
                        .foregroundStyle(WK.Palette.primaryText)
                        .transition(.blurReplace)
                }
                PlaceSearchPanel { place in
                    withAnimation(WKAnimation.content) { destination = place }
                    flow.move(to: .look)
                }
            }
            // Lo de antes: un botón que abría `PlaceSearchSheet`.
            // Button { isPickingPlace = true } label: {
            //     HStack(spacing: WK.Spacing.m) {
            //         Image(systemName: "mappin.and.ellipse")
            //             .foregroundStyle(WK.Palette.secondaryText)
            //         Text(destination?.name ?? String(localized: "suitcases.newsuitcasesheet.searchForACity", defaultValue: "Search for a city"))
            //             .font(WK.Font.rowTitle)
            //             .foregroundStyle(
            //                 destination == nil ? WK.Palette.secondaryText : WK.Palette.primaryText
            //             )
            //         Spacer(minLength: 0)
            //     }
            //     .padding(WK.Spacing.m)
            //     .background(WK.Palette.shelf, in: .rect(cornerRadius: WK.Radius.medium, style: .continuous))
            //     .contentShape(.rect)
            // }
            // .buttonStyle(WKPressStyle())
        }
    }

    /// Icono y color.
    ///
    /// Con varias maletas a la vez el nombre en pequeño no distingue nada a la
    /// velocidad a la que se mira una balda; la forma y el color sí.
    private var lookStep: some View {
        WKFlowScreen(
            title: String(localized: "suitcases.newsuitcasesheet.howDoYouRecogniseIt", defaultValue: "How do you recognise it?"),
            subtitle: String(localized: "suitcases.newsuitcasesheet.anIconAndAColor", defaultValue: "An icon and a color to spot it at a glance."),
            stepID: Step.look,
            transition: flow.transition,
            primaryTitle: String(localized: "common.next", defaultValue: "Next"),
            isAtRoot: false,
            onLeading: { flow.move(to: .place) },
            onPrimary: { flow.move(to: .dates) }
        ) {
            VStack(spacing: WK.Spacing.m) {
                ScrollView(.horizontal) {
                    HStack(spacing: WK.Spacing.s) {
                        ForEach(SuitcaseEmoji.allCases) { option in
                            Button {
                                withAnimation(WKAnimation.selection) { symbol = option }
                            } label: {
                                Text(option.rawValue)
                                    .font(.system(size: 26))
                                    .frame(width: 52, height: 52)
                                    .background(
                                        symbol == option ? WK.Palette.accent : WK.Palette.shelf,
                                        in: .rect(cornerRadius: WK.Radius.medium, style: .continuous)
                                    )
                                    .contentShape(.rect)
                            }
                            .buttonStyle(WKPressStyle())
                        }
                    }
                    .padding(.horizontal, WK.Spacing.screenInset)
                }
                .scrollIndicators(.hidden)
                .wkBleedingStrip()

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: WK.Spacing.s) {
                    ForEach(SuitcaseTint.allCases) { option in
                        Button {
                            withAnimation(WKAnimation.selection) { tint = option }
                        } label: {
                            Circle()
                                .fill(Color(
                                    red: option.components.red,
                                    green: option.components.green,
                                    blue: option.components.blue
                                ))
                                .frame(width: 38, height: 38)
                                .overlay(Circle().stroke(WK.Palette.accent, lineWidth: tint == option ? 3 : 0))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .contentShape(.rect)
                        }
                        .buttonStyle(WKPressStyle())
                    }
                }
            }
        }
    }

    private var datesStep: some View {
        WKFlowScreen(
            title: String(localized: "suitcases.newsuitcasesheet.doYouKnowTheDates", defaultValue: "Do you know the dates?"),
            subtitle: String(localized: "suitcases.newsuitcasesheet.withDatesYouPrepareAn", defaultValue: "With dates you prepare an outfit per day. Without them, you simply get them ready."),
            stepID: Step.dates,
            transition: flow.transition,
            primaryTitle: hasDates ? String(localized: "suitcases.newsuitcasesheet.chooseDates", defaultValue: "Choose dates") : String(localized: "suitcases.newsuitcasesheet.createSuitcase", defaultValue: "Create suitcase"),
            isAtRoot: false,
            onLeading: { flow.move(to: .look) },
            onPrimary: {
                if hasDates { flow.move(to: .when) } else { create() }
            }
        ) {
            VStack(spacing: WK.Spacing.s) {
                DateChoiceRow(title: String(localized: "suitcases.newsuitcasesheet.yesIHaveDates", defaultValue: "Yes, I have dates"), isSelected: hasDates) { hasDates = true }
                DateChoiceRow(title: String(localized: "suitcases.newsuitcasesheet.notYet", defaultValue: "Not yet"), isSelected: !hasDates) { hasDates = false }
            }
        }
    }

    private var whenStep: some View {
        WKFlowScreen(
            title: String(localized: "suitcases.newsuitcasesheet.when", defaultValue: "When?"),
            stepID: Step.when,
            transition: flow.transition,
            primaryTitle: String(localized: "suitcases.newsuitcasesheet.createSuitcase", defaultValue: "Create suitcase"),
            isAtRoot: false,
            onLeading: { flow.move(to: .dates) },
            onPrimary: { create() }
        ) {
            WKSection {
                WKRow {
                    Text(String(localized: "suitcases.newsuitcasesheet.departure", defaultValue: "Departure")).font(WK.Font.rowTitle)
                } trailing: {
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden()
                }
                WKRow(showsSeparator: false) {
                    Text(String(localized: "suitcases.newsuitcasesheet.return", defaultValue: "Return")).font(WK.Font.rowTitle)
                } trailing: {
                    DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
    }

    private func create() {
        let suitcase = Suitcase(
            name: trimmedName,
            startDate: hasDates ? startDate : nil,
            endDate: hasDates ? endDate : nil
        )
        suitcase.destination = destination
        suitcase.symbolName = symbol.rawValue
        suitcase.colorRaw = tint.rawValue
        modelContext.insert(suitcase)
        dismiss()
    }
}

private struct DateChoiceRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(WK.Font.rowTitle)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? WK.Palette.accent : WK.Palette.ink(0.22))
            }
            .padding(WK.Spacing.m)
            .background(WK.Palette.shelf, in: .rect(cornerRadius: WK.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                    .stroke(isSelected ? WK.Palette.accent : .clear, lineWidth: 2)
            )
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}
