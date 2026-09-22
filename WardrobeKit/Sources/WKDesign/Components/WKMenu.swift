import SwiftUI

/// Menú propio, no el `Menu` del sistema.
///
/// El del sistema trae su propio fondo, su tipografía y su animación, y no hay
/// forma de alinearlo con el resto de la app: quedaba como una pieza prestada
/// en medio de pantallas que sí están diseñadas.
///
/// Se presenta como hoja anclada abajo y no como popover: el pulgar llega ahí,
/// y un popover colgando de un botón de la esquina superior obliga a estirar la
/// mano para elegir.
public struct WKMenuItem: Identifiable {
    public let id: String
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let isEnabled: Bool
    let action: () -> Void

    public init(
        id: String,
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isEnabled = isEnabled
        self.action = action
    }
}

public struct WKMenuSheet: View {
    private let title: String?
    private let items: [WKMenuItem]
    /// Una sección propia encima de las opciones, cuando la hoja tiene algo
    /// más que ofrecer que una lista de acciones.
    private let header: AnyView?
    @Environment(\.dismiss) private var dismiss

    public init(title: String? = nil, items: [WKMenuItem]) {
        self.title = title
        self.items = items
        self.header = nil
    }

    public init<Header: View>(
        title: String? = nil,
        items: [WKMenuItem],
        @ViewBuilder header: () -> Header
    ) {
        self.title = title
        self.items = items
        self.header = AnyView(header())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.m) {
            if let title {
                Text(title)
                    .font(WK.Font.title)
                    .foregroundStyle(WK.Palette.primaryText)
            }

            if let header { header }

            WKSection {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    WKRow(
                        showsSeparator: index < items.count - 1,
                        action: {
                            // Se cierra **antes** de actuar: si la acción abre
                            // otra hoja, presentar una sobre otra que se está
                            // cerrando deja las dos a medias.
                            dismiss()
                            item.action()
                        }
                    ) {
                        Label(item.title, systemImage: item.systemImage)
                            .font(WK.Font.rowTitle)
                            .foregroundStyle(
                                item.role == .destructive ? .red : WK.Palette.primaryText
                            )
                    }
                    .disabled(!item.isEnabled)
                    .opacity(item.isEnabled ? 1 : 0.4)
                }
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .wkDynamicSheet()
    }
}
