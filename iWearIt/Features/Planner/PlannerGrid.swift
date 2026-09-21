import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKCore
import WKDesign
import WKPersistence

/// Todo lo planificado, de un vistazo.
///
/// Los outfits **de ese día**, todos a la vez.
///
/// El scroll vertical es bueno para montar uno; es malo para comparar los tres
/// que tienes para el sábado, porque hay que pasar de uno a otro y recordar.
/// En rejilla se ven juntos, que es cuando se decide cuál te pones.
struct PlannerGrid: View {
    let date: Date
    let store: ImageStore
    let onOpen: (Outfit) -> Void
    let onCreate: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var movingOutfit: Outfit?
    /// Compartido con la rejilla de todos los outfits: es lo que hace que al
    /// cambiar de modo **cada lienzo viaje a su sitio nuevo** en vez de que se
    /// funda un bloque entero con otro.
    let morph: Namespace.ID
    /// Para que el editor crezca desde la celda tocada.
    let zoom: Namespace.ID

    @Query private var days: [PlannedDay]

    init(
        date: Date,
        store: ImageStore,
        morph: Namespace.ID,
        zoom: Namespace.ID,
        onOpen: @escaping (Outfit) -> Void,
        onCreate: @escaping () -> Void
    ) {
        let dayStart = Calendar.current.startOfDay(for: date)
        self.date = dayStart
        self.store = store
        self.morph = morph
        self.zoom = zoom
        self.onOpen = onOpen
        self.onCreate = onCreate
        _days = Query(filter: #Predicate<PlannedDay> { $0.dayStart == dayStart })
    }

    private var outfits: [Outfit] { days.first?.orderedOutfits ?? [] }

    /// Copia el outfit **en el mismo día**.
    ///
    /// Con sus prendas y sus stickers: duplicar un outfit para cambiarle los
    /// zapatos es el caso real, y una copia vacía no ahorraría nada.
    private func duplicate(_ outfit: Outfit) {
        let copy = Outfit(name: outfit.name)
        copy.backdropRaw = outfit.backdropRaw
        modelContext.insert(copy)
        copy.plannedDay = outfit.plannedDay

        for item in outfit.visibleItems {
            let clone = CanvasItem(transform: item.transform, garment: item.garment)
            if let sticker = item.sticker { clone.apply(sticker) }
            clone.isFlipped = item.isFlipped
            clone.outfit = copy
            modelContext.insert(clone)
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: outfitGridColumns, spacing: WK.Spacing.m) {
                ForEach(outfits) { outfit in
                    Button { onOpen(outfit) } label: {
                        PlannerGridCell(outfit: outfit, store: store)
                    }
                    .buttonStyle(WKPressStyle())
                    // **Por el `id` del outfit y no por su identificador de
                    // base.** El de la base cambia cuando el contexto guarda,
                    // así que un outfit recién creado cambiaba de identidad a
                    // mitad de la animación y SwiftUI pintaba los dos: el de
                    // antes y el de después, hasta que algo forzaba a redibujar.
                    .matchedGeometryEffect(id: outfit.stableID, in: morph)
                    // El editor crece **desde esta celda**, que es de donde
                    // viene: abrirlo desde el centro de la pantalla haría
                    // perder de vista cuál de los tres outfits se abrió.
                    .adaptiveZoomSource(id: outfit.stableID, in: zoom)
                    // En rejilla se ven varios a la vez, que es justo cuando
                    // apetece reutilizar uno: copiarlo para variarlo o mandarlo
                    // a otro día. En revista no tendría sentido —solo ves uno—
                    // y por eso el menú vive aquí.
                    .contextMenu {
                        Button("Duplicar", systemImage: "plus.square.on.square") {
                            duplicate(outfit)
                        }
                        Button("Mover a otro día", systemImage: "calendar") {
                            movingOutfit = outfit
                        }
                        // Destructivo y el último: en un menú corto, lo que
                        // borra va abajo y en rojo, para que el dedo no lo
                        // encuentre de camino a otra cosa.
                        Button("Eliminar", systemImage: "trash", role: .destructive) {
                            withAnimation(WKAnimation.content) {
                                outfit.markDeleted()
                            }
                        }
                    }
                }

                NewOutfitGridCell(action: onCreate)
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            // El scroll **ignora el área segura** —el fondo llega a los bordes,
            // igual que el lienzo— y el hueco lo pone el contenido por dentro.
            // Al revés, el propio scroll se recorta y aparece un canto donde el
            // papel debería seguir.
            .safeAreaPadding(.vertical)
            // La tira de días flota **encima** de la rejilla, y no es una
            // barra baja: lleva el calendario, los cinco días y el botón de
            // modo. Con 72 puntos la primera fila de celdas le quedaba por
            // debajo justo al abrir, antes de tocar nada.
            .padding(.top, 288)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $movingOutfit) { outfit in
            MoveOutfitSheet(outfit: outfit)
        }
        // Arriba **y abajo**: el fondo llega a los dos bordes igual que el
        // lienzo, y el hueco lo pone el contenido por dentro.
        .ignoresSafeArea(edges: [.top, .bottom])
        // El mismo fondo que el lienzo y que el resto de la pantalla: la
        // rejilla no es otro sitio, es el mismo día visto de otra forma.
        .background(WK.Palette.canvas)
    }
}

/// El hueco para uno más.
///
/// Es el equivalente a seguir bajando en el librito: crear no debería obligar a
/// salir de la vista en la que estás decidiendo.
///
/// Vista propia porque la usan **dos** rejillas —la del plan y la de una maleta
/// sin fechas— y repetirla dentro de cada `@ViewBuilder` costaría dos diffs por
/// cada retoque del trazo discontinuo.
struct NewOutfitGridCell: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: WK.Radius.card, style: .continuous)
                .strokeBorder(
                    WK.Palette.ink(0.18),
                    style: StrokeStyle(lineWidth: 2, dash: [7, 6])
                )
                .aspectRatio(5 / 7, contentMode: .fit)
                .overlay {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(WK.Palette.secondaryText)
                }
                .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}

/// Las columnas de una rejilla de outfits. Dos, en las dos pantallas: con tres
/// la miniatura del lienzo se queda tan pequeña que ya no se distingue una
/// camiseta de otra, que es justo para lo que se mira.
let outfitGridColumns = [
    GridItem(.flexible(), spacing: WK.Spacing.m),
    GridItem(.flexible(), spacing: WK.Spacing.m),
]

/// Un lienzo en miniatura.
///
/// El canvas de verdad, escalado: el espacio lógico es fijo, así que la misma
/// vista sirve a 160 puntos y a pantalla completa sin recolocar nada. Un
/// render aparte se desincronizaría en cuanto se editara el outfit.
struct PlannerGridCell: View {
    let outfit: Outfit
    let store: ImageStore
    /// El fondo cuando el outfit no trae el suyo.
    ///
    /// Dentro de una maleta **es el color de la maleta**, no el de la página:
    /// un lienzo de maleta es de su color siempre, y la rejilla tiene que
    /// enseñar lo mismo que la página. Con el de la app por defecto, las
    /// celdas salían de color claro sobre el tinte de la maleta y parecía que
    /// el fondo del lienzo se colaba por todas partes.
    var fallback: Color = WK.Palette.canvas

    @State private var selection = CanvasSelection()

    var body: some View {
        FreeformCanvas(outfit: outfit, store: store, selection: selection)
            .allowsHitTesting(false)
            .aspectRatio(5 / 7, contentMode: .fit)
            .background(backdropColor)
            .clipShape(.rect(cornerRadius: WK.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WK.Radius.card, style: .continuous)
                    .stroke(WK.Palette.ink(0.07), lineWidth: 1)
            )
    }

    private var backdropColor: Color {
        guard
            let components = OutfitBackdrop(rawValue: outfit.backdropRaw ?? "")?.components
        else { return fallback }
        return Color(red: components.red, green: components.green, blue: components.blue)
    }
}

/// Mandar un outfit a otro día.
private struct MoveOutfitSheet: View {
    let outfit: Outfit

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.m) {
            Text("Mover a otro día")
                .font(WK.Font.title)
                .foregroundStyle(WK.Palette.primaryText)

            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(WK.Palette.accent)

            WKPrimaryButton("Mover") { move() }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .wkDynamicSheet()
        .task {
            if let current = outfit.plannedDay?.dayStart { date = current }
        }
    }

    /// Se mueve, no se copia: el outfit deja de estar en el día viejo.
    ///
    /// El día de destino se crea si no existe, y el de origen se queda sin él
    /// —vacío si era el único—, que es exactamente lo que el usuario pidió al
    /// decir "mover".
    private func move() {
        let dayStart = Calendar.current.startOfDay(for: date)
        let existing = try? modelContext.fetch(
            FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.dayStart == dayStart })
        )
        let day = existing?.first ?? {
            let new = PlannedDay(dayStart: dayStart)
            modelContext.insert(new)
            return new
        }()
        outfit.plannedDay = day
        dismiss()
    }
}

