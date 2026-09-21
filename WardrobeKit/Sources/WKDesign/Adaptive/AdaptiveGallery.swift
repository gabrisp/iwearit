import SwiftUI

/// Galería de los modificadores adaptativos.
///
/// Existe para poder ver de un vistazo qué hace cada uno. La rama que se
/// renderiza depende del destino de la preview: arráncala en un simulador de
/// iOS 26 para ver Liquid Glass, y en uno de iOS 18 para ver los materiales.
/// Las dos tienen que verse dignas — esa es la vara de medir.
public struct AdaptiveGallery: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WK.Spacing.l) {
                GallerySection("adaptiveGlass(in:)") {
                    Text("Superficie")
                        .padding()
                        .adaptiveGlass(in: .rect(cornerRadius: WK.Radius.card))
                }
                GallerySection("adaptiveGlass(tint:in:)") {
                    Text("Teñida")
                        .padding()
                        .adaptiveGlass(tint: WK.Palette.accent, in: .rect(cornerRadius: WK.Radius.card))
                }
                GallerySection("adaptiveGlassInteractive(in:)") {
                    AdaptiveGlassContainer(spacing: WK.Spacing.s) {
                        HStack(spacing: WK.Spacing.s) {
                            GalleryGlassChip(icon: "tshirt")
                            GalleryGlassChip(icon: "shoe")
                            GalleryGlassChip(icon: "bag")
                        }
                    }
                }
                GallerySection("adaptiveProminentButton()") {
                    Button("Continuar") {}
                        .adaptiveProminentButton()
                }
                GallerySection("adaptiveGlassButton()") {
                    Button("Secundario") {}
                        .adaptiveGlassButton()
                }
                GallerySection("adaptiveConcentric(radius:)") {
                    WK.Palette.accent
                        .frame(width: 120, height: 64)
                        .adaptiveConcentric(radius: WK.Radius.medium)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(WK.Spacing.m)
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas.ignoresSafeArea())
        .adaptiveScrollEdge(.top)
    }
}

/// Fila de la galería. Vista propia porque se repite seis veces: meterla inline
/// en el `@ViewBuilder` sería exactamente lo que la arquitectura prohíbe.
private struct GallerySection<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            Text(title)
                .font(.caption.monospaced())
                .foregroundStyle(WK.Palette.secondaryText)
            content
        }
    }
}

private struct GalleryGlassChip: View {
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(.title3)
            .frame(width: 48, height: 48)
            .adaptiveGlassInteractive(in: .circle)
    }
}

#Preview("Modificadores adaptativos") {
    AdaptiveGallery()
}
