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
        let discovery: ScanDiscovery
        /// Rotación fija en el montón, para que parezca un montón.
        let tilt: Double
        var revealed = false
        var flown = false
        var id: UUID { discovery.id }
    }

    struct Collected: Identifiable {
        let piece: ScanDiscovery.Piece
        var id: UUID { piece.id }
    }

    private(set) var stack: [ShownPhoto] = []
    private(set) var collected: [Collected] = []
    private(set) var garmentCount = 0
    private(set) var countsByKind: [GarmentKind: Int] = [:]

    private var queue: [ScanDiscovery] = []
    private var isScanning = true
    private var shownPhotos = 0

    /// Fotos visibles en el montón.
    static let stackDepth = 5
    /// Prendas visibles abajo. Las demás se cuentan.
    static let collectionDepth = 36
    /// Cola máxima: más allá, las más viejas se cuentan sin enseñarse.
    static let queueLimit = 6

    func enqueue(_ discovery: ScanDiscovery) {
        queue.append(discovery)
        if queue.count > Self.queueLimit {
            let dropped = queue.removeFirst()
            count(dropped.pieces)
        }
    }

    func scanFinished() { isScanning = false }

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

    /// Enseña la cola hasta que el escaneo acaba y no queda nada.
    func run() async {
        while !Task.isCancelled {
            guard !queue.isEmpty else {
                if !isScanning { return }
                try? await Task.sleep(for: .milliseconds(120))
                continue
            }
            let next = queue.removeFirst()
            await show(next)
        }
    }

    private func show(_ discovery: ScanDiscovery) async {
        // Con cola, más rápido: la pantalla no puede ir por detrás.
        let pace = queue.count >= 3 ? 0.5 : 1.0
        shownPhotos += 1
        let tilt = Double((shownPhotos * 47) % 13) - 6

        // 1. Llega al montón.
        withAnimation(.spring(duration: 0.55 * pace, bounce: 0.25)) {
            stack.append(ShownPhoto(discovery: discovery, tilt: tilt))
            if stack.count > Self.stackDepth { stack.removeFirst() }
        }
        try? await Task.sleep(for: .seconds(0.5 * pace))

        // 2. Se oscurece y las prendas salen de ella.
        update(discovery.id) { $0.revealed = true }
        try? await Task.sleep(for: .seconds(0.75 * pace))

        // 3. Vuelan a la colección.
        withAnimation(.smooth(duration: 0.5 * pace)) {
            update(discovery.id, animated: false) { $0.flown = true }
            collected.append(contentsOf: discovery.pieces.map(Collected.init))
            if collected.count > Self.collectionDepth {
                collected.removeFirst(collected.count - Self.collectionDepth)
            }
            count(discovery.pieces)
        }
        try? await Task.sleep(for: .seconds(0.45 * pace))
    }

    private func count(_ pieces: [ScanDiscovery.Piece]) {
        garmentCount += pieces.count
        for piece in pieces { countsByKind[piece.kind, default: 0] += 1 }
    }

    private func update(_ id: UUID, animated: Bool = true, _ change: (inout ShownPhoto) -> Void) {
        guard let index = stack.firstIndex(where: { $0.id == id }) else { return }
        if animated {
            withAnimation(.smooth(duration: 0.4)) { change(&stack[index]) }
        } else {
            change(&stack[index])
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
                ScanPhotoCard(photo: photo, isTop: depth == 0)
                    // Las de detrás, giradas y asomando: que se lea montón.
                    .rotationEffect(.degrees(depth == 0 ? photo.tilt * 0.3 : photo.tilt * 1.6))
                    .offset(x: depth == 0 ? 0 : CGFloat(photo.tilt) * 3, y: CGFloat(depth) * -8)
                    .scaleEffect(1 - CGFloat(depth) * 0.035)
                    .zIndex(Double(index))
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: 420).combined(with: .scale(scale: 0.8)),
                            removal: .opacity
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
    let isTop: Bool

    private static let maxWidth: CGFloat = 230
    private static let maxHeight: CGFloat = 300

    private var size: CGSize {
        let image = photo.discovery.photo
        let aspect = CGFloat(image.width) / CGFloat(max(1, image.height))
        let width = min(Self.maxWidth, Self.maxHeight * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    var body: some View {
        let size = size
        ZStack {
            Image(decorative: photo.discovery.photo.cgImage, scale: 1)
                .resizable()
                .frame(width: size.width, height: size.height)
                // La foto se apaga y la prenda queda encima, a su tamaño y en
                // su sitio: es lo que hace que se lea "sale de la foto".
                .overlay {
                    Color.black.opacity(photo.revealed && isTop ? 0.45 : 0)
                }
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .padding(5)
                .background(.white, in: .rect(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)

            if photo.revealed && isTop {
                ForEach(photo.discovery.pieces) { piece in
                    ScanFlyingPiece(piece: piece, photoSize: size, flown: photo.flown)
                }
            }
        }
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
            .scaleEffect(flown ? 0.25 : 1.06)
            .offset(y: flown ? 330 : 0)
            .opacity(flown ? 0 : 1)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

/// Lo encontrado, abajo, creciendo. Y los dos números que importan.
struct ScanCollection: View {
    let model: ScanStageModel

    private let columns = [GridItem(.adaptive(minimum: 38, maximum: 46), spacing: 6)]

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            HStack(spacing: WK.Spacing.xl) {
                counter(model.garmentCount, label: "prendas")
                counter(model.outfitCount, label: "outfits")
            }

            LazyVGrid(columns: columns, spacing: 6) {
                // Lo último, primero: arriba y a la vista, no cortado por abajo.
                ForEach(model.collected.reversed()) { item in
                    Image(decorative: item.piece.image.cgImage, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 42)
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .frame(height: 150, alignment: .top)
            .clipped()
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
                stage.enqueue(Self.fakePhoto(index))
                try? await Task.sleep(for: .seconds(index < 6 ? 1.6 : 0.6))
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
            photo: ImmutableImage(photo),
            pieces: [piece(topRect, top, .upperBody), piece(bottomRect, bottom, .lowerBody)]
        )
    }
}
#endif
