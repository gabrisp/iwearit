import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Todas las maletas, como cualquier otra balda abierta.
///
/// ## Por qué existe
///
/// La cabecera de "Maletas" llevaba chevron y estaba **desactivada**: prometía
/// abrirse y no abría. Las demás baldas se abren desde el primer día, y el
/// altillo no tiene por qué ser distinto — con tres viajes la fila horizontal
/// ya no los enseña todos.
///
/// ## El resumen de arriba
///
/// Una balda de prendas no necesita cabecera: la prenda se explica sola. Un
/// viaje no: lo que hace falta saber de un vistazo es **cuánto queda por
/// meter** y **cuál es el siguiente**, que es justo lo que no cabe en la
/// tarjeta de la maleta. Por eso aquí hay un resumen y en las otras baldas no.
///
/// Va **dentro del scroll** y no en una barra: es contenido, se lee una vez al
/// entrar y a partir de ahí estorba. Fijo arriba robaría sitio a lo que has
/// venido a ver.
struct SuitcasesScreen: View {
    @Query(FetchDescriptor<Suitcase>.visibleSuitcases())
    private var suitcases: [Suitcase]

    @State private var isPresentingNew = false
    @Environment(AppEnvironment.self) private var appEnvironment

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: WK.Spacing.l)]

    var body: some View {
        ScrollView {
            // Aire de sobra entre el resumen y las maletas: son dos cosas
            // distintas —lo que hay que saber y lo que hay que tocar— y con el
            // margen normal se leían como una sola lista.
            LazyVStack(spacing: WK.Spacing.xxl) {
                if !suitcases.isEmpty {
                    SuitcasesSummary(suitcases: suitcases)
                }

                LazyVGrid(columns: columns, spacing: WK.Spacing.l) {
                    ForEach(suitcases) { suitcase in
                        SuitcaseCard(suitcase: suitcase)
                    }

                    NewSuitcaseCard {
                        appEnvironment.gate.require(.suitcases) { isPresentingNew = true }
                    }
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WK.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        // Sin recortar: las maletas llevan sombra y el asa se sale por arriba.
        .scrollClipDisabled()
        .background(WK.Palette.canvas.ignoresSafeArea())
        .adaptiveScrollEdge(.top)
        .navigationTitle("Maletas")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingNew) { NewSuitcaseSheet() }
        .overlay {
            if suitcases.isEmpty {
                ContentUnavailableView(
                    "Todavía no hay maletas",
                    systemImage: "suitcase",
                    description: Text("Crea una para preparar un viaje día a día.")
                )
            }
        }
    }
}

/// Lo que hay que saber antes de abrir ninguna.
private struct SuitcasesSummary: View {
    let suitcases: [Suitcase]

    private var packed: Int { suitcases.reduce(0) { $0 + $1.packedCount } }
    private var total: Int { suitcases.reduce(0) { $0 + $1.packingEntries.count } }

    /// El viaje que viene, si alguno tiene fechas por delante.
    private var next: Suitcase? {
        suitcases
            .filter { ($0.startDate ?? .distantPast) >= Calendar.current.startOfDay(for: Date()) }
            .min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            Text(headline)
                .font(WK.Font.title)
                .foregroundStyle(WK.Palette.primaryText)

            if total > 0 {
                VStack(alignment: .leading, spacing: WK.Spacing.xs) {
                    Text("\(packed) de \(total) prendas metidas")
                        .font(WK.Font.caption)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .monospacedDigit()

                    ProgressView(value: Double(packed), total: Double(max(total, 1)))
                        .tint(WK.Palette.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, WK.Spacing.s)
    }

    private var headline: String {
        guard let next, let start = next.startDate else {
            return suitcases.count == 1 ? "Una maleta" : "\(suitcases.count) maletas"
        }
        return "\(next.name), el \(Self.day.string(from: start))"
    }
}
