import CoreGraphics

/// El espacio de coordenadas **fijo** en el que vive todo outfit.
///
/// Guardar posiciones normalizadas 0-1 parece razonable hasta que cambias de
/// iPhone o giras el dispositivo: el canvas cambia de proporción y todo se
/// desplaza. Con un espacio lógico fijo, lo que se persiste no depende del
/// tamaño de la vista, así que el round-trip es exacto y el layout relativo es
/// idéntico en un iPhone SE y en un iPad.
///
/// El canvas se dibuja siempre en estas coordenadas y se escala entero con un
/// **único** factor para caber en pantalla (`scaleToFit(in:)`).
public enum CanvasSpace {
    public static let width: Double = 1000
    public static let height: Double = 1400

    public static let size = CGSize(width: width, height: height)
    public static let center = CGPoint(x: width / 2, y: height / 2)

    /// Separación de la retícula de puntos, en puntos de canvas.
    /// Es **decorativa**: no hay snap salvo que el outfit lo active explícitamente.
    public static let gridSpacing: Double = 20

    /// Factor único que lleva el canvas lógico al tamaño real de la vista.
    ///
    /// Los deltas de gesto se dividen por este valor para pasar de puntos de
    /// pantalla a puntos de canvas. La rotación y la escala son adimensionales
    /// y **no** se convierten.
    public static func scaleToFit(in viewSize: CGSize) -> Double {
        guard viewSize.width > 0, viewSize.height > 0 else { return 1 }
        return min(viewSize.width / width, viewSize.height / height)
    }
}
