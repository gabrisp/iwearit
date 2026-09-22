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

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: WK.Spacing.m)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: WK.Spacing.m) {
            ForEach(garments) { garment in
                ClosetBulkCell(
                    garment: GarmentRef(garment),
                    isSelected: bulk.contains(garment.persistentModelID),
                    namespace: namespace
                ) {
                    withAnimation(WKAnimation.selection) {
                        bulk.toggle(garment.persistentModelID)
                    }
                }
            }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.top, WK.Spacing.m)
        .padding(.bottom, 140)
    }
}

/// Una prenda en la rejilla de edición.
private struct ClosetBulkCell: View {
    let garment: GarmentRef
    let isSelected: Bool
    let namespace: Namespace.ID
    let onTap: () -> Void

    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        Button(action: onTap) {
            StoredImage(
                key: garment.imageKey,
                variant: .thumb,
                store: appEnvironment.imageStore,
                alignment: .center,
                shadow: .init(opacity: 0.35, radius: 6, y: 4)
            )
            .frame(height: 104)
            .padding(WK.Spacing.xs)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                    .fill(isSelected ? WK.Palette.accent.opacity(0.12) : WK.Palette.ink(0.04))
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
            // **Un solo grupo al componer**: la imagen, su sombra y el aro se
            // mueven como una pieza mientras la prenda viaja desde su percha.
            .compositingGroup()
            .matchedGeometryEffect(id: garment.id, in: namespace)
            .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
        .animation(WKAnimation.selection, value: isSelected)
    }
}

/// Las tres acciones, donde estaba la barra de pestañas.
struct ClosetBulkActionBar: View {
    let count: Int
    let onMove: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            action("Mover", symbol: "tray.full", action: onMove)
            action("Editar", symbol: "slider.horizontal.3", action: onEdit)
            action("Eliminar", symbol: "trash", tint: .red, action: onDelete)
        }
        .disabled(count == 0)
        .opacity(count == 0 ? 0.5 : 1)
        .animation(WKAnimation.selection, value: count == 0)
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
            .frame(width: 92, height: WKLocktyTabBarMetrics.height)
            .contentShape(.capsule)
        }
        .buttonStyle(WKPlainGlassButtonStyle(shape: Capsule(style: .continuous)))
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
            Text(garments.count == 1 ? "Mover 1 prenda" : "Mover \(garments.count) prendas")
                .font(WK.Font.title)
                .foregroundStyle(WK.Palette.primaryText)

            WKWheelPicker(items: categories.map(\.slug), selection: $selection) { slug in
                Text(categories.first { $0.slug == slug }?.name ?? "")
                    .font(WK.Font.title)
            }
            .frame(height: 220)

            WKPrimaryButton("Mover aquí") { apply() }
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
            .navigationTitle(garments.count == 1 ? "Editar prenda" : "Editar \(garments.count) prendas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                        .tint(WK.Palette.primaryText)
                }
            }
            // La ficha completa, empujada: se corrige, se vuelve con el gesto
            // de siempre y se toca la siguiente. Sin cerrar la hoja entre una
            // y otra, que es lo que costaba tiempo.
            .navigationDestination(item: $editing) { garment in
                GarmentEditSheet(garment: garment, embedsNavigation: false)
            }
        }
    }
}

/// Una prenda en la lista de edición rápida: la foto, el nombre y lo que se
/// mira antes de decidir si hay que tocarla.
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
            .frame(width: 72, height: 84)

            VStack(alignment: .leading, spacing: 4) {
                Text(garment.name)
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.primaryText)
                    .lineLimit(1)
                Text(details)
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WK.Palette.tertiaryText)
        }
        .padding(WK.Spacing.m)
        .background(WK.Palette.shelf, in: .rect(cornerRadius: WK.Radius.card, style: .continuous))
        .contentShape(.rect)
    }

    private var details: String {
        [
            garment.category?.name,
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
            Label("Editar prendas", systemImage: "square.grid.2x2")
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
