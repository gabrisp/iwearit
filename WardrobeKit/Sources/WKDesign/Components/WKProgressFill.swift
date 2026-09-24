import SwiftUI

/// Algo que **se va llenando de izquierda a derecha**, con su texto cambiando
/// de color por donde ya ha pasado el relleno.
///
/// ## Por qué una sola pieza para todos
///
/// Porque el gesto es el mismo en tres sitios —tirar para barajar, tirar para
/// crear un outfit, esperar a que una prenda se reconstruya— y cada uno lo
/// contaba a su manera: unos con un aura difusa creciendo desde el centro y
/// otro con un relleno recto. Dos lenguajes para decir "va por la mitad".
///
/// Gana el relleno recto: dice **cuánto** queda, que es la pregunta. El aura
/// decía "está pasando algo", que ya se ve.
///
/// ## Cómo pinta el texto
///
/// El contenido se dibuja dos veces: abajo en tinta y encima en el color de
/// sobre-relleno, recortado justo por donde llega el relleno. Así cada letra se
/// invierte al ser alcanzada, en vez de cambiar todo el bloque de golpe al
/// pasar un umbral. Por eso el contenido llega como función del color: tiene
/// que poder pintarse dos veces, idéntico y con los mismos márgenes.
public struct WKProgressFill<Content: View>: View {

    private let progress: CGFloat
    private let fill: Color
    private let ink: Color
    private let content: (Color) -> Content

    public init(
        progress: CGFloat,
        fill: Color = WK.Palette.accent,
        ink: Color = WK.Palette.onAccent,
        @ViewBuilder content: @escaping (Color) -> Content
    ) {
        self.progress = progress
        self.fill = fill
        self.ink = ink
        self.content = content
    }

    private var clamped: CGFloat { min(max(progress, 0), 1) }

    public var body: some View {
        content(WK.Palette.primaryText)
            .background {
                GeometryReader { proxy in
                    fill.frame(width: proxy.size.width * clamped)
                }
            }
            .overlay {
                GeometryReader { proxy in
                    content(ink)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .mask(alignment: .leading) {
                            Color.black.frame(width: proxy.size.width * clamped)
                        }
                }
            }
    }
}

#Preview {
    VStack(spacing: WK.Spacing.l) {
        ForEach([0.0, 0.35, 0.8, 1.0], id: \.self) { value in
            WKProgressFill(progress: value) { color in
                Label(String(localized: "wkdesign.wkprogressfill.generateEightMore", defaultValue: "Generate eight more", bundle: .module), systemImage: "wand.and.stars")
                    .font(WK.Font.headline)
                    .foregroundStyle(color)
                    .padding(.horizontal, WK.Spacing.l)
                    .padding(.vertical, WK.Spacing.s)
            }
            .clipShape(.capsule)
        }
    }
    .padding()
    .background(WK.Palette.canvas)
}
