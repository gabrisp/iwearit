import SwiftData
import SwiftUI
import WKDesign
import WKPersistence

/// Una prenda "colgada" en la balda.
///
/// Recibe un `GarmentRef` (POD), no el `Garment`: la celda solo muestra imagen
/// y nombre, así que no tiene por qué invalidarse cuando cambia la talla o las
/// notas. El `Garment` completo se resuelve al abrir el detalle.
struct HangingGarmentView: View {
    let garment: GarmentRef
    /// En modo selección el toque **marca** en vez de abrir la ficha: si
    /// abriera, cada prenda que quieres quitar te saca de la balda.
    var isSelecting = false
    var isSelected = false
    var onToggleSelection: (() -> Void)?

    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var isPresentingDetail = false

    var body: some View {
        #if DEBUG
        let _ = Self._logChanges()
        #endif
        Button {
            if isSelecting { onToggleSelection?() } else { isPresentingDetail = true }
        } label: {
            VStack(spacing: 2) {
                StoredImage(
                    key: garment.imageKey,
                    variant: .thumb,
                    store: appEnvironment.imageStore,
                    alignment: .bottom,
                    shadow: .init(opacity: 0.5, radius: 8, y: 5)
                )
                .frame(width: WK.Shelf.garmentWidth, height: WK.Shelf.imageHeight)
                // Ancla arriba: la prenda pivota desde la percha, no del centro.
                .rotationEffect(.degrees(garment.swayDegrees), anchor: .top)
                // La marca de selección, sobre la prenda y no en una esquina
                // del hueco: el hueco es casi todo transparente y una marca
                // flotando en el vacío no se sabe de cuál es.
                .overlay(alignment: .topTrailing) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                isSelected ? WK.Palette.onAccent : WK.Palette.secondaryText,
                                isSelected ? WK.Palette.accent : WK.Palette.ink(0.08)
                            )
                            .padding(WK.Spacing.xs)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .opacity(isSelecting && !isSelected ? 0.55 : 1)
                .animation(WKAnimation.selection, value: isSelected)
                .animation(WKAnimation.selection, value: isSelecting)

                // **Sin nombre debajo.**
                //
                // Una balda de ropa se lee mirando, no leyendo: la foto ya
                // dice cuál es cada prenda, y treinta nombres compuestos por
                // la app —"Camiseta Stüssy", "Camiseta en gris"— eran treinta
                // líneas de texto cortado que no distinguían nada. El nombre
                // sigue existiendo para buscar; simplemente no se pinta.
                //
                // Text(garment.name)
                //     .font(WK.Font.garmentName)
                //     .foregroundStyle(WK.Palette.secondaryText)
                //     .lineLimit(1)
                //     .truncationMode(.tail)
                //     .frame(width: WK.Shelf.garmentWidth)
                //     .padding(.bottom, WK.Shelf.labelBottomInset)
                Color.clear.frame(height: WK.Shelf.labelBottomInset)
            }
            .frame(height: WK.Shelf.height, alignment: .bottom)
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
        .sheet(isPresented: $isPresentingDetail) {
            GarmentDetailLoader(persistentID: garment.persistentID)
        }
    }
}

/// Resuelve el `Garment` completo al abrir el detalle.
///
/// Una búsqueda por identificador al tocar es más barata que mantener todas las
/// celdas de todas las baldas suscritas al objeto entero.
private struct GarmentDetailLoader: View {
    let persistentID: PersistentIdentifier
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let garment = modelContext.model(for: persistentID) as? Garment {
            GarmentSheet(garment: garment)
        } else {
            ContentUnavailableView("Prenda no encontrada", systemImage: "questionmark.circle")
        }
    }
}
