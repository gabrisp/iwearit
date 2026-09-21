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

    @State private var step: Step?
    /// La galería del sistema, abierta **desde el menú**.
    ///
    /// No es un paso más del enum a propósito: el `PhotosPicker` no es una
    /// pantalla nuestra que se presenta en la hoja, es el picker del sistema
    /// presentándose encima de ella. Meterlo en el enum obligaba a que hubiera
    /// una hoja intermedia —un título, un párrafo y un botón "Abrir galería"—
    /// que solo servía para volver a pedir lo que el usuario ya había pedido.
    @State private var isPickingFromLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var isLoadingLibraryPick = false

    private enum Step: Identifiable {
        case menu
        // case library   ← la galería ya no es un paso: se abre desde el menú
        case camera
        case web
        case review(ImportableImage)
        case newCategory
        case shelfOrder

        var id: String {
            switch self {
            case .menu: "menu"
            case .camera: "camera"
            case .web: "web"
            case let .review(image): image.id.uuidString
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
        .sheet(item: $step) { current in
            content(for: current)
        }
    }

    @ViewBuilder
    private func content(for step: Step) -> some View {
        switch step {
        case .menu:
            WKMenuSheet(title: "Añadir", items: menuItems)
                // **La galería del sistema, encima del menú.**
                //
                // `PhotosPicker` corre en otro proceso: no compite por la
                // cámara ni por la ANE y no depende de que una sesión de
                // captura arranque bien. Colgado de la hoja del menú y no del
                // botón de la toolbar, que es quien ya tiene su `sheet` y no
                // admite dos presentaciones.
                .photosPicker(
                    isPresented: $isPickingFromLibrary,
                    selection: $libraryItem,
                    matching: .images
                )
                .overlay {
                    if isLoadingLibraryPick { ProgressView() }
                }
                .task(id: libraryItem) { await loadLibraryPick() }
        case .camera:
            // Al pasar a la revisión, la cámara **se destruye**. Con dos hojas
            // apiladas seguía viva por debajo, y su sesión de captura se
            // peleaba con Vision por la ANE: el análisis se quedaba pensando
            // para siempre.
            CameraScreen { captured in
                self.step = .review(ImportableImage(cgImage: captured))
            }
        case .web:
            // A pantalla completa y sin poder arrastrarse para cerrar: ver
            // `WebImportScreen`.
            WebImportScreen { captured in
                self.step = .review(ImportableImage(cgImage: captured))
            }
        case let .review(image):
            ImportSheet(image: image.cgImage)
        case .newCategory:
            NewCategorySheet()
        case .shelfOrder:
            NavigationStack { ShelfOrderScreen() }
        }
    }

    /// Lo elegido en la galería, **derecho** y listo para revisar.
    private func loadLibraryPick() async {
        guard let libraryItem else { return }
        isLoadingLibraryPick = true
        defer {
            isLoadingLibraryPick = false
            self.libraryItem = nil
        }

        guard
            let data = try? await libraryItem.loadTransferable(type: Data.self),
            // Derecha antes de que la vea nadie: `UIImage.cgImage` da los
            // píxeles en crudo y una foto vertical los guarda en horizontal.
            let image = UprightImage.cgImage(from: data)
        else {
            #if DEBUG
            NSLog("IMPORT: la foto no se pudo leer")
            #endif
            return
        }
        step = .review(ImportableImage(cgImage: image))
    }

    private var menuItems: [WKMenuItem] {
        [
            // Una sola entrada: la cámara ya lleva dentro el acceso a la
            // galería, así que preguntar antes "¿foto nueva o existente?" es
            // una bifurcación que el usuario no había pedido.
            WKMenuItem(id: "library", title: "Elegir de la galería", systemImage: "photo.on.rectangle") {
                appEnvironment.gate.require(.garments) { isPickingFromLibrary = true }
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
struct ImportableImage: Identifiable {
    let id = UUID()
    let cgImage: CGImage
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