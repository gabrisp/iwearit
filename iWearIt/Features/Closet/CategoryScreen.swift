import SwiftData
import SwiftUI
import WKDesign
import WKPersistence

/// Una balda vista en vertical, con todas sus prendas.
struct CategoryScreen: View {
    private let name: String
    @Query private var garments: [Garment]
    @State private var searchText = ""

    init(slug: String, name: String) {
        self.name = name
        _garments = Query(
            filter: #Predicate<Garment> { $0.category?.slug == slug },
            sort: [SortDescriptor(\Garment.dateAdded, order: .reverse)]
        )
    }

    private var visible: [Garment] {
        guard !searchText.isEmpty else { return garments }
        return garments.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108), spacing: WK.Spacing.m)],
                spacing: WK.Spacing.l
            ) {
                ForEach(visible) { garment in
                    HangingGarmentView(garment: GarmentRef(garment))
                }
            }
            .padding(WK.Spacing.m)
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas.ignoresSafeArea())
        .adaptiveScrollEdge(.top)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Buscar en \(name)")
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Balda vacía" : "Sin resultados",
                    systemImage: searchText.isEmpty ? "tray" : "magnifyingglass"
                )
            }
        }
    }
}
