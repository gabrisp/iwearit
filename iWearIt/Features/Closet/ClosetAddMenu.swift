import PhotosUI
import SwiftUI
import WKCore
import WKDesign

/// El "+" de la toolbar del armario.
///
/// Abre un menú propio, no el del sistema: el del sistema trae su fondo, su
/// tipografía y su animación, y quedaba como una pieza prestada entre pantallas
/// que sí están diseñadas.
///
/// ## Una sola hoja
///
/// Todo lo que abre este botón pasa por `sheet`, y **`sheet` solo admite uno
/// por vista**. Apilar cinco modificadores `.sheet` aquí no da error: SwiftUI
/// atiende a uno y los demás se quedan mudos, que es exactamente cómo dejó de
/// abrirse la cámara. Con un enum, encadenar pasos —menú → cámara → revisión—
/// es cambiar de caso, y el paso anterior se destruye al hacerlo.
struct ClosetAddMenu: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    /// Abrir el menú desde fuera: el botón del armario vacío pide lo mismo
    /// que el "+", y el menú es uno solo.
    var openRequest: Binding<Bool> = .constant(false)

    @State private var step: Step?
    /// La galería del sistema, abierta **desde el menú**.
    ///
    /// No es un paso más del enum a propósito: el `PhotosPicker` no es una
    /// pantalla nuestra que se presenta en la hoja, es el picker del sistema
    /// presentándose encima de ella. Meterlo en el enum obligaba a que hubiera
    /// una hoja intermedia —un título, un párrafo y un botón "Abrir galería"—
    /// que solo servía para volver a pedir lo que el usuario ya había pedido.
    @State private var isPickingFromLibrary = false
    /// Varias: en la galería la ropa está en tandas, no de una en una.
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var isLoadingLibraryPick = false

    private enum Step: Identifiable {
        case menu
        // case library   ← la galería ya no es un paso: se abre desde el menú
        case camera
        case web
        case review(ImportableBatch)
        /// La importación que se cerró sin guardar. Con el modelo dentro, sacado
        /// al tocar: sacarlo al dibujar la hoja lo vaciaría en el segundo
        /// dibujado y la hoja saldría en blanco.
        case restore(ImportModel)
        case newCategory
        case shelfOrder

        var id: String {
            switch self {
            case .menu: "menu"
            case .camera: "camera"
            case .web: "web"
            case let .review(batch): batch.id.uuidString
            case let .restore(model): "restore-\(ObjectIdentifier(model).hashValue)"
            case .newCategory: "category"
            case .shelfOrder: "order"
            }
        }
    }

    var body: some View {
        Button {
            step = .menu
        } label: {
            // Sin cristal propio: es un item de barra, y el sistema ya le pone
            // su superficie. Ponérsela aquí da cristal sobre cristal, que no se
            // puede muestrear a sí mismo y se ve turbio.
            Image(systemName: "plus")
                .font(WK.Font.headline)
                .contentShape(.rect)
        }
        .tint(WK.Palette.primaryText)
        .onChange(of: openRequest.wrappedValue) { _, requested in
            guard requested else { return }
            openRequest.wrappedValue = false
            step = .menu
        }
        .sheet(item: $step) { current in
            content(for: current)
        }
        // **La galería cuelga de aquí, no de la hoja del menú.**
        //
        // El menú se cierra a sí mismo al tocar una opción —como cualquier
        // menú—, y con él se iba el `photosPicker` que llevaba colgado: la
        // hoja se cerraba y no se abría nada. Puesto en el botón, que es quien
        // sobrevive, el picker se presenta cuando el menú ya se ha ido.
        //
        // No choca con el `sheet` de arriba porque nunca están los dos a la
        // vez: al abrirse el picker, el paso vale `nil`.
        // **Varias de una vez.** Diez es el tope: más de eso es una tarde de
        // análisis, y la pantalla de revisión se vuelve un catálogo por el que
        // hay que navegar en vez de una tanda que se despacha.
        .photosPicker(
            isPresented: $isPickingFromLibrary,
            selection: $libraryItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .task(id: libraryItems.count) { await loadLibraryPick() }
    }

    @ViewBuilder
    private func content(for step: Step) -> some View {
        switch step {
        case .menu:
            WKMenuSheet(title: "Añadir", items: menuItems) {
                // **Lo que quedó a medias, en su propia sección.** No como una
                // opción más de la lista: son prendas ya analizadas, y verlas
                // es lo que hace que se entienda qué se está retomando.
                if let pending = appEnvironment.importSession.pending {
                    PendingImportSection(model: pending) {
                        if let model = appEnvironment.importSession.take() {
                            self.step = .restore(model)
                        }
                    }
                }
            }
            .overlay {
                if isLoadingLibraryPick { ProgressView() }
            }
        case .camera:
            // Al pasar a la revisión, la cámara **se destruye**. Con dos hojas
            // apiladas seguía viva por debajo, y su sesión de captura se
            // peleaba con Vision por la ANE: el análisis se quedaba pensando
            // para siempre.
            CameraScreen { captured in
                self.step = .review(ImportableBatch(images: captured))
            }
        case .web:
            // A pantalla completa y sin poder arrastrarse para cerrar: ver
            // `WebImportScreen`.
            WebImportScreen { captured in
                self.step = .review(ImportableBatch(images: [captured]))
            }
        case let .review(batch):
            ImportSheet(images: batch.images)
        case let .restore(model):
            ImportSheet(restoring: model)
        case .newCategory:
            NewCategorySheet()
        case .shelfOrder:
            NavigationStack { ShelfOrderScreen() }
        }
    }

    /// Lo elegido en la galería, **derecho** y listo para revisar.
    ///
    /// Las que no se puedan leer se caen por el camino y las demás siguen: una
    /// foto rara de entre seis no puede tirar la tanda entera.
    private func loadLibraryPick() async {
        guard !libraryItems.isEmpty else { return }
        let picked = libraryItems
        isLoadingLibraryPick = true
        defer {
            isLoadingLibraryPick = false
            self.libraryItems = []
        }

        var images: [CGImage] = []
        images.reserveCapacity(picked.count)
        for item in picked {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                // Derecha antes de que la vea nadie: `UIImage.cgImage` da los
                // píxeles en crudo y una foto vertical los guarda en horizontal.
                let image = UprightImage.cgImage(from: data)
            else {
                #if DEBUG
                NSLog("IMPORT: una de las fotos no se pudo leer")
                #endif
                continue
            }
            images.append(image)
        }

        guard !images.isEmpty else { return }
        step = .review(ImportableBatch(images: images))
    }

    /// **Seguir donde lo dejaste**, primero y solo si hay algo que seguir.
    private var restoreItem: [WKMenuItem] {
        guard let pending = appEnvironment.importSession.pending else { return [] }
        let count = pending.candidates.count
        return [
            WKMenuItem(
                id: "restore",
                title: count == 1 ? "Seguir con 1 prenda" : "Seguir con \(count) prendas",
                systemImage: "arrow.uturn.backward"
            ) {
                DispatchQueue.main.async {
                    if let model = appEnvironment.importSession.take() { step = .restore(model) }
                }
            },
        ]
    }

    private var menuItems: [WKMenuItem] {
        // restoreItem +   ← ahora es una sección propia: ver `PendingImportSection`
        [
            // Una sola entrada: la cámara ya lleva dentro el acceso a la
            // galería, así que preguntar antes "¿foto nueva o existente?" es
            // una bifurcación que el usuario no había pedido.
            WKMenuItem(id: "library", title: "Elegir de la galería", systemImage: "photo.on.rectangle") {
                appEnvironment.gate.require(.garments) {
                    // Un turno de margen: pedirlo mientras la hoja del menú
                    // aún se está cerrando deja la petición en el aire.
                    DispatchQueue.main.async { isPickingFromLibrary = true }
                }
            },
            WKMenuItem(id: "camera", title: "Hacer una foto", systemImage: "camera") {
                appEnvironment.gate.require(.garments) { step = .camera }
            },
            // **Desde la tienda.** La mejor foto de una prenda recién
            // comprada no está en tu carrete: está en su ficha, sobre fondo
            // blanco, que es justo con lo que el recorte funciona mejor.
            WKMenuItem(id: "web", title: "Desde la web", systemImage: "globe") {
                appEnvironment.gate.require(.garments) { step = .web }
            },
            // **Lo de las baldas ya no vive aquí.** Se queda comentado y no
            // borrado: crear y ordenar baldas se hace desde la píldora del
            // final del armario, que es donde estás cuando se te ocurre.
            //
            // WKMenuItem(id: "shelf", title: "Nueva balda", systemImage: "rectangle.stack.badge.plus") {
            // appEnvironment.gate.require(.customCategories) { step = .newCategory }
            // },
            // WKMenuItem(id: "order", title: "Ordenar baldas", systemImage: "arrow.up.arrow.down") {
            // step = .shelfOrder
            // },
        ]
    }
}

/// `sheet(item:)` necesita `Identifiable`, y `CGImage` no lo es.
/// Una tanda de fotos camino de la revisión.
///
/// Con identidad propia porque es lo que decide cuándo la hoja se reconstruye:
/// dos tandas distintas son dos importaciones, aunque lleven la misma foto.
struct ImportableBatch: Identifiable {
    let id = UUID()
    let images: [CGImage]
}

/// Entrada al perfil, arriba a la izquierda del armario.
///
/// Un botón y no una pestaña: ajustes, estado de los modelos y suscripción se
/// visitan de vez en cuando, y una pestaña permanente para eso gasta un tercio
/// de la barra en lo que menos se usa.
struct ProfileButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "person.crop.circle")
                .font(WK.Font.headline)
                .contentShape(.rect)
        }
        .tint(WK.Palette.primaryText)
    }
}


// MARK: - La hoja intermedia que ya no hay
//
// Pedía "elige una foto" con un botón "Abrir galería" delante de la galería:
// un paso para repetir lo que el usuario acababa de decir. Ahora el menú abre
// el picker del sistema directamente. Se queda comentada, no borrada.
//
// /// Elegir una foto de la galería y devolverla **derecha**.
// ///
// /// Hoja propia y no un `.photosPicker` colgado de otra vista: apilar
// /// presentaciones en la misma vista es exactamente lo que ha ido dejando mudas
// /// unas y otras. Aquí el picker es el contenido de la hoja, así que no compite
// /// con nadie.
// private struct LibraryImportSheet: View {
//     let onPick: (CGImage) -> Void
//
//     @Environment(\.dismiss) private var dismiss
//     @State private var item: PhotosPickerItem?
//     @State private var isLoading = false
//     @State private var failed = false
//
//     var body: some View {
//         VStack(spacing: WK.Spacing.l) {
//             Text("Elige una foto")
//                 .font(WK.Font.title)
//                 .foregroundStyle(WK.Palette.primaryText)
//
//             Text("Sale mejor con la prenda entera y el fondo despejado.")
//                 .font(WK.Font.caption)
//                 .foregroundStyle(WK.Palette.secondaryText)
//                 .multilineTextAlignment(.center)
//
//             PhotosPicker(selection: $item, matching: .images) {
//                 Label("Abrir galería", systemImage: "photo.on.rectangle")
//                     .font(WK.Font.headline)
//                     .foregroundStyle(WK.Palette.onAccent)
//                     .frame(maxWidth: .infinity)
//                     .padding(.vertical, WK.Spacing.m)
//                     .background(WK.Palette.accent, in: .capsule)
//                     .contentShape(.capsule)
//             }
//             .disabled(isLoading)
//
//             if isLoading {
//                 ProgressView()
//             }
//             if failed {
//                 Text("No se pudo leer esa foto. Prueba con otra.")
//                     .font(WK.Font.caption)
//                     .foregroundStyle(.red)
//             }
//         }
//         .padding(.horizontal, WK.Spacing.screenInset)
//         .wkDynamicSheet()
//         .task(id: item) { await load() }
//     }
//
//     private func load() async {
//         guard let item else { return }
//         isLoading = true
//         failed = false
//         defer { isLoading = false }
//
//         #if DEBUG
//         NSLog("IMPORT: cargando de la galería")
//         #endif
//         guard
//             let data = try? await item.loadTransferable(type: Data.self),
//             // Derecha antes de que la vea nadie: `UIImage.cgImage` da los
//             // píxeles en crudo y una foto vertical los guarda en horizontal.
//             let image = UprightImage.cgImage(from: data)
//         else {
//             #if DEBUG
//             NSLog("IMPORT: la foto no se pudo leer")
//             #endif
//             failed = true
//             return
//         }
//         #if DEBUG
//         NSLog("IMPORT: foto lista %dx%d", image.width, image.height)
//         #endif
//         onPick(image)
//     }
// }
//

/// La importación sin terminar: sus prendas en fila y un botón para seguir.
private struct PendingImportSection: View {
    let model: ImportModel
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            Text("Sin terminar")
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.tertiaryText)

            ScrollView(.horizontal) {
                HStack(spacing: WK.Spacing.s) {
                    ForEach(model.candidates) { candidate in
                        candidate.previewImage
                            .resizable()
                            .scaledToFit()
                            .padding(WK.Spacing.xs)
                            .frame(width: 64, height: 76)
                            .background(
                                WK.Palette.ink(0.05),
                                in: .rect(cornerRadius: WK.Radius.medium, style: .continuous)
                            )
                            .opacity(candidate.isKept ? 1 : 0.4)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()

            WKPrimaryButton(
                model.candidates.count == 1
                    ? "Continuar con 1 prenda"
                    : "Continuar con las \(model.candidates.count) prendas",
                surface: .glass,
                action: onContinue
            )
        }
    }
}
