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

    /// Cuántas cosas se han dicho ya: el título, la explicación y los tres
    /// puntos van apareciendo uno tras otro.
    @State private var shown = 0

    /// **Como la conversación**: todo centrado, cada texto apareciendo letra
    /// a letra desenfocado, sin iconos de color.
    var body: some View {
        VStack(spacing: WK.Spacing.xl) {
            Spacer(minLength: 0)
            VStack(spacing: WK.Spacing.m) {
                TypewriterText(text: String(localized: "onboarding.onboardingscansteps.yourClothesAreAlreadyNin", defaultValue: "Your clothes are already\nin your photos"))
                    .font(WK.Font.largeTitle)
                    .foregroundStyle(WK.Palette.primaryText)
                if shown >= 1 {
                    TypewriterText(text: String(localized: "onboarding.onboardingscansteps.snazzyLooksThroughThemOn", defaultValue: "Snazzy looks through them on your iPhone to cut out the clothes you're wearing."))
                        .font(WK.Font.callout)
                        .foregroundStyle(WK.Palette.secondaryText)
                }
            }
            .multilineTextAlignment(.center)

            VStack(spacing: WK.Spacing.l) {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    if shown >= index + 2 {
                        CalmPoint(symbol: point.symbol, title: point.title, detail: point.detail)
                            .transition(.opacity.combined(with: .offset(y: 12)))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .onboardingButton(
            String(localized: "onboarding.onboardingscansteps.letItLookAtMy", defaultValue: "Let it look at my photos"),
            isEnabled: !isRequesting,
            action: { request() }
        )
        .task {
            guard shown == 0 else { return }
            try? await Task.sleep(for: .seconds(1.0))
            for step in 1...(points.count + 1) {
                withAnimation(.smooth(duration: 0.5)) { shown = step }
                try? await Task.sleep(for: .seconds(step == 1 ? 1.6 : 0.9))
            }
        }
    }

    private var points: [(symbol: String, title: String, detail: String)] {
        [
            ("iphone.gen3",
             String(localized: "onboarding.onboardingscansteps.itAllHappensOnYour2", defaultValue: "It all happens on your iPhone"),
             String(localized: "onboarding.onboardingscansteps.yourPhotosArenTUploaded", defaultValue: "Your photos aren't uploaded anywhere.")),
            ("hand.raised",
             String(localized: "onboarding.onboardingscansteps.youChooseHowMuch", defaultValue: "You choose how much"),
             String(localized: "onboarding.onboardingscansteps.youCanGiveItAccess", defaultValue: "You can give it access to only the photos you want.")),
            ("scissors",
             String(localized: "onboarding.onboardingscansteps.onlyTheClothesAreSaved", defaultValue: "Only the clothes are saved"),
             String(localized: "onboarding.onboardingscansteps.facesAndSkinAreDiscarded", defaultValue: "Faces and skin are discarded; they never reach your closet.")),
        ]
    }

    // El de antes, en la plantilla de siempre, con los puntos en fila y sus
    // iconos de color:
    // var body: some View {
    //     OnboardingStepScaffold(
    //         title: String(localized: "onboarding.onboardingscansteps.yourClothesAreAlreadyNin", defaultValue: "Your clothes are already\nin your photos"),
    //         subtitle: String(localized: "onboarding.onboardingscansteps.snazzyLooksThroughThemOn", defaultValue: "Snazzy looks through them on your iPhone to cut out the clothes you're wearing."),
    //         primaryTitle: String(localized: "onboarding.onboardingscansteps.letItLookAtMy", defaultValue: "Let it look at my photos"),
    //         isEnabled: !isRequesting,
    //         onPrimary: { request() }
    //     ) {
    //         VStack(alignment: .leading, spacing: WK.Spacing.m) {
    //             PermissionPoint(
    //                 symbol: "iphone.gen3",
    //                 tone: .denim,
    //                 title: String(localized: "onboarding.onboardingscansteps.itAllHappensOnYour2", defaultValue: "It all happens on your iPhone"),
    //                 detail: String(localized: "onboarding.onboardingscansteps.yourPhotosArenTUploaded", defaultValue: "Your photos aren't uploaded anywhere.")
    //             )
    //             PermissionPoint(
    //                 symbol: "hand.raised",
    //                 tone: .salvia,
    //                 title: String(localized: "onboarding.onboardingscansteps.youChooseHowMuch", defaultValue: "You choose how much"),
    //                 detail: String(localized: "onboarding.onboardingscansteps.youCanGiveItAccess", defaultValue: "You can give it access to only the photos you want.")
    //             )
    //             PermissionPoint(
    //                 symbol: "scissors",
    //                 tone: .camel,
    //                 title: String(localized: "onboarding.onboardingscansteps.onlyTheClothesAreSaved", defaultValue: "Only the clothes are saved"),
    //                 detail: String(localized: "onboarding.onboardingscansteps.facesAndSkinAreDiscarded", defaultValue: "Faces and skin are discarded; they never reach your closet.")
    //             )
    //         }
    //         .padding(.top, WK.Spacing.m)
    //     }
    // }

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

/// Un punto, centrado y sin color: el icono pequeño encima, y el texto
/// apareciendo como en la conversación.
private struct CalmPoint: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
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
    /// **Dentro de la conversación**: solo el lienzo, detrás del scroll. El
    /// título, el contador y lo encontrado los dice la conversación. Ver
    /// `ConversationStep`.
    var embedded = false
    /// Cuántas prendas lleva, para el contador de la conversación.
    var onCount: (Int) -> Void = { _ in }
    /// Terminado: prendas y combinaciones.
    var onFound: (_ pieces: Int, _ outfits: Int) -> Void = { _, _ in }

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
    /// La foto que se está mirando, en el centro del lienzo. Ver `ScanCloud`.
    @State private var photo: ScanCloud.Photo?
    /// Buscando, o ya encontrado: al acabar, la pantalla no cambia —es el
    /// mismo lienzo— y solo aparece la rueda de combinaciones.
    @State private var isFound = false
    /// Desde cuándo las prendas están abiertas al borde. Ver `ScanCloud`.
    @State private var spreadSince: Date?
    @State private var outfits = 0

    /// **Buscando, en el lienzo**: arriba el título y el contador, que sube;
    /// en el centro, la foto que se mira, y de ella se recortan las prendas y
    /// vuelan a posarse alrededor. Al terminar, en el mismo lienzo, la rueda
    /// con las combinaciones; las prendas se pueden mover con el dedo.
    var body: some View {
        ZStack(alignment: .top) {
            // Al encontrar, las prendas se abren a la pantalla entera y dejan
            // el centro para el mensaje.
            ScanCloud(pieces: pieces, photo: photo, spreadSince: spreadSince)
                .ignoresSafeArea()

            if isFound, !embedded {
                // **Centrado en la pantalla**, subiendo como la conversación.
                ScanFoundMessage(pieces: pieces.count, outfits: outfits)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .offset(y: 60)))
            }

            if !embedded {
            header
                .padding(.horizontal, WK.Spacing.screenInset)
                .padding(.bottom, WK.Spacing.xl)
                // **Un velo fino debajo del texto**: las prendas que pasan por
                // detrás se desenfocan un poco, sin un borde duro. Como la
                // barra de arriba de iOS.
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
                        .allowsHitTesting(false)
                }
                .animation(.smooth(duration: 0.4), value: pieces.count)
                .animation(WKAnimation.content, value: isPreparing)
                .animation(.smooth(duration: 0.6), value: isFound)
                // Con su velo: si se quedaba, las prendas de arriba se veían
                // borrosas.
                .opacity(isFound ? 0 : 1)
                .offset(y: isFound ? -40 : 0)
                .allowsHitTesting(!isFound)
            }

            if !isFound, !embedded {
                VStack {
                    Spacer()
                    Label(String(localized: "onboarding.onboardingscansteps.itAllHappensOnYour", defaultValue: "It all happens on your iPhone · keep the app open"), systemImage: "lock.fill")
                        .font(WK.Font.caption)
                        .foregroundStyle(WK.Palette.tertiaryText)
                        .padding(.bottom, WK.Spacing.m)
                }
                // El hueco del botón, que aquí no se ve, es suyo.
                .ignoresSafeArea(edges: .bottom)
                .padding(.bottom, WK.Spacing.xl)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: pieces.count)
        .modifier(ScanButton(isActive: !embedded, isFound: isFound, model: model))
        .onChange(of: pieces.count) { _, count in onCount(count) }
        .task { await run() }
        // Si la pantalla se va —atrás, o la conversación empieza de nuevo—,
        // el escáner para.
        .onDisappear { Task { await scanner?.cancel() } }
    }

    private var header: some View {
        VStack(spacing: WK.Spacing.xs) {
            // Sin "Saltar": el escaneo termina solo, con diez prendas.
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
                // .opacity(isFound ? 0 : 1)
                // .allowsHitTesting(!isFound)
                .opacity(0)
                .allowsHitTesting(false)
            }
            // **Como lo demás**: el título aparece letra a letra desenfocado,
            // y el contador con el degradado de las cifras.
            // Text(title)
            //     .font(WK.Font.title)
            //     .foregroundStyle(WK.Palette.primaryText)
            //     .contentTransition(.opacity)
            TypewriterText(text: title)
                .font(WK.Font.title)
                .foregroundStyle(WK.Palette.primaryText)
                .id(title)
            Text("\(pieces.count)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                // .foregroundStyle(WK.Palette.primaryText)
                .foregroundStyle(NumberInk.gradient(.denim))
                .contentTransition(.numericText(value: Double(pieces.count)))
                .monospacedDigit()
            Text(pieces.count == 1
                 ? String(localized: "scan.piece", defaultValue: "piece")
                 : String(localized: "scan.pieces", defaultValue: "pieces"))
                .font(WK.Font.callout)
                .foregroundStyle(WK.Palette.secondaryText)
            // Lo encontrado, de antes aquí arriba; ahora centrado, en
            // `ScanFoundMessage`.
            if false {
                // **Las combinaciones, con la rueda**, como las cifras de antes.
                if outfits > 0 {
                    Text(String(localized: "scan.found.moreThan", defaultValue: "and you can make more than"))
                        .font(WK.Font.callout)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .padding(.top, WK.Spacing.s)
                    NumberWheel(target: Double(outfits), format: { Int($0).formatted() }, tone: .denim, fontSize: 40)
                    Text(String(localized: "scan.found.outfits", defaultValue: "outfits"))
                        .font(WK.Font.callout)
                        .foregroundStyle(WK.Palette.secondaryText)
                } else {
                    Text(String(localized: "onboarding.scanfoundstep.asSoonAsYouHave", defaultValue: "As soon as you have something for the bottom, the outfits begin."))
                        .font(WK.Font.callout)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, WK.Spacing.s)
                }
            }
            if let reason = progress.pauseReason, !isFound {
                Label(reason, systemImage: "thermometer.medium")
                    .font(.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
            }
        }
    }

    private var title: String {
        if isFound { return String(localized: "scan.found.title", defaultValue: "We found") }
        return isPreparing
            ? String(localized: "onboarding.onboardingscansteps.gettingRecognitionReady", defaultValue: "Getting recognition ready")
            : String(localized: "onboarding.onboardingscansteps.lookingForYourClothes", defaultValue: "Looking for your clothes")
    }

    // El cuerpo de antes, sin la foto recortándose ni el final en el lienzo:
    // /// Las prendas que van saliendo, en el orden en que salen.
    // @State private var pieces: [ScanCloud.Item] = []
    //
    // /// **Buscando, en el lienzo**: arriba el título y el contador, que sube;
    // /// debajo, las prendas posándose alrededor del centro según aparecen. Sin
    // /// barra ni fotos: lo que importa es lo que sale.
    // var body: some View {
    //     ZStack(alignment: .top) {
    //         ScanCloud(pieces: pieces)
    //             .ignoresSafeArea()
    //
    //         VStack(spacing: WK.Spacing.xs) {
    //             HStack {
    //                 Spacer()
    //                 Button { finish() } label: {
    //                     Text(String(localized: "onboarding.onboardingscansteps.skip", defaultValue: "Skip"))
    //                         .font(WK.Font.captionMedium)
    //                         .foregroundStyle(WK.Palette.primaryText)
    //                         .padding(.horizontal, WK.Spacing.m)
    //                         .padding(.vertical, WK.Spacing.s)
    //                         .contentShape(.capsule)
    //                 }
    //                 .buttonStyle(.plain)
    //                 .adaptiveGlassInteractive(in: .capsule)
    //             }
    //             Text(isPreparing
    //                  ? String(localized: "onboarding.onboardingscansteps.gettingRecognitionReady", defaultValue: "Getting recognition ready")
    //                  : String(localized: "onboarding.onboardingscansteps.lookingForYourClothes", defaultValue: "Looking for your clothes"))
    //                 .font(WK.Font.title)
    //                 .foregroundStyle(WK.Palette.primaryText)
    //                 .contentTransition(.opacity)
    //             Text("\(pieces.count)")
    //                 .font(.system(size: 64, weight: .bold, design: .rounded))
    //                 .foregroundStyle(WK.Palette.primaryText)
    //                 .contentTransition(.numericText(value: Double(pieces.count)))
    //                 .monospacedDigit()
    //             Text(pieces.count == 1
    //                  ? String(localized: "scan.piece", defaultValue: "piece")
    //                  : String(localized: "scan.pieces", defaultValue: "pieces"))
    //                 .font(WK.Font.callout)
    //                 .foregroundStyle(WK.Palette.secondaryText)
    //             if let reason = progress.pauseReason {
    //                 Label(reason, systemImage: "thermometer.medium")
    //                     .font(.caption)
    //                     .foregroundStyle(WK.Palette.secondaryText)
    //             }
    //         }
    //         .padding(.horizontal, WK.Spacing.screenInset)
    //         .padding(.bottom, WK.Spacing.xl)
    //         // **Un velo fino debajo del texto**: las prendas que pasan por
    //         // detrás se desenfocan un poco, sin un borde duro. Como la barra
    //         // de arriba de iOS.
    //         .background {
    //             Rectangle()
    //                 .fill(.ultraThinMaterial)
    //                 .mask {
    //                     LinearGradient(
    //                         stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.6), .init(color: .clear, location: 1)],
    //                         startPoint: .top, endPoint: .bottom
    //                     )
    //                 }
    //                 .ignoresSafeArea(edges: .top)
    //         }
    //         .animation(.smooth(duration: 0.4), value: pieces.count)
    //         .animation(WKAnimation.content, value: isPreparing)
    //
    //         VStack {
    //             Spacer()
    //             Label(String(localized: "onboarding.onboardingscansteps.itAllHappensOnYour", defaultValue: "It all happens on your iPhone · keep the app open"), systemImage: "lock.fill")
    //                 .font(WK.Font.caption)
    //                 .foregroundStyle(WK.Palette.tertiaryText)
    //                 .padding(.bottom, WK.Spacing.m)
    //         }
    //     }
    //     .sensoryFeedback(.impact(weight: .light), trigger: pieces.count)
    //     .task { await run() }
    // }

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
        // `-fakeScan`: la pantalla con prendas del armario, recortándose de
        // una foto de muestra, sin mirar la galería. Para ver la animación en
        // el simulador.
        if ProcessInfo.processInfo.arguments.contains("-fakeScan") {
            let garments = (try? modelContext.fetch(FetchDescriptor<Garment>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
            let sample = UIImage(named: "OnboardingAfter")?.cgImage
            let spots = [CGRect(x: 0.18, y: 0.22, width: 0.3, height: 0.3), CGRect(x: 0.2, y: 0.52, width: 0.26, height: 0.36),
                         CGRect(x: 0.55, y: 0.2, width: 0.3, height: 0.32), CGRect(x: 0.56, y: 0.5, width: 0.26, height: 0.38)]
            var index = 0
            for pair in stride(from: 0, to: min(20, garments.count), by: 2) {
                var found: [ScanDiscovery.Piece] = []
                for garment in garments[pair..<min(pair + 2, garments.count)] {
                    guard let image = try? await appEnvironment.imageStore.image(for: garment.normalizedImageKey, variant: .thumb) else { continue }
                    found.append(.init(image: ImmutableImage(image), sourceRect: spots[index % spots.count], kind: garment.kind))
                    index += 1
                }
                guard let sample, !found.isEmpty else { continue }
                show(ScanLook(photoID: "\(pair)", photo: ImmutableImage(sample)))
                try? await Task.sleep(for: .milliseconds(700))
                await reveal(ScanDiscovery(photoID: "\(pair)", photo: ImmutableImage(sample), pieces: found))
                if hasFinished { return }
            }
            finish()
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

        // **Por tandas de 300 fotos, hasta tener diez prendas.** Antes se
        // miraban de golpe las del plan —o la galería entera en Pro— y luego,
        // si no llegaba, las de antes del último año. Ahora: 300; si no hay
        // diez prendas, otras 300; y así, primero el último año y después lo
        // anterior, hasta llegar o quedarse sin fotos.
        let batch = 300
        let minimum = 10
        search: for searchesOlder in [false, true] {
            var start = 0
            while !hasFinished {
                let result = await scanner.scan(
                    startIndex: start,
                    limit: batch,
                    // **Sin meter nada en el armario todavía.** Lo encontrado
                    // se guarda como pendiente según aparece —así saltar el
                    // paso o cerrar la app no lo pierde— y entra al armario lo
                    // que el usuario diga.
                    inserts: false,
                    stopAfter: 100,
                    searchesOlder: searchesOlder,
                    onProgress: { updated in
                        Task { @MainActor in progress = updated }
                    },
                    // **En orden y esperando al hilo principal**: con un
                    // `Task` suelto por aviso, el resultado de una foto podía
                    // llegar antes que la propia foto.
                    onLook: { look in
                        await show(look)
                    },
                    // Y esperando a que se vea el recorte entero: la foto se
                    // corta, las prendas vuelan, y después sigue.
                    onDiscovery: { discovery in
                        await reveal(discovery)
                    }
                )
                let found = (try? modelContext.fetchCount(FetchDescriptor<PendingGarment>())) ?? pieces.count
                if found >= minimum { break search }
                // Sin más fotos en esta franja: a la siguiente.
                if result.totalPhotos < start + batch { break }
                DiagnosticsLog.record("ESCANEO", "\(found) prendas tras \(start + batch) fotos: otra tanda")
                start += batch
            }
            if hasFinished { break }
        }
        // La foto que quedara en el centro, fuera.
        withAnimation(.smooth(duration: 0.4)) { photo = nil }
        // stage.scanFinished()
        // await showing
        try? await Task.sleep(for: .seconds(0.6))
        finish()
    }

    // MARK: La foto y sus recortes

    /// La foto que se está mirando, en el centro.
    @MainActor
    private func show(_ look: ScanLook) {
        // stage.look(look)
        guard !hasFinished else { return }
        withAnimation(.smooth(duration: 0.3)) {
            photo = ScanCloud.Photo(id: look.photoID, image: look.photo.cgImage)
        }
    }

    /// **La foto se recorta**: las prendas se levantan de donde estaban en
    /// ella, la foto se apaga, y las prendas vuelan a su sitio del lienzo.
    @MainActor
    private func reveal(_ discovery: ScanDiscovery) async {
        // stage.found(discovery)
        guard !hasFinished else { return }
        if photo?.id != discovery.photoID {
            withAnimation(.smooth(duration: 0.3)) {
                photo = ScanCloud.Photo(id: discovery.photoID, image: discovery.photo.cgImage)
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        let items = discovery.pieces.map(ScanCloud.Item.init)
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            pieces.append(contentsOf: items)
            photo?.isCut = true
        }
        try? await Task.sleep(for: .milliseconds(550))
        let ids = Set(items.map(\.id))
        withAnimation(.spring(duration: 0.8, bounce: 0.25)) {
            for index in pieces.indices where ids.contains(pieces[index].id) {
                pieces[index].isPlaced = true
            }
        }
        try? await Task.sleep(for: .milliseconds(250))
        // withAnimation(.smooth(duration: 0.4)) { photo = nil }
        withAnimation(.easeIn(duration: 0.45)) { photo = nil }
        try? await Task.sleep(for: .milliseconds(400))
        // La foto ya no está: vuelven a su capa, con las demás.
        for index in pieces.indices where ids.contains(pieces[index].id) {
            pieces[index].isFresh = false
        }
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

    /// Arriba × abajo × calzado, más vestidos × calzado. Lo mismo que
    /// `ScanFoundStep`.
    private static func outfitCount(_ kinds: [GarmentKind]) -> Int {
        func count(_ wanted: Set<GarmentKind>) -> Int { kinds.filter { wanted.contains($0) }.count }
        let tops = count([.upperBody, .outerLayer])
        let bottoms = count([.lowerBody])
        let dresses = count([.wholeBody])
        let shoes = max(1, count([.feet]))
        return tops * bottoms * shoes + dresses * shoes
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
            // let found = (try? modelContext.fetchCount(FetchDescriptor<PendingGarment>())) ?? 0
            // model.go(to: found > 0 ? .scanFound : .scanReview)
            // **"+X prendas" es este mismo lienzo**: no se pasa de página;
            // las prendas se quedan donde están y aparece la rueda.
            // Dentro de la conversación lo dice ella, haya o no.
            guard !pieces.isEmpty || embedded else {
                model.go(to: .scanReview)
                return
            }
            let pending = (try? modelContext.fetch(FetchDescriptor<PendingGarment>())) ?? []
            outfits = pending.isEmpty
                ? Self.outfitCount(pieces.map(\.kind))
                : Self.outfitCount(pending.map(\.kind))
            withAnimation(.smooth(duration: 0.4)) { photo = nil }
            spreadSince = .now
            withAnimation(.smooth(duration: 0.6)) { isFound = true }
            onFound(pieces.count, outfits)
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

    // **Sin las borradas**: ni en el borde, ni en la cuenta, ni en el color.
    // @Query private var garments: [Garment]
    @Query(filter: #Predicate<Garment> { $0.deletedAt == nil }) private var garments: [Garment]
    /// **Y lo encontrado por revisar**: sin la revisión en el onboarding, lo
    /// del escaneo sigue pendiente, y es lo que más se tiene que ver aquí.
    @Query(sort: [SortDescriptor(\PendingGarment.foundAt, order: .reverse)]) private var pending: [PendingGarment]
    @Environment(AppEnvironment.self) private var appEnvironment

    /// Las prendas del armario, en el borde del lienzo.
    @State private var pieces: [ScanCloud.Item] = []
    @State private var spreadSince = Date()

    /// **El mismo lienzo que el escaneo**: tus prendas por el borde de la
    /// pantalla —se pueden mover— y en el centro el armario ya dentro, con
    /// las combinaciones en la rueda.
    var body: some View {
        ZStack {
            // Las prendas ya no son de esta pantalla: las pinta el onboarding
            // una sola vez, debajo de esta y del paywall, para que al pasar de
            // una a otra no se muevan. Ver `OnboardingClosetCloud`.
            // ScanCloud(pieces: pieces, spreadSince: spreadSince, arrivesInPlace: true)
            //     .ignoresSafeArea()

            VStack(spacing: 2) {
                AuraText(String(localized: "onboarding.onboardingscansteps.yourClosetNowInside", defaultValue: "Your closet, now inside"), font: WK.Font.title)
                    .onboardingEntrance(0)
                NumberWheel(target: Double(outfitCount), format: { Int($0).formatted() }, tone: .denim, fontSize: 52)
                AuraText(String(localized: "onboarding.onboardingscansteps.possibleCombinations", defaultValue: "possible combinations"), font: WK.Font.title)
                    .onboardingEntrance(1)
                AuraText(String(localized: "onboarding.onboardingscansteps.allWithClothesYouAlready", defaultValue: "All with clothes you already own."), font: WK.Font.callout, isSecondary: true)
                    .padding(.top, WK.Spacing.s)
                    .onboardingEntrance(2)
                if topColourName != "—" {
                    AuraText("\(garments.count + pending.count) " + String(localized: "scan.pieces", defaultValue: "pieces") + " · " + String(localized: "onboarding.onboardingscansteps.mainColor", defaultValue: "main color") + " " + topColourName, font: WK.Font.callout, isSecondary: true)
                        .onboardingEntrance(3)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, WK.Spacing.xxl)
            .allowsHitTesting(false)
        }
        .onboardingButton(
            String(localized: "onboarding.onboardingscansteps.seeMyCloset", defaultValue: "See my closet"),
            action: { model.advance() }
        )
        // .task { await loadPieces() }
    }

    private func loadPieces() async {
        guard pieces.isEmpty else { return }
        // **Todas a la vez y ya en el borde**: vienen de estar colocadas en
        // el escaneo; salir otra vez del centro era repetir lo mismo.
        var loaded: [ScanCloud.Item] = []
        // Lo recién encontrado primero; después, lo que ya había.
        let sources = pending.map { ($0.imageKey, $0.kind) }
            + garments.filter { $0.deletedAt == nil }.map { ($0.normalizedImageKey, $0.kind) }
        for (key, kind) in sources.prefix(28) {
            guard let image = try? await appEnvironment.imageStore.image(for: key, variant: .thumb) else { continue }
            var item = ScanCloud.Item(image: image)
            item.kind = kind
            loaded.append(item)
        }
        withAnimation(.easeOut(duration: 0.5)) { pieces = loaded }
    }

    // El de antes, en la plantilla de siempre con las cifras en fila:
    // var body: some View {
    //     OnboardingStepScaffold(
    //         title: String(localized: "onboarding.onboardingscansteps.yourClosetNowInside", defaultValue: "Your closet, now inside"),
    //         primaryTitle: String(localized: "onboarding.onboardingscansteps.seeMyCloset", defaultValue: "See my closet"),
    //         onPrimary: { model.advance() }
    //     ) {
    //         VStack(spacing: WK.Spacing.xl) {
    //             StatReveal(
    //                 // El número de verdad, sin tope: es lo que impresiona.
    //                 // value: "\(model.outfitIdeas(garmentCount: garments.count))+",
    //                 value: outfitCount.formatted(),
    //                 caption: String(localized: "onboarding.onboardingscansteps.possibleCombinations", defaultValue: "possible combinations"),
    //                 detail: String(localized: "onboarding.onboardingscansteps.allWithClothesYouAlready", defaultValue: "All with clothes you already own."),
    //                 tone: .denim
    //             )
    //             .padding(.top, WK.Spacing.l)
    //
    //             HStack(spacing: WK.Spacing.xl) {
    //                 SummaryStat(value: "\(garments.count)", label: "prendas")
    //                 SummaryStat(value: topColourName, label: String(localized: "onboarding.onboardingscansteps.mainColor", defaultValue: "main color"))
    //             }
    //         }
    //     }
    // }

    /// Arriba × abajo × calzado, más vestidos × calzado, con lo que hay.
    private var outfitCount: Int {
        func count(_ kinds: Set<GarmentKind>) -> Int {
            garments.filter { $0.deletedAt == nil && kinds.contains($0.kind) }.count
                + pending.filter { kinds.contains($0.kind) }.count
        }
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
        // Con desempate por nombre: con dos colores igual de repetidos, el
        // diccionario daba uno u otro en cada pintada y el texto parpadeaba.
        // return counts.max { $0.value < $1.value }?.key ?? "—"
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? "—"
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
///
/// En el centro, la foto que se está mirando. Cuando da prendas, cada una
/// aparece **sobre la foto, donde estaba**, la foto se apaga como recortada,
/// y la prenda vuela a su sitio de la espiral. Las ya posadas se pueden mover
/// con el dedo.
struct ScanCloud: View {
    struct Item: Identifiable {
        let id = UUID()
        let image: CGImage
        /// Dónde estaba en la foto, 0-1. `nil`: sale del centro.
        var sourceRect: CGRect?
        var kind: GarmentKind = .other
        /// Ya en su sitio del lienzo, o todavía sobre la foto.
        var isPlaced = false
        /// Cuándo llegó: al abrirse al borde, cada una sale a su ritmo.
        var appearedAt = Date()
        /// **Recién sacada de la foto**: va por encima de la foto mientras
        /// vuela a su sitio. Antes, al empezar a volar, bajaba por debajo de
        /// la foto y parecía salir de detrás.
        var isFresh = false
        init(image: CGImage) { self.image = image; isPlaced = true }
        init(_ piece: ScanDiscovery.Piece) {
            isFresh = true
            image = piece.image.cgImage
            sourceRect = piece.sourceRect
            kind = piece.kind
        }
    }

    /// La foto del centro.
    struct Photo {
        let id: String
        let image: CGImage
        /// Ya recortada: apagada, con las prendas levantadas encima.
        var isCut = false
        var aspect: CGFloat { CGFloat(image.width) / CGFloat(max(1, image.height)) }
    }

    let pieces: [Item]
    var photo: Photo?
    /// Abiertas a la pantalla entera, alrededor de un hueco en el centro.
    // var isSpread = false
    /// Desde cuándo están abiertas al borde, girando despacio a su
    /// alrededor. `nil`: en la espiral del centro.
    var spreadSince: Date?
    private var isSpread: Bool { spreadSince != nil }

    /// **Ya en el borde, sin salir del centro**: para las pantallas que
    /// vienen después del escaneo, donde las prendas ya estaban colocadas.
    var arrivesInPlace = false

    /// **Un solo reloj para la vuelta**, compartido por todas las pantallas:
    /// al pasar de una a otra, las prendas siguen donde estaban en vez de
    /// volver a empezar.
    @MainActor static let orbitEpoch = Date()

    /// Cuánto tarda cada una en salir de la espiral al borde.
    private static let spreadDuration: TimeInterval = 1.8
    /// Lo que avanzan por el borde, en puntos por segundo.
    private static let orbitSpeed: CGFloat = 14

    /// Qué prenda va encima: la última que se ha tocado.
    @State private var front: [UUID: Double] = [:]

    var body: some View {
        // **Al borde, en marcha**: cada fotograma recoloca las prendas —van
        // dando la vuelta a la pantalla despacio y se mecen—. Por reloj y no
        // con animaciones: una animación y un cambio por fotograma se pisan.
        if let spreadSince {
            TimelineView(.animation) { context in
                canvas(at: context.date.timeIntervalSince(spreadSince), now: context.date)
            }
        } else {
            canvas(at: nil, now: .now)
        }
    }

    /// El lienzo en un instante: `elapsed` es el tiempo desde que se
    /// abrieron al borde, o `nil` si no.
    private func canvas(at elapsed: TimeInterval?, now: Date) -> some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.58)
            let middle = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.5)
            let unit = min(proxy.size.width, proxy.size.height)
            let frame = Self.photoFrame(photo, center: center, unit: unit)
            ZStack {
                if let photo {
                    Image(decorative: photo.image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: frame.width, height: frame.height)
                        .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
                        .wkShimmer(isActive: !photo.isCut)
                        .saturation(photo.isCut ? 0 : 1)
                        .opacity(photo.isCut ? 0.35 : 1)
                        .blur(radius: photo.isCut ? 2 : 0)
                        .scaleEffect(photo.isCut ? 0.96 : 1)
                        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
                        .position(x: frame.midX, y: frame.midY)
                        .id(photo.id)
                        // Llega creciendo; se va cayendo hacia abajo.
                        // .transition(.scale(scale: 0.85).combined(with: .opacity))
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.85).combined(with: .opacity),
                            // Hacia dentro de la pantalla: encoge y se
                            // desenfoca. Hacia abajo se veía cortada.
                            // removal: .offset(y: 320).combined(with: .opacity)
                            removal: .scale(scale: 0.45).combined(with: .opacity).combined(with: AnyTransition(.blurReplace))
                        ))
                        .zIndex(1000)
                }
                ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                    CloudPiece(
                        piece: piece,
                        // placed: isSpread
                        //     ? Self.spread(index, of: pieces.count, in: proxy.size)
                        //     : Self.spot(index, unit: unit),
                        placed: place(index, piece: piece, elapsed: elapsed, now: now, size: proxy.size, center: center, middle: middle, unit: unit),
                        center: elapsed == nil ? center : middle,
                        cutFrom: Self.cutRect(piece.sourceRect, in: frame),
                        onTouch: { front[piece.id] = (front.values.max() ?? 0) + 1 }
                    )
                    // Las que se están recortando, encima de la foto.
                    // .zIndex(piece.isPlaced ? (front[piece.id] ?? 0) : 2000)
                    .zIndex(piece.isFresh ? 2000 + (front[piece.id] ?? 0) : (front[piece.id] ?? 0))
                    .transition(.opacity)
                }
            }
        }
    }

    /// Dónde va cada prenda: en la espiral, en el borde, o a medio camino
    /// mientras sale —cada una un poco después de la anterior—.
    private func place(
        _ index: Int, piece: Item, elapsed: TimeInterval?, now: Date,
        size: CGSize, center: CGPoint, middle: CGPoint, unit: CGFloat
    ) -> (offset: CGSize, size: CGFloat, tilt: Double) {
        let spiral = Self.spot(index, unit: unit)
        guard let elapsed, let spreadSince else { return spiral }
        // let edge = Self.border(index, of: pieces.count, in: size, shift: CGFloat(elapsed) * Self.orbitSpeed)
        let edge = Self.border(index, of: pieces.count, in: size, shift: CGFloat(now.timeIntervalSince(Self.orbitEpoch)) * Self.orbitSpeed)
        let sway = sin(now.timeIntervalSince(Self.orbitEpoch) * 0.7 + Double(index) * 1.3) * 7
        if arrivesInPlace {
            return (edge.offset, edge.size, edge.tilt + sway)
        }
        // Desde que se abrió, o desde que llegó si llegó después.
        let start = max(spreadSince.addingTimeInterval(Double(index) * 0.06), piece.appearedAt)
        let raw = min(1, max(0, now.timeIntervalSince(start) / Self.spreadDuration))
        let t = raw < 0.5 ? 4 * raw * raw * raw : 1 - pow(-2 * raw + 2, 3) / 2
        // La espiral se mide desde otro centro: se pasa al de la pantalla.
        let from = CGSize(
            width: spiral.offset.width + center.x - middle.x,
            height: spiral.offset.height + center.y - middle.y
        )
        // Y se mecen un poco, cada una a su aire.
        // let sway = sin(elapsed * 0.7 + Double(index) * 1.3) * 7
        return (
            CGSize(
                width: from.width + (edge.offset.width - from.width) * t,
                height: from.height + (edge.offset.height - from.height) * t
            ),
            spiral.size + (edge.size - spiral.size) * t,
            spiral.tilt + (edge.tilt + sway - spiral.tilt) * t
        )
    }

    /// El marco de la foto en el centro, con su proporción.
    private static func photoFrame(_ photo: Photo?, center: CGPoint, unit: CGFloat) -> CGRect {
        let aspect = photo?.aspect ?? 0.75
        var width = unit * 0.5
        var height = width / aspect
        if height > unit * 0.66 {
            height = unit * 0.66
            width = height * aspect
        }
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    /// Dónde está la prenda sobre la foto, en la pantalla.
    private static func cutRect(_ source: CGRect?, in frame: CGRect) -> CGRect {
        guard let source else {
            return CGRect(x: frame.midX - frame.width * 0.2, y: frame.midY - frame.width * 0.2, width: frame.width * 0.4, height: frame.width * 0.4)
        }
        return CGRect(
            x: frame.minX + source.minX * frame.width,
            y: frame.minY + source.minY * frame.height,
            width: source.width * frame.width,
            height: source.height * frame.height
        )
    }

    /// **Por toda la pantalla**: la misma espiral de oro, pero estirada a lo
    /// ancho y alto de la pantalla y con un hueco en el centro, que es del
    /// mensaje.
    fileprivate static func spread(_ index: Int, of count: Int, in size: CGSize) -> (offset: CGSize, size: CGFloat, tilt: Double) {
        let golden = 137.508 * Double.pi / 180
        let angle = Double(index) * golden
        let reach = 0.5 + 0.5 * sqrt((Double(index) + 0.5) / Double(max(1, count)))
        let side = max(58, min(size.width, size.height) * 0.22 - CGFloat(count) * 0.4)
        let tilt = Double((index * 37) % 24) - 12
        return (
            CGSize(
                width: cos(angle) * reach * (size.width / 2 - side * 0.35),
                height: sin(angle) * reach * (size.height / 2 - side * 0.5)
            ),
            side, tilt
        )
    }

    /// **Por el borde de la pantalla** —arriba, abajo y a los lados—,
    /// repartidas a lo largo del contorno; si no caben en una vuelta, otra un
    /// poco más dentro. El centro queda libre para el mensaje.
    fileprivate static func border(_ index: Int, of count: Int, in size: CGSize, shift: CGFloat = 0) -> (offset: CGSize, size: CGFloat, tilt: Double) {
        let side = max(56, min(78, min(size.width, size.height) * 0.19 - CGFloat(count) * 0.2))
        let step = side * 1.05
        var ring = 0
        var position = index
        var capacity = 0
        var inset = side * 0.5
        // En qué vuelta cae y en qué puesto de esa vuelta.
        while true {
            let width = size.width - inset * 2
            let height = size.height - inset * 2
            capacity = max(4, Int((2 * (width + height)) / step))
            if position < capacity || width < side * 2 { break }
            position -= capacity
            ring += 1
            inset += side * 0.95
        }
        let width = size.width - inset * 2
        let height = size.height - inset * 2
        let perimeter = 2 * (width + height)
        let used = min(capacity, count - (index - position))
        // Repartidas por igual en su vuelta, cada vuelta un poco girada.
        // Y todas avanzando por el borde, dando la vuelta; cada vuelta en
        // un sentido.
        var along = (CGFloat(position) + 0.5 + CGFloat(ring) * 0.5) / CGFloat(max(1, used)) * perimeter
            + (ring.isMultiple(of: 2) ? shift : -shift)
        along = along.truncatingRemainder(dividingBy: perimeter)
        if along < 0 { along += perimeter }
        let point: CGPoint
        if along < width {
            point = CGPoint(x: inset + along, y: inset)
        } else if along < width + height {
            point = CGPoint(x: inset + width, y: inset + along - width)
        } else if along < 2 * width + height {
            point = CGPoint(x: inset + width - (along - width - height), y: inset + height)
        } else {
            point = CGPoint(x: inset, y: inset + height - (along - 2 * width - height))
        }
        let tilt = Double((index * 37) % 24) - 12
        return (CGSize(width: point.x - size.width / 2, height: point.y - size.height / 2), side, tilt)
    }

    /// Dónde cae la n-ésima: ángulo de oro, cada vez un poco más lejos.
    fileprivate static func spot(_ index: Int, unit: CGFloat) -> (offset: CGSize, size: CGFloat, tilt: Double) {
        let golden = 137.508 * Double.pi / 180
        let angle = Double(index) * golden
        // let radius = unit * (0.12 + 0.085 * sqrt(Double(index)))
        // let size = max(64, unit * 0.26 - CGFloat(index) * 1.2)
        let size = max(58, unit * 0.21 - CGFloat(index) * 1)
        let tilt = Double((index * 37) % 24) - 12
        // return (CGSize(width: cos(angle) * radius, height: sin(angle) * radius * 1.15), size, tilt)
        // **Lejos de la foto**: en un anillo por fuera de ella, que crece
        // despacio. Cerca del centro caían debajo de la foto siguiente.
        let growth = unit * 0.05 * sqrt(Double(index))
        let x = cos(angle) * (unit * 0.37 + growth)
        let y = sin(angle) * (unit * 0.5 + growth)
        // Sin salirse por los lados.
        let limit = unit / 2 - size * 0.3
        return (CGSize(width: max(-limit, min(limit, x)), height: y), size, tilt)
    }
}

/// Una prenda del lienzo: sobre la foto mientras se recorta, y en su sitio
/// después, donde se puede arrastrar.
private struct CloudPiece: View {
    let piece: ScanCloud.Item
    let placed: (offset: CGSize, size: CGFloat, tilt: Double)
    let center: CGPoint
    let cutFrom: CGRect
    let onTouch: () -> Void

    /// Lo que la ha movido el usuario.
    @State private var moved: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    @State private var isTouching = false
    /// Cuántas veces se ha soltado: la vuelta a su sitio es solo de la
    /// última.
    @State private var drops = 0

    var body: some View {
        let size = piece.isPlaced ? CGSize(width: placed.size, height: placed.size) : cutFrom.size
        let position = piece.isPlaced
            ? CGPoint(x: center.x + placed.offset.width + moved.width + drag.width,
                      y: center.y + placed.offset.height + moved.height + drag.height)
            : CGPoint(x: cutFrom.midX, y: cutFrom.midY)
        Image(decorative: piece.image, scale: 1)
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
            // Levantada de la foto: un poco más grande y con sombra.
            .scaleEffect(piece.isPlaced ? (drag == .zero ? 1 : 1.06) : 1.08)
            .shadow(color: .black.opacity(piece.isPlaced && drag == .zero ? 0.18 : 0.3), radius: piece.isPlaced ? 10 : 16, y: 6)
            .rotationEffect(.degrees(piece.isPlaced ? placed.tilt : 0))
            .position(position)
            .animation(.spring(duration: 0.3, bounce: 0.2), value: drag == .zero)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onChanged { _ in
                        guard !isTouching else { return }
                        isTouching = true
                        onTouch()
                    }
                    .onEnded { value in
                        isTouching = false
                        moved.width += value.translation.width
                        moved.height += value.translation.height
                        // **A los dos segundos, de vuelta a su sitio**: se
                        // juega con ellas, pero el lienzo no se desordena.
                        drops += 1
                        let drop = drops
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            // Si mientras tanto se ha vuelto a coger, espera a
                            // la siguiente vez que se suelte.
                            guard drop == drops, !isTouching else { return }
                            withAnimation(.spring(duration: 0.9, bounce: 0.25)) { moved = .zero }
                        }
                    },
                isEnabled: piece.isPlaced
            )
    }
}

/// **"Hemos encontrado 20 prendas, y puedes hacer más de 38 outfits"**, en el
/// centro del lienzo. Las dos partes suben una tras otra, como las frases de
/// la conversación; las letras llevan brillo y un halo del color del papel,
/// que las despega de las prendas de detrás.
private struct ScanFoundMessage: View {
    let pieces: Int
    let outfits: Int

    /// Qué se dice ahora: primero las prendas; luego eso sube y se va, y
    /// llegan las combinaciones.
    private enum Beat { case pieces, outfits }
    @State private var beat: Beat = .pieces

    var body: some View {
        ZStack {
            switch beat {
            case .pieces:
                VStack(spacing: 2) {
                    AuraText(String(localized: "scan.found.title", defaultValue: "We found"), font: WK.Font.title)
                    NumberWheel(target: Double(pieces), format: { Int($0).formatted() }, tone: .denim, fontSize: 52)
                    AuraText(pieces == 1
                             ? String(localized: "scan.piece", defaultValue: "piece")
                             : String(localized: "scan.pieces", defaultValue: "pieces"),
                             font: WK.Font.title)
                }
                .transition(Self.beatTransition)
            case .outfits:
                VStack(spacing: 2) {
                    if outfits > 0 {
                        AuraText(String(localized: "scan.found.moreThan", defaultValue: "and you can make more than"), font: WK.Font.title)
                        NumberWheel(target: Double(outfits), format: { Int($0).formatted() }, tone: .oliva, fontSize: 52)
                        AuraText(String(localized: "scan.found.outfits", defaultValue: "outfits"), font: WK.Font.title)
                    } else {
                        AuraText(String(localized: "onboarding.scanfoundstep.asSoonAsYouHave", defaultValue: "As soon as you have something for the bottom, the outfits begin."), font: WK.Font.title)
                    }
                }
                .transition(Self.beatTransition)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, WK.Spacing.xxl)
        // Lo de antes: las dos partes a la vez, con un velo redondo detrás.
        // .background { Ellipse().fill(.ultraThinMaterial)… }
        .task {
            // Lo que tarda la rueda en pararse, y un respiro para leerlo.
            try? await Task.sleep(for: .seconds(NumberWheel.duration + 1.4))
            withAnimation(.smooth(duration: 0.8)) { beat = .outfits }
        }
    }

    /// Entra desde abajo y se va por arriba, desenfocándose: como la
    /// conversación.
    private static let beatTransition = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 70)).combined(with: AnyTransition(.blurReplace)),
        removal: .opacity.combined(with: .offset(y: -70)).combined(with: AnyTransition(.blurReplace))
    )
}

/// Texto con brillo que lo recorre y un halo del papel alrededor.
struct AuraText: View {
    let text: String
    let font: Font
    var isSecondary = false

    init(_ text: String, font: Font, isSecondary: Bool = false) {
        self.text = text
        self.font = font
        self.isSecondary = isSecondary
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(isSecondary ? WK.Palette.secondaryText : WK.Palette.primaryText)
            .wkShimmer(isActive: true)
            .shadow(color: WK.Palette.canvas, radius: 6)
            .shadow(color: WK.Palette.canvas.opacity(0.8), radius: 16)
    }
}

/// El botón de "Elegir cuáles guardo" del escaneo suelto; dentro de la
/// conversación lo pone ella.
private struct ScanButton: ViewModifier {
    let isActive: Bool
    let isFound: Bool
    let model: OnboardingModel

    func body(content: Content) -> some View {
        if isActive {
            content.onboardingButton(isFound ? OnboardingButtonConfig(
                title: String(localized: "onboarding.scanfoundstep.chooseWhichToKeep", defaultValue: "Choose which to keep"),
                action: { model.go(to: .scanReview) }
            ) : nil)
        } else {
            content
        }
    }
}

/// **Tus prendas girando por el borde, debajo de "Tu armario" y del
/// paywall**: una sola capa para las dos pantallas. Cada una tenía la suya, y
/// al pasar de página la de salida subía y se desenfocaba mientras la nueva
/// aparecía: parecía que las prendas se movían.
struct OnboardingClosetCloud: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(filter: #Predicate<Garment> { $0.deletedAt == nil }) private var garments: [Garment]
    @Query(sort: [SortDescriptor(\PendingGarment.foundAt, order: .reverse)]) private var pending: [PendingGarment]
    @State private var pieces: [ScanCloud.Item] = []
    @State private var spreadSince = Date()

    var body: some View {
        ScanCloud(pieces: pieces, spreadSince: spreadSince, arrivesInPlace: true)
            .task {
                guard pieces.isEmpty else { return }
                var loaded: [ScanCloud.Item] = []
                // Lo recién encontrado primero; después, lo que ya había.
                let sources = pending.map { ($0.imageKey, $0.kind) }
                    + garments.map { ($0.normalizedImageKey, $0.kind) }
                for (key, kind) in sources.prefix(28) {
                    guard let image = try? await appEnvironment.imageStore.image(for: key, variant: .thumb) else { continue }
                    var item = ScanCloud.Item(image: image)
                    item.kind = kind
                    loaded.append(item)
                }
                withAnimation(.easeOut(duration: 0.5)) { pieces = loaded }
            }
    }
}
