import SwiftUI
import WKDesign

// MARK: - Las prendas de catálogo

/// Las doce prendas de catálogo del onboarding, recortadas. Ver
/// `Tools/generate_onboarding_catalog.py`. En orden: camisa de rayas,
/// tirantes, oxford, chaquetón, bermudas, pantalón negro, vaquero, jersey,
/// zapatillas, derby, gorra, bolso.
enum CatalogGarment {
    static let all = (1...12).map { String(format: "OnboardingGarment%02d", $0) }
    static func name(_ index: Int) -> String { all[index - 1] }
}

// MARK: - La prueba social

/// **"Nuestros usuarios sacan más de 1.000 combinaciones…"**: arriba las
/// prendas pasando como un carrusel, con la del centro destacada; debajo un
/// outfit, y **cada vez que una prenda pasa por el centro, la de su hueco en
/// el outfit cambia por ella** —un pantalón cambia el pantalón, una camiseta
/// la de arriba—, sin parar.
///
/// Todo sale del reloj: la posición del carrusel y qué hay en cada hueco se
/// calculan del instante, así no hay estado que se desincronice.
struct ProofVisual: View {
    @State private var start = Date()

    /// Los huecos del outfit y qué prendas caben en cada uno.
    private enum Slot: CaseIterable {
        case layer, top, bottom, accessory, shoes

        var garments: [Int] {
            switch self {
            case .layer: [4]
            case .top: [1, 2, 3, 8]
            case .bottom: [5, 6, 7]
            case .accessory: [11, 12]
            case .shoes: [9, 10]
            }
        }

        /// Dónde va en la tarjeta (0-1) y su caja máxima.
        var frame: (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
            switch self {
            case .layer: (0.30, 0.30, 0.44, 0.46)
            case .top: (0.72, 0.26, 0.36, 0.36)
            case .bottom: (0.38, 0.70, 0.30, 0.52)
            case .accessory: (0.73, 0.57, 0.26, 0.18)
            case .shoes: (0.72, 0.83, 0.30, 0.22)
            }
        }
    }

    /// Lo que avanza el carrusel, en puntos por segundo, y lo que ocupa cada
    /// prenda.
    private static let speed: CGFloat = 34
    private static let stride: CGFloat = 78

    var body: some View {
        TimelineView(.animation) { context in
            let travelled = CGFloat(context.date.timeIntervalSince(start)) * Self.speed
            let centred = Int((travelled / Self.stride).rounded())
            VStack(spacing: WK.Spacing.m) {
                carousel(travelled: travelled, centred: centred)
                    .frame(height: 76)
                    .padding(.horizontal, -WK.Spacing.screenInset)
                outfit(centred: centred)
                    .frame(height: 330)
                    .background(WK.Palette.ink(0.06), in: .rect(cornerRadius: WK.Radius.large, style: .continuous))
            }
        }
        .sensoryFeedback(.selection, trigger: Int((CGFloat(Date().timeIntervalSince(start)) * Self.speed / Self.stride).rounded()))
    }

    /// La prenda de la posición `k` del carrusel, que da vueltas a las doce.
    private static func garment(at k: Int) -> Int {
        ((k % 12) + 12) % 12 + 1
    }

    private func carousel(travelled: CGFloat, centred: Int) -> some View {
        GeometryReader { proxy in
            let middle = proxy.size.width / 2
            ZStack {
                ForEach((centred - 6)...(centred + 6), id: \.self) { k in
                    let x = middle + CGFloat(k) * Self.stride - travelled
                    let distance = min(1, abs(x - middle) / (Self.stride * 2))
                    Image(CatalogGarment.name(Self.garment(at: k)))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 54, height: 60)
                        // La del centro, grande y entera; las demás, atrás.
                        .scaleEffect(1.2 - 0.35 * distance)
                        .opacity(1 - 0.55 * distance)
                        .position(x: x, y: proxy.size.height / 2)
                }
            }
        }
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 40)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 40)
            }
        }
    }

    /// El outfit: en cada hueco, la última prenda suya que ha pasado por el
    /// centro.
    private func outfit(centred: Int) -> some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Slot.allCases, id: \.self) { slot in
                    let name = CatalogGarment.name(latest(of: slot, upTo: centred))
                    let frame = slot.frame
                    Image(name)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: proxy.size.width * frame.width, maxHeight: proxy.size.height * frame.height)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        .id(name)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .opacity.combined(with: AnyTransition(.blurReplace))
                        ))
                        .position(x: proxy.size.width * frame.x, y: proxy.size.height * frame.y)
                        .animation(.spring(duration: 0.5, bounce: 0.3), value: name)
                }
            }
        }
    }

    /// La última prenda de este hueco que ha pasado por el centro. Antes de
    /// que pase ninguna, la primera suya.
    private func latest(of slot: Slot, upTo centred: Int) -> Int {
        for k in Swift.stride(from: centred, through: centred - 12, by: -1) {
            let garment = Self.garment(at: k)
            if slot.garments.contains(garment) { return garment }
        }
        return slot.garments[0]
    }
}

// La de antes: la tira pasando sola y el outfit montándose una vez.
// /// **"Nuestros usuarios sacan más de 1.000 combinaciones…"**: las prendas
// /// desfilando en una tira, y debajo un outfit que se monta pieza a pieza.
// struct ProofVisual: View {
//     @State private var shown = 0
//
//     /// El outfit: chaquetón, jersey, pantalón, gorra y derby. Cada una en su
//     /// hueco de la tarjeta (0-1): centro y caja máxima, sin salirse.
//     private static let outfit: [(index: Int, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)] = [
//         (4, 0.30, 0.30, 0.44, 0.46),
//         (8, 0.72, 0.26, 0.36, 0.36),
//         (6, 0.38, 0.70, 0.30, 0.52),
//         (11, 0.73, 0.57, 0.26, 0.18),
//         (10, 0.72, 0.82, 0.30, 0.22),
//     ]
//
//     var body: some View {
//         VStack(spacing: WK.Spacing.m) {
//             GarmentStrip()
//                 .frame(height: 64)
//                 .padding(.horizontal, -WK.Spacing.screenInset)
//             GeometryReader { proxy in
//                 ZStack {
//                     ForEach(Array(Self.outfit.enumerated()), id: \.offset) { order, piece in
//                         if shown > order {
//                             Image(CatalogGarment.name(piece.index))
//                                 .resizable()
//                                 .scaledToFit()
//                                 .frame(maxWidth: proxy.size.width * piece.width, maxHeight: proxy.size.height * piece.height)
//                                 .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
//                                 .position(x: proxy.size.width * piece.x, y: proxy.size.height * piece.y)
//                                 .transition(.scale(scale: 0.7).combined(with: .opacity))
//                         }
//                     }
//                 }
//             }
//             .frame(height: 330)
//             .background(WK.Palette.ink(0.06), in: .rect(cornerRadius: WK.Radius.large, style: .continuous))
//         }
//         .task {
//             for step in 1...Self.outfit.count {
//                 try? await Task.sleep(for: .seconds(0.3))
//                 withAnimation(.spring(duration: 0.5, bounce: 0.3)) { shown = step }
//             }
//         }
//     }
// }
//
// /// Las doce prendas pasando sin fin, de derecha a izquierda.
// private struct GarmentStrip: View {
//     @State private var stretch: CGFloat = 0
//     private static let speed: CGFloat = 28
//
//     var body: some View {
//         Color.clear
//             .overlay(alignment: .leading) {
//                 TimelineView(.animation) { context in
//                     HStack(spacing: WK.Spacing.l) {
//                         row
//                             .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stretch = $0 + WK.Spacing.l }
//                         row
//                     }
//                     .fixedSize()
//                     .offset(x: offset(at: context.date))
//                 }
//             }
//             .mask {
//                 HStack(spacing: 0) {
//                     LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 36)
//                     Rectangle()
//                     LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 36)
//                 }
//             }
//     }
//
//     private var row: some View {
//         HStack(spacing: WK.Spacing.l) {
//             ForEach(CatalogGarment.all, id: \.self) { name in
//                 Image(name).resizable().scaledToFit().frame(width: 52, height: 60)
//             }
//         }
//     }
//
//     private func offset(at date: Date) -> CGFloat {
//         guard stretch > 0 else { return 0 }
//         return -(CGFloat(date.timeIntervalSinceReferenceDate) * Self.speed).truncatingRemainder(dividingBy: stretch)
//     }
// }

// MARK: - El escaneo, por pasos

/// Un paso de cómo funciona el escaneo: titular, una línea y su dibujo.
struct ExplainBlock: View {
    let page: Int
    let lineFont: Font

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            TypewriterText(text: title)
                .font(lineFont)
                .foregroundStyle(WK.Palette.primaryText)
            TypewriterText(text: detail)
                .font(WK.Font.callout)
                .foregroundStyle(WK.Palette.secondaryText)
            DelayedReveal(delay: Double(title.count + detail.count) * TypewriterText.perCharacter * 0.6 + 0.3) {
                switch page {
                case 0: PhotoGridVisual()
                case 1: SelfieReadVisual()
                default: ShelvesVisual()
                }
            }
            .padding(.top, WK.Spacing.s)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        switch page {
        case 0: String(localized: "chat.explain.fill.title", defaultValue: "We fill your closet with your photos")
        case 1: String(localized: "chat.explain.read.title", defaultValue: "Your iPhone reads every outfit")
        default: String(localized: "chat.explain.shelf.title", defaultValue: "Every piece goes to its shelf")
        }
    }

    private var detail: String {
        switch page {
        case 0: String(localized: "chat.explain.fill.detail", defaultValue: "We only look for photos of you and add every piece you're wearing.")
        case 1: String(localized: "chat.explain.read.detail", defaultValue: "It marks each piece right on your iPhone; your photos never leave it.")
        default: String(localized: "chat.explain.shelf.detail", defaultValue: "We cut it out, clean it up and keep it in your closet.")
        }
    }
}

/// **Tus fotos, y solo las tuyas**: una rejilla de fotos de todo —el coche,
/// la cena, el perro— y las tuyas se marcan una a una; las demás se apagan.
private struct PhotoGridVisual: View {
    @State private var marked = 0

    private enum Tile { case scene(String, Color), you(String, UnitPoint) }

    /// La rejilla, 5 × 4. Las "tuyas" son recortes del selfie y de la foto de
    /// la bienvenida.
    private static let tiles: [Tile] = [
        .scene("car.fill", Color(white: 0.18)), .you("OnboardingSelfie", .center), .scene("sun.horizon.fill", .orange),
        .scene("fork.knife", .brown), .scene("sportscourt.fill", .blue),
        .scene("dog.fill", Color(red: 0.8, green: 0.6, blue: 0.3)), .scene("desktopcomputer", Color(white: 0.25)),
        .scene("person.3.fill", Color(white: 0.3)), .scene("cat.fill", .gray), .you("OnboardingAfter", UnitPoint(x: 0.3, y: 0.5)),
        .scene("dumbbell.fill", Color(white: 0.35)), .scene("figure.run", Color(white: 0.6)),
        .scene("building.2.fill", .teal), .scene("laptopcomputer", .indigo), .you("OnboardingSelfie", UnitPoint(x: 0.5, y: 0.3)),
        .scene("mountain.2.fill", .cyan), .scene("cup.and.saucer.fill", .brown.opacity(0.7)),
        .scene("moon.stars.fill", Color(white: 0.15)), .you("OnboardingAfter", UnitPoint(x: 0.72, y: 0.5)), .scene("birthday.cake.fill", .pink),
    ]

    /// En qué orden se marcan las tuyas.
    private static var yours: [Int] {
        tiles.indices.filter { if case .you = tiles[$0] { true } else { false } }
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 5)
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(Array(Self.tiles.enumerated()), id: \.offset) { index, tile in
                tileView(tile, isMarked: isMarked(index))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(4)
        .background(.white, in: .rect(cornerRadius: WK.Radius.large, style: .continuous))
        .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
        .sensoryFeedback(.selection, trigger: marked)
        .task {
            try? await Task.sleep(for: .seconds(1.8))
            for step in 1...Self.yours.count {
                withAnimation(.spring(duration: 0.4, bounce: 0.4)) { marked = step }
                try? await Task.sleep(for: .seconds(0.45))
            }
        }
    }

    private func isMarked(_ index: Int) -> Bool {
        guard let order = Self.yours.firstIndex(of: index) else { return false }
        return order < marked
    }

    @ViewBuilder
    private func tileView(_ tile: Tile, isMarked: Bool) -> some View {
        switch tile {
        case let .scene(symbol, colour):
            ZStack {
                colour.opacity(0.85)
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.9))
            }
            // Lo que no eres tú se apaga según se marcan las tuyas.
            .opacity(marked > 0 ? 0.45 : 1)
        case let .you(name, anchor):
            GeometryReader { proxy in
                Image(name)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width * 2.4, height: proxy.size.height * 2.4)
                    .offset(x: -proxy.size.width * 1.4 * anchor.x, y: -proxy.size.height * 1.4 * anchor.y)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .clipped()
                    .background(Color(white: 0.9))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 3).stroke(.white, lineWidth: isMarked ? 3 : 0)
            }
            .overlay(alignment: .bottomTrailing) {
                if isMarked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .padding(3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}

/// **Cómo se lee un outfit**: el selfie, y encima un recuadro de puntos por
/// prenda con su nombre, apareciendo uno a uno.
private struct SelfieReadVisual: View {
    @State private var shown = 0

    /// Dónde está cada prenda en el selfie (0-1).
    private static let boxes: [(label: String, rect: CGRect)] = [
        (String(localized: "chat.explain.tops", defaultValue: "Tops"), CGRect(x: 0.30, y: 0.27, width: 0.42, height: 0.29)),
        (String(localized: "chat.explain.bottoms", defaultValue: "Bottoms"), CGRect(x: 0.36, y: 0.52, width: 0.30, height: 0.16)),
        (String(localized: "chat.explain.shoes", defaultValue: "Shoes"), CGRect(x: 0.33, y: 0.79, width: 0.35, height: 0.12)),
    ]

    var body: some View {
        let width: CGFloat = 210
        let height = width * 16 / 9
        ZStack(alignment: .topLeading) {
            Image("OnboardingSelfie")
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
            ForEach(Array(Self.boxes.enumerated()), id: \.offset) { index, box in
                if shown > index {
                    let rect = CGRect(x: box.rect.minX * width, y: box.rect.minY * height,
                                      width: box.rect.width * width, height: box.rect.height * height)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .transition(.opacity.combined(with: .scale(scale: 1.08)))
                    HStack(spacing: 4) {
                        Circle().fill(WK.Palette.primaryText).frame(width: 5, height: 5)
                        Text(box.label).font(WK.Font.captionMedium).foregroundStyle(WK.Palette.primaryText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.92), in: .capsule)
                    .offset(x: rect.minX + 4, y: rect.minY - 12)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous).stroke(.white, lineWidth: 4)
        }
        .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
        .rotationEffect(.degrees(-2.5))
        .sensoryFeedback(.selection, trigger: shown)
        .task {
            try? await Task.sleep(for: .seconds(1.8))
            for step in 1...Self.boxes.count {
                withAnimation(.spring(duration: 0.45, bounce: 0.3)) { shown = step }
                try? await Task.sleep(for: .seconds(0.6))
            }
        }
    }
}

/// **Cada prenda a su balda**: tres baldas —tops, pantalones, zapatos— y las
/// prendas llegando a la suya una a una.
private struct ShelvesVisual: View {
    @State private var shown = 0

    private static let shelves: [(label: String, garments: [Int])] = [
        (String(localized: "chat.explain.tops", defaultValue: "Tops"), [1, 2, 3]),
        (String(localized: "chat.explain.bottoms", defaultValue: "Bottoms"), [5, 6, 7]),
        (String(localized: "chat.explain.shoes", defaultValue: "Shoes"), [9, 10]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.shelves.enumerated()), id: \.offset) { row, shelf in
                VStack(alignment: .leading, spacing: WK.Spacing.xs) {
                    HStack(spacing: 2) {
                        Text(shelf.label.lowercased()).font(WK.Font.callout)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(WK.Palette.secondaryText)
                    HStack(spacing: WK.Spacing.m) {
                        ForEach(Array(shelf.garments.enumerated()), id: \.offset) { column, garment in
                            let order = Self.shelves[..<row].reduce(0) { $0 + $1.garments.count } + column
                            ZStack {
                                if shown > order {
                                    Image(CatalogGarment.name(garment))
                                        .resizable()
                                        .scaledToFit()
                                        .transition(.scale(scale: 0.5).combined(with: .opacity).combined(with: .offset(y: -20)))
                                }
                            }
                            .frame(width: 62, height: 62)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                if row < Self.shelves.count - 1 {
                    Rectangle().fill(WK.Palette.ink(0.08)).frame(height: 1)
                }
            }
        }
        .frame(width: 250)
        .background(WK.Palette.ink(0.04), in: .rect(cornerRadius: WK.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous).stroke(.white, lineWidth: 4)
        }
        .shadow(color: .black.opacity(0.1), radius: 14, y: 8)
        .sensoryFeedback(.selection, trigger: shown)
        .task {
            try? await Task.sleep(for: .seconds(1.8))
            let total = Self.shelves.reduce(0) { $0 + $1.garments.count }
            for step in 1...total {
                withAnimation(.spring(duration: 0.45, bounce: 0.3)) { shown = step }
                try? await Task.sleep(for: .seconds(0.22))
            }
        }
    }
}

/// **Aparece después, sin mover nada**: ocupa su sitio desde el principio
/// —así el scroll se mueve una sola vez— y se ve cuando el texto de encima ya
/// se ha dicho.
struct DelayedReveal<Content: View>: View {
    let delay: Double
    @ViewBuilder let content: Content
    @State private var isShown = false

    var body: some View {
        content
            .opacity(isShown ? 1 : 0)
            .blur(radius: isShown ? 0 : 10)
            .offset(y: isShown ? 0 : 14)
            .task {
                try? await Task.sleep(for: .seconds(delay))
                withAnimation(.smooth(duration: 0.7)) { isShown = true }
            }
    }
}
