import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// De qué se tira para montar: **con qué prendas** y **de qué baldas**.
///
/// ## Por qué las dos cosas juntas
///
/// Porque son la misma pregunta —qué entra en lo que me propongas— y estaban
/// en dos botones pegados arriba a la izquierda: dos iconos que abren dos
/// hojas para lo mismo. Uno solo, con las dos secciones dentro, y la barra
/// vuelve a tener un botón por lado.
struct InspoFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnvironment

    /// Qué hacer cuando cambian las baldas que entran: rehacer lo propuesto.
    var onShelvesChanged: () -> Void = {}

    /// Las prendas alrededor de las que montar. Vacío = todo el armario.
    @Binding var anchors: Set<UUID>

    @Query(FetchDescriptor<Garment>.visibleGarments())
    private var garments: [Garment]

    @Query(
        filter: #Predicate<GarmentCategory> { !$0.isHidden && $0.deletedAt == nil },
        sort: [SortDescriptor(\GarmentCategory.sortOrder)]
    )
    private var categories: [GarmentCategory]

    @State private var isPickingGarments = false

    private var shelves: [GarmentCategory] {
        var seen = Set<String>()
        return categories.filter { seen.insert($0.slug).inserted && !$0.visibleGarments.isEmpty }
    }

    private var anchored: [Garment] {
        let byID = Dictionary(garments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return anchors.compactMap { byID[$0] }.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WK.Spacing.l) {
                    garmentsSection
                    shelvesSection
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .padding(.vertical, WK.Spacing.m)
            }
            .scrollIndicators(.hidden)
            .background(WK.Palette.canvas.ignoresSafeArea())
            .navigationTitle(String(localized: "inspo.inspofilterssheet.whatGoesIn", defaultValue: "What goes in"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "checkmark") }
                        .tint(WK.Palette.primaryText)
                        .adaptiveProminentButton()
                }
            }
            // **El armario por baldas, como al crear un outfit.**
            //
            // Es el mismo gesto —marcar prendas del armario— y estaba resuelto
            // ahí: baldas en horizontal y lo marcado abajo a la izquierda, sin
            // que la rejilla se recoloque bajo el dedo. Dos formas de elegir
            // ropa hacían parecer que hay dos armarios.
            .sheet(isPresented: $isPickingGarments) {
                OutfitPickerSheet(
                    mode: .many,
                    title: String(localized: "inspo.inspofilterssheet.withTheseClothes", defaultValue: "With these clothes"),
                    subtitle: String(localized: "inspo.inspofilterssheet.upToThreeTheOutfits", defaultValue: "Up to three: the outfits will include them"),
                    store: appEnvironment.imageStore,
                    limit: 3,
                    preselectedIDs: anchored.map(\.persistentModelID)
                ) { garments in
                    withAnimation(WKAnimation.content) {
                        anchors = Set(garments.map(\.id))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Las prendas de partida, con su recorte y su equis.
    private var garmentsSection: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            Text(String(localized: "inspo.inspofilterssheet.withTheseClothes", defaultValue: "With these clothes"))
                .font(WK.Font.headline)
                .foregroundStyle(WK.Palette.primaryText)
            Text(String(localized: "inspo.inspofilterssheet.upToThreeEveryOutfit", defaultValue: "Up to three. Every outfit will include them."))
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)

            ScrollView(.horizontal) {
                HStack(spacing: WK.Spacing.s) {
                    Button { isPickingGarments = true } label: {
                        Image(systemName: "plus")
                            .font(WK.Font.headline)
                            .foregroundStyle(WK.Palette.primaryText)
                            .frame(width: 64, height: 64)
                            .background(WK.Palette.ink(0.06), in: .circle)
                    }
                    .buttonStyle(WKPressStyle())

                    ForEach(anchored, id: \.persistentModelID) { garment in
                        Button { remove(garment) } label: {
                            StoredImage(
                                key: garment.normalizedImageKey,
                                variant: .thumb,
                                store: appEnvironment.imageStore
                            )
                            .frame(width: 64, height: 64)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(WK.Palette.onAccent)
                                    .frame(width: 20, height: 20)
                                    .background(WK.Palette.ink(0.55), in: .circle)
                            }
                        }
                        .buttonStyle(WKPressStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    /// Y qué baldas entran.
    private var shelvesSection: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            Text(String(localized: "common.shelves", defaultValue: "Shelves"))
                .font(WK.Font.headline)
                .foregroundStyle(WK.Palette.primaryText)
            Text(String(localized: "inspo.inspofilterssheet.anythingYouTurnOffStays", defaultValue: "Anything you turn off stays in your closet: it just stops being suggested."))
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)

            WKChipFlow(
                options: shelves.map { .init(id: $0.slug, label: $0.displayName) },
                selection: Set(shelves.filter { !$0.isExcludedFromInspo }.map(\.slug))
            ) { slug in
                guard let shelf = shelves.first(where: { $0.slug == slug }) else { return }
                withAnimation(WKAnimation.selection) {
                    shelf.isExcludedFromInspo.toggle()
                }
                // Y que se entere quien monta: si no, apagar una balda no
                // cambiaba nada hasta pasado medio minuto. Ver
                // `InspoFeed.wardrobeChanged`.
                onShelvesChanged()
            }
        }
    }

    private func remove(_ garment: Garment) {
        withAnimation(WKAnimation.content) {
            _ = anchors.remove(garment.id)
        }
    }
}
