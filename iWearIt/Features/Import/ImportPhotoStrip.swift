import CoreGraphics
import SwiftUI
import WKDesign

/// Varias fotos analizándose, en fila.
///
/// ## Por qué en horizontal y no una lista
///
/// Al vaciar un armario no se hace una foto, se hacen seis seguidas. Con una
/// sola pantalla por foto habría que esperar a que acabe una para elegir la
/// siguiente, y con una lista vertical de miniaturas no se ve ninguna: lo que
/// hace falta es mirar la que está trabajando ahora y saber cuántas quedan.
///
/// Por eso el carrete avanza **solo**: en cuanto una foto termina, el scroll
/// pasa a la siguiente, que es exactamente lo que estaría haciendo el dedo.
/// Se puede volver atrás a mirar cualquiera sin que se pierda el sitio —el
/// avance automático solo ocurre cuando de verdad acaba una.
///
/// Las vecinas asoman a los lados, un poco más pequeñas y apagadas: así se ve
/// de un vistazo cuántas hay y por dónde va, sin necesidad de contarlas.
struct ImportPhotoStrip: View {
    let photos: [CGImage]
    let candidates: [ImportCandidate]
    /// Cuántas llevan analizadas. Las que van por detrás siguen brillando.
    let analysed: Int
    /// Se llama cuando la última termina de revelar sus prendas.
    let onFinished: () -> Void

    @State private var focused: Int?

    /// Lo que asoma de las vecinas por cada lado.
    private static let peek: CGFloat = 44
    private static let spacing: CGFloat = 12

    var body: some View {
        VStack(spacing: WK.Spacing.s) {
            counter

            // **El margen se mide, no se supone.**
            //
            // Para que la primera foto quede centrada, el hueco de la
            // izquierda tiene que ser exactamente *medio ancho de pantalla
            // menos medio ancho de foto*, y el de la derecha lo mismo con la
            // última. Puesto como una constante a ojo, la primera se quedaba
            // desplazada justo en el caso más común, que es el de una sola
            // foto. Con el ancho real del contenedor delante, sale solo.
            GeometryReader { proxy in
                let width = itemWidth(in: proxy.size.width)
                let margin = max((proxy.size.width - width) / 2, 0)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: Self.spacing) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                            ImportRevealView(
                                photo: photo,
                                candidates: candidates.filter { $0.photoIndex == index },
                                isScanning: index >= analysed,
                                // El brillo, solo en la que se está mirando.
                                isCurrent: index == analysed,
                                isFocused: index == (focused ?? 0),
                                onFinished: index == photos.count - 1 ? onFinished : {}
                            )
                            .frame(width: width)
                            // La centrada, entera; las demás, un pelín más
                            // pequeñas y apagadas. Interactivo para que la
                            // transición vaya con el dedo, no al soltar.
                            .scrollTransition(.interactive) { content, phase in
                                // Las vecinas, un poco borrosas y al 80%: se ve
                                // que están ahí sin competir con la del centro.
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.97)
                                    .opacity(phase.isIdentity ? 1 : 0.8)
                                    .blur(radius: phase.isIdentity ? 0 : 2.5)
                            }
                            .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $focused, anchor: .center)
                .contentMargins(.horizontal, margin, for: .scrollContent)
                // **Quieto mientras analiza.** El carrete avanza solo conforme
                // acaban las fotos; dejarlo arrastrar es dejar mirar una que
                // todavía no ha empezado mientras la de verdad trabaja fuera
                // de la pantalla.
                .scrollDisabled(true)
                .scrollIndicators(.hidden)
                // El recorte cae en el canto de la pantalla, donde no molesta.
                .scrollClipDisabled()
            }
            .wkBleedingStrip()
        }
        .onChange(of: analysed) { _, done in
            // **Primero se ve salir la prenda, luego se pasa.** Al terminar
            // una foto, sus recortes salen de ella —el esqueleto de la prenda
            // despegándose de la foto— y eso necesita su momento. Pasando a la
            // siguiente en el acto no se llegaba a ver nunca: el carrete se
            // iba justo cuando empezaba. El análisis sigue mientras tanto; lo
            // que espera es solo la cámara.
            //
            // Con la última no se pasa a ningún sitio: se queda, y es la
            // revisión la que entra encima.
            guard done < photos.count else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(1400))
                withAnimation(.smooth(duration: 0.6)) {
                    focused = min(done, photos.count - 1)
                }
            }
        }
    }

    /// Lo que mide una foto del carrete.
    ///
    /// Con una sola no hay vecinas que enseñar, así que ocupa lo que hay; con
    /// varias se deja sitio a los lados para que asomen, que es lo que dice
    /// cuántas hay sin tener que contarlas.
    private func itemWidth(in container: CGFloat) -> CGFloat {
        guard container > 0 else { return 0 }
        guard photos.count > 1 else {
            return max(container - 2 * WK.Spacing.screenInset, 120)
        }
        return max(container - 2 * (Self.peek + Self.spacing), 160)
    }

    /// "3 de 6 imágenes analizadas".
    ///
    /// Con `numericText` el número gira en su sitio en vez de desaparecer y
    /// aparecer: es lo que hace que se lea como un contador y no como un texto
    /// que se reemplaza.
    @ViewBuilder
    private var counter: some View {
        if photos.count > 1 {
            HStack(spacing: WK.Spacing.xs) {
                Text("\(analysed)")
                    .contentTransition(.numericText(value: Double(analysed)))
                Text("de \(photos.count) imágenes analizadas")
            }
            .font(WK.Font.callout)
            .foregroundStyle(WK.Palette.secondaryText)
            .animation(WKAnimation.content, value: analysed)
        }
    }
}
