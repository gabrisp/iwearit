import CoreGraphics
import Foundation
import Observation
import SwiftUI
import WKDesign

/// Un trazo pintado a mano sobre el lienzo.
///
/// Los puntos van en **el espacio lógico del lienzo** (1000×1400), igual que
/// las prendas: es lo que hace que lo pintado en un iPhone SE caiga exactamente
/// donde estaba al abrirlo en un iPad, y que no haya que reescalar nada al
/// cambiar de pantalla.
public struct CanvasStroke: Codable, Hashable, Sendable {
    public var points: [CGPoint]
    public var colorHex: String
    public var width: Double
    /// Si en vez de pintar, borra lo pintado.
    ///
    /// La goma es **un trazo más** y no una operación que quite trazos. Así
    /// borrar media línea es posible —quitar trazos enteros sería una goma que
    /// no borra lo que tocas, sino lo que dibujaste hace rato— y deshacer
    /// sigue siendo "quita el último", tanto si pintaba como si borraba.
    public var erases: Bool

    public init(points: [CGPoint] = [], colorHex: String, width: Double, erases: Bool) {
        self.points = points
        self.colorHex = colorHex
        self.width = width
        self.erases = erases
    }
}

/// Lo pintado sobre un outfit, y con qué se está pintando.
///
/// ## Por qué no PencilKit
///
/// `PKCanvasView` trae su paleta, su comportamiento y su aspecto, y ninguno se
/// parece al resto de la app: aparecería una pieza de otro sistema justo encima
/// del lienzo. Y trae de fondo un modelo de datos propio (`PKDrawing`) que
/// habría que guardar aparte y que no sabe nada del espacio lógico de 1000×1400
/// sobre el que está montado todo esto.
///
/// Un trazo es una lista de puntos. No hace falta más.
///
/// ## La pintura está por encima y no estorba
///
/// Se dibuja sobre las prendas y **no participa del hit testing** salvo
/// mientras estás pintando. Fuera de ese modo, arrastrar una prenda que tiene
/// una raya encima mueve la prenda, no la raya: la pintura es una capa de
/// anotación sobre el conjunto, no un elemento más del conjunto.
@MainActor
@Observable
public final class CanvasDrawing {

    public enum Tool: String, CaseIterable, Sendable {
        case brush, eraser
    }

    public private(set) var strokes: [CanvasStroke] = []
    /// El trazo que se está haciendo ahora mismo. Aparte de los demás para que
    /// pintar no reescriba el array entero en cada punto.
    public private(set) var live: CanvasStroke?

    public var tool: Tool = .brush
    public var colorHex: String = "#111111"
    public var width: Double = 10

    /// Si el lienzo está en modo pintura.
    ///
    /// Mientras lo está, las prendas no responden al dedo: si respondieran, el
    /// mismo arrastre pintaría una línea **y** movería la prenda de debajo.
    public var isActive = false

    /// Qué hacer cuando lo pintado cambia. Lo pone quien aloja el lienzo, y es
    /// por donde se guarda en el outfit.
    public var onCommit: ((Data?) -> Void)?

    public init() {}

    public var isEmpty: Bool { strokes.isEmpty && live == nil }

    // MARK: Trazar

    public func begin(at point: CGPoint) {
        live = CanvasStroke(
            points: [point],
            colorHex: colorHex,
            width: width,
            erases: tool == .eraser
        )
    }

    public func extend(to point: CGPoint) {
        guard var stroke = live else { return }
        // Puntos demasiado juntos no añaden nada a la curva y multiplican lo
        // que hay que guardar: con el dedo quieto llegan decenas por segundo.
        if let last = stroke.points.last {
            let dx = point.x - last.x
            let dy = point.y - last.y
            guard dx * dx + dy * dy > Self.minimumStep * Self.minimumStep else { return }
        }
        stroke.points.append(point)
        live = stroke
    }

    /// Distancia mínima entre dos puntos guardados, en puntos de lienzo.
    private static let minimumStep: Double = 3

    public func end() {
        defer { live = nil }
        guard let stroke = live else { return }
        // Un toque sin arrastre es un punto: se guarda igual, duplicando el
        // punto para que el trazo tenga longitud y se pinte el redondel.
        var finished = stroke
        if finished.points.count == 1, let only = finished.points.first {
            finished.points.append(CGPoint(x: only.x + 0.01, y: only.y))
        }
        strokes.append(finished)
        commit()
    }

    // MARK: Deshacer y limpiar

    public func undo() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        commit()
    }

    public func clear() {
        guard !strokes.isEmpty else { return }
        strokes.removeAll()
        commit()
    }

    // MARK: Guardar y cargar

    public func load(from data: Data?) {
        strokes = Self.decode(data)
    }

    private func commit() {
        onCommit?(Self.encode(strokes))
    }

    public static func decode(_ data: Data?) -> [CanvasStroke] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([CanvasStroke].self, from: data)) ?? []
    }

    public static func encode(_ strokes: [CanvasStroke]) -> Data? {
        guard !strokes.isEmpty else { return nil }
        return try? JSONEncoder().encode(strokes)
    }

    /// Los colores de pintar.
    ///
    /// La misma paleta que los textos más un par de tonos que ahí no hacen
    /// falta y aquí sí: rotulador sobre una foto se usa mucho para rodear y
    /// tachar, y para eso hacen falta un rojo y un amarillo que canten.
    public static let palette = [
        "#111111", "#FFFFFF", "#E5484D", "#F5B14C",
        "#FFE04D", "#3FA96B", "#5AC8F5", "#3B5BDB",
        "#8B5CF6", "#F472B6", "#8B5E3C", "#9AA0A6",
    ]
}

/// Trazos pintados, sin nada más.
///
/// Sirve para los lienzos que **solo miran**: el día del plan, la rejilla, la
/// página de la maleta. Ahí no se pinta, pero lo pintado tiene que verse — si
/// no, lo que dibujaste en el editor desaparece en cuanto sales de él.
public struct CanvasStrokesView: View {
    private let strokes: [CanvasStroke]

    public init(strokes: [CanvasStroke]) {
        self.strokes = strokes
    }

    public var body: some View {
        Canvas { context, _ in
            for stroke in strokes { CanvasStrokePainter.draw(stroke, in: &context) }
        }
        .allowsHitTesting(false)
    }
}

/// Cómo se pinta un trazo. En un sitio: lo usan la capa viva del editor y la
/// estática de las demás pantallas, y dos copias divergen en cuanto se toque
/// el grosor o la goma.
enum CanvasStrokePainter {
    static func draw(_ stroke: CanvasStroke, in context: inout GraphicsContext) {
        guard stroke.points.count > 1 else { return }
        var path = Path()
        path.addLines(stroke.points)

        // La goma borra **dentro de esta capa**: `destinationOut` recorta lo
        // que ya se pintó aquí y no toca las prendas, que están en otra vista
        // por debajo. Es lo que hace que la goma borre pintura y no ropa.
        context.blendMode = stroke.erases ? .destinationOut : .normal
        context.stroke(
            path,
            with: .color(Color(hex: stroke.colorHex) ?? .black),
            style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round)
        )
    }
}

/// Lo pintado, dibujado **y tocable**.
///
/// Un solo `Canvas` para todos los trazos: una vista por trazo serían cientos
/// de vistas que se rehacen en cada punto nuevo.
public struct CanvasDrawingLayer: View {
    private let drawing: CanvasDrawing

    public init(drawing: CanvasDrawing) {
        self.drawing = drawing
    }

    public var body: some View {
        Canvas { context, _ in
            for stroke in drawing.strokes { CanvasStrokePainter.draw(stroke, in: &context) }
            if let live = drawing.live { CanvasStrokePainter.draw(live, in: &context) }
        }
        // **Transparente al dedo salvo mientras se pinta.** Es lo que permite
        // que la pintura viva encima de las prendas sin estorbar para moverlas.
        .allowsHitTesting(drawing.isActive)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if drawing.live == nil {
                        drawing.begin(at: value.startLocation)
                    }
                    drawing.extend(to: value.location)
                }
                .onEnded { _ in drawing.end() }
        )
    }

}
