import SwiftUI
import WKDesign

/// El saldo de las dos monedas, en una píldora.
///
/// ## Por qué una píldora y no dos filas
///
/// Porque el saldo no es un ajuste, es un dato que se mira: cuántas mejoras me
/// quedan antes de gastar otra. Metido entre las filas de iCloud y las de los
/// modelos había que buscarlo; arriba a la derecha está donde se mira la hora.
///
/// Las dos monedas caben porque son dos números cortos con su icono al lado —el
/// de la varita para mejorar y el del retrato para probarse—, y porque leerlos
/// juntos es lo que dice de un vistazo qué puedes hacer hoy.
struct CreditsPill: View {
    let store: Store

    var body: some View {
        HStack(spacing: WK.Spacing.s) {
            ForEach(StoreIDs.Currency.allCases, id: \.self) { currency in
                HStack(spacing: 3) {
                    Image(systemName: currency.symbol)
                        .font(.caption2)
                        .foregroundStyle(WK.Palette.secondaryText)
                    Text("\(store.balance(of: currency))")
                        .font(WK.Font.caption.weight(.semibold))
                        .foregroundStyle(WK.Palette.primaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(.horizontal, WK.Spacing.m)
        .padding(.vertical, WK.Spacing.s)
        .adaptiveGlassInteractive(in: .capsule)
        .fixedSize()
        .animation(WKAnimation.content, value: store.balances)
    }
}

/// En qué se ha ido el saldo.
///
/// ## Por qué existe
///
/// Porque un número que baja sin explicación se lee como un cobro raro. Aquí
/// está lo que la app ha hecho, con su fecha y su precio, de lo último a lo
/// primero. No es la contabilidad de RevenueCat —el saldo lo lleva él— es el
/// registro de esta app: qué pidió y cuándo.
struct CreditsHistoryScreen: View {
    let store: Store

    @Environment(\.dismiss) private var dismiss

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        Group {
            if store.ledger.isEmpty {
                ContentUnavailableView {
                    Label("Todavía no has gastado nada", systemImage: "wand.and.stars")
                } description: {
                    Text("Aquí aparecerá cada mejora y cada prueba, con lo que costó.")
                }
            } else {
                list
            }
        }
        .background(WK.Palette.canvas.ignoresSafeArea())
        .navigationTitle("Gastos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .tint(WK.Palette.primaryText)
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: WK.Spacing.l) {
                WKSection("Saldo") {
                    ForEach(Array(StoreIDs.Currency.allCases.enumerated()), id: \.element) { index, currency in
                        WKValueRow(
                            store.name(of: currency),
                            value: "\(store.balance(of: currency))",
                            showsSeparator: index < StoreIDs.Currency.allCases.count - 1
                        )
                    }
                }

                WKSection("En qué se ha ido") {
                    ForEach(Array(store.ledger.enumerated()), id: \.element.id) { index, entry in
                        WKRow(showsSeparator: index < store.ledger.count - 1) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.detail ?? entry.cost.label)
                                    .font(WK.Font.rowTitle)
                                    .foregroundStyle(WK.Palette.primaryText)
                                    .lineLimit(1)
                                Text(Self.stamp.string(from: entry.date))
                                    .font(WK.Font.caption)
                                    .foregroundStyle(WK.Palette.secondaryText)
                            }
                        } trailing: {
                            HStack(spacing: 3) {
                                Text("−\(entry.amount)")
                                    .font(WK.Font.rowTitle)
                                    .monospacedDigit()
                                Image(systemName: entry.currency.symbol)
                                    .font(.caption2)
                            }
                            .foregroundStyle(WK.Palette.secondaryText)
                        }
                    }
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WK.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }
}
