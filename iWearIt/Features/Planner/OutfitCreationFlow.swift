import SwiftData
import SwiftUI
import WKCanvas
import WKCore
import WKDesign
import WKPersistence

/// Crear un outfit: elegir prendas y colocarlas.
///
/// Un modificador y no una pantalla porque lo usan tres sitios —el armario, la
/// hoja de una prenda y el planificador— y son **los mismos dos pasos** en los
/// tres. Cuando esto vivía duplicado, el armario se quedó con el compositor
/// viejo mientras el planificador ya usaba el selector nuevo.
private struct OutfitCreationFlow: ViewModifier {
    @Binding var isActive: Bool
    /// Entra ya colocada en su hueco. Es el caso de "crear outfit" desde una
    /// prenda concreta: empezar por la que acabas de mirar.
    var startingGarment: Garment?
    /// Qué hacer con el outfit recién creado antes de abrirlo.
    ///
    /// Existe por el armario: crear un outfit desde ahí tiene que colgarlo del
    /// día de hoy, y quien sabe de días es quien llama, no este modificador.
    var onCreate: ((Outfit) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    /// El outfit no existe hasta que hay algo que poner en él. Abrir y cerrar
    /// el selector sin elegir nada no debe dejar outfits vacíos en la base de
    /// datos.
    @State private var outfit: Outfit?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isActive) {
                OutfitPickerSheet(
                    store: appEnvironment.imageStore,
                    preselected: startingGarment
                ) { picked in
                    create(with: picked)
                }
            }
            .fullScreenCover(item: $outfit) { outfit in
                AdvancedCanvasScreen(outfit: outfit, store: appEnvironment.imageStore)
            }
    }

    private func create(with garments: [Garment]) {
        guard !garments.isEmpty else { return }
        let created = Outfit()
        modelContext.insert(created)

        for garment in garments {
            let slot = OutfitSlot.slot(for: garment.kind)
            let item = CanvasItem(transform: slot.transform, garment: garment)
            item.outfit = created
            modelContext.insert(item)
        }
        onCreate?(created)
        outfit = created
    }
}

extension View {
    /// Elegir prendas y abrir el editor con ellas puestas.
    func outfitCreationFlow(
        isActive: Binding<Bool>,
        startingGarment: Garment? = nil,
        onCreate: ((Outfit) -> Void)? = nil
    ) -> some View {
        modifier(
            OutfitCreationFlow(
                isActive: isActive,
                startingGarment: startingGarment,
                onCreate: onCreate
            )
        )
    }
}

extension Outfit: @retroactive Identifiable {
    public var id: PersistentIdentifier { persistentModelID }
}
