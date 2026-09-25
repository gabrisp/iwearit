import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence
import WKScanning
import WKServices
import WKVision

/// Pide el permiso de fotos **después** de explicar para qué.
///
/// Un diálogo del sistema en frío se acepta alrededor del 40% de las veces; uno
/// precedido de contexto, bastante más. Y solo hay una oportunidad: si el
/// usuario deniega, ya solo queda mandarle a Ajustes.
struct PhotoPermissionStep: View {
    let model: OnboardingModel
    @State private var isRequesting = false
    private let photos = PhotoLibraryService()

    var body: some View {
        OnboardingStepScaffold(
            title: String(localized: "onboarding.onboardingscansteps.yourClothesAreAlreadyNin", defaultValue: "Your clothes are already\nin your photos"),
            subtitle: String(localized: "onboarding.onboardingscansteps.snazzyLooksThroughThemOn", defaultValue: "Snazzy looks through them on your iPhone to cut out the clothes you're wearing."),
            primaryTitle: String(localized: "onboarding.onboardingscansteps.letItLookAtMy", defaultValue: "Let it look at my photos"),
            isEnabled: !isRequesting,
            onPrimary: { request() }
        ) {
            VStack(alignment: .leading, spacing: WK.Spacing.m) {
                PermissionPoint(
                    symbol: "iphone.gen3",
                    tone: .denim,
                    title: String(localized: "onboarding.onboardingscansteps.itAllHappensOnYour2", defaultValue: "It all happens on your iPhone"),
                    detail: String(localized: "onboarding.onboardingscansteps.yourPhotosArenTUploaded", defaultValue: "Your photos aren't uploaded anywhere.")
                )
                PermissionPoint(
                    symbol: "hand.raised",
                    tone: .salvia,
                    title: String(localized: "onboarding.onboardingscansteps.youChooseHowMuch", defaultValue: "You choose how much"),
                    detail: String(localized: "onboarding.onboardingscansteps.youCanGiveItAccess", defaultValue: "You can give it access to only the photos you want.")
                )
                PermissionPoint(
                    symbol: "scissors",
                    tone: .camel,
                    title: String(localized: "onboarding.onboardingscansteps.onlyTheClothesAreSaved", defaultValue: "Only the clothes are saved"),
                    detail: String(localized: "onboarding.onboardingscansteps.facesAndSkinAreDiscarded", defaultValue: "Faces and skin are discarded; they never reach your closet.")
                )
            }
            .padding(.top, WK.Spacing.m)
        }
    }

    private func request() {
        isRequesting = true
        Task {
            let access = await photos.requestAuthorization()
            isRequesting = false
            // Aunque deniegue se sigue: el armario funciona importando fotos
            // sueltas, y bloquear aquí sería perder al usuario del todo.
            _ = access
            model.advance()
        }
    }
}

private struct PermissionPoint: View {
    let symbol: String
    let tone: OnboardingTone
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: WK.Spacing.m) {
            // Image(systemName: symbol)
            //     .font(.title3)
            //     .foregroundStyle(WK.Palette.accent)
            //     .frame(width: 28)
            ToneIcon(symbol, tone: tone, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(WK.Palette.secondaryText)
            }
        }
    }
}

/// El escaneo de verdad.
///
/// Es a la vez el "momento de procesado" del guion de conversión y el trabajo
/// real: mientras el usuario mira los recortes aparecer, el armario se está
/// llenando. Por eso es la pantalla que más justifica el flujo entero.
struct ScanningStep: View {
    let model: OnboardingModel

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @State private var progress = ScanProgress()
    // @State private var discoveries: [ScanDiscovery] = []
    /// El montón de fotos y la colección. Ver `ScanStageModel`.
    @State private var stage = ScanStageModel()
    @State private var scanner: GalleryScanner?
    @State private var isPreparing = false
    @State private var hasFinished = false

    /// Las prendas que van saliendo, en el orden en que salen.
    @State private var pieces: [ScanCloud.Item] = []

    /// **Buscando, en el lienzo**: arriba el título y el contador, que sube;
    /// debajo, las prendas posándose alrededor del centro según aparecen. Sin
    /// barra ni fotos: lo que importa es lo que sale.
    var body: some View {
        ZStack(alignment: .top) {
            ScanCloud(pieces: pieces)
                .ignoresSafeArea()

            VStack(spacing: WK.Spacing.xs) {
                HStack {
                    Spacer()
                    Button { finish() } label: {
                        Text(String(localized: "onboarding.onboardingscansteps.skip", defaultValue: "Skip"))
                            .font(WK.Font.captionMedium)
                            .foregroundStyle(WK.Palette.primaryText)
                            .padding(.horizontal, WK.Spacing.m)
                            .padding(.vertical, WK.Spacing.s)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .adaptiveGlassInteractive(in: .capsule)
                }
                Text(isPreparing
                     ? String(localized: "onboarding.onboardingscansteps.gettingRecognitionReady", defaultValue: "Getting recognition ready")
                     : String(localized: "onboarding.onboardingscansteps.lookingForYourClothes", defaultValue: "Looking for your clothes"))
                    .font(WK.Font.title)
                    .foregroundStyle(WK.Palette.primaryText)
                    .contentTransition(.opacity)
                Text("\(pieces.count)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(WK.Palette.primaryText)
                    .contentTransition(.numericText(value: Double(pieces.count)))
                    .monospacedDigit()
                Text(pieces.count == 1
                     ? String(localized: "scan.piece", defaultValue: "piece")
                     : String(localized: "scan.pieces", defaultValue: "pieces"))
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.secondaryText)
                if let reason = progress.pauseReason {
                    Label(reason, systemImage: "thermometer.medium")
                        .font(.caption)
                        .foregroundStyle(WK.Palette.secondaryText)
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WK.Spacing.xl)
            // **Un velo fino debajo del texto**: las prendas que pasan por
            // detrás se desenfocan un poco, sin un borde duro. Como la barra
            // de arriba de iOS.
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask {
                        LinearGradient(
                            stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6), .init(color: .clear, location: 1)],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea(edges: .top)
            }
            .animation(.smooth(duration: 0.4), value: pieces.count)
            .animation(WKAnimation.content, value: isPreparing)

            VStack {
                Spacer()
                Label(String(localized: "onboarding.onboardingscansteps.itAllHappensOnYour", defaultValue: "It all happens on your iPhone · keep the app open"), systemImage: "lock.fill")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.tertiaryText)
                    .padding(.bottom, WK.Spacing.m)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: pieces.count)
        .task { await run() }
    }

    // La pantalla de antes: el montón de fotos soltando prendas, con barra.
    // var body: some View {
    //     VStack(spacing: WK.Spacing.m) {
    //         HStack {
    //             Spacer()
    //             // Cristal interactivo, como el resto de botones del
    //             // onboarding. Antes: texto gris suelto.
    //             // Button("Saltar") { finish() }
    //             //     .font(.subheadline)
    //             //     .foregroundStyle(WK.Palette.secondaryText)
    //             Button { finish() } label: {
    //                 Text(String(localized: "onboarding.onboardingscansteps.skip", defaultValue: "Skip"))
    //                     .font(WK.Font.captionMedium)
    //                     .foregroundStyle(WK.Palette.primaryText)
    //                     .padding(.horizontal, WK.Spacing.m)
    //                     .padding(.vertical, WK.Spacing.s)
    //                     .contentShape(.capsule)
    //             }
    //             .buttonStyle(.plain)
    //             .adaptiveGlassInteractive(in: .capsule)
    //         }

    //         VStack(spacing: WK.Spacing.xs) {
    //             Text(isPreparing ? String(localized: "onboarding.onboardingscansteps.gettingRecognitionReady", defaultValue: "Getting recognition ready") : String(localized: "onboarding.onboardingscansteps.lookingForYourClothes", defaultValue: "Looking for your clothes"))
    //                 .font(.system(.title, weight: .bold))
    //                 .multilineTextAlignment(.center)
    //                 .contentTransition(.opacity)
    //             Text(statusLine)
    //                 .font(.subheadline)
    //                 .foregroundStyle(WK.Palette.secondaryText)
    //                 .monospacedDigit()
    //                 .contentTransition(.numericText())

    //             // Cuánto queda, siempre a la vista: con miles de fotos, sin
    //             // barra parece que no avanza.
    //             OnboardingProgressBar(
    //                 step: progress.photosProcessed,
    //                 total: max(1, progress.totalPhotos)
    //             )
    //             .frame(maxWidth: 220)
    //             .padding(.top, WK.Spacing.xs)
    //             .opacity(isPreparing ? 0 : 1)
    //         }
    //         .animation(WKAnimation.content, value: isPreparing)

    //         // Tus fotos, en un montón, soltando las prendas.
    //         ScanPhotoStack(model: stage)
    //             .frame(maxHeight: .infinity)

    //         ScanCollection(model: stage)

    //         if let reason = progress.pauseReason {
    //             Label(reason, systemImage: "thermometer.medium")
    //                 .font(.caption)
    //                 .foregroundStyle(WK.Palette.secondaryText)
    //         }

    //         Label(String(localized: "onboarding.onboardingscansteps.itAllHappensOnYour", defaultValue: "It all happens on your iPhone · keep the app open"), systemImage: "lock.fill")
    //             .font(WK.Font.caption)
    //             .foregroundStyle(WK.Palette.tertiaryText)
    //     }
    //     .padding(.horizontal, WK.Spacing.screenInset)
    //     .padding(.bottom, WK.Spacing.m)
    //     .task { await run() }
    // }

    // La pantalla de antes: barra de progreso y recortes sueltos cayendo.
    // var body: some View {
    //     VStack(spacing: WK.Spacing.l) {
    //         HStack {
    //             Spacer()
    //             Button("Saltar") { finish() }
    //                 .font(.subheadline)
    //                 .foregroundStyle(WK.Palette.secondaryText)
    //         }

    //         VStack(spacing: WK.Spacing.s) {
    //             Text(isPreparing ? "Preparando el reconocimiento" : "Mirando tus fotos")
    //                 .font(.system(.title, weight: .bold))
    //                 .multilineTextAlignment(.center)
    //                 .contentTransition(.opacity)
    //             Text(statusLine)
    //                 .font(.subheadline)
    //                 .foregroundStyle(WK.Palette.secondaryText)
    //                 .monospacedDigit()
    //                 .contentTransition(.numericText())
    //         }
    //         .animation(WKAnimation.content, value: isPreparing)

    //         OnboardingProgressBar(step: progress.photosProcessed, total: max(1, progress.totalPhotos))

    //         DiscoveryWall(discoveries: discoveries)
    //             .frame(maxHeight: .infinity)

    //         if let reason = progress.pauseReason {
    //             Label(reason, systemImage: "thermometer.medium")
    //                 .font(.caption)
    //                 .foregroundStyle(WK.Palette.secondaryText)
    //         }

    //         VStack(spacing: WK.Spacing.xs) {
    //             Label("Nada sale de tu iPhone", systemImage: "lock.fill")
    //                 .font(WK.Font.captionMedium)
    //                 .foregroundStyle(WK.Palette.secondaryText)
    //             Text("Tus fotos se analizan aquí mismo. No se suben a ningún servidor, ni las fotos ni los recortes.")
    //                 .font(WK.Font.caption)
    //                 .foregroundStyle(WK.Palette.tertiaryText)
    //                 .multilineTextAlignment(.center)
    //             Text("Mantén la app abierta mientras miramos")
    //                 .font(WK.Font.caption)
    //                 .foregroundStyle(WK.Palette.tertiaryText)
    //                 .padding(.top, WK.Spacing.xs)
    //         }
    //     }
    //     .padding(.horizontal, WK.Spacing.screenInset)
    //     .padding(.bottom, WK.Spacing.m)
    //     .task { await run() }
    // }

    private func run() async {
        #if DEBUG
        // `-fakeScan`: la pantalla con prendas del armario, una tras otra, sin
        // mirar la galería. Para ver la animación en el simulador.
        if ProcessInfo.processInfo.arguments.contains("-fakeScan") {
            let garments = (try? modelContext.fetch(FetchDescriptor<Garment>())) ?? []
            for garment in garments.prefix(24) {
                guard let image = try? await appEnvironment.imageStore.image(for: garment.normalizedImageKey, variant: .thumb) else { continue }
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.spring(duration: 0.6, bounce: 0.3)) { pieces.append(.init(image: image)) }
            }
            return
        }
        #endif
        // **Esperar al modelo antes de mirar una sola foto.**
        //
        // Sin esto el escaneo arrancaba con `segmenter == nil` —la descarga
        // tarda decenas de segundos y el onboarding llega aquí mucho antes— y
        // la galería entera se procesaba por la ruta degradada, que corta la
        // silueta de la persona en franjas por las articulaciones. El resultado
        // no eran prendas: eran trozos de foto. Y una vez guardados, el armario
        // queda lleno de basura que hay que borrar a mano.
        await waitForSegmenter()

        // La coreografía del montón de fotos, fuera: ya no se enseña.
        // async let showing: Void = stage.run()

        let scanner = GalleryScanner(
            pipeline: GarmentPipeline(
                segmenter: appEnvironment.segmenter,
                embedder: appEnvironment.embedder,
                promptBank: appEnvironment.promptBank,
                // Sin OCR en el escaneo masivo: son minutos por un dato que no
                // hace falta para enseñar la prenda.
                readsBrands: false,
                // Y aquí sí se descartan recibos, capturas y documentos: son
                // miles de fotos y la mayoría no tienen ropa.
                skipsUtilityImages: true
            ),
            imageStore: appEnvironment.imageStore,
            wardrobe: appEnvironment.wardrobe
        )
        self.scanner = scanner

        _ = await scanner.scan(
            // `nil` en Pro: la galería entera. El número lo decide el gate,
            // no esta pantalla.
            limit: appEnvironment.gate.scanPhotoLimit,
            // **Sin meter nada en el armario todavía.** Lo encontrado se
            // guarda como pendiente según aparece —así saltar el paso o cerrar
            // la app no lo pierde— y entra al armario lo que el usuario diga.
            inserts: false,
            // Con sesenta prendas distintas ya hay armario de sobra para
            // empezar. Seguir era dejar al usuario mirando cómo se repasan
            // años de fotos; lo demás se puede escanear luego desde el armario.
            // stopAfter: 60,
            stopAfter: 100,
            onProgress: { updated in
                Task { @MainActor in progress = updated }
            },
            // **En orden y esperando al hilo principal**: con un `Task`
            // suelto por aviso, el resultado de una foto podía llegar antes
            // que la propia foto. Son microsegundos; el escáner no lo nota.
            onLook: { look in
                await MainActor.run { stage.look(look) }
            },
            onDiscovery: { discovery in
                await MainActor.run {
                    stage.found(discovery)
                    withAnimation(.spring(duration: 0.6, bounce: 0.3)) { pieces.append(contentsOf: discovery.pieces.map(ScanCloud.Item.init)) }
                }
            }
        )

        // **Al menos diez prendas.** Si el último año no da para tanto, se
        // sigue por las fotos de antes hasta llegar.
        let minimum = 10
        let found = (try? modelContext.fetchCount(FetchDescriptor<PendingGarment>())) ?? pieces.count
        if found < minimum, !hasFinished {
            DiagnosticsLog.record("ESCANEO", "solo \(found) prendas en el último año: se sigue hacia atrás")
            _ = await scanner.scan(
                limit: appEnvironment.gate.scanPhotoLimit,
                inserts: false,
                stopAfter: minimum - found,
                searchesOlder: true,
                onProgress: { updated in
                    Task { @MainActor in progress = updated }
                },
                onDiscovery: { discovery in
                    await MainActor.run {
                        withAnimation(.spring(duration: 0.6, bounce: 0.3)) { pieces.append(contentsOf: discovery.pieces.map(ScanCloud.Item.init)) }
                    }
                }
            )
        }
        // Se deja terminar lo que está en pantalla: la última foto soltando
        // sus prendas es el final de la función, no algo que cortar.
        stage.scanFinished()
        // await showing
        try? await Task.sleep(for: .seconds(1.2))
        finish()
    }

    /// Espera a que la preparación de modelos termine, con un tope.
    ///
    /// El tope no es impaciencia: si no hay red, `prepareModels` puede tardar
    /// lo que tarde en fallar, y dejar al usuario mirando una barra parada sin
    /// explicación es peor que escanear en modo degradado avisando de ello.
    /// Qué se está haciendo ahora mismo, en una línea.
    private var statusLine: String {
        guard isPreparing else {
            // Antes de la primera cifra, algo que diga que ya está en marcha.
            if progress.totalPhotos == 0 { return String(localized: "onboarding.onboardingscansteps.lookingForYourMostRecent", defaultValue: "Looking for your most recent photos…") }
            return String(localized: "onboarding.onboardingscansteps.ofPhotos", defaultValue: "\(String(describing: progress.photosProcessed.formatted())) of \(String(describing: progress.totalPhotos.formatted())) photos")
        }
        return switch appEnvironment.modelState {
        case let .downloading(fraction): String(localized: "onboarding.onboardingscansteps.downloading", defaultValue: "Downloading · \(String(describing: Int(fraction * 100)))%")
        case .compiling: String(localized: "onboarding.onboardingscansteps.installingOnYourIphone", defaultValue: "Installing on your iPhone")
        // El paso que antes no se nombraba y era el más largo de todos: con
        // `computeUnits = .all` esto eran minutos con la pantalla quieta.
        case .loading: String(localized: "onboarding.onboardingscansteps.gettingTheModelReady", defaultValue: "Getting the model ready")
        default: String(localized: "onboarding.onboardingscansteps.oneMoment", defaultValue: "One moment")
        }
    }

    private func waitForSegmenter() async {
        guard !appEnvironment.hasSettledModels else { return }
        isPreparing = true
        defer { isPreparing = false }

        // Aquí sí merece esperar: son cientos de fotos y hacerlas todas con
        // la ruta barata llenaría el armario de recortes peores. Pero con
        // tope, y con la pantalla diciendo en qué va la descarga.
        let deadline = ContinuousClock.now.advanced(by: .seconds(60))
        while !appEnvironment.hasSettledModels, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func finish() {
        // **Una sola vez.** "Saltar" cancela la tarea, pero `run()` sigue
        // hasta el final y volvía a llamar aquí: el onboarding avanzaba dos
        // pasos de golpe y la revisión de lo encontrado no se llegaba a ver.
        guard !hasFinished else { return }
        hasFinished = true
        Task {
            // Lo encontrado ya está guardado como pendiente según salía: el
            // paso siguiente lo lee de ahí. Lo de antes:
            // model.harvest = await scanner?.harvest ?? []
            await scanner?.cancel()
            // Con algo encontrado, primero la pantalla de "+X prendas"; sin
            // nada, directo a la revisión, que ya lo dice.
            let found = (try? modelContext.fetchCount(FetchDescriptor<PendingGarment>())) ?? 0
            model.go(to: found > 0 ? .scanFound : .scanReview)
        }
    }
}

// Sustituido por `ScanPhotoStack` y `ScanCollection`.
// /// Los recortes apareciendo. Decorado, no inventario.
// private struct DiscoveryWall: View {
//     let discoveries: [ScanDiscovery]

//     var body: some View {
//         ZStack {
//             ForEach(Array(discoveries.enumerated()), id: \.offset) { index, discovery in
//                 Image(decorative: discovery.image.cgImage, scale: 1)
//                     .resizable()
//                     .scaledToFit()
//                     .frame(width: 90, height: 100)
//                     .rotationEffect(.degrees(Double((index * 37) % 24) - 12))
//                     .offset(
//                         x: CGFloat((index * 61) % 200) - 100,
//                         y: CGFloat((index * 43) % 220) - 110
//                     )
//                     .transition(.scale.combined(with: .opacity))
//             }
//         }
//         .animation(.spring(duration: 0.45, bounce: 0.3), value: discoveries.count)
//     }
// }

/// El resumen: lo que hemos encontrado, en números.
struct ScanSummaryStep: View {
    let model: OnboardingModel

    @Query private var garments: [Garment]

    var body: some View {
        OnboardingStepScaffold(
            title: String(localized: "onboarding.onboardingscansteps.yourClosetNowInside", defaultValue: "Your closet, now inside"),
            primaryTitle: String(localized: "onboarding.onboardingscansteps.seeMyCloset", defaultValue: "See my closet"),
            onPrimary: { model.advance() }
        ) {
            VStack(spacing: WK.Spacing.xl) {
                StatReveal(
                    // El número de verdad, sin tope: es lo que impresiona.
                    // value: "\(model.outfitIdeas(garmentCount: garments.count))+",
                    value: outfitCount.formatted(),
                    caption: String(localized: "onboarding.onboardingscansteps.possibleCombinations", defaultValue: "possible combinations"),
                    detail: String(localized: "onboarding.onboardingscansteps.allWithClothesYouAlready", defaultValue: "All with clothes you already own."),
                    tone: .denim
                )
                .padding(.top, WK.Spacing.l)

                HStack(spacing: WK.Spacing.xl) {
                    SummaryStat(value: "\(garments.count)", label: "prendas")
                    SummaryStat(value: topColourName, label: String(localized: "onboarding.onboardingscansteps.mainColor", defaultValue: "main color"))
                }
            }
        }
    }

    /// Arriba × abajo × calzado, más vestidos × calzado, con lo que hay.
    private var outfitCount: Int {
        func count(_ kinds: Set<GarmentKind>) -> Int { garments.filter { kinds.contains($0.kind) }.count }
        let tops = count([.upperBody, .outerLayer])
        let bottoms = count([.lowerBody])
        let dresses = count([.wholeBody])
        let shoes = max(1, count([.feet]))
        return max(1, tops * bottoms * shoes + dresses * shoes)
    }

    /// El color más repetido del armario.
    private var topColourName: String {
        var counts: [String: Double] = [:]
        for garment in garments {
            guard let colour = garment.dominantColor else { continue }
            counts[colour.nameKey, default: 0] += colour.weight
        }
        return counts.max { $0.value < $1.value }?.key ?? "—"
    }
}

private struct SummaryStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, weight: .bold))
                .foregroundStyle(WK.Palette.primaryText)
            Text(label)
                .font(.caption)
                .foregroundStyle(WK.Palette.secondaryText)
        }
    }
}

/// **Las prendas encontradas, posadas en el lienzo** alrededor del centro:
/// una espiral —cada una en su sitio, sin pisarse— que crece según llegan.
/// Cada una entra desde el centro y se asienta con un giro suyo.
struct ScanCloud: View {
    struct Item: Identifiable {
        let id = UUID()
        let image: CGImage
        init(image: CGImage) { self.image = image }
        init(_ piece: ScanDiscovery.Piece) { image = piece.image.cgImage }
    }

    let pieces: [Item]

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.58)
            let unit = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                    let spot = Self.spot(index, unit: unit)
                    Image(decorative: piece.image, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(width: spot.size, height: spot.size)
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                        .rotationEffect(.degrees(spot.tilt))
                        .position(x: center.x + spot.offset.width, y: center.y + spot.offset.height)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.3).combined(with: .opacity).combined(with: .offset(x: -spot.offset.width * 0.6, y: -spot.offset.height * 0.6)),
                            removal: .opacity
                        ))
                }
            }
        }
    }

    /// Dónde cae la n-ésima: ángulo de oro, cada vez un poco más lejos.
    private static func spot(_ index: Int, unit: CGFloat) -> (offset: CGSize, size: CGFloat, tilt: Double) {
        let golden = 137.508 * Double.pi / 180
        let angle = Double(index) * golden
        let radius = unit * (0.12 + 0.085 * sqrt(Double(index)))
        let size = max(64, unit * 0.26 - CGFloat(index) * 1.2)
        let tilt = Double((index * 37) % 24) - 12
        return (CGSize(width: cos(angle) * radius, height: sin(angle) * radius * 1.15), size, tilt)
    }
}
