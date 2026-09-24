import SwiftUI
import WKCore
import WKDesign

/// Escribir un texto para el canvas.
///
/// A pantalla completa y con el teclado arriba desde el primer frame: es una
/// pantalla para escribir, y abrirla con el teclado bajado obliga a un toque
/// que no decide nada. El fondo deja ver el collage a través porque lo que se
/// escribe se lee **sobre** él — elegir blanco sin ver dónde cae es adivinar.
public struct TextStickerEditor: View {
    @State private var sticker: TextSticker
    private let onDone: (TextSticker) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isWriting: Bool

    public init(sticker: TextSticker = TextSticker(), onDone: @escaping (TextSticker) -> Void) {
        _sticker = State(initialValue: sticker)
        self.onDone = onDone
    }

    public var body: some View {
        ZStack {
            // Cierra al tocar fuera. `contentShape` porque un color con
            // opacidad sigue necesitando forma para recibir toques.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { finish() }

            VStack(spacing: WK.Spacing.l) {
                Spacer(minLength: 0)
                field
                Spacer(minLength: 0)
                palette
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .animation(WKAnimation.arrival, value: isWriting)
        }
        .adaptiveSafeAreaBar(edge: .top) { chrome }
        // **El teclado no empuja nada.**
        //
        // Sin esto, al subir el teclado toda la pila se comprimía: el texto
        // saltaba hacia arriba a mitad de escribir y la paleta se iba detrás.
        // Lo que tiene que pasar es que el teclado se ponga **encima** y el
        // texto se quede donde estaba.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            // Sin retardo el foco llega antes de que la vista esté en pantalla
            // y el teclado no sube.
            try? await Task.sleep(for: .milliseconds(120))
            isWriting = true
        }
    }

    private var chrome: some View {
        HStack {
            ChromeButton(symbol: "xmark") { dismiss() }
            Spacer()
            ChromeButton(symbol: "textformat") { cycleBackground() }
            ChromeButton(symbol: alignmentSymbol) { cycleAlignment() }
            Spacer()
            Button(String(localized: "wkcanvas.textstickereditor.done", defaultValue: "Done", bundle: .module)) { finish() }
                .font(WK.Font.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .background(.white.opacity(0.18), in: .capsule)
                .contentShape(.capsule)
                .buttonStyle(WKPressStyle())
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        // Más aire arriba: pegados al borde, los controles quedaban a la altura
        // de la isla dinámica y se tocaban sin querer al bajar la mano.
        .padding(.top, WK.Spacing.l)
        .padding(.bottom, WK.Spacing.m)
    }

    private var field: some View {
        TextField("", text: $sticker.string, axis: .vertical)
            .focused($isWriting)
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(Color(hex: sticker.colorHex) ?? .white)
            .multilineTextAlignment(sticker.alignment.textAlignment)
            .tint(Color(hex: sticker.colorHex) ?? .white)
            .padding(WK.Spacing.m)
            .background {
                if let hex = sticker.backgroundHex, let color = Color(hex: hex) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color)
                }
            }
            .animation(WKAnimation.selection, value: sticker.backgroundHex)
            .animation(WKAnimation.selection, value: sticker.alignment)
    }

    /// Los colores. **Se esconden mientras se escribe.**
    ///
    /// Con el teclado puesto quedan justo encima de él, medio tapados y a un
    /// dedo de distancia de las teclas de arriba: se tocan sin querer y cambian
    /// el color del texto a mitad de una palabra. Vuelven en cuanto se suelta
    /// el teclado, que es cuando se van a usar.
    @ViewBuilder
    private var palette: some View {
        if !isWriting {
            colors.transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var colors: some View {
        HStack(spacing: WK.Spacing.m) {
            ForEach(TextSticker.palette, id: \.self) { hex in
                SwatchButton(
                    hex: hex,
                    isSelected: sticker.colorHex == hex
                ) {
                    sticker.colorHex = hex
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, WK.Spacing.s)
    }

    private var alignmentSymbol: String {
        switch sticker.alignment {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }

    /// Sin caja → caja del color del texto con el texto en contraste → sin
    /// caja. Tres estados y vuelta a empezar, como en las historias: un menú
    /// para algo que se decide mirando no merece un menú.
    private func cycleBackground() {
        withAnimation(WKAnimation.selection) {
            if sticker.backgroundHex == nil {
                sticker.backgroundHex = sticker.colorHex
                sticker.colorHex = sticker.backgroundHex == "#111111" ? "#FFFFFF" : "#111111"
            } else {
                sticker.colorHex = sticker.backgroundHex ?? "#FFFFFF"
                sticker.backgroundHex = nil
            }
        }
    }

    private func cycleAlignment() {
        let all = TextSticker.Alignment.allCases
        guard let index = all.firstIndex(of: sticker.alignment) else { return }
        withAnimation(WKAnimation.selection) {
            sticker.alignment = all[(index + 1) % all.count]
        }
    }

    /// Un texto vacío no se guarda: dejaría un item invisible que se puede
    /// seleccionar y arrastrar sin verlo.
    private func finish() {
        let trimmed = sticker.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dismiss()
            return
        }
        var result = sticker
        result.string = trimmed
        onDone(result)
        dismiss()
    }
}

/// Un botón del chrome. Vista propia: son cuatro con la misma forma.
private struct ChromeButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(WK.Font.headline)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.18), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(WKPressStyle())
    }
}

/// Una muestra de color.
private struct SwatchButton: View {
    let hex: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: hex) ?? .white)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(.white, lineWidth: isSelected ? 3 : 1.5))
                .scaleEffect(isSelected ? 1.15 : 1)
                // El área de toque es mayor que el círculo: 30 puntos de
                // diámetro con ocho en fila deja un blanco de dedo entre ellos.
                .frame(width: 40, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
        .animation(WKAnimation.selection, value: isSelected)
    }
}
