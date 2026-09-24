import SwiftUI
import WKCore
import WKDesign
import WKScanning
import WKVision

/// El escaneo, contado con las fotos de verdad.
///
/// La gracia del onboarding es **impresionar**: tus fotos, pequeñas, en un
/// montón, y de cada una van saliendo las prendas —desde el sitio exacto en
/// el que estaban— hasta la colección de abajo, que no para de crecer. Las
/// fotos sin ropa, o con recortes que se ven mal, ni aparecen: ver
/// `GalleryScanner.isShowcaseQuality`.
///
/// ## El ritmo
///
/// El escáner encuentra fotos a su ritmo y esto las enseña al suyo: una cola,
/// y una coreografía por foto (llega al montón → se oscurece y salen las
/// prendas → vuelan abajo). Si la cola crece, la coreografía acelera; si crece
/// demasiado, las más viejas se cuentan pero no se enseñan. Lo que no puede
/// pasar es que la pantalla vaya diez fotos por detrás de la realidad.
@MainActor
@Observable
final class ScanStageModel {

    struct ShownPhoto: Identifiable {
        let id: String
        let photo: ImmutableImage
        /// Rotación fija en el montón, para que parezca un montón.
        let tilt: Double
        var phase: Phase = .analyzing

        enum Phase: Equatable {
            /// Se está mirando: barrido y "Analizando".
            case analyzing
            /// Ha dado prendas y esperan su turno para salir.
            case found
            /// Oscurecida, con las prendas encima.
            case revealed
            /// Las prendas ya han volado a la tira.
            case flown
            /// Mirada y sin nada.
            case empty
        }
    }

    struct Collected: Identifiable {
        let piece: ScanDiscovery.Piece
        var id: UUID { piece.id }
    }

    private(set) var stack: [ShownPhoto] = []
    /// **Todo** lo encontrado, lo último primero. Sin tope: el escaneo ya
    /// para solo al llegar a sus prendas (ver `stopAfter`), y la tira es
    /// justo el sitio donde se tiene que ver todo.
    private(set) var collected: [Collected] = []
    private(set) var garmentCount = 0
    private(set) var countsByKind: [GarmentKind: Int] = [:]
    /// Las piezas de cada foto, hasta que salen.
    private(set) var piecesByPhoto: [String: [ScanDiscovery.Piece]] = [:]

    private var reveals: [ScanDiscovery] = []
    private var isScanning = true
    /// Mientras una foto suelta sus prendas no entra otra encima: la taparía
    /// y el momento bueno no se vería.
    private var isRevealing = false
    private var lastLook: ContinuousClock.Instant?

    /// Fotos visibles en el montón.
    static let stackDepth = 4
    /// Entre dos fotos nuevas, como poco: más deprisa es un parpadeo.
    static let minimumLookInterval: Duration = .milliseconds(200)

    // MARK: - Lo que llega del escáner

    /// Una foto que se empieza a mirar: **al montón ya**.
    func look(_ look: ScanLook) {
        // Lo que seguía mirándose y no ha dado nada, ya está: sin ropa.
        markUnfoundAsEmpty()

        if isRevealing { return }
        if let lastLook, ContinuousClock.now - lastLook < Self.minimumLookInterval, !stack.isEmpty {
            return
        }
        lastLook = .now

        let tilt = Double((look.photoID.hashValue & 0xff) % 13) - 6
        withAnimation(.spring(duration: 0.42, bounce: 0.18)) {
            stack.append(ShownPhoto(id: look.photoID, photo: look.photo, tilt: tilt))
            trimStack()
        }
    }

    /// Una foto que ha dado prendas.
    func found(_ discovery: ScanDiscovery) {
        if let index = stack.firstIndex(where: { $0.id == discovery.photoID }) {
            stack[index].phase = .found
        }
        piecesByPhoto[discovery.photoID] = discovery.pieces
        reveals.append(discovery)
    }

    func scanFinished() {
        isScanning = false
        markUnfoundAsEmpty()
    }

    /// Combinaciones con lo encontrado: arriba × abajo × calzado, más
    /// vestidos × calzado. Sin tope: el número grande es justo lo que se
    /// quiere enseñar.
    var outfitCount: Int {
        let tops = (countsByKind[.upperBody] ?? 0) + (countsByKind[.outerLayer] ?? 0)
        let bottoms = countsByKind[.lowerBody] ?? 0
        let dresses = countsByKind[.wholeBody] ?? 0
        let shoes = max(1, countsByKind[.feet] ?? 0)
        return tops * bottoms * shoes + dresses * shoes
    }

    // MARK: - La coreografía

    /// Saca las prendas de cada foto, una foto tras otra, hasta que el
    /// escaneo acaba y no queda nada por sacar.
    func run() async {
        while !Task.isCancelled {
            guard !reveals.isEmpty else {
                if !isScanning { return }
                try? await Task.sleep(for: .milliseconds(80))
                continue
            }
            await reveal(reveals.removeFirst())
        }
    }

    private func reveal(_ discovery: ScanDiscovery) async {
        // Con cola, más rápido: la pantalla no puede ir por detrás.
        let pace = reveals.count >= 2 ? 0.55 : 1.0

        // Ya no está en el montón —llegaron otras encima y se cayó—: las
        // prendas van directas a la tira.
        guard stack.contains(where: { $0.id == discovery.photoID }) else {
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) { collect(discovery) }
            try? await Task.sleep(for: .seconds(0.2))
            return
        }

        isRevealing = true
        defer { isRevealing = false }

        // 1. Sube arriba del montón, si no lo estaba.
        withAnimation(.smooth(duration: 0.3 * pace)) {
            if let index = stack.firstIndex(where: { $0.id == discovery.photoID }) {
                let photo = stack.remove(at: index)
                stack.append(photo)
            }
        }
        try? await Task.sleep(for: .seconds(0.2 * pace))

        // 2. Se oscurece y las prendas salen de ella.
        setPhase(.revealed, of: discovery.photoID, animation: .smooth(duration: 0.3))
        try? await Task.sleep(for: .seconds(0.5 * pace))

        // 3. Vuelan a la tira.
        withAnimation(.smooth(duration: 0.45 * pace)) {
            setPhase(.flown, of: discovery.photoID, animation: nil)
            collect(discovery)
        }
        try? await Task.sleep(for: .seconds(0.3 * pace))
    }

    private func collect(_ discovery: ScanDiscovery) {
        collected.insert(contentsOf: discovery.pieces.map(Collected.init), at: 0)
        garmentCount += discovery.pieces.count
        for piece in discovery.pieces { countsByKind[piece.kind, default: 0] += 1 }
    }

    private func markUnfoundAsEmpty() {
        for index in stack.indices where stack[index].phase == .analyzing {
            withAnimation(.smooth(duration: 0.3)) { stack[index].phase = .empty }
        }
    }

    private func setPhase(_ phase: ShownPhoto.Phase, of id: String, animation: Animation?) {
        guard let index = stack.firstIndex(where: { $0.id == id }) else { return }
        if let animation {
            withAnimation(animation) { stack[index].phase = phase }
        } else {
            stack[index].phase = phase
        }
    }

    /// Fuera las de abajo del todo, pero **nunca** una que aún tiene prendas
    /// por soltar.
    private func trimStack() {
        while stack.count > Self.stackDepth,
              let index = stack.firstIndex(where: { $0.phase != .found && $0.phase != .revealed }) {
            stack.remove(at: index)
        }
    }
}

/// El montón de fotos.
struct ScanPhotoStack: View {
    let model: ScanStageModel

    var body: some View {
        ZStack {
            ForEach(Array(model.stack.enumerated()), id: \.element.id) { index, photo in
                let depth = model.stack.count - 1 - index
                ScanPhotoCard(
                    photo: photo,
                    pieces: model.piecesByPhoto[photo.id] ?? [],
                    isTop: depth == 0
                )
                    // Las de detrás, giradas y asomando: que se lea montón.
                    .rotationEffect(.degrees(depth == 0 ? photo.tilt * 0.3 : photo.tilt * 1.6))
                    .offset(x: depth == 0 ? 0 : CGFloat(photo.tilt) * 3, y: CGFloat(depth) * -8)
                    .scaleEffect(1 - CGFloat(depth) * 0.035)
                    .zIndex(Double(index))
                    // **Desde arriba**, como una foto que cae en el montón.
                    // Antes subían desde abajo y parecían salir de la nada.
                    .transition(
                        .asymmetric(
                            // insertion: .offset(y: 420).combined(with: .scale(scale: 0.8)),
                            insertion: .offset(y: -520).combined(with: .scale(scale: 0.92)),
                            removal: .opacity.combined(with: .scale(scale: 0.9))
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Una foto del montón, con sus prendas encima.
private struct ScanPhotoCard: View {
    let photo: ScanStageModel.ShownPhoto
    let pieces: [ScanDiscovery.Piece]
    let isTop: Bool

    private static let maxWidth: CGFloat = 230
    private static let maxHeight: CGFloat = 300

    private var size: CGSize {
        let image = photo.photo
        let aspect = CGFloat(image.width) / CGFloat(max(1, image.height))
        let width = min(Self.maxWidth, Self.maxHeight * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    private var isRevealed: Bool { photo.phase == .revealed || photo.phase == .flown }

    var body: some View {
        let size = size
        ZStack {
            Image(decorative: photo.photo.cgImage, scale: 1)
                .resizable()
                .frame(width: size.width, height: size.height)
                // Sin ropa: se apaga y se queda en gris. Se ha mirado, y se
                // ve que se ha mirado.
                .saturation(photo.phase == .empty ? 0 : 1)
                .opacity(photo.phase == .empty ? 0.55 : 1)
                // La foto se apaga y la prenda queda encima, a su tamaño y en
                // su sitio: es lo que hace que se lea "sale de la foto".
                .overlay {
                    Color.black.opacity(isRevealed && isTop ? 0.45 : 0)
                }
                .overlay {
                    if photo.phase == .analyzing && isTop {
                        ScanSweep()
                            .transition(.opacity)
                    }
                }
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .padding(5)
                .background(.white, in: .rect(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                .overlay(alignment: .bottom) {
                    if isTop && (photo.phase == .analyzing || photo.phase == .found) {
                        AnalyzingBadge()
                            .offset(y: 14)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }

            if isRevealed && isTop {
                ForEach(pieces) { piece in
                    ScanFlyingPiece(piece: piece, photoSize: size, flown: photo.phase == .flown)
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: photo.phase)
    }
}

/// El barrido de luz sobre la foto que se está mirando.
///
/// Un solo cambio de estado: el vaivén lo hace `repeatForever` en el
/// renderizador, no un `TimelineView` reevaluando la vista cada frame.
private struct ScanSweep: View {
    @State private var isAtBottom = false

    var body: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: proxy.size.height * 0.35)
            .offset(y: isAtBottom ? proxy.size.height : -proxy.size.height * 0.35)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) {
                isAtBottom = true
            }
        }
    }
}

/// "Analizando", debajo de la foto que se está mirando.
private struct AnalyzingBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            Text("Analizando")
                .font(WK.Font.captionMedium)
        }
        .foregroundStyle(WK.Palette.primaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .adaptiveGlass(in: .capsule)
    }
}

/// Una prenda saliendo de su foto y volando hacia abajo.
private struct ScanFlyingPiece: View {
    let piece: ScanDiscovery.Piece
    let photoSize: CGSize
    let flown: Bool

    private var rect: CGRect {
        let fallback = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        let unit = piece.sourceRect ?? fallback
        return CGRect(
            x: unit.minX * photoSize.width,
            y: unit.minY * photoSize.height,
            width: unit.width * photoSize.width,
            height: unit.height * photoSize.height
        )
    }

    var body: some View {
        let rect = rect
        Image(decorative: piece.image.cgImage, scale: 1)
            .resizable()
            .frame(width: rect.width, height: rect.height)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .position(x: rect.midX, y: rect.midY)
            .frame(width: photoSize.width, height: photoSize.height)
            .scaleEffect(flown ? 0.3 : 1.06)
            .offset(y: flown ? 300 : 0)
            .opacity(flown ? 0 : 1)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

/// Lo encontrado, abajo: los dos números y **una tira con todas las
/// prendas**, que se desliza de lado.
///
/// Antes era una rejilla de 150 pt recortada por abajo y con tope de 36: con
/// media pantalla vacía encima, las prendas se quedaban mordidas y las
/// primeras desaparecían. En una tira caben todas, a un tamaño en el que se
/// ven, y la última siempre entra por el principio.
struct ScanCollection: View {
    let model: ScanStageModel

    // private let columns = [GridItem(.adaptive(minimum: 38, maximum: 46), spacing: 6)]
    private static let tile: CGFloat = 84

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            HStack(spacing: WK.Spacing.xl) {
                counter(model.garmentCount, label: "prendas")
                counter(model.outfitCount, label: "outfits")
            }

            // LazyVGrid(columns: columns, spacing: 6) {
            //     ForEach(model.collected.reversed()) { item in
            //         Image(decorative: item.piece.image.cgImage, scale: 1)
            //             .resizable()
            //             .scaledToFit()
            //             .frame(height: 42)
            //             .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
            //             .transition(.scale(scale: 0.3).combined(with: .opacity))
            //     }
            // }
            // .frame(height: 150, alignment: .top)
            // .clipped()

            // **Sin tira abajo.** Las prendas se enseñan al acabar, todas y
            // desfilando: ver `ScanFoundStep`. Aquí se quedan los números.
            // ScrollView(.horizontal) {
            //     LazyHStack(spacing: WK.Spacing.s) {
            //         if model.collected.isEmpty {
            //             // Huecos esperando: se ve dónde van a caer.
            //             ForEach(0..<4, id: \.self) { index in
            //                 PlaceholderTile(size: Self.tile, index: index)
            //             }
            //         }
            //         ForEach(model.collected) { item in
            //             // La prenda con su recorte, sin caja: como en el
            //             // armario.
            //             Image(decorative: item.piece.image.cgImage, scale: 1)
            //                 .resizable()
            //                 .scaledToFit()
            //                 .frame(width: Self.tile, height: Self.tile)
            //                 .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
            //                 // Cae desde arriba, como las fotos.
            //                 .transition(
            //                     .offset(y: -60)
            //                         .combined(with: .scale(scale: 0.5))
            //                         .combined(with: .opacity)
            //                 )
            //         }
            //     }
            //     .padding(.vertical, WK.Spacing.s)
            // }
            // .contentMargins(.horizontal, WK.Spacing.screenInset, for: .scrollContent)
            // .scrollIndicators(.hidden)
            // // De borde a borde: la tira se sale del margen de la pantalla.
            // .padding(.horizontal, -WK.Spacing.screenInset)
            // .frame(height: Self.tile + WK.Spacing.m)
            // .animation(.spring(duration: 0.45, bounce: 0.2), value: model.collected.count)
        }
    }

    private func counter(_ value: Int, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value.formatted())
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(WK.Palette.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            Text(label)
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
        }
    }
}

/// Un hueco de la tira mientras no hay nada, latiendo.
private struct PlaceholderTile: View {
    let size: CGFloat
    let index: Int
    @State private var isBright = false

    var body: some View {
        RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
            .fill(WK.Palette.ink(isBright ? 0.09 : 0.04))
            .frame(width: size, height: size)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(Double(index) * 0.15)
                ) {
                    isBright = true
                }
            }
    }
}

#if DEBUG
/// Demo del escaneo con fotos inventadas. En el simulador la visión no corre,
/// así que sin esto la animación no se puede ver. Argumento `scan-demo`.
struct ScanStageDemo: View {
    @State private var stage = ScanStageModel()

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            Text("Buscando tu ropa").font(.system(.title, weight: .bold))
            ScanPhotoStack(model: stage).frame(maxHeight: .infinity)
            ScanCollection(model: stage)
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .background(WK.Palette.canvas.ignoresSafeArea())
        .task {
            async let showing: Void = stage.run()
            for index in 0..<24 {
                let discovery = Self.fakePhoto(index)
                stage.look(ScanLook(photoID: discovery.photoID, photo: discovery.photo))
                try? await Task.sleep(for: .seconds(0.4))
                // Una de cada tres, sin ropa.
                if index % 3 != 2 { stage.found(discovery) }
                try? await Task.sleep(for: .seconds(0.3))
            }
            stage.scanFinished()
            await showing
        }
    }

    /// Una "foto": fondo de color con una camiseta y un pantalón encima.
    static func fakePhoto(_ index: Int) -> ScanDiscovery {
        let width = 600, height = 800
        let hue = Double((index * 37) % 100) / 100
        let background = CGColor(red: 0.55 + 0.3 * hue, green: 0.6, blue: 0.5 + 0.2 * (1 - hue), alpha: 1)
        let top = CGColor(red: hue, green: 0.3, blue: 1 - hue, alpha: 1)
        let bottom = CGColor(red: 0.15, green: 0.2, blue: 0.35 + 0.3 * hue, alpha: 1)
        let topRect = CGRect(x: 170, y: 150, width: 260, height: 250)
        let bottomRect = CGRect(x: 200, y: 400, width: 200, height: 330)

        func draw(_ size: CGSize, _ body: (CGContext) -> Void) -> CGImage {
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            // Origen arriba a la izquierda, como `sourceRect`.
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            body(context)
            return context.makeImage()!
        }
        let photo = draw(CGSize(width: width, height: height)) { ctx in
            ctx.setFillColor(background); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.setFillColor(top); ctx.fill(topRect)
            ctx.setFillColor(bottom); ctx.fill(bottomRect)
        }
        func piece(_ rect: CGRect, _ color: CGColor, _ kind: GarmentKind) -> ScanDiscovery.Piece {
            let image = draw(rect.size) { ctx in
                ctx.setFillColor(color)
                ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: rect.size), cornerWidth: 24, cornerHeight: 24, transform: nil))
                ctx.fillPath()
            }
            return .init(
                image: ImmutableImage(image),
                sourceRect: CGRect(
                    x: rect.minX / Double(width), y: rect.minY / Double(height),
                    width: rect.width / Double(width), height: rect.height / Double(height)
                ),
                kind: kind
            )
        }
        return ScanDiscovery(
            photoID: "demo-\(index)",
            photo: ImmutableImage(photo),
            pieces: [piece(topRect, top, .upperBody), piece(bottomRect, bottom, .lowerBody)]
        )
    }
}
#endif
