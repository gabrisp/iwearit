import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Editar el armario **en bloque**, sin salir del armario.
///
/// ## Por qué
///
/// Corregir veinte prendas recién importadas de una en una es abrir la balda,
/// tocar la prenda, editar, volver, buscar la siguiente. El armario ya sabe
/// dónde está todo: lo que falta es poder verlo junto, marcar lo que quieras y
/// hacerle una cosa a todo a la vez.
///
/// Con el modo encendido, las baldas se convierten en una rejilla con **todas**
/// las prendas —cada una viaja desde su percha con `matchedGeometryEffect`—, la
/// barra de pestañas se va y en su sitio aparecen las tres acciones: mover a
/// otra balda, editar y eliminar.
@MainActor
@Observable
final class ClosetBulkEdit {
    private(set) var isActive = false
    /// Lo marcado, por identidad persistente: sobrevive a que la consulta se
    /// reordene, que es justo lo que pasa al mover una prenda de balda.
    private(set) var selection: Set<PersistentIdentifier> = []

    func start() {
        isActive = true
        selection.removeAll()
    }

    func stop() {
        isActive = false
        selection.removeAll()
    }

    func toggle(_ id: PersistentIdentifier) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func contains(_ id: PersistentIdentifier) -> Bool { selection.contains(id) }

    func select(_ ids: [PersistentIdentifier]) { selection = Set(ids) }
}

extension EnvironmentValues {
    /// El espacio compartido entre las perchas del armario y la rejilla de
    /// edición, para que cada prenda viaje de una a otra. `nil` fuera del
    /// armario: la misma percha se usa en pantallas donde no hay rejilla.
    @Entry var closetMatchNamespace: Namespace.ID?
}

/// Todas las prendas en una rejilla, para marcarlas.
///
/// Su propia `@Query`: el armario pasa las baldas ya repartidas y aquí hace
/// falta justo lo contrario, la lista entera y en un orden estable.
struct ClosetBulkGrid: View {
    let bulk: ClosetBulkEdit
    /// El espacio compartido con las perchas: cada prenda **vuela** desde su
    /// balda hasta su celda en vez de aparecer donde le toque.
    let namespace: Namespace.ID

    @Query(FetchDescriptor<Garment>.visibleGarments())
    private var garments: [Garment]

    @Environment(AppEnvironment.self) private var appEnvironment

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: WK.Spacing.m)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: WK.Spacing.l) {
            ForEach(garments) { garment in
                // **La misma percha que dentro de una balda**, marcándose
                // igual: sin recuadro ni aro, la prenda y su visto. Tenía su
                // propia celda con fondo y borde y se leía como otra pantalla.
                HangingGarmentView(
                    garment: GarmentRef(garment),
                    isSelecting: true,
                    isSelected: bulk.contains(garment.persistentModelID),
                    onToggleSelection: {
                        withAnimation(WKAnimation.selection) {
                            bulk.toggle(garment.persistentModelID)
                        }
                    }
                )
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.top, WK.Spacing.m)
        .padding(.bottom, 140)
    }
}

// La celda propia de la rejilla, con su fondo y su aro. Sustituida por
// `HangingGarmentView`, que es como se marca una prenda en una balda.
// /// Una prenda en la rejilla de edición.
// private struct ClosetBulkCell: View {
//     let garment: GarmentRef
//     let isSelected: Bool
//     let namespace: Namespace.ID
//     let onTap: () -> Void

//     @Environment(AppEnvironment.self) private var appEnvironment

//     var body: some View {
//         Button(action: onTap) {
//             StoredImage(
//                 key: garment.imageKey,
//                 variant: .thumb,
//                 store: appEnvironment.imageStore,
//                 alignment: .center,
//                 shadow: .init(opacity: 0.35, radius: 6, y: 4)
//             )
//             .frame(height: 104)
//             .padding(WK.Spacing.xs)
//             .frame(maxWidth: .infinity)
//             .background {
//                 RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
//                     .fill(isSelected ? WK.Palette.accent.opacity(0.12) : WK.Palette.ink(0.04))
//             }
//             .overlay {
//                 RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
//                     .stroke(WK.Palette.accent, lineWidth: isSelected ? 2 : 0)
//             }
//             .overlay(alignment: .topTrailing) {
//                 Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
//                     .font(.footnote)
//                     .symbolRenderingMode(.palette)
//                     .foregroundStyle(
//                         isSelected ? WK.Palette.onAccent : WK.Palette.secondaryText,
//                         isSelected ? WK.Palette.accent : WK.Palette.ink(0.10)
//                     )
//                     .padding(WK.Spacing.xs)
//             }
//             // **Un solo grupo al componer**: la imagen, su sombra y el aro se
//             // mueven como una pieza mientras la prenda viaja desde su percha.
//             .compositingGroup()
//             .matchedGeometryEffect(id: garment.id, in: namespace)
//             .contentShape(.rect)
//         }
//         .buttonStyle(WKPressStyle())
//         .animation(WKAnimation.selection, value: isSelected)
//     }
// }

/// Las acciones en bloque, donde estaba la barra de pestañas.
///
/// **Dos filas.** Abajo lo que cambia la prenda de sitio o la quita, y arriba
/// lo que se corrige en tanda y es justo lo que se viene a hacer después de
/// importar: marcar favoritas, poner una etiqueta de uso a todas o decir
/// cuánto abrigan.
struct ClosetBulkActionBar: View {
    let count: Int
    let isAllFavourite: Bool
    let onMove: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onFavourite: () -> Void
    let onTags: () -> Void
    let onWarmth: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                action(
                    String(localized: "closet.closetbulkedit.favorite", defaultValue: "Favorite"),
                    symbol: isAllFavourite ? "heart.fill" : "heart",
                    tint: isAllFavourite ? .red : WK.Palette.primaryText,
                    action: onFavourite
                )
                action(String(localized: "closet.closetbulkedit.tags", defaultValue: "Tags"), symbol: "tag", action: onTags)
                action(String(localized: "common.warmth", defaultValue: "Warmth"), symbol: "thermometer.medium", action: onWarmth)
            }
            HStack(spacing: 12) {
                action(String(localized: "closet.closetbulkedit.move", defaultValue: "Move"), symbol: "tray.full", action: onMove)
                action(String(localized: "common.edit", defaultValue: "Edit"), symbol: "slider.horizontal.3", action: onEdit)
                action(String(localized: "common.delete", defaultValue: "Delete"), symbol: "trash", tint: .red, action: onDelete)
            }
        }
        .disabled(count == 0)
        .opacity(count == 0 ? 0.5 : 1)
        .animation(WKAnimation.selection, value: count == 0)
        // De borde a borde, con el mismo margen que los botones de la barra de
        // arriba: tres píldoras pequeñas centradas se leían como un accesorio
        // suelto y no como la barra de la pantalla.
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.xs)
    }

    private func action(
        _ label: String,
        symbol: String,
        tint: Color = WK.Palette.primaryText,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                Text(label)
                    .font(WK.Font.caption)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .contentShape(.capsule)
        }
        .buttonStyle(WKPlainGlassButtonStyle(shape: Capsule(style: .continuous)))
    }
}

/// Poner las mismas **etiquetas de uso** a todas las marcadas.
///
/// Se ponen, no se mezclan: lo que quede marcado es lo que tendrán todas. Es
/// lo que se espera al elegir diez prendas y decir "esto es de deporte".
struct ClosetBulkTagsSheet: View {
    let garments: [Garment]

    @Environment(\.dismiss) private var dismiss
    @State private var tags: Set<String> = []

    var body: some View {
        WKChipSheet(
            title: String(localized: "closet.closetbulkedit.tags", defaultValue: "Tags"),
            subtitle: garments.count == 1
                ? String(localized: "closet.closetbulkedit.appliesTo1Item", defaultValue: "Applies to 1 item")
                : String(localized: "closet.closetbulkedit.appliesToItems2", defaultValue: "Applies to \(String(describing: garments.count)) items"),
            options: GarmentVocabulary.usageTags.map { .init(id: $0, label: $0) },
            selection: Binding(
                get: { tags },
                set: { newValue in
                    tags = newValue
                    for garment in garments { garment.tags = Array(newValue) }
                }
            ),
            allowsCustom: true
        )
        .onAppear {
            // Lo que ya comparten todas: así quitar una etiqueta común se
            // entiende, en vez de partir de cero siempre.
            let shared = garments
                .map { Set(GarmentVocabulary.visibleTags($0.tags)) }
                .reduce(into: Set<String>?.none) { result, next in
                    result = result.map { $0.intersection(next) } ?? next
                }
            tags = shared ?? []
        }
    }
}

/// Cuánto abrigan, para todas a la vez.
struct ClosetBulkWarmthSheet: View {
    let garments: [Garment]

    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []

    var body: some View {
        WKChipSheet(
            title: String(localized: "common.warmth", defaultValue: "Warmth"),
            subtitle: garments.count == 1
                ? String(localized: "closet.closetbulkedit.appliesTo1Item", defaultValue: "Applies to 1 item")
                : String(localized: "closet.closetbulkedit.appliesToItems", defaultValue: "Applies to \(String(describing: garments.count)) items"),
            options: GarmentVocabulary.Warmth.allCases.map { .init(id: $0.rawValue, label: $0.label) },
            selection: Binding(
                get: { picked },
                set: { newValue in
                    picked = newValue
                    guard
                        let raw = newValue.first,
                        let warmth = GarmentVocabulary.Warmth(rawValue: raw)
                    else {
                        // Sin nada marcado: valen para todo el año.
                        for garment in garments { garment.seasons = .all }
                        return
                    }
                    for garment in garments { garment.seasons = warmth.seasons }
                }
            ),
            limit: 1,
            allowsEmpty: true
        )
    }
}

/// Mover **varias** prendas a una balda, con la misma rueda que una sola.
struct ClosetBulkShelfSheet: View {
    let garments: [Garment]

    @Query(
        filter: #Predicate<GarmentCategory> { !$0.isHidden && $0.deletedAt == nil },
        sort: [SortDescriptor(\GarmentCategory.sortOrder)]
    )
    private var categories: [GarmentCategory]

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            Text(garments.count == 1 ? String(localized: "closet.closetbulkedit.move1Item", defaultValue: "Move 1 item") : String(localized: "closet.closetbulkedit.moveItems", defaultValue: "Move \(String(describing: garments.count)) items"))
                .font(WK.Font.title)
                .foregroundStyle(WK.Palette.primaryText)

            WKWheelPicker(items: categories.map(\.slug), selection: $selection) { slug in
                Text(categories.first { $0.slug == slug }?.displayName ?? "")
                    .font(WK.Font.title)
            }
            .frame(height: 220)

            WKPrimaryButton(String(localized: "closet.closetbulkedit.moveHere", defaultValue: "Move here")) { apply() }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .wkDynamicSheet()
        .onAppear { selection = garments.first?.category?.slug ?? categories.first?.slug }
    }

    private func apply() {
        if let slug = selection, let category = categories.first(where: { $0.slug == slug }) {
            for garment in garments {
                garment.category = category
                // A mano: la clasificación automática no vuelve a tocarla.
                garment.categoryLockedByUser = true
            }
        }
        dismiss()
    }
}

/// Editar las marcadas, **una detrás de otra**.
///
/// Como la revisión de una importación —una fila por prenda y la ficha entera
/// a un toque— pero sin la casilla: aquí ya elegiste cuáles en el armario, y lo
/// que se viene a hacer es corregirlas deprisa.
struct ClosetBulkEditSheet: View {
    let garments: [Garment]

    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var editing: Garment?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: WK.Spacing.s) {
                    ForEach(garments) { garment in
                        Button { editing = garment } label: {
                            ClosetBulkEditRow(garment: garment)
                        }
                        .buttonStyle(WKPressStyle())
                    }
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .padding(.vertical, WK.Spacing.m)
            }
            .scrollIndicators(.hidden)
            .background(WK.Palette.canvas.ignoresSafeArea())
            .navigationTitle(garments.count == 1 ? String(localized: "closet.closetbulkedit.editItem", defaultValue: "Edit item") : String(localized: "closet.closetbulkedit.editItems2", defaultValue: "Edit \(String(describing: garments.count)) items"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Un símbolo, nunca texto: es la regla de todas las barras
                    // de la app.
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(WK.Font.headline)
                            .contentShape(.rect)
                    }
                    .tint(WK.Palette.primaryText)
                }
            }
            // **Otra hoja encima, no una pantalla empujada.** La ficha es una
            // hoja en todo el resto de la app y aquí tiene que llegar igual:
            // se corrige, se cierra y se toca la siguiente, sin salir de la
            // lista.
            // .navigationDestination(item: $editing) { garment in
            //     GarmentEditSheet(garment: garment, embedsNavigation: false)
            // }
            .sheet(item: $editing) { garment in
                GarmentEditSheet(garment: garment)
            }
        }
    }
}

/// Una prenda en la lista de edición rápida.
///
/// **La misma tarjeta que al importar** —`ImportGarmentCard`— sin la franja de
/// la casilla: la foto a la izquierda, la muestra de color con el nombre, y
/// debajo lo que se mira antes de decidir si hay que tocarla. Aquí no se
/// marca nada: eso ya se hizo en el armario.
private struct ClosetBulkEditRow: View {
    @Bindable var garment: Garment

    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        HStack(spacing: WK.Spacing.m) {
            StoredImage(
                key: garment.normalizedImageKey,
                variant: .thumb,
                store: appEnvironment.imageStore,
                alignment: .center
            )
            .padding(WK.Spacing.xs)
            .frame(width: 96, height: 112)
            .background(
                WK.Palette.ink(0.04),
                in: .rect(cornerRadius: WK.Radius.medium, style: .continuous)
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: WK.Spacing.xs) {
                    swatch
                    Text(garment.name)
                        .font(WK.Font.callout)
                        .foregroundStyle(WK.Palette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Text(details)
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(WK.Spacing.s)
        .frame(maxWidth: .infinity)
        .background(
            WK.Palette.shelf,
            in: .rect(cornerRadius: WK.Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WK.Radius.card, style: .continuous)
                .stroke(WK.Palette.ink(0.06), lineWidth: 1)
        }
        .contentShape(.rect)
    }

    /// El color, sin palabra: la muestra lo dice mejor. Igual que al importar.
    @ViewBuilder
    private var swatch: some View {
        if let color = garment.dominantColor {
            Circle()
                .fill(Color(red: color.red, green: color.green, blue: color.blue))
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(WK.Palette.ink(0.12), lineWidth: 1))
        }
    }

    /// "Camisetas · Camiseta · Algodón · Zara".
    private var details: String {
        [
            garment.category?.displayName,
            GarmentVocabulary.displayType(garment.subcategory),
            garment.material?.capitalized,
            garment.brand,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

/// La píldora que enciende el modo, debajo de "Editar baldas".
struct ClosetBulkEditPill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(String(localized: "closet.closetbulkedit.editItems", defaultValue: "Edit items"), systemImage: "square.grid.2x2")
                .font(WK.Font.captionMedium)
                .foregroundStyle(WK.Palette.secondaryText)
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s)
                .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
        .adaptiveGlassInteractive(in: .capsule)
        .frame(maxWidth: .infinity)
        .padding(.top, WK.Spacing.s)
    }
}

/// El `matchedGeometryEffect` de una prenda, **solo dentro del armario**.
///
/// En un modificador y no suelto en la percha: fuera del armario no hay
/// rejilla a la que viajar, y un efecto sin pareja reserva sitio para nada.
struct ClosetMatchedGarment: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// Las acciones en bloque, listas para colgarlas de cualquier pantalla.
///
/// En un modificador y no repetidas: el armario entero y una balda abierta
/// hacen exactamente lo mismo con lo que hay marcado, y tenerlo dos veces
/// significa que la segunda se queda atrás en cuanto se añade una acción.
struct ClosetBulkActionsModifier: ViewModifier {
    /// Lo marcado, ya resuelto a prendas.
    let garments: [Garment]
    let isActive: Bool
    /// Se llama cuando lo marcado deja de existir —se ha borrado— para que
    /// quien manda limpie su selección.
    let onDeleted: () -> Void

    @State private var sheet: BulkSheet?
    @State private var isConfirmingDelete = false

    private enum BulkSheet: String, Identifiable {
        case move, edit, tags, warmth
        var id: String { rawValue }
    }

    func body(content: Content) -> some View {
        content
            .adaptiveSafeAreaBar(edge: .bottom) {
                if isActive {
                    ClosetBulkActionBar(
                        count: garments.count,
                        isAllFavourite: !garments.isEmpty && garments.allSatisfy(\.isFavorite),
                        onMove: { sheet = .move },
                        onEdit: { sheet = .edit },
                        onDelete: { isConfirmingDelete = true },
                        onFavourite: { toggleFavourite() },
                        onTags: { sheet = .tags },
                        onWarmth: { sheet = .warmth }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(item: $sheet) { which in
                switch which {
                case .move: ClosetBulkShelfSheet(garments: garments)
                case .edit: ClosetBulkEditSheet(garments: garments)
                case .tags: ClosetBulkTagsSheet(garments: garments)
                case .warmth: ClosetBulkWarmthSheet(garments: garments)
                }
            }
            .alert(
                garments.count == 1 ? String(localized: "closet.closetbulkedit.deleteThisItem", defaultValue: "Delete this item?") : String(localized: "closet.closetbulkedit.deleteItems", defaultValue: "Delete \(String(describing: garments.count)) items?"),
                isPresented: $isConfirmingDelete
            ) {
                Button(String(localized: "common.delete", defaultValue: "Delete"), role: .destructive) { delete() }
                Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
            }
    }

    /// Marca todas como favoritas, o las desmarca si ya lo eran todas.
    private func toggleFavourite() {
        let makeFavourite = !garments.allSatisfy(\.isFavorite)
        withAnimation(WKAnimation.selection) {
            for garment in garments { garment.isFavorite = makeFavourite }
        }
    }

    private func delete() {
        withAnimation(WKAnimation.content) {
            for garment in garments { garment.markDeleted() }
            onDeleted()
        }
    }
}

extension View {
    /// Las acciones en bloque sobre lo marcado. Ver `ClosetBulkActionsModifier`.
    func closetBulkActions(
        on garments: [Garment],
        isActive: Bool,
        onDeleted: @escaping () -> Void
    ) -> some View {
        modifier(
            ClosetBulkActionsModifier(garments: garments, isActive: isActive, onDeleted: onDeleted)
        )
    }
}
