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
    /// El arrastre del armario, si esta prenda está en él. Opcional: la misma
    /// vista se usa en pantallas donde no se arrastra nada.
    @Environment(ShelfDragModel.self) private var drag: ShelfDragModel?
    @State private var isPresentingDetail = false
    /// Para viajar a la rejilla de edición en bloque. Ver `ClosetBulkEdit`.
    @Environment(\.closetMatchNamespace) private var matchNamespace
    /// Quién presenta la ficha. Opcional: la misma percha se usa en hojas que
    /// viven fuera de la raíz. Ver `AppRouter`.
    @Environment(AppRouter.self) private var router: AppRouter?
    /// Se pidió borrar desde la ficha: se borra al cerrarse. Ver `GarmentSheet`.
    @State private var deletesOnDismiss = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        #if DEBUG
        let _ = Self._logChanges()
        #endif
        Button {
            // El toque que cae al soltar un arrastre no abre nada.
            guard drag?.ignoresTaps != true else { return }
            if isSelecting {
                onToggleSelection?()
            } else if let router {
                router.open(garment)
            } else {
                // Sin router —dentro de una hoja— la presenta la propia
                // percha, que es lo que había antes.
                isPresentingDetail = true
            }
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
                // Y un poco más pequeña: lo marcado queda a tamaño natural y
                // se lee de un vistazo qué entra y qué no, sin mirar vistos.
                .scaleEffect(isSelecting && !isSelected ? 0.8 : 1)
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
            .compositingGroup()
            .modifier(ClosetMatchedGarment(id: garment.id, namespace: matchNamespace))
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
        .sheet(isPresented: $isPresentingDetail, onDismiss: {
            guard deletesOnDismiss else { return }
            deletesOnDismiss = false
            if let model = modelContext.model(for: garment.persistentID) as? Garment {
                withAnimation(WKAnimation.content) { model.markDeleted() }
            }
        }) {
            GarmentDetailLoader(persistentID: garment.persistentID) { deletesOnDismiss = true }
        }
    }
}

/// Resuelve el `Garment` completo al abrir el detalle.
///
/// Una búsqueda por identificador al tocar es más barata que mantener todas las
/// celdas de todas las baldas suscritas al objeto entero.
struct GarmentDetailLoader: View {
    let persistentID: PersistentIdentifier
    var onDelete: (() -> Void)?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let garment = modelContext.model(for: persistentID) as? Garment {
            GarmentSheet(garment: garment, onDelete: onDelete)
        } else {
            ContentUnavailableView("Prenda no encontrada", systemImage: "questionmark.circle")
        }
    }
}
