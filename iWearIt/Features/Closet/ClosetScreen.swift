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
    #endif
    /// La pila de navegación del armario. **En las dos configuraciones**: en
    /// Release era una constante y empujar cualquier pantalla —ajustes,
    /// favoritas, maletas— no hacía nada.
    @State private var debugPath = NavigationPath()

    // **Fuera del `#if DEBUG`.** Estaban dentro por error: en Debug compilaba
    // y en Release —el archive— no existía nada de esto.
    /// El arrastre de prendas entre baldas. Vive aquí porque cruza baldas: es
    /// el único sitio que las ve todas.
    @State private var shelfDrag = ShelfDragModel()
    /// El botón del armario vacío abre el menú del "+".
    @State private var isRequestingAdd = false
    /// Editar el armario en bloque. Ver `ClosetBulkEdit`.
    @State private var bulk = ClosetBulkEdit()
    /// El espacio por el que las prendas viajan de su percha a la rejilla.
    @Namespace private var closetGrid
    /// Para desplazar el armario solo mientras se lleva una prenda. Ver
    /// `autoScroll()`.
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var scrollOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    /// Lo abre el estado vacío. Vive aquí porque el botón vacío ocupa la
    /// pantalla entera y no cuelga de ninguna balda.
    /// Una sola hoja. Ver `ClosetAddMenu`: apilar `.sheet` en la misma vista
    /// deja mudos a todos menos a uno.
    @State private var sheet: Sheet?

    private enum Sheet: Identifiable {
        // `profile` ya no está: Ajustes se empuja como pantalla, no se
        // presenta como hoja. Ver `ClosetRoute.settings`.
        case capture
        /// **Con las fotos dentro.** Antes las fotos iban en un estado aparte
        /// y la hoja las leía al abrirse; pero la hoja se construía con el
        /// valor de antes de hacer la foto —vacío— y salía en blanco. Metidas
        /// en el propio caso no hay nada que pueda llegar tarde.
        case review(ImportableBatch)
        case shelves
        /// Lo que el escaneo encontró y aún no se ha decidido. Ver
        /// `PendingGarment`.
        case pending

        var id: String {
            switch self {
            case .capture: "capture"
            case let .review(batch): batch.id.uuidString
            case .shelves: "shelves"
            case .pending: "pending"
            }
        }
    }
    /// El atajo del sobre-scroll: seguir tirando al final del armario crea un
    /// outfit para hoy.
    @State private var isCreatingOutfit = false

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext

    // **Y sin las borradas.** Faltaba el filtro: una balda que la
    // reconciliación había juntado seguía saliendo en el armario como una
    // balda más, así que después de sincronizar se veía la copia vacía al
    // lado de la buena.
    @Query(
        filter: #Predicate<GarmentCategory> { !$0.isHidden && $0.deletedAt == nil },
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
        // **Sin slugs repetidos.** Dos baldas con el mismo `slug` —lo que deja
        // una sincronización antes de juntarlas— daban dos filas con el mismo
        // identificador, y un `ForEach` con identificadores repetidos hace
        // exactamente lo que se veía: filas que aparecen y desaparecen al
        // desplazarse. Se queda la primera de cada slug; la otra la junta
        // `reconcileDuplicates`.
        var seen = Set<String>()
        return categories.filter { seen.insert($0.slug).inserted }.map { category in
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

    /// **Llevar una prenda a una balda que no se ve.**
    ///
    /// El armario está quieto mientras hay una prenda en el dedo —si no, el
    /// dedo que la lleva lo desplazaría—, así que se desplaza él: acercar la
    /// prenda al borde de arriba o de abajo lo mueve, más deprisa cuanto más
    /// cerca del borde. Es lo que hace el sistema al reordenar una lista.
    private func autoScroll() async {
        guard shelfDrag.isDragging else { return }
        let edge: CGFloat = 110
        let maximumStep: CGFloat = 12

        while shelfDrag.isDragging, !Task.isCancelled {
            let y = shelfDrag.location.y
            let bottom = viewportHeight - WKTabBarMetrics.reservedHeight
            var step: CGFloat = 0
            if y < edge {
                step = -maximumStep * min(1, (edge - y) / edge)
            } else if y > bottom - edge {
                step = maximumStep * min(1, (y - (bottom - edge)) / edge)
            }

            if step != 0, !shelfDrag.isLanding {
                scrollPosition.scrollTo(y: max(0, scrollOffset + step))
                // Con el dedo quieto el destino también cambia: lo que hay
                // debajo es otra balda.
                shelfDrag.refreshTarget()
            }
            try? await Task.sleep(for: .milliseconds(16))
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
                        // **El mismo menú que el "+"**, no la cámara directa:
                        // con el armario vacío se puede empezar igual desde la
                        // galería o desde una tienda, y abrir la cámara sin
                        // preguntar dejaba esas dos fuera.
                        //
                        // appEnvironment.gate.require(.garments) { sheet = .capture }
                        isRequestingAdd = true
                    }
                        .containerRelativeFrame(.vertical)
                        // Con el armario vacío también: si del escaneo no se
                        // importó nada, lo pendiente es justo lo que falta.
                        .overlay(alignment: .top) {
                            PendingGarmentsPill { sheet = .pending }
                        }
                        .transition(AnyTransition(.blurReplace))
                } else if bulk.isActive {
                    // Todas las prendas juntas, cada una llegando desde su
                    // percha. Ver `ClosetBulkGrid`.
                    ClosetBulkGrid(bulk: bulk, namespace: closetGrid)
                } else {
                    LazyVStack(spacing: 0) {
                        // Lo que el escaneo dejó por decidir, antes que nada.
                        PendingGarmentsPill { sheet = .pending }

                        ForEach(shelves) { shelf in
                            ShelfSection(data: shelf)
                                .equatable()
                        }
                        SuitcaseShelfSection()

                        // Cuánta ropa hay en total, justo encima de editar.
                        Text("\(garments.count.formatted()) \(garments.count == 1 ? "prenda" : "prendas")")
                            .font(WK.Font.caption)
                            .foregroundStyle(WK.Palette.tertiaryText)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(garments.count)))
                            .frame(maxWidth: .infinity)
                            .padding(.top, WK.Spacing.l)

                        // Al final del todo, donde se te ocurre. Ver
                        // `ShelfEditPill`.
                        ShelfEditPill { sheet = .shelves }

                        // Y debajo, editar las prendas en bloque. **Ahora se
                        // entra por el lápiz de arriba**, así que la píldora
                        // se queda comentada.
                        // ClosetBulkEditPill {
                        //     withAnimation(WKAnimation.content) { bulk.start() }
                        // }
                        // .padding(.bottom, WK.Spacing.xxl)
                    }
                    .padding(.top, WK.Spacing.s)
                    .transition(AnyTransition(.blurReplace))
                }
            }
            .scrollIndicators(.hidden)
            // **Rebota aunque quepa todo**: con dos baldas no hay nada que
            // desplazar y el gesto no existiría.
            .scrollBounceBehavior(.always, axes: .vertical)
            // **Una prenda en el dedo lo congela todo.** Con el armario
            // desplazándose por debajo, soltar la prenda donde apuntas es
            // imposible: la balda se ha ido de sitio mientras llegabas.
            .scrollDisabled(shelfDrag.locksScroll)
            .scrollPosition($scrollPosition)
            // En coordenadas del contenido: el desplazamiento crudo empieza en
            // negativo —el hueco de la barra de arriba— y `scrollTo` cuenta
            // desde el principio del contenido. Mezclarlos dejaba el armario
            // clavado arriba creyendo que ya estaba ahí.
            .onScrollGeometryChange(for: CGFloat.self) {
                $0.contentOffset.y + $0.contentInsets.top
            } action: { _, y in
                scrollOffset = y
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, height in
                viewportHeight = height
            }
            // Mientras hay una prenda en el dedo, el borde desplaza el armario.
            .task(id: shelfDrag.isDragging) { await autoScroll() }
            // El espacio donde se miden las baldas y las prendas, y donde se
            // dibuja la que va levantada. Ver `ShelfDragModel`.
            .coordinateSpace(.named(ShelfDragModel.space))
            .overlay { ShelfDragOverlay(model: shelfDrag) }
            .environment(shelfDrag)
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
            // Con el modo bloque encendido la barra de pestañas se va y en su
            // sitio quedan las tres acciones.
            // `onPlus:` con su nombre y no como cierre final: desde que el
            // botón del estilista es opcional, un cierre suelto se lo queda él
            // —así lo empareja Swift— y el "+" acababa abriendo el estilista.
            .rootTabBar(
                .closet,
                selection: $tab,
                isHidden: bulk.isActive,
                onPlus: { isRequestingAdd = true }
            )
            // Las acciones sobre lo marcado, las mismas que dentro de una
            // balda. Ver `ClosetBulkActionsModifier`.
            .closetBulkActions(on: selectedGarments, isActive: bulk.isActive) {
                bulk.stop()
            }
            .environment(\.closetMatchNamespace, closetGrid)
            .animation(WKAnimation.content, value: bulk.isActive)
            // Se enseña cuando hay ropa que mover: con el armario vacío, un
            // aviso sobre arrastrar prendas explica algo que no se puede hacer.
            .wkTip(.dragGarment, in: appEnvironment.tips, when: garments.count >= 2)
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
                // **Con el modo bloque encendido no queda nada**: solo el
                // visto para salir. Lo que se está haciendo es marcar prendas,
                // y ajustes, favoritas o añadir sacan de ahí.
                if bulk.isActive {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(WKAnimation.content) { bulk.stop() }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(WK.Font.headline)
                                .contentShape(.rect)
                        }
                        .tint(WK.Palette.primaryText)
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        // **El icono suelto, no un `Button` dentro del enlace.**
                        // Metido dentro, el botón se comía el toque y el enlace
                        // no llegaba a dispararse nunca; apagándole el hit
                        // testing, el enlace se quedaba sin nada que tocar. Un
                        // `NavigationLink` ya es pulsable: lo que necesita es
                        // una etiqueta, no otro botón.
                        NavigationLink(value: ClosetRoute.settings) {
                            // Ajustes, no "perfil": es lo que hay detrás.
                            // Image(systemName: "person.crop.circle")
                            Image(systemName: "gearshape")
                                .font(WK.Font.headline)
                                .contentShape(.rect)
                        }
                        .tint(WK.Palette.primaryText)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // **El corazón, arriba.** Las favoritas no son una balda
                        // —la camisa favorita sigue siendo una camisa— pero sí
                        // son lo que se busca cuando se busca deprisa.
                        NavigationLink(value: ClosetRoute.favourites) {
                            Image(systemName: "heart")
                                .font(WK.Font.headline)
                                .contentShape(.rect)
                        }
                        .tint(WK.Palette.primaryText)
                    }
                    // **El archivo de probados**, junto a las favoritas: las
                    // dos son "lo que has guardado", y ahí es donde se busca.
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: ClosetRoute.tryOns) {
                            Image(systemName: "person.crop.rectangle.stack")
                                .font(WK.Font.headline)
                                .contentShape(.rect)
                        }
                        .tint(WK.Palette.primaryText)
                        .accessibilityLabel("Probados")
                    }
                    // Separados en grupos: el corazón y el lápiz a un lado, y
                    // el "+" al final del todo, que es la acción principal. En
                    // iOS 26 el hueco además parte el cristal en dos píldoras.
                    AdaptiveToolbarSpacer()
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(WKAnimation.content) { bulk.start() }
                        } label: {
                            Image(systemName: "pencil")
                                .font(WK.Font.headline)
                                .contentShape(.rect)
                        }
                        .tint(WK.Palette.primaryText)
                    }
                    AdaptiveToolbarSpacer()
                    ToolbarItem(placement: .topBarTrailing) {
                        ClosetAddMenu(openRequest: $isRequestingAdd)
                    }
                }
            }
            .sheet(item: $sheet) { which in
                switch which {
                case .capture:
                    CameraScreen { images in
                        sheet = .review(ImportableBatch(images: images))
                    }
                case let .review(batch):
                    ImportSheet(images: batch.images)
                case .shelves:
                    NavigationStack { ShelfOrderScreen() }
                case .pending:
                    PendingGarmentsSheet()
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

    /// Lo marcado, resuelto a prendas.
    private var selectedGarments: [Garment] {
        garments.filter { bulk.contains($0.persistentModelID) }
    }

    private var navigationPath: Binding<NavigationPath> { $debugPath }
    // Antes, en Release: `.constant(NavigationPath())`, que no dejaba navegar.

    #if DEBUG
    private func openSuitcaseIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-open"),
              ProcessInfo.processInfo.arguments.contains("suitcase"),
              let suitcase = allSuitcases.first,
              debugPath.isEmpty
        else { return }
        debugPath.append(ClosetRoute.suitcase(id: suitcase.id))
    }
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
            // **Prendas y conjuntos, juntos.** La pantalla de solo prendas se
            // queda comentada: el corazón significa lo mismo en los dos casos
            // y separarlos obligaba a acordarse de dónde guardaste qué.
            // CategoryScreen(favourites: "Favoritas")
            FavouritesScreen()
        case .tryOns:
            TryOnArchiveScreen()
        }
    }
}

#Preview {
    @Previewable @State var tab = RootTab.closet
    return ClosetScreen(tab: $tab)
        .environment(AppEnvironment.live())
        .modelContainer(try! WardrobeStore.makeContainer(inMemory: true))
}
