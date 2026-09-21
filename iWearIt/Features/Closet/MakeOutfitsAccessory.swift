import SwiftUI
import WKDesign

/// El CTA flotante del Armario: una píldora sobre la tab bar, como en la
/// referencia de diseño.
///
/// Vive en la pantalla y no en el `TabView` (ver `adaptiveFloatingAccessory`):
/// el accesorio global de iOS 26 pinta su superficie aunque esté vacío, así que
/// usarlo aquí dejaba una cápsula fantasma en Plan y en Perfil.
struct MakeOutfitsAccessory: View {
    @State private var isPresentingComposer = false

    var body: some View {
        AdaptiveGlassContainer(spacing: WK.Spacing.s) {
            content
        }
        .outfitCreationFlow(isActive: $isPresentingComposer)
    }

    private var content: some View {
        Button {
            isPresentingComposer = true
        } label: {
            Label("Crear outfit", systemImage: "tshirt")
                .font(.headline)
                .padding(.horizontal, WK.Spacing.l)
                .padding(.vertical, WK.Spacing.s + 2)
        }
        .adaptiveGlassInteractive(in: .capsule)
        .adaptiveGlassTransition()
    }
}

#Preview {
    ZStack {
        WK.Palette.canvas.ignoresSafeArea()
        MakeOutfitsAccessory()
    }
}
