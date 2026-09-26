import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence
import WKServices

/// **Las primeras preguntas, como una conversación.** Snazzy escribe —letra a
/// letra—, pregunta, tú contestas, y lo dicho sube y se apaga bajo el borde de
/// arriba mientras lo nuevo aparece debajo. Sustituye a los pasos sueltos de
/// objetivo, dolores, gasto y tamaño del armario, que siguen en el código.
struct ConversationStep: View {
    let model: OnboardingModel

    /// Cada vez que se vuelve atrás, una conversación nueva desde el
    /// principio.
    @State private var run = 0
    @State private var hasProgressed = false

    /// **Atrás, dentro de la conversación, la rebobina entera**: vuelve a
    /// empezar desde el principio. Sin nada contestado todavía, atrás es
    /// atrás —a la bienvenida—.
    var body: some View {
        ConversationScript(model: model, hasProgressed: $hasProgressed)
            .id(run)
            .transition(.opacity.combined(with: AnyTransition(.blurReplace)))
            // Rebobinar entero, de antes. Ahora atrás va paso a paso: lo
            // decide `ConversationScript.stepBack`.
            // .onAppear {
            //     model.backHandler = {
            //         guard hasProgressed else { return false }
            //         withAnimation(.smooth(duration: 0.6)) { hasProgressed = false; run += 1 }
            //         return true
            //     }
            // }
            .onDisappear { model.backHandler = nil }
    }
}

/// Se apaga al irse la conversación: lo que quedara en marcha de ella no
/// debe mover el onboarding.
@MainActor
private final class RunToken {
    var isCancelled = false
}

/// La conversación en sí. Ver `ConversationStep`.
private struct ConversationScript: View {
    let model: OnboardingModel
    @Binding var hasProgressed: Bool

    /// Una pieza de la conversación.
    private enum Item: Identifiable, Equatable {
        case line(id: Int, text: String)
        case answer(id: Int, text: String)
        case progress(id: Int)
        /// Una cifra que importa, sola en su línea: en color, con brillo.
        case highlight(id: Int, text: String)
        /// "La mala noticia:" / "La buena noticia:", en su color y con brillo.
        case news(id: Int, text: String, isGood: Bool)
        /// La cifra girando como una rueda hasta pararse. Ver `NumberWheel`.
        case wheel(id: Int, value: Double, isGood: Bool)
        /// Una nota pequeña y apagada: "Una estimación…".
        case note(id: Int, text: String)
        /// **Una cifra que se elige con el deslizador**: mientras se pregunta,
        /// el número y el deslizador; al contestar, el deslizador se va y el
        /// número se queda —es la respuesta— con brillo.
        case pick(id: Int, kind: Pick)
        /// Un titular grande y sin color: "Tu ropa ya está en tus fotos".
        case heading(id: Int, text: String)
        /// Un punto con su icono pequeño encima.
        case point(id: Int, symbol: String, title: String, detail: String)
        /// **El permiso de fotos entero, en un solo bloque**: el titular, la
        /// explicación y los tres puntos en tarjetas, apareciendo uno tras
        /// otro. En filas sueltas, la última se centraba y el titular se iba
        /// por arriba.
        case photos(id: Int)
        /// **Las opciones de una pregunta, en la conversación**: al contestar,
        /// las no elegidas se van y la elegida se queda —sin icono ni
        /// cristal— como la respuesta. Ver `optionsRow`.
        case options(id: Int, kind: Choice)
        /// "Nuestros usuarios sacan más de 1.000 combinaciones…", con las
        /// prendas desfilando y un outfit montándose. Ver `ProofVisual`.
        case proof(id: Int)
        /// **El escaneo explicado por pasos**: 0 tus fotos, 1 cómo se lee un
        /// outfit, 2 cada prenda a su balda. Ver `ExplainBlock`.
        case explain(id: Int, page: Int)
        /// **La tarjeta del final**: prendas, tu estilo y tus colores. Ver
        /// `ClosetStatsCard`.
        case stats(id: Int)
        /// El contador del escaneo, subiendo según salen prendas.
        case counter(id: Int)
        /// "Buscando tu ropa", que al terminar se transforma en "Hemos
        /// encontrado", en el mismo sitio.
        case scanTitle(id: Int)
        /// Una cantidad en la rueda: prendas, combinaciones.
        case count(id: Int, value: Double, tone: OnboardingTone)

        var id: Int {
            switch self {
            case let .line(id, _), let .answer(id, _), let .progress(id), let .highlight(id, _),
                 let .news(id, _, _), let .wheel(id, _, _), let .note(id, _), let .pick(id, _),
                 let .heading(id, _), let .point(id, _, _, _), let .photos(id),
                 let .counter(id), let .count(id, _, _), let .options(id, _),
                 let .scanTitle(id), let .proof(id), let .explain(id, _),
                 let .stats(id): id
            }
        }
    }

    /// Qué se elige con opciones.
    private enum Choice: Equatable { case wardrobe, goal, pains }

    /// Qué se elige con deslizador.
    private enum Pick: Equatable { case spend, wardrobe }

    /// Qué se le está preguntando ahora mismo.
    /// `bad` y `good`: la mala y la buena noticia, esperando al botón.
    /// `photos`: el permiso de fotos, esperando al botón.
    /// `found`: el escaneo ha terminado; "Elegir cuáles guardo".
    /// `proof` y `explain(n)`: la prueba social y los pasos del escaneo,
    /// esperando a "Continuar".
    /// `closet`: "¿Qué armario es el tuyo?", hombre o mujer.
    private enum Question: Equatable { case closet, goal, pains, spend, wardrobe, done, bad, good, photos, found, proof, explain(Int) }

    @State private var items: [Item] = []
    @State private var question: Question?
    @State private var nextID = 0
    @State private var pains: Set<String> = []
    @State private var spend: Double = 60
    @State private var wardrobe: Double = 80
    @State private var analysis: Double = 0
    /// La barra de "Analizando", ya llena.
    @State private var analysisDone = false
    @State private var hasStarted = false
    /// Lo que se queda en el centro aunque llegue algo debajo: la cifra
    /// grande, mientras se escriben las frases que la acompañan. `nil`: lo
    /// último.
    @State private var focusID: Int?
    @State private var isRequestingPhotos = false
    /// Dónde empieza el paso de ahora: lo de antes se apaga y se desenfoca;
    /// lo de este paso, entero. Ver `beginStep`.
    @State private var stepStart = 0
    /// Cuánto del bloque de fotos se ha dicho ya. Ver `Item.photos`.
    @State private var photosShown = 0
    /// **El escaneo, detrás de la conversación**: el lienzo con la foto y las
    /// prendas. Ver `ScanningStep(embedded:)`.
    @State private var isScanning = false
    @State private var scanCount = 0
    /// El escaneo ha terminado: el título cambia y el contador brilla.
    @State private var scanDone = false
    /// Lo que dice la tarjeta del final. Ver `ClosetStats`.
    @State private var closetStats: ClosetStats?
    /// Dónde se ancla lo enfocado: al centro, o arriba mientras se escanea,
    /// para dejar el centro a la foto.
    @State private var focusAnchor: UnitPoint = .center
    @State private var token = RunToken()
    /// Los puntos a los que se puede volver con atrás, uno por pregunta.
    @State private var checkpoints: [Checkpoint] = []
    /// El tramo del guion en marcha. Ver `run`.
    @State private var scriptTask: Task<Void, Never>?
    @Environment(\.modelContext) private var modelContext
    /// Lo elegido en cada bloque de opciones ya contestado, por su fila.
    @State private var chosen: [Int: Set<String>] = [:]
    /// El bloque de opciones abierto ahora.
    @State private var openOptionsID: Int?

    /// Tamaño de conversación, no de titular.
    private static let lineFont = Font.custom("PlusJakartaSans-SemiBold", size: 19, relativeTo: .headline)

    var body: some View {
        ZStack {
            if isScanning {
                ScanningStep(
                    model: model,
                    embedded: true,
                    onCount: { scanCount = $0 },
                    onFound: { pieces, outfits in run { await found(pieces: pieces, outfits: outfits) } }
                )
                .transition(.opacity)
            }
            // **Un velo desenfocado entre las prendas y el texto**: con muchas
            // prendas girando detrás, el texto dejaba de leerse. Arriba
            // mientras se busca —ahí están el título y el contador— y en el
            // centro con lo encontrado.
            if isScanning {
                ScanTextVeil(isCentered: scanDone)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            conversation
                // Durante el escaneo, la conversación no tiene nada que
                // tocar: que los dedos lleguen a las prendas de detrás.
                .allowsHitTesting(!isScanning || question != nil && question != .found)
        }
        .onboardingButton(button)
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await start()
        }
        .onAppear { model.backHandler = { stepBack() } }
        .onDisappear { token.isCancelled = true }
    }

    private var conversation: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .center, spacing: WK.Spacing.l) {
                    // Aire arriba y abajo: lo de ahora puede quedar en el centro
                    // aunque sea lo primero o lo último.
                    Color.clear.containerRelativeFrame(.vertical) { height, _ in height * 0.5 }
                    // **Todo en un solo `ForEach`**, y la pregunta abierta
                    // lleva sus opciones debajo dentro de su misma fila. Antes
                    // la última línea se sacaba del `ForEach` al abrirse la
                    // pregunta: era otra vista, y la máquina de escribir
                    // volvía a empezar — la pregunta se escribía dos veces.
                    // ForEach(items.dropLast(question == nil ? 0 : 1)) { item in … }
                    // if let question, let last = items.last { VStack { row(last); controls(for: question) }.id("current") }
                    ForEach(items) { item in
                        VStack(alignment: .center, spacing: WK.Spacing.l) {
                            row(item)
                            if let question, item.id == items.last?.id {
                                controls(for: question)
                                    // Se van desenfocándose y encogiendo un
                                    // poco, sin prisa.
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .offset(y: 16)),
                                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: AnyTransition(.blurReplace))
                                    ))
                            }
                        }
                        .opacity(opacity(of: item))
                        // Y cuanto más arriba, más desenfocado.
                        .blur(radius: blur(of: item))
                        .id(item.id)
                        .transition(.opacity.combined(with: .offset(y: 12)))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                    Color.clear.containerRelativeFrame(.vertical) { height, _ in height * 0.5 }
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .padding(.bottom, WK.Spacing.m)
            }
            // El hueco del botón global, que va por encima.
            // Ya no: la barra del botón ocupa siempre su sitio, y con esto
            // encima el centro quedaba 48 puntos más arriba de la cuenta.
            // .safeAreaPadding(.bottom, 96)
            .scrollIndicators(.hidden)
            // **Lo lleva la conversación, no el dedo**: nunca se desplaza a
            // mano, y lo de ahora siempre queda centrado en la pantalla.
            .scrollDisabled(true)
            // .defaultScrollAnchor(.bottom)
            // Lo de arriba se apaga, como en una conversación que sigue.
            .mask {
                LinearGradient(
                    // Corto: una pregunta con muchas opciones —"marca todo lo
                    // que te suene"— es tan alta que, centrada, su pregunta
                    // caía en el degradado y se leía apagada antes de
                    // contestarla. Lo de antes ya se apaga solo, por su
                    // opacidad.
                    // stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.28)],
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            // Abajo del todo cuando llega algo —con un respiro, para que las
            // opciones ya estén puestas y se vean enteras encima del botón—.
            .onChange(of: items.count) { _, _ in scrollDown(reader) }
            .onChange(of: question) { _, _ in scrollDown(reader) }
            .onChange(of: focusID) { _, _ in scrollDown(reader) }
            .onChange(of: photosShown) { _, _ in scrollDown(reader) }
            .onChange(of: focusAnchor) { _, _ in scrollDown(reader) }
        }
    }

    /// **Lo de ahora, al centro**: las opciones si hay pregunta abierta; si
    /// no, la última línea.
    private func scrollDown(_ reader: ScrollViewProxy) {
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.smooth(duration: 0.6)) {
                // La última fila ya lleva dentro sus opciones.
                // if let last = items.last { reader.scrollTo(last.id, anchor: .center) }
                if let target = focusID ?? items.last?.id {
                    reader.scrollTo(target, anchor: focusAnchor)
                }
            }
        }
    }

    // MARK: Guion

    private func start() async {
        #if DEBUG
        // `-chatMoney`: directo a la mala noticia, sin contestar lo de antes.
        if ProcessInfo.processInfo.arguments.contains("-chatMoney") {
            await badNews()
            return
        }
        // `-chatPhotos`: directo al permiso de fotos.
        if ProcessInfo.processInfo.arguments.contains("-chatPhotos") {
            question = .good
            await photosIntro()
            return
        }
        // `-chatScan`: directo al escaneo (con `-fakeScan`, de prueba).
        if ProcessInfo.processInfo.arguments.contains("-chatScan") {
            await startScan()
            return
        }
        // `-chatProof`: directo a la prueba social y los pasos del escaneo.
        if ProcessInfo.processInfo.arguments.contains("-chatProof") {
            question = .good
            await proof()
            return
        }
        // `-chatExplain 0|1|2`: directo a un paso del escaneo explicado.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-chatExplain"), arguments.indices.contains(index + 1),
           let page = Int(arguments[index + 1]) {
            await explain(page)
            return
        }
        // `-chatSpend`: directo a la pregunta del gasto.
        if ProcessInfo.processInfo.arguments.contains("-chatSpend") {
            await say(String(localized: "chat.spend", defaultValue: "Roughly, how much do you spend on clothes a month?"))
            append(.pick(id: takeID(), kind: .spend))
            ask(.spend)
            return
        }
        #endif
        await say(String(localized: "chat.hello", defaultValue: "Hi, I'm Snazzy. I'll help you get the most out of your closet."))
        await say(String(localized: "chat.intro", defaultValue: "I'll ask you a few quick questions. Don't overthink them."))
        // **Primero, qué armario**: hombre o mujer.
        beginStep()
        await say(String(localized: "chat.closet", defaultValue: "Which closet is yours?"))
        offer(.wardrobe)
        ask(.closet)
    }

    private func answerCloset(_ option: OnboardingOption) async {
        guard question == .closet else { return }
        hasProgressed = true
        model.closetKind = option.id
        await settleOptions([option.id])
        beginStep()
        await say(String(localized: "chat.goal", defaultValue: "What do you want to achieve?"))
        offer(.goal)
        ask(.goal)
    }

    private func answerGoal(_ option: OnboardingOption) async {
        // Un toque: dos seguidos contestaban dos veces.
        guard question == .goal else { return }
        model.goal = option.id
        // await answer(option.label)
        // **La elegida se queda; las demás se van.** Sin volver a escribirla.
        await settleOptions([option.id])
        await say(String(localized: "chat.goal.reply", defaultValue: "Perfect, we'll start there."))
        beginStep()
        await say(String(localized: "chat.pains", defaultValue: "What gets in the way? Pick everything that sounds familiar."))
        offer(.pains)
        ask(.pains)
    }

    private func answerPains() async {
        guard question == .pains else { return }
        model.pains = pains
        let labels = OnboardingContent.pains.filter { pains.contains($0.id) }.map(\.label)
        // Lo que ha marcado, con sus palabras: "3 cosas" no dice nada.
        // answer(labels.count <= 2 ? labels.joined(separator: " · ") : String(localized: "chat.pains.count", defaultValue: "\(String(describing: labels.count)) things"))
        // await answer(labels.joined(separator: " · "))
        _ = labels
        await settleOptions(pains)
        await say(String(localized: "chat.pains.reply", defaultValue: "You're not the only one. It happens to almost everyone."))
        beginStep()
        await say(String(localized: "chat.spend", defaultValue: "Roughly, how much do you spend on clothes a month?"))
        append(.pick(id: takeID(), kind: .spend))
        ask(.spend)
    }

    private func answerSpend() async {
        guard question == .spend else { return }
        model.monthlySpend = spend
        // **Sin borrar y volver a escribir**: la cifra elegida se queda donde
        // está y el deslizador se va.
        // await answer(model.money(spend) + String(localized: "chat.perMonth", defaultValue: " a month"))
        await settle()
        // La cifra, aparte y destacada: ver `Item.highlight`.
        // await say(String(localized: "chat.spend.reply", defaultValue: "That's \(String(describing: model.money(spend * 12))) a year on clothes."))
        await say(String(localized: "chat.spend.reply.lead", defaultValue: "That's"))
        // **La cifra al año, con la rueda**, como las del dinero, y centrada
        // mientras se escribe lo de debajo.
        // append(.highlight(id: takeID(), text: String(localized: "chat.spend.reply.value", defaultValue: "\(String(describing: model.money(spend * 12))) a year")))
        // try? await Task.sleep(for: .seconds(0.9))
        // await say(String(localized: "chat.spend.reply.tail", defaultValue: "on clothes."))
        let wheel = takeID()
        focusID = wheel
        append(.wheel(id: wheel, value: spend * 12, isGood: true))
        try? await Task.sleep(for: .seconds(NumberWheel.duration + 0.3))
        await say(String(localized: "chat.spend.reply.tail2", defaultValue: "a year on clothes."))
        // Un segundo más para leerlo antes de seguir.
        // try? await Task.sleep(for: .seconds(0.6))
        try? await Task.sleep(for: .seconds(1.6))
        focusID = nil
        beginStep()
        await say(String(localized: "chat.wardrobe", defaultValue: "And how many pieces would you say you have?"))
        await say(String(localized: "chat.estimate", defaultValue: "Just an estimate."))
        append(.pick(id: takeID(), kind: .wardrobe))
        ask(.wardrobe)
    }

    private func answerWardrobe() async {
        guard question == .wardrobe else { return }
        model.wardrobeSize = wardrobe
        // await answer(String(localized: "chat.pieces", defaultValue: "\(String(describing: Int(wardrobe))) pieces"))
        await settle()
        beginStep()
        await say(String(localized: "chat.analyzing", defaultValue: "Analysing your answers…"))
        append(.progress(id: takeID()))
        withAnimation(.easeInOut(duration: 2.2)) { analysis = 1 }
        try? await Task.sleep(for: .seconds(2.25))
        // **Llena, hace algo**: se vuelve verde, da un salto y sale el check.
        withAnimation(.spring(duration: 0.5, bounce: 0.45)) { analysisDone = true }
        try? await Task.sleep(for: .seconds(0.9))
        await say(String(localized: "chat.done", defaultValue: "You have more closet than you can see. Let me show you."))
        // Sigue sola, sin botón: ya lo ha dicho.
        // ask(.done)
        try? await Task.sleep(for: .seconds(0.9))
        // **Y el dinero, aquí mismo**, siguiendo la conversación: ya no es
        // otra pantalla (`RevealStep`).
        // model.advance()
        await badNews()
    }

    // MARK: El dinero

    private func badNews() async {
        beginStep()
        append(.news(id: takeID(), text: String(localized: "reveal.bad.title", defaultValue: "The bad news:"), isGood: false))
        try? await Task.sleep(for: .seconds(0.9))
        await say(String(localized: "reveal.bad.lead2", defaultValue: "in your closet you have"))
        let wheel = takeID()
        // **La cifra, en el centro**, y lo que viene después se escribe
        // debajo sin moverla.
        focusID = wheel
        append(.wheel(id: wheel, value: model.idleValue, isGood: false))
        try? await Task.sleep(for: .seconds(NumberWheel.duration + 0.4))
        await say(String(localized: "reveal.bad.caption2", defaultValue: "in clothes you barely wear."))
        try? await Task.sleep(for: .seconds(0.5))
        await say(String(localized: "reveal.bad.coda", defaultValue: "Yes, you read that right."))
        // **"Cambiar esto" pasa a la buena, y si no se toca, pasa sola.** Ni
        // una cosa ni la otra añaden una respuesta a la conversación.
        ask(.bad)
        try? await Task.sleep(for: .seconds(3.5))
        await goodNews()
    }

    private func goodNews() async {
        // Una vez: el botón y la espera llegan aquí los dos.
        guard question == .bad else { return }
        withAnimation(.smooth(duration: 0.35)) { question = nil }
        // La respuesta "Cambiar esto", de cuando había botón:
        // answer(String(localized: "reveal.bad.button", defaultValue: "Change this"))
        // try? await Task.sleep(for: .seconds(0.5))
        focusID = nil
        beginStep()
        append(.news(id: takeID(), text: String(localized: "reveal.good.title", defaultValue: "The good news:"), isGood: true))
        try? await Task.sleep(for: .seconds(0.9))
        await say(String(localized: "reveal.good.lead2", defaultValue: "Snazzy can save you"))
        let wheel = takeID()
        focusID = wheel
        append(.wheel(id: wheel, value: model.yearlySaving, isGood: true))
        try? await Task.sleep(for: .seconds(NumberWheel.duration + 0.4))
        await say(String(localized: "reveal.good.caption2", defaultValue: "a year,"))
        await say(String(localized: "reveal.good.coda", defaultValue: "wearing what you already have instead of buying more of the same."))
        // La nota, en la conversación y no bajo el botón: debajo del botón
        // cambiaba el alto de la barra y la pantalla saltaba.
        append(.note(id: takeID(), text: String(localized: "reveal.footnote", defaultValue: "An estimate based on what you told us.")))
        ask(.good)
    }

    // MARK: Las fotos

    /// **El permiso de fotos, en la misma conversación**: ya no es otra
    /// pantalla (`PhotoPermissionStep`).
    // MARK: La prueba y los pasos

    /// "Nuestros usuarios…": las prendas desfilando y un outfit montándose.
    private func proof() async {
        guard question == .good else { return }
        withAnimation(.smooth(duration: 0.45)) { question = nil }
        focusID = nil
        try? await Task.sleep(for: .seconds(0.5))
        beginStep()
        append(.proof(id: takeID()))
        try? await Task.sleep(for: .seconds(2.6))
        ask(.proof)
    }

    /// Un paso de cómo funciona el escaneo, en el scroll.
    private func explain(_ page: Int) async {
        withAnimation(.smooth(duration: 0.45)) { question = nil }
        try? await Task.sleep(for: .seconds(0.45))
        beginStep()
        append(.explain(id: takeID(), page: page))
        try? await Task.sleep(for: .seconds(2.2))
        ask(.explain(page))
    }

    private func photosIntro() async {
        // Llega desde el último paso del escaneo explicado.
        // guard question == .good else { return }
        withAnimation(.smooth(duration: 0.45)) { question = nil }
        focusID = nil
        try? await Task.sleep(for: .seconds(0.5))
        beginStep()
        // En filas sueltas, de antes: el titular, la explicación y cada
        // punto como una fila más.
        // append(.heading(…)); await say(…); for … { append(.point(…)) }
        append(.photos(id: takeID()))
        for step in 1...(photoPoints.count + 1) {
            try? await Task.sleep(for: .seconds(step == 1 ? 1.2 : 1.4))
            withAnimation(.smooth(duration: 0.5)) { photosShown = step }
        }
        try? await Task.sleep(for: .seconds(0.8))
        ask(.photos)
    }

    /// Los tres puntos del permiso. **El del medio recomienda elegir las
    /// fotos**: no hace falta dar acceso a todas.
    private var photoPoints: [(symbol: String, title: String, detail: String, isRecommended: Bool)] {
        [
            ("iphone.gen3",
             String(localized: "onboarding.onboardingscansteps.itAllHappensOnYour2", defaultValue: "It all happens on your iPhone"),
             String(localized: "onboarding.onboardingscansteps.yourPhotosArenTUploaded", defaultValue: "Your photos aren't uploaded anywhere."),
             false),
            ("hand.raised",
             String(localized: "onboarding.onboardingscansteps.youChooseHowMuch", defaultValue: "You choose how much"),
             String(localized: "chat.photos.choose", defaultValue: "We recommend picking the photos yourself: there's no need to give access to all of them."),
             true),
            ("scissors",
             String(localized: "onboarding.onboardingscansteps.onlyTheClothesAreSaved", defaultValue: "Only the clothes are saved"),
             String(localized: "onboarding.onboardingscansteps.facesAndSkinAreDiscarded", defaultValue: "Faces and skin are discarded; they never reach your closet."),
             false),
        ]
    }

    private func requestPhotos() {
        guard question == .photos, !isRequestingPhotos else { return }
        isRequestingPhotos = true
        run {
            // Aunque deniegue se sigue: el armario funciona importando fotos
            // sueltas. Ver `PhotoPermissionStep`.
            _ = await PhotoLibraryService().requestAuthorization()
            isRequestingPhotos = false
            guard !token.isCancelled else { return }
            // model.advance()
            // **Y el escaneo, aquí mismo**: sigue la conversación.
            await startScan()
        }
    }

    // MARK: El escaneo

    private func startScan() async {
        withAnimation(.smooth(duration: 0.45)) { question = nil }
        try? await Task.sleep(for: .seconds(0.4))
        beginStep()
        let title = takeID()
        // append(.line(id: title, text: String(localized: "onboarding.onboardingscansteps.lookingForYourClothes", defaultValue: "Looking for your clothes")))
        append(.scanTitle(id: title))
        // Arriba, para dejar el centro a la foto que se mira.
        focusID = title
        focusAnchor = UnitPoint(x: 0.5, y: 0.16)
        try? await Task.sleep(for: .seconds(0.6))
        append(.counter(id: takeID()))
        append(.note(id: takeID(), text: String(localized: "onboarding.onboardingscansteps.itAllHappensOnYour", defaultValue: "It all happens on your iPhone · keep the app open")))
        guard !Task.isCancelled else { return }
        withAnimation(.smooth(duration: 0.6)) { isScanning = true }
    }

    /// Terminado: lo encontrado, en la conversación, con las ruedas.
    private func found(pieces: Int, outfits: Int) async {
        guard !token.isCancelled else { return }
        // Nada esta vez: se dice y se sigue.
        guard pieces > 0 else {
            beginStep()
            focusID = nil
            focusAnchor = .center
            await say(String(localized: "chat.scan.none", defaultValue: "I couldn't find clothes this time. You can add them whenever you like."))
            ask(.found)
            return
        }
        // **Sin "Hemos encontrado X prendas" aparte**: "Buscando tu ropa" se
        // transforma en "Hemos encontrado" y el contador brilla, en su sitio.
        // Dicho debajo, se leía dos veces.
        guard !Task.isCancelled else { return }
        withAnimation(.smooth(duration: 0.6)) { scanDone = true }
        try? await Task.sleep(for: .seconds(1.8))
        beginStep()
        focusID = nil
        focusAnchor = .center
        // **Aquí va lo de "Tu armario, ya dentro"**, que ya no es otra
        // pantalla: las combinaciones con todo el armario —lo que había y lo
        // encontrado—, el total de prendas y el color principal. Lo de las
        // combinaciones solo de lo encontrado, de antes:
        // if outfits > 0 {
        //     // await say(String(localized: "scan.found.moreThan", defaultValue: "and you can make more than"))
        //     await say(String(localized: "chat.found.canMake", defaultValue: "You can make more than"))
        //     let second = takeID()
        //     focusID = second
        //     append(.count(id: second, value: Double(outfits), tone: .oliva))
        //     try? await Task.sleep(for: .seconds(NumberWheel.duration + 0.2))
        //     await say(String(localized: "scan.found.outfits", defaultValue: "combinations"))
        // } else {
        //     await say(String(localized: "onboarding.scanfoundstep.asSoonAsYouHave", defaultValue: "As soon as you have something for the bottom, the outfits begin."))
        // }
        let closet = (try? modelContext.fetch(FetchDescriptor<Garment>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let pendingAll = (try? modelContext.fetch(FetchDescriptor<PendingGarment>())) ?? []
        let combinations = max(1, ScanningStep.outfitCount(closet.map(\.kind) + pendingAll.map(\.kind)))
        await say(String(localized: "onboarding.onboardingscansteps.yourClosetNowInside", defaultValue: "Your closet, now inside"))
        let wheel = takeID()
        focusID = wheel
        append(.count(id: wheel, value: Double(combinations), tone: .denim))
        try? await Task.sleep(for: .seconds(NumberWheel.duration + 0.2))
        await say(String(localized: "onboarding.onboardingscansteps.possibleCombinations", defaultValue: "possible combinations"))
        await say(String(localized: "onboarding.onboardingscansteps.allWithClothesYouAlready", defaultValue: "All with clothes you already own."))
        // La línea de prendas y color principal, de antes; ahora es una
        // tarjeta con las prendas, el estilo y los colores.
        // let colour = ScanSummaryStep.mainColour(of: closet)
        // var detail = "\(closet.count + pendingAll.count) " + String(localized: "scan.pieces", defaultValue: "pieces")
        // if colour != "—" { detail += " · " + … + colour }
        // append(.note(id: takeID(), text: detail))
        closetStats = ClosetStats(
            garments: closet.map { ($0.subcategory, $0.kind, $0.colors) }
                + pendingAll.compactMap { pending in pending.draft.map { ($0.subcategory, $0.kind, $0.colors) } }
        )
        try? await Task.sleep(for: .seconds(0.3))
        append(.stats(id: takeID()))
        try? await Task.sleep(for: .seconds(0.8))
        // **Sin revisar ahora**: se quedan pendientes y se revisan luego.
        try? await Task.sleep(for: .seconds(0.4))
        append(.note(id: takeID(), text: String(localized: "chat.scan.reviewLater", defaultValue: "You'll be able to review them later.")))
        ask(.found)
    }

    private func say(_ text: String) async {
        guard !Task.isCancelled else { return }
        append(.line(id: takeID(), text: text))
        // Lo que tarda en escribirse, y un respiro.
        try? await Task.sleep(for: .seconds(Double(text.count) * TypewriterText.perCharacter + 0.45))
    }

    /// **Las opciones se van despacio y la respuesta se escribe**, como lo
    /// demás. Antes las opciones desaparecían de golpe y la respuesta salía
    /// ya escrita.
    private func answer(_ text: String) async {
        withAnimation(.smooth(duration: 0.5)) { question = nil }
        try? await Task.sleep(for: .seconds(0.45))
        append(.answer(id: takeID(), text: text))
        try? await Task.sleep(for: .seconds(Double(text.count) * TypewriterText.perCharacter + 0.35))
    }

    /// Pone las opciones de una pregunta en la conversación.
    private func offer(_ kind: Choice) {
        let id = takeID()
        openOptionsID = id
        append(.options(id: id, kind: kind))
    }

    /// Cierra una pregunta de opciones: las no elegidas se van y las elegidas
    /// pierden icono y cristal y se quedan, como la respuesta.
    private func settleOptions(_ ids: Set<String>) async {
        guard let open = openOptionsID else { return }
        withAnimation(.smooth(duration: 0.55)) {
            chosen[open] = ids
            question = nil
        }
        openOptionsID = nil
        try? await Task.sleep(for: .seconds(0.8))
    }

    /// Cierra una pregunta de deslizador: se va el deslizador y la cifra se
    /// queda, con brillo.
    private func settle() async {
        withAnimation(.smooth(duration: 0.55)) { question = nil }
        try? await Task.sleep(for: .seconds(0.8))
    }

    private func ask(_ next: Question) {
        guard !Task.isCancelled else { return }
        // Un punto al que volver con atrás. Ver `stepBack`.
        checkpoints.append(Checkpoint(
            itemsCount: items.count, question: next, stepStart: stepStart,
            focusID: focusID, focusAnchor: focusAnchor, openOptionsID: openOptionsID,
            isScanning: isScanning, scanDone: scanDone, photosShown: photosShown
        ))
        withAnimation(.smooth(duration: 0.45)) { question = next }
    }

    private func append(_ item: Item) {
        guard !Task.isCancelled else { return }
        withAnimation(.smooth(duration: 0.4)) { items.append(item) }
    }

    // MARK: Atrás

    /// Cómo estaba la conversación al hacer una pregunta.
    private struct Checkpoint {
        let itemsCount: Int
        let question: Question
        let stepStart: Int
        let focusID: Int?
        let focusAnchor: UnitPoint
        let openOptionsID: Int?
        let isScanning: Bool
        let scanDone: Bool
        let photosShown: Int
    }

    /// Lanza un tramo del guion, y se queda con él para poder pararlo.
    private func run(_ work: @escaping @MainActor () async -> Void) {
        scriptTask = Task { await work() }
    }

    /// **Atrás, un paso**: vuelve a la pregunta anterior —con sus opciones
    /// otra vez abiertas— y quita lo que vino después. A mitad de un tramo
    /// sin pregunta, vuelve a la última que se hizo. En la primera, atrás es
    /// atrás: a la bienvenida.
    private func stepBack() -> Bool {
        guard let last = checkpoints.last else { return false }
        let target: Checkpoint
        if question != nil, question == last.question {
            guard checkpoints.count >= 2 else { return false }
            checkpoints.removeLast()
            target = checkpoints[checkpoints.count - 1]
        } else {
            target = last
        }
        // Primero se para lo que estuviera en marcha —y se deja terminar, que
        // cancelado ya no añade nada—; después se vuelve.
        let running = scriptTask
        running?.cancel()
        scriptTask = nil
        Task {
            await running?.value
            restore(target)
        }
        return true
    }

    private func restore(_ point: Checkpoint) {
        withAnimation(.smooth(duration: 0.5)) {
            items = Array(items.prefix(point.itemsCount))
            stepStart = point.stepStart
            focusID = point.focusID
            focusAnchor = point.focusAnchor
            isScanning = point.isScanning
            scanDone = point.scanDone
            photosShown = point.photosShown
            if let id = point.openOptionsID { chosen[id] = nil }
            openOptionsID = point.openOptionsID
            question = point.question
        }
    }

    private func takeID() -> Int {
        nextID += 1
        return nextID
    }

    // MARK: Piezas

    @ViewBuilder
    private func row(_ item: Item) -> some View {
        switch item {
        // **Todo centrado**: las líneas, las respuestas y las cifras. Antes,
        // a la izquierda, como un chat.
        case let .line(_, text):
            TypewriterText(text: text)
                .font(Self.lineFont)
                .foregroundStyle(WK.Palette.primaryText)
                .multilineTextAlignment(.center)
                // .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        case let .answer(_, text):
            // Text(text)
            TypewriterText(text: text)
                .font(Self.lineFont)
                .foregroundStyle(OnboardingTone.denim.color)
                .multilineTextAlignment(.center)
                // .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        case let .news(_, text, isGood):
            GlowingText(text: text, tone: isGood ? .oliva : .granate, size: 26)
                .frame(maxWidth: .infinity, alignment: .center)
        case let .wheel(_, value, isGood):
            NumberWheel(target: value, format: { model.money($0) }, tone: isGood ? .oliva : .granate)
                .frame(maxWidth: .infinity, alignment: .center)
        case let .options(id, kind):
            optionsRow(id: id, kind: kind)
        case .stats:
            if let closetStats {
                ClosetStatsCard(stats: closetStats)
            }
        case .proof:
            VStack(spacing: WK.Spacing.l) {
                TypewriterText(text: String(localized: "chat.proof.title", defaultValue: "Our users get more than 1,000 combinations out of what they already have"))
                    .font(Self.lineFont)
                    .foregroundStyle(WK.Palette.primaryText)
                    .multilineTextAlignment(.center)
                // Ocupa su sitio desde el principio y aparece tras el texto:
                // antes llegaba a la vez que el scroll y se veía un doble salto.
                DelayedReveal(delay: 1.2) { ProofVisual() }
            }
            .frame(maxWidth: .infinity)
        case let .explain(_, page):
            ExplainBlock(page: page, lineFont: Self.lineFont, isWomen: model.closetKind == "women")
        case .scanTitle:
            TypewriterText(text: scanDone
                           ? String(localized: "scan.found.title", defaultValue: "We found")
                           : String(localized: "onboarding.onboardingscansteps.lookingForYourClothes", defaultValue: "Looking for your clothes"))
                .font(Self.lineFont)
                .foregroundStyle(WK.Palette.primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        case .counter:
            VStack(spacing: 0) {
                Text("\(scanCount)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(NumberInk.gradient(.denim))
                    // Terminado: brilla, como las cifras que importan.
                    .wkShimmer(isActive: scanDone)
                    .scaleEffect(scanDone ? 1.08 : 1)
                    .shadow(color: OnboardingTone.denim.color.opacity(scanDone ? 0.35 : 0), radius: 16)
                    .contentTransition(.numericText(value: Double(scanCount)))
                    .monospacedDigit()
                    .animation(.smooth(duration: 0.4), value: scanCount)
                Text(scanCount == 1
                     ? String(localized: "scan.piece", defaultValue: "piece")
                     : String(localized: "scan.pieces", defaultValue: "pieces"))
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.secondaryText)
            }
            .frame(maxWidth: .infinity)
        case let .count(_, value, tone):
            NumberWheel(target: value, format: { Int($0).formatted() }, tone: tone)
                .frame(maxWidth: .infinity, alignment: .center)
        case .photos:
            VStack(spacing: WK.Spacing.l) {
                TypewriterText(text: String(localized: "onboarding.onboardingscansteps.yourClothesAreAlreadyNin", defaultValue: "Your clothes are already\nin your photos"))
                    // Del tamaño del resto de la conversación, no de titular.
                    // .font(WK.Font.largeTitle)
                    .font(Self.lineFont)
                    .foregroundStyle(WK.Palette.primaryText)
                    .multilineTextAlignment(.center)
                if photosShown >= 1 {
                    TypewriterText(text: String(localized: "onboarding.onboardingscansteps.snazzyLooksThroughThemOn", defaultValue: "Snazzy looks through them on your iPhone to cut out the clothes you're wearing."))
                        .font(WK.Font.callout)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: WK.Spacing.s) {
                    ForEach(Array(photoPoints.enumerated()), id: \.offset) { index, point in
                        if photosShown >= index + 2 {
                            PhotoPointCard(symbol: point.symbol, title: point.title, detail: point.detail, isRecommended: point.isRecommended)
                                .transition(.opacity.combined(with: .offset(y: 14)).combined(with: AnyTransition(.blurReplace)))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        case let .heading(_, text):
            TypewriterText(text: text)
                // .font(WK.Font.largeTitle)
                .font(Self.lineFont)
                .foregroundStyle(WK.Palette.primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        case let .point(_, symbol, title, detail):
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WK.Palette.secondaryText)
                    .padding(.bottom, 2)
                TypewriterText(text: title)
                    .font(WK.Font.headline)
                    .foregroundStyle(WK.Palette.primaryText)
                TypewriterText(text: detail)
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.secondaryText)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
        case let .pick(id, kind):
            pickRow(kind, isOpen: id == items.last?.id && (question == .spend || question == .wardrobe))
        case let .note(_, text):
            Text(text)
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        case let .highlight(_, text):
            GlowingText(text: text, tone: .oliva)
                .multilineTextAlignment(.center)
                // .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        case .progress:
            HStack(spacing: WK.Spacing.s) {
                Capsule()
                    .fill(WK.Palette.ink(0.08))
                    .frame(height: analysisDone ? 8 : 5)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(analysisDone ? OnboardingTone.oliva.color : OnboardingTone.denim.color)
                                .frame(width: proxy.size.width * analysis)
                                .wkShimmer(isActive: analysisDone)
                                .shadow(color: OnboardingTone.oliva.color.opacity(analysisDone ? 0.5 : 0), radius: 10)
                        }
                    }
                if analysisDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(OnboardingTone.oliva.color)
                        .symbolEffect(.bounce, value: analysisDone)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .scaleEffect(analysisDone ? 1.03 : 1)
            .sensoryFeedback(.success, trigger: analysisDone)
        }
    }

    /// Las opciones: todas mientras se pregunta; después, solo las elegidas,
    /// ya integradas en la conversación.
    private func optionsRow(id: Int, kind: Choice) -> some View {
        let settled = chosen[id]
        let list = switch kind {
        case .wardrobe: OnboardingContent.closets
        case .goal: OnboardingContent.goals
        case .pains: OnboardingContent.pains
        }
        return VStack(spacing: WK.Spacing.s) {
            ForEach(list) { option in
                if settled == nil || settled?.contains(option.id) == true {
                    ChatOptionRow(
                        option: option,
                        isSelected: kind == .pains && pains.contains(option.id),
                        isCheckbox: kind == .pains,
                        isSettled: settled != nil
                    ) {
                        switch kind {
                        case .wardrobe:
                            run { await answerCloset(option) }
                        case .goal:
                            run { await answerGoal(option) }
                        case .pains:
                            withAnimation(WKAnimation.selection) {
                                if pains.contains(option.id) { pains.remove(option.id) } else { pains.insert(option.id) }
                            }
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 16)),
                        removal: .opacity.combined(with: .scale(scale: 0.96)).combined(with: AnyTransition(.blurReplace))
                    ))
                }
            }
        }
        .allowsHitTesting(settled == nil)
    }

    /// La cifra y, mientras se pregunta, su deslizador.
    private func pickRow(_ kind: Pick, isOpen: Bool) -> some View {
        let value = kind == .spend ? $spend : $wardrobe
        let range: ClosedRange<Double> = kind == .spend ? 10...400 : 20...400
        let format: (Double) -> String = kind == .spend
            ? { model.money($0) }
            : { String(localized: "chat.pieces", defaultValue: "\(String(describing: Int($0))) pieces") }
        return VStack(spacing: WK.Spacing.m) {
            VStack(spacing: 2) {
                Text(format(value.wrappedValue))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: value.wrappedValue)
                    .foregroundStyle(isOpen ? WK.Palette.primaryText : OnboardingTone.denim.color)
                    // Contestada: brillo, como las cifras que importan.
                    .wkShimmer(isActive: !isOpen)
                if kind == .spend {
                    Text(String(localized: "chat.perMonth.label", defaultValue: "a month"))
                        .font(WK.Font.callout)
                        .foregroundStyle(WK.Palette.secondaryText)
                }
            }
            .scaleEffect(isOpen ? 1 : 0.82)
            if isOpen {
                VStack(spacing: WK.Spacing.s) {
                    // De euro en euro: a saltos de cinco se notaba a tirones.
                    Slider(value: value, in: range, step: kind == .spend ? 1 : 10)
                        .tint(WK.Palette.accent)
                    HStack {
                        Text(format(range.lowerBound))
                        Spacer()
                        Text(format(range.upperBound))
                    }
                    .font(.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 16)),
                    removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: AnyTransition(.blurReplace))
                ))
            }
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: value.wrappedValue)
    }

    /// **Por pasos y no por distancia**: lo del paso de ahora, nítido; lo de
    /// pasos anteriores —"Te haré unas preguntas" cuando ya se pregunta—,
    /// apagado y un poco desenfocado, más cuanto más atrás.
    private func blur(of item: Item) -> CGFloat {
        let behind = stepsBehind(item)
        return behind == 0 ? 0 : min(6, 1.5 + CGFloat(behind - 1) * 1.3)
    }

    private func opacity(of item: Item) -> Double {
        let behind = stepsBehind(item)
        return behind == 0 ? 1 : max(0.18, 0.55 - Double(behind - 1) * 0.15)
    }

    /// Cuántas filas por detrás del paso de ahora. 0: es de este paso.
    private func stepsBehind(_ item: Item) -> Int {
        guard let index = items.firstIndex(of: item) else { return 0 }
        return max(0, stepStart - index)
    }

    /// Empieza un paso nuevo: lo dicho hasta aquí pasa a segundo plano.
    private func beginStep() {
        guard !Task.isCancelled else { return }
        withAnimation(.smooth(duration: 0.6)) { stepStart = items.count }
    }

    // Por distancia al final, de antes:
    // private func blur(of item: Item) -> CGFloat {
    //     guard let index = items.firstIndex(of: item) else { return 0 }
    //     let fromEnd = items.count - 1 - index - sharpness(of: item)
    //     return fromEnd <= 1 ? 0 : min(4, CGFloat(fromEnd - 1) * 1.2)
    // }
    //
    // /// Lo último, entero; lo de antes, apagado.
    // private func opacity(of item: Item) -> Double {
    //     guard let index = items.firstIndex(of: item) else { return 1 }
    //     let fromEnd = items.count - 1 - index - sharpness(of: item)
    //     return fromEnd <= 1 ? 1 : max(0.28, 1 - Double(fromEnd - 1) * 0.3)
    // }
    //
    // /// **La cifra y su titular aguantan más**: con dos frases detrás ya se
    // /// apagaban, y es lo que hay que leer.
    // private func sharpness(of item: Item) -> Int {
    //     switch item {
    //     case .wheel, .news: 3
    //     case .heading: 2
    //     default: 0
    //     }
    // }

    @ViewBuilder
    private func controls(for question: Question) -> some View {
        switch question {
        // Las opciones van en su propia fila: ver `Item.options`.
        case .closet, .goal, .pains:
            EmptyView()
        /*
        case .goal:
            VStack(spacing: WK.Spacing.s) {
                ForEach(OnboardingContent.goals) { option in
                    ChatOptionRow(option: option, isSelected: false) {
                        run { await answerGoal(option) }
                    }
                }
            }
        case .pains:
            VStack(spacing: WK.Spacing.s) {
                ForEach(OnboardingContent.pains) { option in
                    ChatOptionRow(option: option, isSelected: pains.contains(option.id), isCheckbox: true) {
                        withAnimation(WKAnimation.selection) {
                            if pains.contains(option.id) { pains.remove(option.id) } else { pains.insert(option.id) }
                        }
                    }
                }
            }
        */
        // Los deslizadores van en la fila de su cifra: ver `Item.pick`.
        // case .spend:
        //     ValueStepperSlider(value: $spend, range: 10...400, step: 1) { model.money($0) }
        //         .padding(.top, WK.Spacing.m)
        // case .wardrobe:
        //     ValueStepperSlider(value: $wardrobe, range: 20...400, step: 10) {
        //         String(localized: "chat.pieces", defaultValue: "\(String(describing: Int($0))) pieces")
        //     }
        //     .padding(.top, WK.Spacing.m)
        case .spend, .wardrobe, .done, .bad, .good, .photos, .found, .proof, .explain:
            EmptyView()
        }
    }

    /// El botón global según lo que toque: nada mientras se escribe o en una
    /// pregunta de un toque; "Listo" o "Esto" cuando hay que confirmar.
    private var button: OnboardingButtonConfig {
        switch question {
        case .pains:
            OnboardingButtonConfig(
                title: String(localized: "chat.button.done", defaultValue: "Done"),
                isEnabled: !pains.isEmpty,
                action: { run { await answerPains() } }
            )
        case .spend:
            OnboardingButtonConfig(
                title: String(localized: "chat.button.thatsIt", defaultValue: "That's about it"),
                action: { run { await answerSpend() } }
            )
        case .wardrobe:
            OnboardingButtonConfig(
                title: String(localized: "chat.button.thatsIt", defaultValue: "That's about it"),
                action: { run { await answerWardrobe() } }
            )
        case .done:
            OnboardingButtonConfig(
                title: String(localized: "common.continue", defaultValue: "Continue"),
                action: { model.advance() }
            )
        case .bad:
            OnboardingButtonConfig(
                title: String(localized: "reveal.bad.button", defaultValue: "Change this"),
                action: { run { await goodNews() } }
            )
        case .good:
            OnboardingButtonConfig(
                title: String(localized: "reveal.good.button", defaultValue: "I want that"),
                // **Con aviso de tocar**: al llegar a lo bueno no siempre se
                // sabe que hay que tocar para seguir.
                nudges: true,
                // action: { model.advance() }
                // action: { Task { await photosIntro() } }
                action: { run { await proof() } }
            )
        case .proof:
            OnboardingButtonConfig(
                title: String(localized: "common.continue", defaultValue: "Continue"),
                // El primer paso —tu galería— fuera: se empieza por cómo se
                // lee cada prenda.
                // action: { Task { await explain(0) } }
                action: { run { await explain(1) } }
            )
        case let .explain(page):
            OnboardingButtonConfig(
                title: page == 2
                    ? String(localized: "chat.explain.fillButton", defaultValue: "Fill my closet")
                    : String(localized: "common.continue", defaultValue: "Continue"),
                action: {
                    guard question == .explain(page) else { return }
                    run { page < 2 ? await explain(page + 1) : await photosIntro() }
                }
            )
        case .found:
            // La revisión, fuera: "Más adelante podrás revisarlas".
            // OnboardingButtonConfig(
            //     title: String(localized: "onboarding.scanfoundstep.chooseWhichToKeep", defaultValue: "Choose which to keep"),
            //     action: { model.go(to: .scanReview) }
            // )
            // "Tu armario" ya se ha dicho aquí: directo a lo siguiente.
            // OnboardingButtonConfig(
            //     title: String(localized: "common.continue", defaultValue: "Continue"),
            //     action: { model.go(to: .scanSummary) }
            // )
            OnboardingButtonConfig(
                title: String(localized: "common.continue", defaultValue: "Continue"),
                action: { model.advance() }
            )
        case .photos:
            OnboardingButtonConfig(
                title: String(localized: "onboarding.onboardingscansteps.letItLookAtMy", defaultValue: "Let it look at my photos"),
                isEnabled: !isRequestingPhotos,
                action: { requestPhotos() }
            )
        // **El botón no se va nunca**: mientras se escribe o en una pregunta
        // de un toque está, pero apagado. Si aparecía y desaparecía, la
        // pantalla saltaba.
        // case .goal, nil:
        //     nil
        case .closet, .goal, nil:
            OnboardingButtonConfig(
                title: String(localized: "common.continue", defaultValue: "Continue"),
                isEnabled: false,
                action: {}
            )
        }
    }
}

/// **Texto que aparece letra a letra, cada una desenfocándose**: una ola
/// que recorre el texto, y cada letra pasa de borrosa y transparente a
/// nítida. Con un `TextRenderer`, así el texto ocupa su sitio entero desde el
/// principio y nada salta.
///
/// Lo de en medio —el texto entero de golpe con desenfoque— y lo de antes
/// —letra a letra sin desenfoque—, comentados.
struct TypewriterText: View {
    let text: String
    /// Cuánto tarda cada letra en empezar a aparecer.
    static let perCharacter = 0.022
    /// Cuántas letras dura el desenfoque de cada una: la ola.
    private static let spread = 7.0
    @State private var progress = 0.0

    var body: some View {
        Text(text)
            .textRenderer(BlurReveal(progress: progress, spread: Self.spread))
            .task(id: text) {
                progress = 0
                let total = Double(text.count) + Self.spread
                withAnimation(.linear(duration: total * Self.perCharacter)) { progress = total }
            }
    }
}

/// Pinta cada letra según por dónde va la ola.
private struct BlurReveal: TextRenderer, Animatable {
    var progress: Double
    let spread: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var index = 0.0
        for line in layout {
            for run in line {
                for glyph in run {
                    let t = max(0, min(1, (progress - index) / spread))
                    var copy = context
                    copy.opacity = t
                    if t < 1 {
                        copy.addFilter(.blur(radius: (1 - t) * 6))
                        copy.translateBy(x: 0, y: (1 - t) * 3)
                    }
                    copy.draw(glyph)
                    index += 1
                }
            }
        }
    }
}

// El texto entero de golpe, desenfocándose:
// struct TypewriterText: View {
//     let text: String
//     static let perCharacter = 0.014
//     @State private var isShown = false
//
//     var body: some View {
//         Text(text)
//             .opacity(isShown ? 1 : 0)
//             .blur(radius: isShown ? 0 : 10)
//             .scaleEffect(isShown ? 1 : 0.97)
//             .task(id: text) {
//                 isShown = false
//                 withAnimation(.smooth(duration: 0.6)) { isShown = true }
//             }
//     }
// }

// La de antes, letra a letra:
// /// Texto que se escribe solo, letra a letra.
// struct TypewriterText: View {
//     let text: String
//     /// Cuánto tarda cada letra.
//     static let perCharacter = 0.022
//     @State private var shown = 0
//
//     var body: some View {
//         // El texto entero ocupa su sitio desde el principio —invisible lo que
//         // falta—, así las líneas no saltan al crecer.
//         (Text(visible) + Text(hidden).foregroundColor(.clear))
//             .task(id: text) {
//                 shown = 0
//                 for index in 0...text.count {
//                     shown = index
//                     try? await Task.sleep(for: .seconds(Self.perCharacter))
//                 }
//             }
//     }
//
//     private var visible: AttributedString { AttributedString(String(text.prefix(shown))) }
//     private var hidden: AttributedString { AttributedString(String(text.dropFirst(shown))) }
// }

/// Una opción de la conversación: una fila de cristal.
private struct ChatOptionRow: View {
    let option: OnboardingOption
    let isSelected: Bool
    var isCheckbox = false
    /// Contestada: sin icono, sin check y sin cristal; el texto se queda
    /// donde está, en el color de las respuestas.
    var isSettled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WK.Spacing.m) {
                // Sin color: los tonos por opción, y el contorno al marcar,
                // sobraban. Lo único que cambia al marcar es el check.
                Image(systemName: option.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    // .foregroundStyle(option.tone.color)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .frame(width: 22)
                    .opacity(isSettled ? 0 : 1)
                // El texto, centrado en la fila: el icono a un lado y el
                // check —o su hueco— al otro, para que quede en medio.
                Spacer(minLength: 0)
                Text(option.label)
                    .font(WK.Font.body)
                    // El texto, igual: solo se va el cristal.
                    .foregroundStyle(WK.Palette.primaryText)
                    // .foregroundStyle(isSettled ? OnboardingTone.denim.color : WK.Palette.primaryText)
                    // .multilineTextAlignment(.leading)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                if !isCheckbox {
                    Color.clear.frame(width: 22, height: 1)
                }
                if isCheckbox {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        // .foregroundStyle(isSelected ? option.tone.color : WK.Palette.tertiaryText)
                        // .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 20))
                        .frame(width: 22)
                        .foregroundStyle(isSelected ? WK.Palette.primaryText : WK.Palette.tertiaryText)
                        // El círculo se convierte en el check.
                        .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating))
                        .opacity(isSettled ? 0 : 1)
                }
            }
            .padding(.horizontal, WK.Spacing.m)
            .padding(.vertical, WK.Spacing.m - 2)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        // .adaptiveGlassInteractive(in: .capsule)
        // Quitando el modificador la vista se rehacía y el texto saltaba; así
        // el cristal se apaga animando y el texto no se mueve.
        // .modifier(OptionGlass(isOn: !isSettled))
        .adaptiveGlassInteractive(in: .capsule, isEnabled: !isSettled)
        // .overlay {
        //     Capsule().stroke(isSelected ? option.tone.color : .clear, lineWidth: 1.5)
        // }
    }
}

/// **Una cifra que importa**: grande, en color, con un brillo que la recorre y
/// un halo detrás. La usan la conversación y el paso del dinero.
struct GlowingText: View {
    let text: String
    let tone: OnboardingTone
    var size: CGFloat = 30

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(tone.color)
            .wkShimmer(isActive: true)
            .shadow(color: tone.color.opacity(0.45), radius: 18)
            .shadow(color: tone.color.opacity(0.25), radius: 40)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

/// Un punto del permiso de fotos, **en su tarjeta con borde**: el icono a un
/// lado y el texto al otro. El recomendado lo dice.
private struct PhotoPointCard: View {
    let symbol: String
    let title: String
    let detail: String
    let isRecommended: Bool

    var body: some View {
        HStack(alignment: .top, spacing: WK.Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WK.Palette.secondaryText)
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: WK.Spacing.s) {
                    Text(title)
                        .font(WK.Font.headline)
                        .foregroundStyle(WK.Palette.primaryText)
                    if isRecommended {
                        Text(String(localized: "chat.photos.recommended", defaultValue: "Recommended"))
                            .font(WK.Font.captionMedium)
                            .foregroundStyle(WK.Palette.canvas)
                            .padding(.horizontal, WK.Spacing.s)
                            .padding(.vertical, 2)
                            .background(WK.Palette.primaryText, in: .capsule)
                    }
                }
                Text(detail)
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(WK.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WK.Palette.canvas.opacity(0.6), in: .rect(cornerRadius: WK.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
                .stroke(WK.Palette.ink(0.12), lineWidth: 1)
        }
    }
}

/// El cristal de una opción, que se va al contestarla.
private struct OptionGlass: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.adaptiveGlassInteractive(in: .capsule)
        } else {
            content
        }
    }
}

/// **Lo que dice el armario de ti**: cuántas prendas, qué estilo y qué
/// colores. El estilo es una lectura sencilla de lo que hay —deportivo si
/// abundan zapatillas y sudaderas, elegante si camisas y americanas,
/// minimalista si casi todo es neutro, casual si no—: una etiqueta simpática,
/// no un diagnóstico.
struct ClosetStats {
    let count: Int
    let style: String
    let colors: [Color]

    init(garments: [(subcategory: String?, kind: GarmentKind, colors: [NamedColor])]) {
        count = garments.count

        // Los colores más repetidos, con su color de verdad.
        var weights: [String: Double] = [:]
        var samples: [String: NamedColor] = [:]
        for colour in garments.flatMap(\.colors) {
            weights[colour.nameKey, default: 0] += colour.weight
            samples[colour.nameKey] = samples[colour.nameKey] ?? colour
        }
        let top = weights.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(5)
        colors = top.compactMap { samples[$0.key] }.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }

        let words = garments.compactMap { $0.subcategory?.lowercased() }
        func share(_ keys: [String]) -> Double {
            guard !words.isEmpty else { return 0 }
            return Double(words.filter { word in keys.contains { word.contains($0) } }.count) / Double(words.count)
        }
        let sporty = share(["hoodie", "sudadera", "sneaker", "zapatilla", "jogger", "chándal", "legging", "deport", "sport", "tank", "tirantes"])
        let smart = share(["blazer", "americana", "shirt", "camisa", "traje", "suit", "oxford", "loafer", "mocas", "derby", "abrigo", "coat"])
        let neutralKeys = ["negro", "black", "blanco", "white", "gris", "grey", "gray", "beige", "crema", "cream", "marino", "navy", "camel", "arena"]
        let neutral = top.isEmpty ? 0 : Double(top.filter { entry in neutralKeys.contains { entry.key.lowercased().contains($0) } }.count) / Double(top.count)
        if sporty >= 0.3 && sporty >= smart {
            style = String(localized: "stats.style.sporty", defaultValue: "Sporty")
        } else if smart >= 0.3 {
            style = String(localized: "stats.style.smart", defaultValue: "Smart")
        } else if neutral >= 0.6 {
            style = String(localized: "stats.style.minimal", defaultValue: "Minimal")
        } else {
            style = String(localized: "stats.style.casual", defaultValue: "Casual")
        }
    }
}

/// La tarjeta de cristal con las tres cifras, como un resumen de tu armario.
private struct ClosetStatsCard: View {
    let stats: ClosetStats

    var body: some View {
        // **Solo los colores, centrados**. Las prendas y el estilo, fuera; lo
        // de antes, con las tres columnas:
        // HStack(spacing: 0) {
        //     column(label: String(localized: "stats.pieces", defaultValue: "pieces found")) {
        //         Text("\(stats.count)")
        //             .font(.system(size: 28, weight: .bold, design: .rounded))
        //             .foregroundStyle(NumberInk.gradient(.denim))
        //             .monospacedDigit()
        //     }
        //     Divider().frame(height: 44)
        //     column(label: String(localized: "stats.style", defaultValue: "your style")) {
        //         Text(stats.style)
        //             .font(.system(size: 24, weight: .bold, design: .rounded))
        //             .foregroundStyle(WK.Palette.primaryText)
        //             .lineLimit(1)
        //             .minimumScaleFactor(0.7)
        //     }
        //     Divider().frame(height: 44)
        //     column(label: String(localized: "stats.colors", defaultValue: "main colors")) {
        //         HStack(spacing: -8) {
        //             ForEach(Array(stats.colors.enumerated()), id: \.offset) { _, colour in
        //                 Circle()
        //                     .fill(colour)
        //                     .frame(width: 24, height: 24)
        //                     .overlay(Circle().stroke(.white, lineWidth: 1.5))
        //             }
        //         }
        //         .frame(height: 34)
        //     }
        // }
        column(label: String(localized: "stats.colors", defaultValue: "main colors")) {
            HStack(spacing: -8) {
                ForEach(Array(stats.colors.enumerated()), id: \.offset) { _, colour in
                    Circle()
                        .fill(colour)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            .frame(height: 36)
        }
        .padding(.horizontal, WK.Spacing.xl)
        .padding(.vertical, WK.Spacing.m)
        .adaptiveGlass(in: .rect(cornerRadius: WK.Radius.large, style: .continuous))
    }

    private func column(label: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(spacing: 4) {
            value()
            Text(label)
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

/// El velo detrás del texto del escaneo: un desenfoque redondo que se apaga
/// hacia los bordes, sin forma que se note.
private struct ScanTextVeil: View {
    let isCentered: Bool

    var body: some View {
        GeometryReader { proxy in
            Ellipse()
                .fill(.ultraThinMaterial)
                .mask {
                    RadialGradient(
                        colors: [.black, .black.opacity(0.85), .clear],
                        center: .center, startRadius: 0, endRadius: proxy.size.width * 0.55
                    )
                }
                .frame(width: proxy.size.width * 1.1, height: isCentered ? proxy.size.height * 0.62 : proxy.size.height * 0.42)
                .position(x: proxy.size.width / 2, y: proxy.size.height * (isCentered ? 0.5 : 0.3))
                .animation(.smooth(duration: 0.8), value: isCentered)
        }
        .ignoresSafeArea()
    }
}
