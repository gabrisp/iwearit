import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Elegir qué entra al armario, después de escanear.
///
/// ## Por qué existe este paso
///
/// Antes el escaneo insertaba todo lo que encontraba mientras lo encontraba, y
/// el armario nacía con doscientas prendas: las buenas, las de fotos de hace
/// seis años, las que salen tres veces porque llevabas la misma camiseta, y los
/// recortes que no son ropa. Quitarlas era abrir cada ficha y eliminarla.
///
/// Escanear es una propuesta, no una decisión. Aquí se ve lo encontrado y entra
/// lo que tú digas — y lo que no entre no se pierde: sus recortes siguen en
/// disco el tiempo suficiente como para volver a importarlos desde el armario.
struct ScanReviewStep: View {
    let model: OnboardingModel

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext

    /// Lo encontrado, **guardado como pendiente** mientras se decide. Ver
    /// `PendingGarment`: antes vivía en memoria y cualquier salida lo perdía.
    @Query private var pending: [PendingGarment]
    @State private var selection: Set<UUID> = []
    @State private var isSaving = false
    /// Lo que ya se ha visto aparecer, para marcar **solo lo nuevo**: si el
    /// usuario desmarca algo, que la lista cambie no se lo vuelve a marcar.
    /// Hace falta porque al saltar el escaneo el último lote se guarda un
    /// instante después de llegar aquí.
    @State private var known: Set<UUID> = []

    var body: some View {
        OnboardingStepScaffold(
            title: pending.isEmpty ? String(localized: "onboarding.scanreviewstep.weDidnTFindAny", defaultValue: "We didn't find any clothes") : String(localized: "onboarding.scanreviewstep.hereSWhatWeFound", defaultValue: "Here's what we found"),
            subtitle: pending.isEmpty
                ? String(localized: "onboarding.scanreviewstep.youCanAddThemBy", defaultValue: "You can add them by hand whenever you like, one photo at a time.")
                : String(localized: "onboarding.scanreviewstep.chooseTheOnesYouWant", defaultValue: "Choose the ones you want in your closet. The rest stay to review later from the closet."),
            primaryTitle: primaryTitle,
            isEnabled: !isSaving,
            // El scroll de prendas pasa por debajo del botón.
            fillsToBottom: !pending.isEmpty,
            onPrimary: { Task { await save() } }
        ) {
            if !pending.isEmpty {
                PendingGarmentsGrid(selection: $selection)
            }
        }
        // Todas marcadas de entrada: lo normal es quedarse con casi todas, y
        // empezar con la rejilla en blanco obligaría a tocar cien veces para
        // llegar al caso normal.
        .onAppear(perform: preselect)
        .onChange(of: pending.count) { preselect() }
    }

    private var primaryTitle: String {
        if pending.isEmpty { return String(localized: "common.continue", defaultValue: "Continue") }
        if isSaving { return "Guardando…" }
        return selection.isEmpty ? String(localized: "common.notNow", defaultValue: "Not now") : String(localized: "common.add", defaultValue: "Add \(String(describing: selection.count))")
    }

    private func preselect() {
        let arrived = Set(pending.map(\.id)).subtracting(known)
        guard !arrived.isEmpty else { return }
        known.formUnion(arrived)
        selection.formUnion(arrived)
    }

    private func save() async {
        guard !selection.isEmpty else {
            model.advance()
            return
        }
        isSaving = true
        defer { isSaving = false }
        // Lo no marcado **se queda pendiente**: no se tira, se decide luego.
        await PendingGarments.importing(
            selection,
            context: modelContext,
            wardrobe: appEnvironment.wardrobe
        )
        model.advance()
    }
}

// **La revisión de antes, comentada.** Leía lo encontrado de un array en
// memoria (`model.harvest`) y lo que no se marcaba se perdía; ahora todo queda
// guardado como pendiente. Ver `PendingGarmentsGrid`.
//
// struct ScanReviewStep: View {
//     let model: OnboardingModel
//
//     @Environment(AppEnvironment.self) private var appEnvironment
//
//     /// Lo marcado, por clave de imagen: es lo único estable que tiene un
//     /// borrador —no existe todavía como prenda, así que no hay id de modelo—.
//     @State private var selected: Set<String> = []
//     @State private var isSaving = false
//
//     private let columns = [GridItem(.adaptive(minimum: 96), spacing: WK.Spacing.m)]
//
//     var body: some View {
//         OnboardingStepScaffold(
//             title: model.harvest.isEmpty ? "No hemos encontrado prendas" : "Esto hemos encontrado",
//             subtitle: model.harvest.isEmpty
//                 ? "Puedes añadirlas a mano cuando quieras, una foto cada vez."
//                 : "Elige las que quieras en tu armario. Las demás no se guardan.",
//             primaryTitle: primaryTitle,
//             isEnabled: !isSaving,
//             onPrimary: { Task { await save() } }
//         ) {
//             if !model.harvest.isEmpty {
//                 selectionBar
//
//                 ScrollView {
//                     LazyVGrid(columns: columns, spacing: WK.Spacing.m) {
//                         ForEach(model.harvest, id: \.normalizedImageKey) { draft in
//                             HarvestCell(
//                                 draft: draft,
//                                 store: appEnvironment.imageStore,
//                                 isSelected: selected.contains(draft.normalizedImageKey)
//                             ) {
//                                 toggle(draft)
//                             }
//                         }
//                     }
//                     .padding(.vertical, WK.Spacing.s)
//                 }
//                 .scrollIndicators(.hidden)
//             }
//         }
//         // Todas marcadas de entrada: lo normal es quedarse con casi todas, y
//         // empezar con la rejilla en blanco obligaría a tocar doscientas veces
//         // para llegar al caso normal.
//         .task {
//             if selected.isEmpty {
//                 selected = Set(model.harvest.map(\.normalizedImageKey))
//             }
//         }
//     }
//
//     private var primaryTitle: String {
//         if model.harvest.isEmpty { return "Continuar" }
//         if isSaving { return "Guardando…" }
//         return selected.isEmpty ? "No añadir ninguna" : "Añadir \(selected.count)"
//     }
//
//     private var selectionBar: some View {
//         HStack {
//             Text("\(selected.count) de \(model.harvest.count)")
//                 .font(WK.Font.caption)
//                 .foregroundStyle(WK.Palette.secondaryText)
//                 .contentTransition(.numericText())
//
//             Spacer(minLength: 0)
//
//             Button(selected.count == model.harvest.count ? "Ninguna" : "Todas") {
//                 withAnimation(WKAnimation.selection) {
//                     selected = selected.count == model.harvest.count
//                         ? []
//                         : Set(model.harvest.map(\.normalizedImageKey))
//                 }
//             }
//             .font(WK.Font.callout)
//             .foregroundStyle(WK.Palette.accent)
//             .buttonStyle(WKPressStyle())
//         }
//         .animation(WKAnimation.selection, value: selected.count)
//     }
//
//     private func toggle(_ draft: GarmentDraft) {
//         withAnimation(WKAnimation.selection) {
//             if selected.contains(draft.normalizedImageKey) {
//                 selected.remove(draft.normalizedImageKey)
//             } else {
//                 selected.insert(draft.normalizedImageKey)
//             }
//         }
//     }
//
//     private func save() async {
//         guard !model.harvest.isEmpty else {
//             model.advance()
//             return
//         }
//         isSaving = true
//         defer { isSaving = false }
//
//         let chosen = model.harvest.filter { selected.contains($0.normalizedImageKey) }
//         // Por lotes, como el escaneo: una transacción por prenda con doscientas
//         // prendas es doscientas transacciones y varios segundos de pantalla
//         // quieta.
//         for start in stride(from: 0, to: chosen.count, by: WardrobeActor.batchSize) {
//             let slice = Array(chosen[start..<min(start + WardrobeActor.batchSize, chosen.count)])
//             try? await appEnvironment.wardrobe.insert(slice)
//         }
//         DiagnosticsLog.record(
//             "ESCANEO",
//             "el usuario se queda con \(chosen.count) de \(model.harvest.count)"
//         )
//         model.harvest = []
//         model.advance()
//     }
// }

/// Una prenda encontrada, para marcarla o no.
///
/// Se pinta desde el `ImageStore` por su clave: el recorte ya está escrito en
/// disco aunque la prenda todavía no exista en la base.
private struct HarvestCell: View {
    let draft: GarmentDraft
    let store: ImageStore
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            StoredImage(key: draft.normalizedImageKey, variant: .thumb, store: store)
                .frame(height: 96)
                .padding(WK.Spacing.xs)
                .background {
                    RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                        .fill(WK.Palette.ink(0.04))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                        .stroke(WK.Palette.accent, lineWidth: isSelected ? 2 : 0)
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.footnote)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            isSelected ? WK.Palette.onAccent : WK.Palette.secondaryText,
                            isSelected ? WK.Palette.accent : WK.Palette.ink(0.10)
                        )
                        .padding(WK.Spacing.xs)
                }
                .opacity(isSelected ? 1 : 0.5)
                .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
        .animation(WKAnimation.selection, value: isSelected)
    }
}
