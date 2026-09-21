import SwiftUI
import WKDesign

/// Con qué se pinta: pincel o goma, color y grosor.
///
/// Va dentro de la misma bandeja que las prendas y los stickers, y por eso es
/// una vista de contenido y no una pantalla: el comportamiento —arrastrar para
/// bajarla, el lienzo vivo detrás, el alto según lo que lleva— lo pone
/// `canvasTraySheet`, igual que a las demás.
///
/// No es la paleta de PencilKit a propósito: esa trae su propio aspecto y su
/// propio modelo de datos, y aparecería como una pieza de otro sistema justo
/// encima del lienzo.
public struct DrawingPicker: View {
    private let drawing: CanvasDrawing

    public init(drawing: CanvasDrawing) {
        self.drawing = drawing
    }

    public var body: some View {
        VStack(spacing: WK.Spacing.m) {
            tools
            colors
            thickness
            actions
        }
        .padding(.horizontal, WK.Spacing.m)
        .animation(WKAnimation.selection, value: drawing.tool)
    }

    /// Pincel o goma.
    private var tools: some View {
        HStack(spacing: WK.Spacing.xs) {
            ToolChip(
                label: "Pincel",
                symbol: "scribble",
                isSelected: drawing.tool == .brush
            ) {
                withAnimation(WKAnimation.selection) { drawing.tool = .brush }
            }
            ToolChip(
                label: "Goma",
                symbol: "eraser",
                isSelected: drawing.tool == .eraser
            ) {
                withAnimation(WKAnimation.selection) { drawing.tool = .eraser }
            }
        }
    }

    /// Los colores, en una fila que se desplaza.
    ///
    /// **Desaparecen con la goma puesta.** Una goma no tiene color, y dejar la
    /// paleta encendida mientras borras es ofrecer un control que no hace nada
    /// a lo que estás haciendo.
    @ViewBuilder
    private var colors: some View {
        if drawing.tool == .brush {
            colorRow.transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var colorRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.s) {
                ForEach(CanvasDrawing.palette, id: \.self) { hex in
                    DrawingSwatch(hex: hex, isSelected: drawing.colorHex == hex) {
                        withAnimation(WKAnimation.selection) { drawing.colorHex = hex }
                    }
                }
            }
            .padding(.horizontal, WK.Spacing.m)
        }
        .scrollIndicators(.hidden)
        .frame(height: 44)
        // El swatch elegido crece y se le dibuja un aro: sin sacar el scroll
        // fuera del margen, al primero y al último se les corta.
        .wkBleedingStrip(WK.Spacing.m)
    }

    /// El grosor, con su muestra al lado.
    ///
    /// La muestra es el propio círculo a tamaño real: un número —"12 pt"— no
    /// dice nada hasta que pintas, y entonces ya has pintado.
    private var thickness: some View {
        HStack(spacing: WK.Spacing.m) {
            Circle()
                .fill(Color(hex: drawing.colorHex) ?? .black)
                .frame(width: drawing.width, height: drawing.width)
                .frame(width: 34, height: 34)
                .animation(WKAnimation.selection, value: drawing.width)

            Slider(
                value: Binding(get: { drawing.width }, set: { drawing.width = $0 }),
                in: 2...40
            )
            .tint(WK.Palette.accent)
        }
    }

    private var actions: some View {
        HStack(spacing: WK.Spacing.s) {
            ActionChip(label: "Deshacer", symbol: "arrow.uturn.backward") {
                withAnimation(WKAnimation.content) { drawing.undo() }
            }
            .disabled(drawing.strokes.isEmpty)

            ActionChip(label: "Borrar todo", symbol: "trash") {
                withAnimation(WKAnimation.content) { drawing.clear() }
            }
            .disabled(drawing.strokes.isEmpty)
        }
        .opacity(drawing.strokes.isEmpty ? 0.4 : 1)
        .animation(WKAnimation.selection, value: drawing.strokes.isEmpty)
    }
}

/// Un útil: pincel o goma.
private struct ToolChip: View {
    let label: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .font(WK.Font.captionMedium)
                .foregroundStyle(isSelected ? WK.Palette.onAccent : WK.Palette.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, WK.Spacing.s)
                .background {
                    Capsule().fill(isSelected ? WK.Palette.accent : WK.Palette.ink(0.08))
                }
                .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
    }
}

/// Un color de pintar.
private struct DrawingSwatch: View {
    let hex: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: hex) ?? .black)
                .frame(width: 28, height: 28)
                // Doble aro: uno claro y otro oscuro. Con uno solo, el blanco
                // sobre el lienzo claro y el negro sobre el oscuro se quedaban
                // sin contorno y no se veía cuál estaba elegido.
                .overlay(Circle().stroke(.white, lineWidth: isSelected ? 3 : 1))
                .overlay(Circle().stroke(WK.Palette.ink(0.25), lineWidth: 1))
                .scaleEffect(isSelected ? 1.15 : 1)
                .frame(width: 40, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
        .animation(WKAnimation.selection, value: isSelected)
    }
}

private struct ActionChip: View {
    let label: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, WK.Spacing.s)
                .background { Capsule().fill(WK.Palette.ink(0.08)) }
                .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
    }
}
