import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Monta un outfit eligiendo prenda por hueco.
///
/// Es la forma normal de crear un outfit: tocas una categoría, deslizas entre
/// tus prendas y la tarjeta se rehace. Para colocar al milímetro está el canvas
/// libre, que edita **el mismo outfit** porque un hueco no es más que una
/// transformada preestablecida.
public struct OutfitComposer: View {
    private let outfit: Outfit?
    private let store: ImageStore
    /// Crea el outfit la primera vez que hace falta.
    ///
    /// Perezoso a propósito: si se creara al mostrar el día, pasar el dedo por
    /// un mes dejaría treinta outfits vacíos en la base de datos. Y crear
    /// dentro del `body` es peor todavía — la inserción cambia el contexto, el
    /// contexto reevalúa el `body`, y el `body` vuelve a insertar.
    private let makeOutfit: () -> Outfit
    private let onOpenCanvas: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var selectedSlot: OutfitSlot = .top

    public init(
        outfit: Outfit?,
        store: ImageStore,
        makeOutfit: @escaping () -> Outfit,
        onOpenCanvas: (() -> Void)? = nil
    ) {
        self.outfit = outfit
        self.store = store
        self.makeOutfit = makeOutfit
        self.onOpenCanvas = onOpenCanvas
    }

    public var body: some View {
        VStack(spacing: WK.Spacing.m) {
            OutfitCard(outfit: outfit, store: store, onOpenCanvas: onOpenCanvas)
                .padding(.horizontal, WK.Spacing.screenInset)

            SlotChipBar(selected: $selectedSlot)

            SlotGarmentStrip(
                slot: selectedSlot,
                store: store,
                selectedID: outfit?.garment(in: selectedSlot)?.id,
                onPick: { garment in place(garment, in: selectedSlot) },
                onClear: { clear(selectedSlot) }
            )
        }
    }

    /// Coloca una prenda en su hueco, sustituyendo lo que hubiera.
    ///
    /// Sustituir y no acumular: un hueco es una posición del conjunto, y dos
    /// pantalones a la vez no son un outfit.
    private func place(_ garment: Garment, in slot: OutfitSlot) {
        // Aquí sí se puede crear: estamos en una acción, no evaluando el `body`.
        let target = outfit ?? makeOutfit()
        withAnimation(WKAnimation.arrival) {
            if let existing = target.item(in: slot) {
                existing.garment = garment
                return
            }
            let item = CanvasItem(transform: slot.transform, garment: garment)
            item.outfit = target
            modelContext.insert(item)
        }
    }

    private func clear(_ slot: OutfitSlot) {
        guard let existing = outfit?.item(in: slot) else { return }
        withAnimation(WKAnimation.content) { modelContext.delete(existing) }
    }
}

/// La tarjeta del outfit: fondo pastel, retícula y las prendas colocadas.
private struct OutfitCard: View {
    let outfit: Outfit?
    let store: ImageStore
    let onOpenCanvas: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let scale = CanvasSpace.scaleToFit(in: proxy.size)
            ZStack {
                ZStack {
                    backdrop
                    DotGridBackground(spacing: CanvasSpace.gridSpacing * 3)
                        .opacity(0.5)

                    if let outfit {
                        ForEach(outfit.visibleItems) { item in
                            SlotGarmentImage(item: item, store: store)
                                .transition(.wkPlace)
                        }
                    }
                }
                .frame(width: CanvasSpace.width, height: CanvasSpace.height)
                .scaleEffect(scale)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .animation(WKAnimation.arrival, value: outfit?.items.count ?? 0)
            }
            .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
            .overlay(alignment: .topLeading) { canvasButton }
        }
        .aspectRatio(CanvasSpace.width / CanvasSpace.height, contentMode: .fit)
    }

    private var backdrop: some View {
        let components = OutfitBackdrop(rawValue: outfit?.backdropRaw ?? "")?.components
        return (components.map { WK.Palette.canvasTint(red: $0.red, green: $0.green, blue: $0.blue) }
            ?? WK.Palette.shelf)
    }

    @ViewBuilder
    private var canvasButton: some View {
        if let onOpenCanvas {
            Button(action: onOpenCanvas) {
                Image(systemName: "move.3d")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WK.Palette.primaryText)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())
            .padding(WK.Spacing.m)
        }
    }
}

/// Una prenda dentro de la tarjeta. Vista propia para que cargar su imagen no
/// dé estado a la tarjeta.
private struct SlotGarmentImage: View {
    let item: CanvasItem
    let store: ImageStore

    var body: some View {
        let transform = item.transform
        StoredImage(
            key: item.garment?.normalizedImageKey ?? "",
            variant: .display,
            store: store,
            shadow: .init(opacity: 0.5, radius: 18, y: 11)
        )
        .frame(width: transform.baseWidth, height: transform.baseHeight)
        .scaleEffect(transform.scale)
        .rotationEffect(.radians(transform.rotation))
        .position(x: transform.x, y: transform.y)
        .zIndex(transform.zIndex)
    }
}

/// Chips de categoría.
private struct SlotChipBar: View {
    @Binding var selected: OutfitSlot
    /// El fondo del chip es **una sola vista** que viaja entre posiciones.
    ///
    /// Con `matchedGeometryEffect` se desliza de un chip a otro en vez de
    /// desaparecer aquí y aparecer allá. Es la animación que más se nota por lo
    /// poco que cuesta: convierte un cambio de estado en un movimiento.
    @Namespace private var chipNamespace

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.s) {
                ForEach(OutfitSlot.allCases) { slot in
                    Button {
                        withAnimation(WKAnimation.selection) { selected = slot }
                    } label: {
                        Text(slot.label)
                            .font(selected == slot ? WK.Font.headline : WK.Font.body)
                            .foregroundStyle(
                                selected == slot ? WK.Palette.primaryText : WK.Palette.secondaryText
                            )
                            .padding(.horizontal, WK.Spacing.m)
                            .padding(.vertical, WK.Spacing.s)
                            .background {
                                if selected == slot {
                                    Capsule()
                                        .fill(WK.Palette.ink(0.08))
                                        .matchedGeometryEffect(id: "chip", in: chipNamespace)
                                }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(WKPressStyle())
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
        }
        .scrollIndicators(.hidden)
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Las prendas disponibles para el hueco elegido.
private struct SlotGarmentStrip: View {
    let slot: OutfitSlot
    let store: ImageStore
    let selectedID: UUID?
    let onPick: (Garment) -> Void
    let onClear: () -> Void

    @Query(FetchDescriptor<Garment>.visibleGarments())
    private var garments: [Garment]

    private var candidates: [Garment] {
        garments.filter { slot.kinds.contains($0.kind) }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.m) {
                // El hueco vacío primero: quitar una prenda tiene que ser tan
                // fácil como ponerla.
                ClearSlotCell(isSelected: selectedID == nil, action: onClear)

                ForEach(candidates) { garment in
                    StripCell(
                        garment: garment,
                        store: store,
                        isSelected: selectedID == garment.id
                    ) {
                        onPick(garment)
                    }
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
        }
        .scrollIndicators(.hidden)
        .frame(height: 120)
        .overlay {
            if candidates.isEmpty {
                Text(String(localized: "wkcanvas.outfitcomposer.nothingInYet", defaultValue: "Nothing in \(String(describing: slot.label.lowercased())) yet", bundle: .module))
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.tertiaryText)
            }
        }
    }
}

private struct StripCell: View {
    let garment: Garment
    let store: ImageStore
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            StoredImage(
                key: garment.normalizedImageKey,
                variant: .thumb,
                store: store,
                shadow: isSelected
                    ? .init(opacity: 0.85, radius: 12, y: 0, tint: WK.Palette.accent)
                    : .init(opacity: 0.5, radius: 6, y: 3)
            )
            .frame(width: 84, height: 96)
            .padding(WK.Spacing.xs)
            .scaleEffect(isSelected ? 1.08 : 1)
            .animation(WKAnimation.selection, value: isSelected)
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}

private struct ClearSlotCell: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "nosign")
                .font(.title3)
                .foregroundStyle(WK.Palette.tertiaryText)
                .frame(width: 84, height: 96)
                .background(WK.Palette.ink(0.05), in: .rect(cornerRadius: WK.Radius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: WK.Radius.small, style: .continuous)
                        .stroke(isSelected ? WK.Palette.accent : .clear, lineWidth: 2)
                )
                .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}

public extension Outfit {
    /// El `CanvasItem` que ocupa un hueco, si lo hay.
    ///
    /// Se busca por la posición del hueco y no por una relación explícita: así
    /// un outfit movido a mano en el canvas sigue siendo editable por huecos,
    /// que es lo que permite ir y volver entre los dos modos.
    func item(in slot: OutfitSlot) -> CanvasItem? {
        items.first { item in
            guard let kind = item.garment?.kind else { return false }
            return OutfitSlot.slot(for: kind) == slot
        }
    }

    func garment(in slot: OutfitSlot) -> Garment? {
        item(in: slot)?.garment
    }
}
