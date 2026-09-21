import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Pantalla principal: el armario.
///
/// Esta vista **sí** se reevalúa cuando cambia cualquier prenda: SwiftData
/// observa el tipo entero, no el predicado, así que eso no se puede evitar. Lo
/// que sí se evita es que la reevaluación se propague: aquí solo se construye
/// un array de valores (`ShelfData`), y cada `ShelfSection` es `Equatable`, de
/// modo que únicamente la balda que haya cambiado ejecuta su `body`.
///
/// Construir el array cuesta un recorrido por las prendas. Con miles sigue
/// siendo microsegundos, y es mucho más barato que reevaluar cuatro jerarquías
/// de vistas con sus imágenes.
struct ClosetScreen: View {
    /// Qué pestaña está activa. La barra se dibuja **aquí dentro**, en la raíz
    /// de esta pila de navegación, para que abrir una maleta la tape.
    @Binding var tab: RootTab

    #if DEBUG
    /// `-open suitcase` empuja la primera maleta al arrancar, para poder
    /// capturar pantallas profundas sin navegar a mano.
    @Query private var allSuitcases: [Suitcase]
    @State private var debugPath = NavigationPath()
    #endif

    /// Lo abre el estado vacío. Vive aquí porque el botón vacío ocupa la
    /// pantalla entera y no cuelga de ninguna balda.
    /// Una sola hoja. Ver `ClosetAddMenu`: apilar `.sheet` en la misma vista
    /// deja mudos a todos menos a uno.
    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable {
        // `profile` ya no está: Ajustes se empuja como pantalla, no se
        // presenta como hoja. Ver `ClosetRoute.settings`.
        case capture, review
        var id: String { rawValue }
    }

    @State private var captured: ImportableImage?

    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(
        filter: #Predicate<GarmentCategory> { !$0.isHidden },
        sort: [SortDescriptor(\GarmentCategory.sortOrder)]
    )
    private var categories: [GarmentCategory]

    @Query(FetchDescriptor<Garment>.visibleGarments())
    private var garments: [Garment]

    private var shelves: [ShelfData] {
        var bySlug: [String: [GarmentRef]] = [:]
        for garment in garments {
            guard let slug = garment.category?.slug else { continue }
            bySlug[slug, default: []].append(GarmentRef(garment))
        }
        return categories.map { category in
            ShelfData(
                id: category.slug,
                name: category.name,
                symbol: category.symbolName,
                garments: bySlug[category.slug] ?? []
            )
        }
    }

    var body: some View {
        #if DEBUG
        let _ = Self._logChanges()
        #endif
        NavigationStack(path: navigationPath) {
            ScrollView {
                if garments.isEmpty {
                    ClosetEmptyState {
                        appEnvironment.gate.require(.garments) { sheet = .capture }
                    }
                        .containerRelativeFrame(.vertical)
                        .transition(AnyTransition(.blurReplace))
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(shelves) { shelf in
                            ShelfSection(data: shelf)
                                .equatable()
                        }
                        SuitcaseShelfSection()
                    }
                    .padding(.top, WK.Spacing.s)
                    .transition(AnyTransition(.blurReplace))
                }
            }
            .scrollIndicators(.hidden)
            .animation(WKAnimation.content, value: garments.isEmpty)
            .background(WK.Palette.canvas.ignoresSafeArea())
            .adaptiveScrollEdge(.top)
            .adaptiveFloatingAccessory { MakeOutfitsAccessory() }
            .rootTabBar(selection: $tab)
            .navigationDestination(for: ClosetRoute.self) { route in
                ClosetRouteDestination(route: route)
            }
            // En la barra de verdad, no en un `overlay` puesto a mano.
            //
            // Quitar el **título** no es quitar la barra: puesta con el título
            // vacío, el sistema coloca los dos botones donde tocan, les da su
            // cristal en iOS 26 y difumina solo el contenido que pasa por
            // debajo. Imitando todo eso con un overlay había que reservar el
            // hueco a mano —y me quedaba corto— y el contenido pasaba por
            // detrás sin ningún tratamiento.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(value: ClosetRoute.settings) {
                        ProfileButton {}
                            .allowsHitTesting(false)
                    }
                    .buttonStyle(WKPressStyle())
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ClosetAddMenu()
                }
            }
            .sheet(item: $sheet) { which in
                switch which {
                case .capture:
                    CameraScreen { image in
                        captured = ImportableImage(cgImage: image)
                        sheet = .review
                    }
                case .review:
                    if let captured {
                        ImportSheet(image: captured.cgImage)
                    }
                }
            }
            #if DEBUG
            .task { openSuitcaseIfRequested() }
            #endif
        }
    }

    #if DEBUG
    private var navigationPath: Binding<NavigationPath> { $debugPath }

    private func openSuitcaseIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-open"),
              ProcessInfo.processInfo.arguments.contains("suitcase"),
              let suitcase = allSuitcases.first,
              debugPath.isEmpty
        else { return }
        debugPath.append(ClosetRoute.suitcase(id: suitcase.id))
    }
    #else
    private var navigationPath: Binding<NavigationPath> { .constant(NavigationPath()) }
    #endif
}

/// Resuelve una ruta en su pantalla. Extraída para que `ClosetScreen` no lleve
/// un `switch` dentro de un `@ViewBuilder`.
private struct ClosetRouteDestination: View {
    let route: ClosetRoute

    var body: some View {
        switch route {
        case let .category(slug, name):
            CategoryScreen(slug: slug, name: name)
        case let .suitcase(id):
            SuitcaseDetailScreen(id: id)
        case .settings:
            ProfileScreen()
        }
    }
}

#Preview {
    @Previewable @State var tab = RootTab.closet
    return ClosetScreen(tab: $tab)
        .environment(AppEnvironment.live())
        .modelContainer(try! WardrobeStore.makeContainer(inMemory: true))
}
