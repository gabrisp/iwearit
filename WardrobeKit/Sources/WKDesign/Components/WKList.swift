import SwiftUI

/// Listas propias, no `List` del sistema.
///
/// `List` trae su propio fondo, sus propios separadores y su propio margen, y
/// pelearse con ellos acaba en una pila de `listRowBackground` y
/// `listRowInsets` que se comporta distinto en cada iOS. Una tarjeta con filas
/// dentro se controla entera y se ve igual en todas partes.

/// Sección: título opcional y una tarjeta con filas.
public struct WKSection<Content: View>: View {
    private let title: String?
    private let footer: String?
    private let content: Content

    public init(
        _ title: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            if let title {
                Text(title.uppercased())
                    .font(.caption2.weight(.medium))
                    .tracking(0.6)
                    .foregroundStyle(WK.Palette.tertiaryText)
                    .padding(.horizontal, WK.Spacing.cardInset)
            }

            VStack(spacing: 0) { content }
                .wkCard()

            if let footer {
                Text(footer)
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.tertiaryText)
                    .padding(.horizontal, WK.Spacing.cardInset)
            }
        }
    }
}

/// Fila de una sección.
///
/// El separador lo dibuja la fila y no la sección, y solo si no es la última:
/// así una sección no necesita saber cuántos hijos tiene para no dejar una
/// línea suelta al final.
public struct WKRow<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing
    private let showsSeparator: Bool
    private let action: (() -> Void)?

    public init(
        showsSeparator: Bool = true,
        action: (() -> Void)? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.showsSeparator = showsSeparator
        self.action = action
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let action {
                Button(action: action) { row }
                    .buttonStyle(WKRowButtonStyle())
            } else {
                row
            }

            if showsSeparator {
                Rectangle()
                    .fill(WK.Palette.ink(0.07))
                    .frame(height: 1)
                    .padding(.leading, WK.Spacing.cardInset)
            }
        }
    }

    private var row: some View {
        HStack(spacing: WK.Spacing.m) {
            leading
            Spacer(minLength: WK.Spacing.s)
            trailing
        }
        .padding(.horizontal, WK.Spacing.cardInset)
        .padding(.vertical, WK.Spacing.m - 2)
        .contentShape(.rect)
    }
}

/// Fila de texto con valor a la derecha, que es el 80% de los casos.
public struct WKValueRow: View {
    private let label: String
    private let value: String?
    private let showsSeparator: Bool

    public init(_ label: String, value: String? = nil, showsSeparator: Bool = true) {
        self.label = label
        self.value = value
        self.showsSeparator = showsSeparator
    }

    public var body: some View {
        WKRow(showsSeparator: showsSeparator) {
            Text(label)
                .font(WK.Font.rowTitle)
                .foregroundStyle(WK.Palette.primaryText)
        } trailing: {
            if let value {
                Text(value)
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .monospacedDigit()
            }
        }
    }
}

/// Resalte al pulsar una fila, sin el gris de sistema que se queda pegado.
public struct WKRowButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? WK.Palette.ink(0.05) : .clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: WK.Spacing.l) {
            WKSection(String(localized: "wkdesign.wklist.plan", defaultValue: "Plan", bundle: .module), footer: String(localized: "wkdesign.wklist.cancelAnytime", defaultValue: "Cancel anytime.", bundle: .module)) {
                WKValueRow(String(localized: "wkdesign.wklist.status", defaultValue: "Status", bundle: .module), value: String(localized: "wkdesign.wklist.free", defaultValue: "Free", bundle: .module))
                WKValueRow(String(localized: "common.clothes", defaultValue: "Clothes", bundle: .module), value: "12 de 25")
                WKValueRow(String(localized: "common.suitcases", defaultValue: "Suitcases", bundle: .module), value: "0 de 1", showsSeparator: false)
            }
            WKSection(String(localized: "wkdesign.wklist.models", defaultValue: "Models", bundle: .module)) {
                WKValueRow(String(localized: "wkdesign.wklist.source", defaultValue: "Source", bundle: .module), value: "appwrite")
                WKValueRow(String(localized: "wkdesign.wklist.segmenter", defaultValue: "Segmenter", bundle: .module), value: "listo (v1)", showsSeparator: false)
            }
        }
        .padding(WK.Spacing.screenInset)
    }
    .scrollIndicators(.hidden)
    .background(WK.Palette.canvas)
}
