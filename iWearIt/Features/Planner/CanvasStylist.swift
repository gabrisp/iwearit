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
            return Outcome(note: String(localized: "planner.canvasstylist.thereArenTEnoughClothes", defaultValue: "There aren't enough clothes in the closet yet."), didChange: false)
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

        // **Siempre hay algo que soltar.**
        //
        // Si todo lo que hay puesto se queda fijo, el estilista devuelve el
        // mismo conjunto y contesta sin haber cambiado nada — que es
        // exactamente lo que parecía roto: respondía y el lienzo seguía igual.
        // Así que cuando no has dicho qué cambiar, se decide aquí, por este
        // orden, y se cuenta cuál ha sido.
        var swapped: [StylistGarment] = []
        if reading.freedRoles.isEmpty, base.banned.isEmpty, !currentValues.isEmpty {
            for piece in loosen(currentValues, brief: base, phrase: reading) {
                pinned.remove(piece.id)
                base.banned.insert(piece.id)
                swapped.append(piece)
            }
        }
        base.pinned = pinned

        guard let look = Stylist().look(from: wardrobe, brief: base) else {
            return Outcome(
                note: reading.isBlank
                    ? String(localized: "planner.canvasstylist.iDidnTUnderstandTry", defaultValue: "I didn't understand. Try «other trousers», «something warmer» or «no black».")
                    : String(localized: "planner.canvasstylist.nothingInTheClosetWorks", defaultValue: "Nothing in the closet works with that."),
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
            return Outcome(note: String(localized: "planner.canvasstylist.nothingInTheClosetWorks", defaultValue: "Nothing in the closet works with that."), didChange: false)
        }

        // **Y si sale lo mismo, se dice.** Rehacer el lienzo con las mismas
        // prendas y contestar como si algo hubiera pasado es la forma más
        // rápida de que no te fíes de lo que propone.
        let before = Set(current.map(\.id))
        let after = Set(pieces.map(\.id))
        guard before != after else {
            return Outcome(
                note: String(localized: "planner.canvasstylist.withWhatSInYour", defaultValue: "With what's in your closet, this is the best match. I'll leave it."),
                didChange: false
            )
        }

        OutfitAssembly.place(pieces, in: outfit, context: context, keeping: pinned)

        var note = look.reason
        let removed = swapped.filter { !after.contains($0.id) }
        if let first = removed.first {
            note = String(localized: "planner.canvasstylist.out", defaultValue: "Out \(String(describing: first.name.lowercasedFirst)) · ") + note
        }
        return Outcome(note: note, didChange: true)
    }

    /// Qué se suelta cuando no lo has dicho tú.
    ///
    /// Por este orden, y siempre algo mientras haya más de una prenda:
    ///
    /// 1. **Lo que choca con lo que pediste**: si pides azul y no hay nada
    ///    azul, se va lo que menos aporta para dejarle sitio; si pides
    ///    deporte, se va lo que no es de deporte; si pides abrigo, lo que no
    ///    abriga.
    /// 2. **Lo que peor pega** del conjunto, medido quitándolo y viendo si el
    ///    resto mejora (ver `Stylist.weakest`).
    /// 3. Y si ni eso —un conjunto de dos piezas que encajan—, la que no es
    ///    imprescindible, o la de arriba: algo tiene que moverse cuando pides
    ///    un cambio.
    private static func loosen(
        _ pieces: [StylistGarment],
        brief: StylistBrief,
        phrase: StylistPhrase.Reading
    ) -> [StylistGarment] {
        guard pieces.count > 1 else { return pieces }

        let preferred = Set(brief.preferredColors)
        let required = Set(brief.requiredTags)

        var conflicting: [StylistGarment] = []
        if !preferred.isEmpty, !pieces.contains(where: { preferred.contains($0.tone.familyName) }) {
            // Nadie lleva el color pedido: sale el que menos pinta, que es el
            // que menos se echa en falta.
            conflicting += weakestOrLast(pieces, brief: brief).map { [$0] } ?? []
        }
        if !required.isEmpty {
            conflicting += pieces.filter { Set($0.tags).isDisjoint(with: required) }
        }
        if let warmth = brief.warmth {
            conflicting += pieces.filter {
                $0.seasons != .all && $0.seasons.intersection(warmth.seasons).isEmpty
            }
        }
        if !conflicting.isEmpty {
            var seen = Set<UUID>()
            // Nunca todas: algo tiene que quedar de lo que tenías puesto.
            return conflicting
                .filter { seen.insert($0.id).inserted }
                .prefix(max(1, pieces.count - 1))
                .map { $0 }
        }

        return weakestOrLast(pieces, brief: brief).map { [$0] } ?? []
    }

    /// La que peor pega; y si todas pegan, la más prescindible.
    private static func weakestOrLast(
        _ pieces: [StylistGarment],
        brief: StylistBrief
    ) -> StylistGarment? {
        var probe = brief
        probe.pinned = []
        if let id = Stylist().weakest(among: pieces, brief: probe) {
            return pieces.first { $0.id == id }
        }
        // El orden es el de leerse un conjunto: complemento, abrigo, arriba,
        // abajo, calzado. Lo primero que sobra es lo accesorio.
        return pieces.min { $0.role.sortOrder < $1.role.sortOrder }
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
            // **La equis cierra el teclado además del campo.**
            //
            // Quitar el campo del árbol no siempre se lleva el teclado por
            // delante: se quedaba el teclado puesto tapando media pantalla sin
            // nada donde escribir. Se suelta el foco aquí, a mano, y el
            // teclado baja con él.
            Button {
                isFocused = false
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(WK.Font.headline)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .frame(width: 40, height: 40)
                    .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())

            TextField(String(localized: "planner.canvasstylist.whatShouldIChange", defaultValue: "What should I change?"), text: $text, axis: .vertical)
                .lineLimit(1...3)
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit {
                    isFocused = false
                    onSend()
                }
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .adaptiveGlass(in: .capsule)

            // Y al enviar, lo mismo: lo que hay que mirar ahora es el lienzo
            // rehaciéndose, no el teclado.
            Button {
                isFocused = false
                onSend()
            } label: {
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
