import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// Inspiración **con lo que te llevas**.
///
/// ## Por qué aquí y no la de siempre
///
/// Porque en un viaje la pregunta es otra. En casa tienes el armario entero y
/// lo que falta es decidir; en la maleta ya has decidido —metes ocho prendas—
/// y lo que falta es sacarles partido: cuántos conjuntos distintos salen de
/// eso, y si con una camisa más salen cuatro más.
///
/// Así que el estilista trabaja **solo con lo que hay en el equipaje**, y
/// ponerle fecha a un conjunto es ponerlo en un día del viaje, no en el
/// calendario de casa. El corazón sí guarda fuera: un conjunto que te gusta te
/// gusta también cuando vuelves.
struct SuitcaseInspoTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    let suitcase: Suitcase
    /// Cuánto hay que dejar libre arriba y abajo: lo pone la pantalla, que es
    /// la que sabe dónde está la barra de la maleta.
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    @Query(FetchDescriptor<Garment>.visibleGarments())
    private var garments: [Garment]

    @State private var feed: InspoFeed?
    @State private var swipe = InspoSwipe()
    @State private var saved: Set<UUID> = []
    @State private var datingLook: StylistLook?
    @State private var editingOutfit: Outfit?
    @State private var scrolled: UUID?
    @State private var pageHeight: CGFloat = 0
    @State private var pageWidth: CGFloat = 0
    /// Si el estilista ya ha dado su primera vuelta.
    ///
    /// Sin esto la pantalla no sabía distinguir "todavía no ha montado nada"
    /// de "no hay con qué montarlo", y las dos se veían igual: una rueda
    /// girando para siempre.
    @State private var hasRun = false
    /// Si hay una tanda montándose ahora mismo.
    @State private var isGenerating = false
    /// Si la maleta ya ha dado todo lo que tenía.
    @State private var isExhausted = false
    /// Cuántas tandas han entrado, para el golpecito. Ver `InspoScreen`.
    @State private var batches = 0

    /// Lo que va en la maleta: las prendas del equipaje y las que ya están
    /// puestas en algún conjunto del viaje.
    private var packed: Set<UUID> {
        var ids = Set(suitcase.packingEntries.compactMap(\.garment?.id))
        for outfit in suitcase.visibleOutfits {
            for garment in outfit.garments { ids.insert(garment.id) }
        }
        return ids
    }

    private var byID: [UUID: Garment] {
        Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var looks: [StylistLook] { feed?.looks ?? [] }

    /// **Qué da de sí lo que llevas.**
    ///
    /// Un conjunto necesita algo de arriba y algo de abajo —o un vestido, que
    /// es las dos cosas—. Con uno de cada sale **un** conjunto, y un conjunto
    /// no es inspiración: es el que ya tenías pensado. Para que vayan
    /// cambiando hace falta que haya con qué variar, y eso se multiplica, no
    /// se suma: dos y dos son cuatro conjuntos; tres y dos, seis.
    private var readiness: InspoReadiness {
        InspoReadiness(garments: packed.compactMap { byID[$0] })
    }

    /// **Lo que mide una tarjeta, medido a mano.**
    ///
    /// En la pestaña de inspiración el alto sale de `containerRelativeFrame`,
    /// que mide el contenedor del scroll. Aquí no vale: la maleta ignora el
    /// área segura, así que el contenedor es la pantalla entera y las mismas
    /// once doceavas partes salían mucho más grandes que allí. Se resta a mano
    /// lo que tapan las dos barras y se reparte igual.
    private var pageStride: CGFloat {
        max(320, pageHeight - topInset - bottomInset)
    }

    /// **El papel es el de la maleta.**
    ///
    /// Dentro de un viaje el color no es decoración: es lo que distingue esta
    /// maleta de la otra, y por eso lo llevan también sus lienzos. Los colores
    /// rotatorios de la inspiración del armario aquí sobran — dirían que cada
    /// conjunto es de un sitio distinto.
    private var suitcaseColour: Color {
        guard
            let raw = suitcase.colorRaw,
            let tint = SuitcaseTint(rawValue: raw)
        else { return WK.Palette.canvas }
        return WK.Palette.canvasTint(
            red: tint.components.red,
            green: tint.components.green,
            blue: tint.components.blue
        )
    }

    var body: some View {
        Group {
            // **Aquí sí se dice lo que falta, con todas las letras.**
            //
            // La tarjeta con brillo es de la pestaña de inspiración, donde no
            // hay nada que puedas hacer más que añadir ropa al armario. En una
            // maleta sí lo hay —meter un pantalón más— y merece el recuento
            // entero: cuántas llevas de arriba, de abajo y de calzado.
            if !readiness.canGenerate {
                SuitcaseInspoGate(readiness: readiness)
            } else if looks.isEmpty {
                // Ya ha dado la vuelta y no ha sacado nada: se dice, en vez de
                // dejar la rueda girando.
                if hasRun {
                    SuitcaseInspoGate(readiness: readiness)
                } else {
                    ProgressView()
                }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: packed) { await prepare() }
        .sheet(item: $datingLook) { look in
            SuitcaseDayPicker(suitcase: suitcase) { dayIndex in
                plan(look, on: dayIndex)
                saved.insert(look.id)
                datingLook = nil
            }
        }
        .navigationDestination(item: $editingOutfit) { outfit in
            AdvancedCanvasScreen(outfit: outfit, store: appEnvironment.imageStore, isNew: true)
        }
    }

    private var list: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(looks) { look in
                    InspoLookCard(
                        look: look,
                        garments: look.garmentIDs.compactMap { byID[$0] },
                        outfit: nil,
                        store: appEnvironment.imageStore,
                        backdrop: suitcaseColour,
                        isSaved: saved.contains(look.id),
                        // Aquí no hay corazón: el corazón es de tu armario, y
                        // esto es un viaje. El "+" lo mete en los outfits de
                        // esta maleta, y el calendario solo aparece si el
                        // viaje tiene días.
                        keep: .trip,
                        // Sin calendario aparte: ver `onSave`.
                        showsPlan: false,
                        // **El "+" pregunta el día si hay días.**
                        //
                        // Metía el conjunto en la maleta sin preguntar nada y
                        // luego no había forma de decirle cuándo: el
                        // calendario de al lado hacía eso mismo, así que eran
                        // dos botones para una decisión partida en dos. Ahora
                        // el "+" es la decisión entera —y "sin día" es una
                        // opción de la lista, no el resultado de no elegir.
                        onSave: {
                            if suitcase.tripDayCount == nil {
                                addToTrip(look)
                            } else {
                                datingLook = look
                            }
                        },
                        onPlan: { datingLook = look },
                        onRegenerate: { regenerate(look) },
                        onEdit: { edit(look) },
                        onDismiss: { withAnimation(WKAnimation.content) { feed?.dismiss(look) } },
                        onDislike: { withAnimation(WKAnimation.content) { feed?.dislike(look) } },
                        swipe: swipe
                    )
                    // **La misma medida que en la pestaña de inspiración.**
                    // La tenía calculada aparte y las tarjetas salían un pelín
                    // más grandes aquí, que es lo que se notaba al pasar de una
                    // pantalla a la otra. Ver `InspoCardSize`.
                    .modifier(
                        InspoCardSize(
                            axis: .vertical,
                            page: CGSize(width: pageWidth, height: pageStride),
                            stride: pageStride
                        )
                    )
                }


                // La misma tarjeta del final que en la pestaña: tirar de ella
                // trae otros tantos. Ver `InspoMoreCard`.
                InspoMoreCard(
                    count: InspoFeed.capacity,
                    isWorking: isGenerating,
                    isExhausted: isExhausted
                )
                .modifier(
                    InspoCardSize(
                        axis: .vertical,
                        page: CGSize(width: pageWidth, height: pageStride),
                        stride: pageStride
                    )
                )
                .id(Self.moreCardID)
                .onScrollVisibilityChange(threshold: 0.6) { isVisible in
                    guard isVisible else { return }
                    generateMore()
                }
            }
            // **Los mismos márgenes que en la pestaña.** La maleta ignora el
            // área segura, así que aquí el margen lateral se pone a mano: sin
            // él las tarjetas llegaban al borde de la pantalla y la
            // inspiración de la maleta parecía otra pantalla distinta.
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolled, anchor: .center)
        .scrollIndicators(.hidden)
        .overlay { InspoVerdictPill(swipe: swipe, keep: .trip) }
        // **Lo que da de sí la maleta, a la vista.** Con lo justo para un par
        // de conjuntos la inspiración se repite y parece rota; decir cuántos
        // salen —y qué prenda los doblaría— convierte eso en algo que puedes
        // arreglar antes de cerrar la maleta.
        .overlay(alignment: .top) {
            if !readiness.rotates {
                InspoReadinessPill(readiness: readiness)
                    .padding(.top, topInset + WK.Spacing.xs)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: batches)
        .safeAreaPadding(.top, topInset)
        .safeAreaPadding(.bottom, bottomInset)
        .onGeometryChange(for: CGSize.self) { $0.size } action: {
            pageHeight = $0.height
            pageWidth = $0.width
        }
        // Y la página, del color de siempre: el de la maleta es el de las
        // tarjetas, no el del fondo. Con el tinte detrás **y** delante, las
        // tarjetas se perdían dentro de su propio color.
        .background(WK.Palette.canvas.ignoresSafeArea())
    }

    // MARK: Acciones

    /// Monta el feed la primera vez y lo rehace si cambia lo que llevas.
    private func prepare() async {
        let made = feed ?? InspoFeed(
            container: appEnvironment.container,
            weather: appEnvironment.weather
        )
        made.restrictedTo = packed
        // Si cambia lo que llevas, vuelve a haber de dónde sacar.
        isExhausted = false
        if feed == nil {
            feed = made
            // **Primero montar, luego el tiempo.** Al revés —que es como
            // estaba— la pestaña se quedaba en la rueda hasta que contestara
            // el parte del destino, y si no había red no contestaba nunca. El
            // parte llega después y rehace la tanda él solo: ver
            // `InspoFeed.loadWeather`.
            made.start()
            hasRun = true
            await made.loadWeather()
        } else {
            made.shuffle()
            hasRun = true
        }
    }

    private static let moreCardID = UUID()

    /// **Más conjuntos, igual que en la pestaña.**
    ///
    /// Antes esto llamaba a `extend()` a pelo: si la maleta ya no daba más
    /// combinaciones distintas no pasaba nada de nada —ni tanda, ni aviso—, y
    /// tirar de la última tarjeta parecía roto. Ahora, cuando no llega nada,
    /// la tarjeta del final lo dice.
    private func generateMore() {
        guard let feed, !isGenerating else { return }
        isGenerating = true
        let before = Set(feed.looks.map(\.id))
        withAnimation(WKAnimation.content) { feed.extend() }
        let fresh = feed.looks.first { !before.contains($0.id) }

        guard let fresh else {
            withAnimation(WKAnimation.content) { isExhausted = true }
            isGenerating = false
            return
        }
        batches += 1
        // Después, no ahora: moverlo con el dedo todavía tirando de la tarjeta
        // del final se ve como un corte. Ver `InspoScreen.generateMore`.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(WKAnimation.content) { scrolled = fresh.id }
            isGenerating = false
        }
    }

    /// **Meterlo en la maleta**, que es lo que se hace con un conjunto en un
    /// viaje.
    ///
    /// Antes esto era el corazón, y guardaba fuera: en favoritos, con el resto
    /// de tu armario. Pero un conjunto montado con lo que te llevas a Lisboa
    /// no es un favorito tuyo, es un outfit **de esta maleta** —y acababa en
    /// una lista donde no pintaba nada—. Ahora entra en los outfits del viaje,
    /// como preparado; ponerle día es lo otro, y es el calendario.
    private func addToTrip(_ look: StylistLook) {
        guard materialise(look, isFavorite: false, inTrip: true) != nil else { return }
        try? modelContext.save()
        feed?.record(.packed, for: look, source: .suitcase)
        saved.insert(look.id)
    }

    /// Y la fecha es un día **de este viaje**.
    private func plan(_ look: StylistLook, on dayIndex: Int?) {
        guard let outfit = materialise(look, isFavorite: false, inTrip: true) else { return }
        // `nil` es "preparado": entra en la maleta y todavía no tiene día.
        outfit.suitcaseDayIndex = dayIndex
        try? modelContext.save()
        saved.insert(look.id)
    }

    private func edit(_ look: StylistLook) {
        guard let outfit = materialise(look, isFavorite: false, inTrip: true) else { return }
        try? modelContext.save()
        editingOutfit = outfit
    }

    private func regenerate(_ look: StylistLook) {
        guard
            let feed,
            let replacement = feed.replacement(
                for: look, excluding: Set(looks.flatMap(\.garmentIDs))
            )
        else { return }
        withAnimation(WKAnimation.content) { feed.replace(look, with: replacement) }
    }

    private func materialise(_ look: StylistLook, isFavorite: Bool, inTrip: Bool) -> Outfit? {
        let pieces = look.garmentIDs.compactMap { byID[$0] }
        guard !pieces.isEmpty else { return nil }
        let outfit = OutfitAssembly.make(
            from: pieces,
            name: look.headline,
            origin: .inspo,
            isFavorite: isFavorite,
            // Sin color propio: dentro de la maleta lo pone ella. Ver
            // `AdvancedCanvasScreen.backdropColor`.
            backdropRaw: inTrip ? nil : InspoPalette.backdrop(for: look).rawValue,
            context: modelContext,
            seed: InspoPalette.seed(for: look)
        )
        if inTrip { outfit.suitcase = suitcase }
        return outfit
    }
}

/// Qué día del viaje.
///
/// Días del viaje y no un calendario: dentro de una maleta, "el 25" no
/// significa nada hasta que sabes que es el tercer día. Con fechas puestas se
/// enseñan las dos cosas.
struct SuitcaseDayPicker: View {
    let suitcase: Suitcase
    /// El día del viaje, o `nil` para dejarlo preparado sin día.
    let onPick: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // La misma lista que al elegir maleta desde inspiración, con su
            // hueco de "sin día" delante: ver `SuitcaseDayList`.
            SuitcaseDayList(suitcase: suitcase) { index in
                onPick(index)
                dismiss()
            }
            .navigationTitle(String(localized: "common.whichDay", defaultValue: "Which day?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(WK.Palette.primaryText)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// **Lo que hace falta para que haya inspiración**, dicho con números.
///
/// No es un mínimo inventado: es el que impone montar un conjunto. Hace falta
/// algo de arriba y algo de abajo —o un vestido— y, para que las propuestas
/// vayan cambiando, más de uno de alguno de los dos.
struct InspoReadiness {
    /// Camisetas, camisas, jerséis… y los vestidos, que cuentan por arriba.
    let tops: Int
    /// Y los vestidos aparte, porque no necesitan pantalón.
    let dresses: Int
    let bottoms: Int
    let shoes: Int

    init(garments: [Garment]) {
        var tops = 0, dresses = 0, bottoms = 0, shoes = 0
        for garment in garments {
            switch garment.kind {
            case .upperBody: tops += 1
            case .wholeBody: dresses += 1; tops += 1
            case .lowerBody: bottoms += 1
            case .feet: shoes += 1
            case .outerLayer, .head, .bag, .other: break
            }
        }
        self.tops = tops
        self.dresses = dresses
        self.bottoms = bottoms
        self.shoes = shoes
    }

    /// Cuántas prendas cuentan para un conjunto.
    var counted: Int { tops + bottoms + shoes }

    /// Los de arriba que necesitan pantalón.
    private var pairables: Int { max(0, tops - dresses) }

    /// **Cuántos conjuntos distintos salen.** Arriba por abajo, más los
    /// vestidos, por el calzado que haya.
    var combinations: Int {
        let bases = pairables * bottoms + dresses
        return bases * max(1, shoes)
    }

    /// Con uno ya se puede enseñar algo.
    var canGenerate: Bool { combinations > 0 }

    /// **Y con cuatro empiezan a cambiar.** Por debajo, pasar tarjetas es ver
    /// la misma ropa recolocada, que es peor que no ofrecer nada.
    static let rotationThreshold = 4
    var rotates: Bool { combinations >= Self.rotationThreshold }

    /// Qué falta, en una frase corta. Lo primero que más multiplica.
    var missing: String {
        if tops == 0 { return String(localized: "suitcases.suitcaseinspotab.somethingForTheTopIs", defaultValue: "Something for the top is missing: a T-shirt, a shirt or a dress.") }
        if bottoms == 0, dresses == 0 { return String(localized: "suitcases.suitcaseinspotab.somethingForTheBottomIs", defaultValue: "Something for the bottom is missing: trousers, a skirt or a dress.") }
        if pairables > 0, bottoms == 1 { return String(localized: "suitcases.suitcaseinspotab.withAnotherPairOfTrousers", defaultValue: "With another pair of trousers you'd get \(String(describing: combinations * 2)).") }
        if bottoms > 0, pairables == 1 { return String(localized: "suitcases.suitcaseinspotab.withAnotherTopYouD", defaultValue: "With another top you'd get \(String(describing: combinations * 2)).") }
        if shoes == 0 { return String(localized: "suitcases.suitcaseinspotab.withSomeShoesTheOutfits", defaultValue: "With some shoes the outfits are complete.") }
        return String(localized: "suitcases.suitcaseinspotab.packOneMorePieceAnd", defaultValue: "Pack one more piece and more combinations will appear.")
    }
}

/// La puerta: **lo que falta para que esto tenga algo que enseñar**.
private struct SuitcaseInspoGate: View {
    let readiness: InspoReadiness

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: "suitcases.suitcaseinspotab.nothingToWorkWithYet", defaultValue: "Nothing to work with yet"), systemImage: "suitcase")
        } description: {
            VStack(spacing: WK.Spacing.m) {
                Text(
                    readiness.counted == 0
                        ? String(localized: "suitcases.suitcaseinspotab.putClothesInTheLuggage", defaultValue: "Put clothes in the luggage and you'll see here which outfits come out of them.")
                        : readiness.missing
                )

                // El mínimo, dicho con lo que llevas puesto al lado: así no es
                // una regla abstracta, es lo que te falta.
                HStack(spacing: WK.Spacing.l) {
                    tally(String(localized: "suitcases.suitcaseinspotab.top", defaultValue: "Top"), count: readiness.tops, needs: 2, symbol: "tshirt")
                    tally(String(localized: "suitcases.suitcaseinspotab.bottom", defaultValue: "Bottom"), count: readiness.bottoms + readiness.dresses, needs: 2, symbol: "rectangle.portrait")
                    tally(String(localized: "suitcases.suitcaseinspotab.footwear", defaultValue: "Footwear"), count: readiness.shoes, needs: 1, symbol: "shoe")
                }
                .padding(.top, WK.Spacing.xs)

                Text(String(localized: "suitcases.suitcaseinspotab.with2TopsAnd2", defaultValue: "With 2 tops and 2 bottoms they start to vary."))
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
            }
        }
    }

    private func tally(_ title: String, count: Int, needs: Int, symbol: String) -> some View {
        VStack(spacing: WK.Spacing.xs) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(count >= needs ? WK.Palette.accent : WK.Palette.secondaryText)
            Text("\(count)/\(needs)")
                .font(WK.Font.caption.weight(.semibold))
                .foregroundStyle(count >= needs ? WK.Palette.primaryText : WK.Palette.secondaryText)
                .monospacedDigit()
            Text(title)
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
        }
    }
}

/// Cuántos conjuntos salen con lo que llevas, cuando salen pocos.
private struct InspoReadinessPill: View {
    let readiness: InspoReadiness

    var body: some View {
        HStack(spacing: WK.Spacing.xs) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(WK.Palette.secondaryText)
            Text(count)
                .font(WK.Font.caption.weight(.medium))
                .foregroundStyle(WK.Palette.primaryText)
            Text("·")
                .foregroundStyle(WK.Palette.secondaryText)
            Text(readiness.missing)
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, WK.Spacing.m)
        .padding(.vertical, WK.Spacing.xs)
        .adaptiveGlass(in: .capsule)
        .fixedSize()
    }

    private var count: String {
        switch readiness.combinations {
        case 0: String(localized: "suitcases.suitcaseinspotab.noOutfits", defaultValue: "No outfits")
        case 1: String(localized: "suitcases.suitcaseinspotab.1Outfit", defaultValue: "1 outfit")
        default: String(localized: "suitcases.suitcaseinspotab.outfits", defaultValue: "\(String(describing: readiness.combinations)) outfits")
        }
    }
}
