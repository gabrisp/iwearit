import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// El estilista **dentro del editor**: cambia el look que tienes delante.
///
/// ## Qué respeta
///
/// Lo que ya está puesto. Las prendas del lienzo son las que quieres llevar
/// —"estas zapatillas"— así que se quedan donde están y el resto se monta
/// alrededor. Solo se suelta lo que pides soltar: "otro pantalón", "sin
/// chaqueta". Y si no dices qué cambiar y el conjunto está completo, se
/// cambia **lo que menos pega**, que es lo único que se puede decidir solo
/// sin contradecirte.
///
/// ## Y qué deshace
///
/// Nada por su cuenta: escribe en el lienzo como escribiría tu dedo, así que
/// el historial del editor lo recoge igual que cualquier otro cambio y
/// deshacer lo quita de un toque.
@MainActor
enum CanvasStylist {

    struct Outcome {
        /// Qué se ha hecho, en una línea. Se enseña un momento y se va.
        let note: String
        let didChange: Bool
    }

    static func restyle(
        prompt: String,
        outfit: Outfit,
        context: ModelContext,
        weather: WeatherSnapshot?,
        date: Date
    ) -> Outcome {
        let wardrobe = context.stylistWardrobe()
        guard !wardrobe.isEmpty else {
            return Outcome(note: "Todavía no hay ropa suficiente en el armario.", didChange: false)
        }

        let current = outfit.garments
        let currentValues = current.map(\.stylistValue)

        var base = StylistBrief(
            date: date,
            weather: weather,
            // Lo que hay puesto se queda: es lo que has elegido llevar.
            pinned: Set(current.map(\.id)),
            recentlyWorn: context.recentlyWornGarments(from: date),
            seed: UInt64(truncatingIfNeeded: Int(Date().timeIntervalSince1970))
        )

        let reading = StylistPhrase.read(prompt, wardrobe: wardrobe, base: base)
        base = reading.brief

        // Lo que se suelta: por parte nombrada —"otro pantalón"— o porque lo
        // has prohibido —"sin el jersey"—.
        var pinned = base.pinned
        for garment in currentValues where reading.freedRoles.contains(garment.role) {
            pinned.remove(garment.id)
            base.banned.insert(garment.id)
        }
        pinned.subtract(base.banned)

        // Ni has dicho qué cambiar ni falta nada: entonces se cambia lo que
        // peor pega, y se dice cuál para que no parezca capricho.
        var swapped: StylistGarment?
        let isComplete = Set(currentValues.map(\.role)).isSuperset(of: [.top, .bottom, .shoes])
        if reading.freedRoles.isEmpty, base.banned.isEmpty, isComplete {
            var probe = base
            probe.pinned = []
            if let weakest = Stylist().weakest(among: currentValues, brief: probe) {
                pinned.remove(weakest)
                base.banned.insert(weakest)
                swapped = currentValues.first { $0.id == weakest }
            }
        }
        base.pinned = pinned

        guard let look = Stylist().look(from: wardrobe, brief: base) else {
            return Outcome(
                note: reading.isBlank
                    ? "No te he entendido. Prueba con «otro pantalón», «algo más abrigado» o «sin negro»."
                    : "Con eso no me sale nada del armario.",
                didChange: false
            )
        }

        let byID = Dictionary(
            current.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        ).merging(
            fetchGarments(ids: look.garmentIDs, context: context),
            uniquingKeysWith: { first, _ in first }
        )
        let pieces = look.garmentIDs.compactMap { byID[$0] }
        guard !pieces.isEmpty else {
            return Outcome(note: "Con eso no me sale nada del armario.", didChange: false)
        }

        OutfitAssembly.place(pieces, in: outfit, context: context, keeping: pinned)

        var note = look.reason
        if let swapped {
            note = "Fuera \(swapped.name.lowercasedFirst) · " + note
        }
        return Outcome(note: note, didChange: true)
    }

    /// Las prendas que el conjunto propuesto necesita y no estaban puestas.
    private static func fetchGarments(ids: [UUID], context: ModelContext) -> [UUID: Garment] {
        let wanted = Set(ids)
        let descriptor = FetchDescriptor<Garment>(
            predicate: #Predicate { wanted.contains($0.id) && $0.deletedAt == nil }
        )
        let found = (try? context.fetch(descriptor)) ?? []
        return Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// El brillo que recorre el lienzo mientras el estilista piensa.
///
/// Encima de **todo** el lienzo y no de una prenda: lo que está cambiando es
/// el conjunto entero, y un indicador pequeño en una esquina no diría que lo
/// que estás viendo está a punto de no ser lo mismo.
struct CanvasShimmer: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            LinearGradient(
                colors: [
                    .white.opacity(0),
                    .white.opacity(0.55),
                    .white.opacity(0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: width * 0.6)
            .offset(x: phase * width * 1.6)
            .blur(radius: 18)
        }
        .background(WK.Palette.ink(0.06))
        .allowsHitTesting(false)
        .onAppear {
            // Un solo barrido continuo: parpadear o pulsar se lee como un
            // error, no como trabajo en curso.
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .transition(.opacity)
    }
}

/// Donde se le pide algo al estilista, **pegado al teclado**.
///
/// No es una hoja: abrir una hoja taparía el lienzo justo cuando lo que
/// quieres es verlo cambiar. Es una línea encima del teclado, del ancho de la
/// pantalla, y se va sola en cuanto envías.
struct CanvasStylistField: View {
    @Binding var text: String
    var isEnabled = true
    let onSend: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: WK.Spacing.s) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(WK.Font.headline)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .frame(width: 40, height: 40)
                    .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())

            TextField("¿Qué te cambio?", text: $text, axis: .vertical)
                .lineLimit(1...3)
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit(onSend)
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .adaptiveGlass(in: .capsule)

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(WK.Font.headline)
                    .foregroundStyle(WK.Palette.primaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())
            .adaptiveGlassInteractive(in: .circle)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || !isEnabled)
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.xs)
        // El foco se pide al aparecer: el botón de la barra **es** el que
        // abre el teclado, así que llegar aquí y tener que tocar otra vez
        // sería un paso de más.
        .onAppear { isFocused = true }
    }
}
