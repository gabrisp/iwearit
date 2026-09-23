import CoreGraphics
import SwiftUI
import WKCore
import WKDesign
import WKVision

/// Rodear la prenda con el dedo.
///
/// Se abre cuando la detección no ha acertado: parte un pantalón, se deja media
/// manga o se lleva un trozo del sofá. Dos segundos de dedo y el recorte es el
/// que tú digas — y **manda sobre el detectado**, que es de lo que se trata.
///
/// ## Por qué a pantalla completa y no en la ficha
///
/// Porque hay que ver la foto grande para acertar el contorno. En la miniatura
/// de la ficha el dedo tapa justo lo que estás bordeando.
struct ManualCropScreen: View {
    let image: CGImage
    /// Devuelve **el trozo rodeado y el recorte del trazo**. Quien llama
    /// decide qué hacer con ellos: en la importación se busca el sujeto dentro
    /// del trozo; en la ficha se usa el recorte.
    ///
    /// Puede llamarse **varias veces**: una foto suele traer más de una prenda
    /// y obligar a entrar y salir por cada una era hacer el mismo camino tres
    /// veces. Ver `keepsGoing`.
    let onCrop: (ManualCrop.Result) -> Void
    /// Si al terminar un recorte la pantalla se queda para el siguiente.
    ///
    /// **Ya no se usa**: se recorta una y se cierra, siempre. Ver `crop()`. Se
    /// queda el parámetro porque quien llama sigue diciendo cuál de los dos
    /// casos es, y porque volver atrás es cambiar una línea.
    var keepsGoing = false

    @Environment(\.dismiss) private var dismiss

    /// El lazo, en coordenadas **unitarias** de la imagen. Unitarias y no de
    /// pantalla porque es lo que entiende `ManualCrop`, y porque así girar el
    /// teléfono a mitad no invalida lo dibujado.
    @State private var path: [CGPoint] = []
    @State private var isWorking = false
    /// Cuántas van en esta sesión. Solo para poder decirlo.
    @State private var cropped = 0

    private var canCrop: Bool { path.count >= ManualCrop.minimumPoints }

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            chrome

            GeometryReader { proxy in
                // El rectángulo que ocupa **la imagen** dentro del hueco: la
                // foto va a `scaledToFit`, así que sobran bandas a los lados o
                // arriba, y un punto que caiga ahí no pertenece a la imagen.
                let box = fitted(in: proxy.size)

                ZStack {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFit()

                    LassoShape(points: path, in: box)
                        .stroke(
                            WK.Palette.accent,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [8, 6])
                        )
                    // Lo de fuera, apagado: es la forma de ver **lo que te vas
                    // a quedar** mientras lo dibujas, en vez de una línea sobre
                    // la foto que no dice qué lado es el bueno.
                    LassoShape(points: path, in: box)
                        .fill(style: FillStyle(eoFill: true))
                        .foregroundStyle(.black.opacity(0.35))
                        .mask {
                            Rectangle()
                        }
                        .allowsHitTesting(false)
                        .opacity(canCrop ? 1 : 0)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            append(value.location, in: box)
                        }
                )
            }

            footer
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WK.Palette.canvas.ignoresSafeArea())
    }

    private var chrome: some View {
        HStack {
            Button("Cancelar") { dismiss() }
                .font(WK.Font.callout)
                .foregroundStyle(WK.Palette.secondaryText)
            Spacer()
            // **Sin exigir puntería.** El trazo es una pista de por dónde
            // anda el contorno, no la línea de corte: decirlo aquí evita que
            // la gente intente rodear una manga al píxel con el dedo, que no
            // se puede y encima sale peor.
            VStack(spacing: 2) {
                Text("Rodea la prenda")
                    .font(WK.Font.headline)
                    .foregroundStyle(WK.Palette.primaryText)

                Text("Nos vale aproximado: lo usamos de referencia")
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
            }
            Spacer()
            Button("Repetir") { path = [] }
                .font(WK.Font.callout)
                .foregroundStyle(canCrop ? WK.Palette.accent : WK.Palette.tertiaryText)
                .disabled(!canCrop)
        }
        .padding(.top, WK.Spacing.m)
    }

    private var footer: some View {
        VStack(spacing: WK.Spacing.s) {
            Text(status)
            .font(WK.Font.caption)
            .foregroundStyle(WK.Palette.secondaryText)
            .contentTransition(.opacity)

            WKPrimaryButton(primaryTitle) { crop() }
            .disabled(!canCrop || isWorking)
            .opacity(canCrop ? 1 : 0.4)
        }
        .animation(WKAnimation.selection, value: canCrop)
    }

    private var status: String {
        if canCrop { return "Se queda lo de dentro del trazo." }
        if cropped > 0 { return "Recortada." }
        return "Dibuja alrededor de la prenda sin levantar el dedo."
    }

    private var primaryTitle: String {
        isWorking ? "Recortando…" : "Usar este recorte"
    }

    /// Dónde cae la imagen dentro del hueco, con `scaledToFit`.
    private func fitted(in size: CGSize) -> CGRect {
        let imageRatio = Double(image.width) / Double(image.height)
        let boxRatio = size.width / max(size.height, 1)
        if imageRatio > boxRatio {
            let height = size.width / imageRatio
            return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
        }
        let width = size.height * imageRatio
        return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
    }

    private func append(_ point: CGPoint, in box: CGRect) {
        guard box.width > 0, box.height > 0 else { return }
        // Se recorta al marco de la imagen en vez de descartar el punto: al
        // bordear una prenda que toca el canto de la foto, el dedo se sale, y
        // descartar esos puntos abriría un boquete en el lazo.
        let unit = CGPoint(
            x: min(1, max(0, (point.x - box.minX) / box.width)),
            y: min(1, max(0, (point.y - box.minY) / box.height))
        )
        if let last = path.last {
            let dx = unit.x - last.x
            let dy = unit.y - last.y
            guard dx * dx + dy * dy > 0.000_04 else { return }
        }
        path.append(unit)
    }

    private func crop() {
        isWorking = true
        // En un `Task` y no aquí mismo: recorrer una foto de 12 Mpx bloquea el
        // hilo principal lo suficiente para que el botón se quede hundido.
        Task {
            let points = path
            let source = image
            let result = await Task.detached(priority: .userInitiated) {
                ManualCrop.apply(to: source, path: points)
            }.value
            isWorking = false
            guard let result else { return }
            onCrop(result)
            cropped += 1

            // **Se recorta una vez y se cierra.**
            //
            // Antes, rodeando prendas nuevas, la pantalla se quedaba puesta
            // para la siguiente: la idea era ahorrar el camino de entrar y
            // salir por cada prenda. En la mano no se lee así — le das a
            // recortar, la pantalla sigue ahí y parece que no ha pasado nada,
            // porque lo que ha pasado está **detrás** de la hoja. Cerrar es lo
            // que enseña el resultado, y rodear otra es volver a tocar el
            // botón, que está a un toque.
            //
            // if keepsGoing {
            //     withAnimation(WKAnimation.content) { path = [] }
            // } else {
            dismiss()
            // }
        }
    }
}

/// El lazo dibujado, en coordenadas de pantalla.
///
/// `Shape` y no un `Path` suelto para que SwiftUI lo redibuje solo al cambiar
/// los puntos, sin que la pantalla tenga que reconstruir nada más.
private struct LassoShape: Shape {
    let points: [CGPoint]
    let box: CGRect

    init(points: [CGPoint], in box: CGRect) {
        self.points = points
        self.box = box
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: place(first))
        for point in points.dropFirst() { path.addLine(to: place(point)) }
        // Cerrado siempre: un lazo a mano no acaba donde empezó, y sin cerrar
        // no se ve qué zona es la de dentro.
        path.closeSubpath()
        return path
    }

    private func place(_ unit: CGPoint) -> CGPoint {
        CGPoint(x: box.minX + unit.x * box.width, y: box.minY + unit.y * box.height)
    }
}
