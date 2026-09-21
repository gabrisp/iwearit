import SwiftUI

// Botones, formas y búsqueda.

public extension View {

    /// Botón de acción principal, grande. `glassProminent` en iOS 26,
    /// `borderedProminent` en iOS 18 — ambos leen como "esto es lo que hay que pulsar".
    @ViewBuilder
    func adaptiveProminentButton() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glassProminent).controlSize(.extraLarge)
        } else {
            self.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    /// Botón secundario sobre cristal.
    @ViewBuilder
    func adaptiveGlassButton() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Esquinas continuas, consistentes en toda la app.
    ///
    /// La concentricidad real de iOS 26 (`ConcentricRectangle`) se evaluará
    /// cuando haya contenedores anidados que la necesiten; hoy no los hay, y
    /// `.continuous` se ve idéntico en ambas versiones.
    func adaptiveConcentric(radius: CGFloat) -> some View {
        clipShape(.rect(cornerRadius: radius, style: .continuous))
    }

    /// Extiende y difumina la imagen fuera del safe area para que no se vea
    /// recortada bajo una barra de cristal.
    @ViewBuilder
    func adaptiveBackgroundExtension() -> some View {
        if #available(iOS 26, *) {
            self.backgroundExtensionEffect()
        } else {
            self
        }
    }
}
