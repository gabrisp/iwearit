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
struct ImportPhotoStrip: View {
    let photos: [CGImage]
    let candidates: [ImportCandidate]
    /// Cuántas llevan analizadas. Las que van por detrás siguen brillando.
    let analysed: Int
    /// Se llama cuando la última termina de revelar sus prendas.
    let onFinished: () -> Void

    @State private var focused: Int?

    var body: some View {
        VStack(spacing: WK.Spacing.s) {
            counter

            ScrollView(.horizontal) {
                LazyHStack(spacing: WK.Spacing.m) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                        ImportRevealView(
                            photo: photo,
                            candidates: candidates.filter { $0.photoIndex == index },
                            isScanning: index >= analysed,
                            onFinished: index == photos.count - 1 ? onFinished : {}
                        )
                        // Una foto por pantalla: media foto asomando invita a
                        // arrastrar justo cuando lo que toca es esperar.
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focused, anchor: .center)
            .scrollIndicators(.hidden)
        }
        .onChange(of: analysed) { _, done in
            // Se pasa a la que acaba de empezar, no a la que acaba de
            // terminar: lo interesante es dónde está trabajando ahora.
            withAnimation(WKAnimation.content) {
                focused = min(done, photos.count - 1)
            }
        }
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
