import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Cómo se ve la maleta: nombre, icono, color y destino.
///
/// Todo junto porque son las cuatro cosas que se deciden a la vez —al crear el
/// viaje— y repartirlas en cuatro sitios obligaría a recorrer la app para
/// preparar una escapada.
struct SuitcaseStyleSheet: View {
    @Bindable var suitcase: Suitcase

    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var isPickingPlace = false

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.l) {
            Text("Maleta")
                .font(WK.Font.title)
                .foregroundStyle(WK.Palette.primaryText)

            TextField("Nombre", text: $suitcase.name)
                .font(WK.Font.rowTitle)
                .padding(WK.Spacing.m)
                .background(WK.Palette.shelf, in: .rect(cornerRadius: WK.Radius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                        .stroke(WK.Palette.ink(0.07), lineWidth: 1)
                )

            symbols
            tints

            WKSection {
                WKRow(showsSeparator: false, action: { isPickingPlace = true }) {
                    HStack {
                        Label("Destino", systemImage: "mappin.and.ellipse")
                            .foregroundStyle(WK.Palette.primaryText)
                        Spacer()
                        Text(suitcase.destinationName ?? "Elegir")
                            .foregroundStyle(WK.Palette.secondaryText)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WK.Palette.tertiaryText)
                    }
                }
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .wkDynamicSheet()
        .sheet(isPresented: $isPickingPlace) {
            PlaceSearchSheet(title: "¿A dónde vas?") { place in
                suitcase.destination = place
            }
        }
    }

    private var symbols: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.s) {
                ForEach(SuitcaseEmoji.allCases) { symbol in
                    SymbolChip(
                        symbol: symbol,
                        isSelected: SuitcaseEmoji.display(for: suitcase.symbolName) == symbol.rawValue
                    ) {
                        withAnimation(WKAnimation.selection) {
                            suitcase.symbolName = symbol.rawValue
                        }
                    }
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
        }
        .scrollIndicators(.hidden)
        // Fuera del margen, y el margen se lo pone el contenido: si no, el aro
        // del emoji elegido sale cortado en el primero y en el último.
        .wkBleedingStrip()
    }

    private var tints: some View {
        // En rejilla: diez en una fila salen a 30 puntos cada uno y se tocan
        // entre ellos.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: WK.Spacing.s) {
            ForEach(SuitcaseTint.allCases) { tint in
                TintChip(
                    tint: tint,
                    isSelected: suitcase.colorRaw == tint.rawValue
                ) {
                    withAnimation(WKAnimation.selection) {
                        suitcase.colorRaw = tint.rawValue
                    }
                }
            }
        }
    }
}

/// Un icono elegible.
private struct SymbolChip: View {
    let symbol: SuitcaseEmoji
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(symbol.rawValue)
                .font(.system(size: 26))
                .frame(width: 52, height: 52)
                .background(
                    isSelected ? WK.Palette.accent : WK.Palette.shelf,
                    in: .rect(cornerRadius: WK.Radius.medium, style: .continuous)
                )
                .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}

/// Un color elegible.
private struct TintChip: View {
    let tint: SuitcaseTint
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(
                    red: tint.components.red,
                    green: tint.components.green,
                    blue: tint.components.blue
                ))
                .frame(width: 38, height: 38)
                .overlay(Circle().stroke(WK.Palette.accent, lineWidth: isSelected ? 3 : 0))
                // El toque es mayor que el círculo: seis en fila a 38 puntos
                // dejan un hueco de dedo entre ellos.
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
        .animation(WKAnimation.selection, value: isSelected)
    }
}
