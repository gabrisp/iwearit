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
            title: "+\(pending.count.formatted()) prendas",
            subtitle: subtitle,
            primaryTitle: "Elegir cuáles guardo",
            onPrimary: { model.advance() }
        ) {
            GarmentMarquee(
                keys: pending.map(\.imageKey),
                store: appEnvironment.imageStore
            )
            // De borde a borde: las filas entran y salen por los lados.
            .padding(.horizontal, -WK.Spacing.screenInset)
            .frame(maxHeight: .infinity)
        }
    }

    private var subtitle: String {
        let outfits = outfitCount
        guard outfits > 0 else {
            return "En cuanto tengas algo para abajo, empiezan los outfits."
        }
        return "Puedes hacer más de \(outfits.formatted()) outfits con ellas."
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
/// Un solo cambio de estado: el desfile lo hace `repeatForever` en el
/// renderizador, no un `TimelineView` reevaluando la fila cada frame.
private struct MarqueeRow: View {
    let keys: [String]
    let store: ImageStore
    let isReversed: Bool
    /// Puntos por segundo.
    let speed: CGFloat

    @State private var stretch: CGFloat = 0
    @State private var isRunning = false

    private static let spacing: CGFloat = WK.Spacing.m
    private static let side: CGFloat = 92

    var body: some View {
        HStack(spacing: Self.spacing) {
            stretchView
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    guard width > 0, stretch == 0 else { return }
                    stretch = width + Self.spacing
                    start()
                }
            stretchView
        }
        .fixedSize()
        .offset(x: offset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.side)
    }

    private var offset: CGFloat {
        let far = -stretch
        return isReversed ? (isRunning ? 0 : far) : (isRunning ? far : 0)
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

    private func start() {
        guard stretch > 0 else { return }
        withAnimation(.linear(duration: Double(stretch / speed)).repeatForever(autoreverses: false)) {
            isRunning = true
        }
    }
}
