import SwiftUI
import WKDesign

/// Muestra una imagen del `ImageStore`, con caché en memoria.
///
/// Es la **única** vista con estado dentro de una balda. Todo lo demás en el
/// armario es POD y se difunde con `memcmp`, así que scrollear una balda no
/// invalida ninguna otra.
///
/// Carga en `.task(id:)` en vez de `.onAppear`: si la celda se recicla para
/// otra prenda mientras la carga está en vuelo, la tarea anterior se cancela
/// sola y no se pinta la imagen equivocada.
public struct StoredImage: View {
    private let key: String
    private let variant: ImageStore.Variant
    private let store: ImageStore
    private let alignment: Alignment
    private let shadow: Shadow?
    /// Si se prefiere la versión reconstruida cuando la haya.
    ///
    /// **Encendido por defecto.** Estuvo apagado con el argumento de que el
    /// recorte es lo que estuvo delante de la cámara y la reconstrucción es una
    /// interpretación. Cierto, pero irrelevante para lo que se usa la imagen
    /// aquí: el recorte del segmentador parte las prendas largas y deja cantos
    /// sucios, y en una balda o en un lienzo eso es exactamente lo que se ve.
    /// La versión de catálogo es la que sirve para montar un outfit.
    ///
    /// El recorte real no se pierde ni se tapa: sigue guardado bajo la misma
    /// clave y la ficha de la prenda lo enseña a un toque — que es el único
    /// sitio donde importa cuál es cuál.
    private let prefersCatalog: Bool

    /// Sombra que sigue la silueta de la prenda.
    ///
    /// Se aplica **a la imagen**, no al hueco que ocupa: SwiftUI la calcula a
    /// partir del alfa, así que sale con la forma del recorte en vez de un
    /// rectángulo. Aplicada al contenedor daría una caja gris detrás de una
    /// camiseta, que es justo lo que no se quiere.
    public struct Shadow: Sendable {
        let opacity: Double
        let radius: CGFloat
        let y: CGFloat
        /// Color propio. `nil` usa `ink`, que es negro en claro y blanco en
        /// oscuro. Con color se convierte en un halo — que es como se marca
        /// una prenda seleccionada **sin** dibujarle un rectángulo alrededor,
        /// porque una prenda recortada no es rectangular y el rectángulo se ve
        /// como lo que es: una caja ajena puesta encima.
        let tint: Color?

        public init(
            opacity: Double = 0.22,
            radius: CGFloat = 10,
            y: CGFloat = 5,
            tint: Color? = nil
        ) {
            self.opacity = opacity
            self.radius = radius
            self.y = y
            self.tint = tint
        }
    }

    @State private var image: UIImage?

    /// - Parameter alignment: dónde se apoya la imagen dentro del hueco que le
    ///   den. Las prendas del armario van a `.bottom` para que parezcan
    ///   apoyadas en el tablero; en el canvas van centradas.
    public init(
        key: String,
        variant: ImageStore.Variant,
        store: ImageStore,
        alignment: Alignment = .center,
        shadow: Shadow? = nil,
        // **Encendida por defecto**, otra vez y a propósito: ver
        // `resolvedVariant()`. Quien quiera el recorte de verdad lo pide.
        prefersCatalog: Bool = true
    ) {
        self.key = key
        self.variant = variant
        self.store = store
        self.alignment = alignment
        self.shadow = shadow
        self.prefersCatalog = prefersCatalog
    }

    public var body: some View {
        ZStack(alignment: alignment) {
            // Ocupa todo el hueco para que `alignment` tenga algo contra lo que
            // alinear; sin esto el ZStack se encoge a la imagen y da igual.
            Color.clear
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    // Dos pasadas, y el orden importa. La primera es el
                    // contorno: radio muy corto y casi sin desplazamiento, así
                    // que traza el borde del recorte en vez de difuminarse.
                    // La segunda es el apoyo, mucho más flojo, y se dibuja
                    // *detrás* de la primera — por eso el contorno se sigue
                    // leyendo nítido y no se lo come la mancha.
                    //
                    // `ink` y no negro: en modo oscuro la sombra se dibuja en
                    // blanco, que sobre fondo oscuro lee como un halo y separa
                    // la prenda del fondo igual que la sombra lo hace en claro.
                    .shadow(
                        color: shadowColor(opacity: shadow?.opacity ?? 0),
                        radius: contourRadius,
                        y: contourOffset
                    )
                    .shadow(
                        color: shadowColor(opacity: groundOpacity),
                        radius: shadow?.radius ?? 0,
                        y: shadow?.y ?? 0
                    )
            }
        }
        .task(id: TaskKey(key: key, prefersCatalog: prefersCatalog)) { await load() }
    }

    /// Cuánto de la sombra configurada se reserva para el apoyo. El resto de
    /// la intensidad se la lleva el contorno, que es lo que dibuja la forma.
    private static let groundOpacityRatio = 0.3

    /// El apoyo se queda con toda la intensidad cuando no hay contorno.
    private var groundOpacity: Double {
        guard let shadow else { return 0 }
        return shadow.tint == nil ? shadow.opacity * Self.groundOpacityRatio : shadow.opacity
    }

    private func shadowColor(opacity: Double) -> Color {
        guard let shadow else { return .clear }
        if let tint = shadow.tint { return tint.opacity(opacity) }
        return WK.Palette.ink(opacity)
    }

    /// Corto a propósito: por encima de ~3 pt el borde deja de leerse como
    /// borde y empieza a leerse como una mancha por debajo de la prenda.
    ///
    /// Con `tint` no hay contorno: una sombra de color no es una sombra, es un
    /// halo de selección, y un halo tiene que ser ancho para leerse como tal.
    private var contourRadius: CGFloat {
        guard let shadow, shadow.tint == nil else { return 0 }
        return min(3, max(1, shadow.radius * 0.16))
    }

    /// Casi nada. Un contorno desplazado dos puntos ya no es un contorno.
    private var contourOffset: CGFloat {
        guard let shadow else { return 0 }
        return shadow.y * 0.12
    }

    /// Carga, y **si no sale, vuelve a intentarlo**.
    ///
    /// El caso real: en un iPad que cambia de tamaño —girarlo, arrastrar el
    /// borde de la ventana— las vistas se rehacen a ráfagas y alguna lectura
    /// se queda por el camino. Con un solo intento eso dejaba la prenda en
    /// blanco **para siempre**: la clave no ha cambiado, así que `task(id:)`
    /// no vuelve a dispararse y no hay nada que la despierte hasta que la
    /// celda se recicla. Dos intentos más, muy seguidos, y el hueco vacío deja
    /// de ser permanente.
    private func load() async {
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(120 * attempt))
                guard !Task.isCancelled else { return }
            }
            await attemptLoad()
            if image != nil { return }
        }
    }

    private func attemptLoad() async {
        let resolved = await resolvedVariant()
        // La de catálogo mide 1024 y pesa lo que pesa un PNG con alfa. Cuando
        // lo que se pedía era una miniatura, se decodifica al tamaño de la
        // miniatura: en la balda se ve igual y cabe diez veces más en memoria.
        let cap: CGFloat? =
            resolved == .catalog && variant == .thumb ? ImageStore.Variant.thumb.maxPixelSize : nil

        // Golpe de caché: síncrono, sin parpadeo entre frames al reciclar celdas.
        if let cached = ThumbnailCache.shared.image(for: key, variant: resolved, cappedAt: cap) {
            image = cached
            return
        }
        guard
            let loaded = try? await store.image(for: key, variant: resolved, cappedAt: cap)
        else { return }
        guard !Task.isCancelled else { return }

        let rendered = UIImage(cgImage: loaded)
        ThumbnailCache.shared.insert(rendered, for: key, variant: resolved, cappedAt: cap)
        image = rendered
    }

    /// Qué variante se acaba enseñando.
    ///
    /// **Por defecto, el recorte elegido.** El que se ve en la app es el que
    /// se aceptó al importar, y el mismo en todas partes: la balda, el lienzo,
    /// la rejilla y la maleta. Que exista otra versión de la prenda —una
    /// reconstruida, la de una importación anterior— no cambia lo que se
    /// enseña; lo que se enseña es lo que elegiste.
    ///
    /// `prefersCatalog` sigue estando para quien quiera pedirla a propósito
    /// —la sección de imágenes de la ficha, por ejemplo—, pero ya no es lo que
    /// pasa sin decir nada. Antes sí lo era, y por eso una prenda se veía de
    /// una manera en la ficha y de otra en la balda.
    ///
    /// ## Y sin embargo vuelve a estar encendida
    ///
    /// Porque el razonamiento de arriba describía mal el caso real. La versión
    /// reconstruida **no aparece sola**: cuesta dinero y se genera porque
    /// alguien la pide. Pagar por mejorar una prenda y seguir viendo en la
    /// balda el recorte malo —que es justo lo que se quería arreglar— no es
    /// respetar la elección del usuario, es ignorarla; y encima la ficha sí
    /// enseñaba la buena, así que la misma prenda se veía de dos maneras
    /// según dónde la miraras.
    ///
    /// La vuelta atrás sigue existiendo y es explícita: "Usar el recorte real"
    /// en la ficha borra la reconstrucción, y entonces no hay nada que
    /// preferir.
    private func resolvedVariant() async -> ImageStore.Variant {
        guard prefersCatalog, await store.hasCatalog(for: key) else { return variant }
        return .catalog
    }
}

/// Lo que hace que la imagen se vuelva a cargar.
///
/// La clave **y** si se prefiere la reconstruida: al generarla, la clave no
/// cambia, así que con solo la clave la vista seguía enseñando el recorte hasta
/// que se reciclara la celda.
private struct TaskKey: Equatable {
    let key: String
    let prefersCatalog: Bool
}
