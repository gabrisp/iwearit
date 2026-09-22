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
        case capture, review, shelves
        var id: String { rawValue }
    }

    @State private var captured: ImportableBatch?
    /// El atajo del sobre-scroll: seguir tirando al final del armario crea un
    /// outfit para hoy.
    @State private var isCreatingOutfit = false

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext

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
                // Primero lo colocado a mano, y lo demás por fecha. Con el
                // orden a cero —nadie lo ha tocado— sale como siempre.
                garments: (bySlug[category.slug] ?? []).sorted {
                    $0.shelfOrder == $1.shelfOrder
                        ? $0.dateAdded > $1.dateAdded
                        : $0.shelfOrder < $1.shelfOrder
                }
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

                        // Al final del todo, donde se te ocurre. Ver
                        // `ShelfEditPill`.
                        ShelfEditPill { sheet = .shelves }
                    }
                    .padding(.top, WK.Spacing.s)
                    .transition(AnyTransition(.blurReplace))
                }
            }
            .scrollIndicators(.hidden)
            // **Rebota aunque quepa todo**: con dos baldas no hay nada que
            // desplazar y el gesto no existiría.
            .scrollBounceBehavior(.always, axes: .vertical)
            // **El atajo.** Seguir tirando al final del armario abre el
            // selector y monta un outfit **para hoy**: estabas mirando ropa y
            // te ha apetecido combinarla, que es exactamente el momento en que
            // ir a la otra pestaña, buscar el día y crear allí sobra.
            //
            // Va donde iba el botón de "Crear outfit", justo encima de la
            // barra de pestañas — el hueco ya está reservado por ella, así que
            // basta un respiro.
            .overscrollAction(
                threshold: 84,
                symbol: "plus",
                label: "Crear nuevo outfit",
                bottomInset: WK.Spacing.m
            ) {
                appEnvironment.gate.require(.garments) { isCreatingOutfit = true }
            }
            .outfitCreationFlow(isActive: $isCreatingOutfit, onCreate: planForToday)
            .animation(WKAnimation.content, value: garments.isEmpty)
            .background(WK.Palette.canvas.ignoresSafeArea())
            .adaptiveScrollEdge(.top)
            // **Sin "Crear outfit" en el armario, por ahora.** Se queda
            // comentado y no se borra: el CTA y su flujo siguen enteros, solo
            // que el armario no es ahora mismo el sitio desde el que se monta
            // un outfit.
            // .adaptiveFloatingAccessory { MakeOutfitsAccessory() }
            .rootTabBar(selection: $tab)
            // Se enseña cuando hay ropa que mover: con el armario vacío, un
            // aviso sobre arrastrar prendas explica algo que no se puede hacer.
            .wkTip(.dragGarment, in: appEnvironment.tips)
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
                    // **El icono suelto, no un `Button` dentro del enlace.**
                    // Metido dentro, el botón se comía el toque y el enlace no
                    // llegaba a dispararse nunca; apagándole el hit testing,
                    // el enlace se quedaba sin nada que tocar. Un
                    // `NavigationLink` ya es pulsable: lo que necesita es una
                    // etiqueta, no otro botón.
                    NavigationLink(value: ClosetRoute.settings) {
                        Image(systemName: "person.crop.circle")
                            .font(WK.Font.headline)
                            .contentShape(.rect)
                    }
                    .tint(WK.Palette.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // **El corazón, arriba.** Las favoritas no son una balda
                    // —la camisa favorita sigue siendo una camisa— pero sí son
                    // lo que se busca cuando se busca deprisa.
                    NavigationLink(value: ClosetRoute.favourites) {
                        Image(systemName: "heart")
                            .font(WK.Font.headline)
                            .contentShape(.rect)
                    }
                    .tint(WK.Palette.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ClosetAddMenu()
                }
            }
            .sheet(item: $sheet) { which in
                switch which {
                case .capture:
                    CameraScreen { image in
                        captured = ImportableBatch(images: [image])
                        sheet = .review
                    }
                case .review:
                    if let captured {
                        ImportSheet(images: captured.images)
                    }
                case .shelves:
                    NavigationStack { ShelfOrderScreen() }
                }
            }
            #if DEBUG
            .task { openSuitcaseIfRequested() }
            #endif
        }
    }

    /// Cuelga el outfit recién creado del día de hoy.
    ///
    /// **De hoy y no de ninguno**, porque desde el armario no hay día a la
    /// vista: un outfit suelto no aparecería en el plan y habría que ir a
    /// buscarlo. Desde el plan se cuelga del día que estés mirando, que ahí sí
    /// se sabe cuál es.
    private func planForToday(_ outfit: Outfit) {
        let today = Calendar.current.startOfDay(for: Date())
        let existing = try? modelContext.fetch(
            FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.dayStart == today })
        )
        let day = existing?.first ?? {
            let new = PlannedDay(dayStart: today)
            modelContext.insert(new)
            return new
        }()
        outfit.plannedDay = day
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
        case .suitcases:
            SuitcasesScreen()
        case .favourites:
            CategoryScreen(favourites: "Favoritas")
        }
    }
}

#Preview {
    @Previewable @State var tab = RootTab.closet
    return ClosetScreen(tab: $tab)
        .environment(AppEnvironment.live())
        .modelContainer(try! WardrobeStore.makeContainer(inMemory: true))
}
