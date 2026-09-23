import SwiftUI

/// Un botón que **se va llenando** mientras dura lo que has pedido.
///
/// ## Por qué llenarse y no dar vueltas
///
/// Porque "mejorar" tarda entre cinco y cuarenta segundos y una rueda girando
/// no dice si va por la mitad o si se ha colgado. Un relleno que avanza sí: se
/// ve que la cosa sigue, y de un vistazo se sabe si queda mucho. El texto se
/// pinta dos veces —el de debajo en tinta y el de encima recortado por el
/// relleno— así que la palabra va cambiando de color según pasa por ella, como
/// el nivel de un vaso.
///
/// ## Lo que el relleno **no** es
///
/// No es progreso de verdad: al otro lado hay una petición que contesta cuando
/// contesta, sin decir por dónde va. Esto es una estimación por el tiempo que
/// suele tardar, y por eso se para en el noventa y pico por ciento en vez de
/// llegar al final ella sola: llegar arriba y quedarse ahí esperando sería
/// mentir dos veces. Cuando llega la respuesta, se completa.
public struct WKProgressPill: View {

    public enum Size {
        case regular, compact

        @MainActor
        var font: Font {
            switch self {
            case .regular: WK.Font.callout
            case .compact: WK.Font.caption
            }
        }

        var horizontal: CGFloat {
            switch self {
            case .regular: WK.Spacing.m
            case .compact: WK.Spacing.s
            }
        }

        var vertical: CGFloat {
            switch self {
            case .regular: WK.Spacing.s
            case .compact: 5
            }
        }
    }

    private let title: String
    private let symbol: String
    private let isWorking: Bool
    private let size: Size
    private let action: () -> Void

    @State private var progress: Double = 0

    public init(
        _ title: String,
        symbol: String,
        isWorking: Bool,
        size: Size = .regular,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.isWorking = isWorking
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // El relleno y el texto que se invierte, compartidos con el resto
            // de la app. Ver `WKProgressFill`.
            WKProgressFill(progress: progress) { color in label(color) }
                .background(WK.Palette.ink(0.07))
                .clipShape(.capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
        .disabled(isWorking)
        .task(id: isWorking) { await run() }
    }

    private func label(_ color: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(size.font)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(color)
            .padding(.horizontal, size.horizontal)
            .padding(.vertical, size.vertical)
    }

    /// Cuánto suele tardar una reconstrucción. Ni el mejor caso ni el peor: lo
    /// normal, que es lo que hace que la barra se parezca a la espera.
    private static let typicalDuration: TimeInterval = 18

    @MainActor
    private func run() async {
        guard isWorking else {
            // Al acabar: se completa, se ve un instante lleno y se apaga. Sin
            // ese instante, el relleno desaparece a media palabra y parece que
            // se ha cancelado en vez de terminado.
            guard progress > 0 else { return }
            withAnimation(.easeOut(duration: 0.22)) { progress = 1 }
            try? await Task.sleep(for: .milliseconds(420))
            withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
            return
        }

        progress = 0
        // Un turno antes de animar: si se ponen el valor inicial y el final en
        // la misma pasada, SwiftUI no tiene un "antes" que dibujar y no anima.
        await Task.yield()
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: Self.typicalDuration)) { progress = 0.93 }
    }
}

#Preview {
    VStack(spacing: WK.Spacing.l) {
        WKProgressPill("mejorar", symbol: "wand.and.sparkles", isWorking: false) {}
        WKProgressPill("mejorando…", symbol: "wand.and.sparkles", isWorking: true) {}
        WKProgressPill("mejorando…", symbol: "wand.and.sparkles", isWorking: true, size: .compact) {}
    }
    .padding()
    .background(WK.Palette.canvas)
}
