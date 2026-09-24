import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Lo encontrado, **antes de elegir**: "+X prendas, más de N outfits", con
/// todas las prendas desfilando en varias filas.
///
/// El escaneo enseña foto a foto; aquí se ve el armario entero de golpe, que
/// es el momento que hace que valga la pena lo de antes. Después viene elegir
/// qué se guarda. Las prendas salen de lo pendiente, así que es lo mismo que
/// se va a elegir.
struct ScanFoundStep: View {
    let model: OnboardingModel

    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: [SortDescriptor(\PendingGarment.foundAt, order: .reverse)])
    private var pending: [PendingGarment]

    var body: some View {
        OnboardingStepScaffold(
            title: String(localized: "onboarding.scanfoundstep.pieces", defaultValue: "+\(String(describing: pending.count.formatted())) pieces"),
            subtitle: subtitle,
            primaryTitle: String(localized: "onboarding.scanfoundstep.chooseWhichToKeep", defaultValue: "Choose which to keep"),
            onPrimary: { model.advance() }
        ) {
            // **Por encima y no dentro del paso**: las filas son más anchas
            // que la pantalla —tienen que serlo para desfilar—, y metidas en
            // el paso lo ensanchaban entero, botón incluido. En un `overlay`
            // se dibujan de borde a borde sin tocar el tamaño de nada.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    GarmentMarquee(
                        keys: pending.map(\.imageKey),
                        store: appEnvironment.imageStore
                    )
                    .padding(.horizontal, -WK.Spacing.screenInset)
                }
        }
    }

    private var subtitle: String {
        let outfits = outfitCount
        guard outfits > 0 else {
            return String(localized: "onboarding.scanfoundstep.asSoonAsYouHave", defaultValue: "As soon as you have something for the bottom, the outfits begin.")
        }
        return String(localized: "onboarding.scanfoundstep.youCanMakeMoreThan", defaultValue: "You can make more than \(String(describing: outfits.formatted())) outfits with them.")
    }

    /// Arriba × abajo × calzado, más vestidos × calzado.
    private var outfitCount: Int {
        func count(_ kinds: Set<GarmentKind>) -> Int { pending.filter { kinds.contains($0.kind) }.count }
        let tops = count([.upperBody, .outerLayer])
        let bottoms = count([.lowerBody])
        let dresses = count([.wholeBody])
        let shoes = max(1, count([.feet]))
        return tops * bottoms * shoes + dresses * shoes
    }
}

/// Las prendas desfilando en varias filas, sin fin, cada fila a su ritmo y
/// en sentido contrario a la de al lado.
private struct GarmentMarquee: View {
    let keys: [String]
    let store: ImageStore

    /// Cuántas filas, según cuánto hay: con pocas prendas, cuatro filas son
    /// la misma camiseta cuatro veces.
    private var rows: [[String]] {
        guard !keys.isEmpty else { return [] }
        let count = keys.count >= 24 ? 4 : keys.count >= 8 ? 3 : 2
        var result = Array(repeating: [String](), count: count)
        for (index, key) in keys.enumerated() { result[index % count].append(key) }
        // Cada fila con bastantes para llenar el ancho y dar la vuelta.
        return result.map { row in
            guard !row.isEmpty else { return keys }
            var filled = row
            while filled.count < 8 { filled += row }
            return filled
        }
    }

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                MarqueeRow(
                    keys: row,
                    store: store,
                    isReversed: index.isMultiple(of: 2) == false,
                    speed: [26, 34, 22, 30][index % 4]
                )
            }
        }
        .frame(maxHeight: .infinity)
        // Se desvanecen al entrar y al salir por los lados.
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 40)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 40)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Una fila: el mismo tramo dos veces seguidas, desplazándose lo que mide un
/// tramo y vuelta a empezar. Como el segundo es igual al primero, el salto no
/// se ve.
///
/// **Con `TimelineView` y no con `repeatForever`.** La animación infinita no
/// llegaba a arrancar dentro de la pantalla —la transacción del paso de
/// página se la comía— y las filas se quedaban quietas. Calculando la
/// posición a partir del reloj en cada fotograma no hay nada que arrancar:
/// se mueve siempre. Son pocas imágenes por fila, y solo se recoloca la fila.
private struct MarqueeRow: View {
    let keys: [String]
    let store: ImageStore
    let isReversed: Bool
    /// Puntos por segundo.
    let speed: CGFloat

    @State private var stretch: CGFloat = 0

    private static let spacing: CGFloat = WK.Spacing.m
    private static let side: CGFloat = 92

    var body: some View {
        // El hueco de la fila lo pone un `Color.clear` del ancho disponible;
        // la tira, más ancha, va encima y no cuenta para el tamaño.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: Self.side)
            .overlay(alignment: .leading) {
                TimelineView(.animation) { context in
                    HStack(spacing: Self.spacing) {
                        stretchView
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                                guard width > 0 else { return }
                                stretch = width + Self.spacing
                            }
                        stretchView
                    }
                    .fixedSize()
                    .offset(x: offset(at: context.date))
                }
            }
    }

    /// Cuánto se ha desplazado la fila en este instante: de 0 a un tramo, y
    /// vuelta a empezar.
    private func offset(at date: Date) -> CGFloat {
        guard stretch > 0 else { return 0 }
        let travelled = CGFloat(date.timeIntervalSinceReferenceDate) * speed
        let phase = travelled.truncatingRemainder(dividingBy: stretch)
        return isReversed ? phase - stretch : -phase
    }

    private var stretchView: some View {
        HStack(spacing: Self.spacing) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                StoredImage(key: key, variant: .thumb, store: store)
                    .frame(width: Self.side, height: Self.side)
                    .shadow(color: .black.opacity(0.14), radius: 6, y: 4)
            }
        }
    }
}
