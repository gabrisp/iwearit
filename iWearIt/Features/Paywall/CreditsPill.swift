import RevenueCat
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
        // **Sin cristal detrás.** En la barra ya hay un botón con su píldora a
        // la izquierda; otra al lado convertía la barra en una fila de
        // pastillas. Los dos números con su icono se leen igual de bien y la
        // barra respira.
        .padding(.horizontal, WK.Spacing.xs)
        .padding(.vertical, WK.Spacing.xs)
        .contentShape(.capsule)
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
    /// Si ya paga: quien no tiene plan verá el paywall y quien lo tiene, los
    /// paquetes sueltos.
    let isPro: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingPaywall = false

    /// Si se ha quedado sin nada que gastar.
    private var isEmptyHanded: Bool {
        StoreIDs.Currency.allCases.allSatisfy { store.balance(of: $0) == 0 }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        // **Primero lo que tienes.** Un cartel de "todavía no has gastado
        // nada" ocupaba la pantalla entera para decir algo que no se venía a
        // leer: lo que se viene a mirar es el saldo, y el gasto es el detalle
        // de debajo.
        list
        .background(WK.Palette.canvas.ignoresSafeArea())
        .navigationTitle(String(localized: "paywall.creditspill.spending", defaultValue: "Spending"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .tint(WK.Palette.primaryText)
            }
        }
        // **La salida cuando no queda nada.**
        //
        // Sin monedas y sin plan, la pantalla decía "0" y ahí se acababa. El
        // botón es la respuesta a "¿y ahora qué?": suscribirse si no tienes
        // plan, o comprar un puñado si ya lo tienes y te has quedado seco.
        .adaptiveSafeAreaBar(edge: .bottom) { bottom }
        // El paywall se presenta **desde aquí** y no desde la raíz: la raíz ya
        // tiene su hoja puesta —esta— y dos en la misma vista dejan muda a una.
        .sheet(isPresented: $isShowingPaywall) {
            PaywallSheet(feature: nil)
        }
    }

    @ViewBuilder
    private var bottom: some View {
        if !isPro {
            VStack(spacing: WK.Spacing.xs) {
                WKPrimaryButton(String(localized: "paywall.creditspill.getCoins", defaultValue: "Get coins")) { isShowingPaywall = true }
                Text(String(localized: "paywall.creditspill.everyPlanAddsCoinsOn", defaultValue: "Every plan adds coins on each renewal."))
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.tertiaryText)
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WK.Spacing.xs)
        } else if !store.coinPacks.isEmpty {
            VStack(spacing: WK.Spacing.s) {
                if isEmptyHanded {
                    Text(String(localized: "paywall.creditspill.youVeRunOutOf", defaultValue: "You've run out of coins."))
                        .font(WK.Font.caption)
                        .foregroundStyle(WK.Palette.secondaryText)
                }
                ForEach(store.coinPacks, id: \.identifier) { pack in
                    WKPrimaryButton(
                        "\(pack.storeProduct.localizedTitle) · \(pack.storeProduct.localizedPriceString)"
                    ) {
                        Task { _ = await store.purchase(pack) }
                    }
                    .disabled(store.isWorking)
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WK.Spacing.xs)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: WK.Spacing.l) {
                WKSection(String(localized: "paywall.creditspill.balance", defaultValue: "Balance")) {
                    ForEach(Array(StoreIDs.Currency.allCases.enumerated()), id: \.element) { index, currency in
                        WKValueRow(
                            store.name(of: currency),
                            value: "\(store.balance(of: currency))",
                            showsSeparator: index < StoreIDs.Currency.allCases.count - 1
                        )
                    }
                }

                WKSection(String(localized: "paywall.creditspill.whereItWent", defaultValue: "Where it went")) {
                    if store.ledger.isEmpty {
                        WKRow(showsSeparator: false) {
                            Text(String(localized: "paywall.creditspill.nothingYet", defaultValue: "Nothing yet"))
                                .font(WK.Font.rowTitle)
                                .foregroundStyle(WK.Palette.secondaryText)
                        }
                    }
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
