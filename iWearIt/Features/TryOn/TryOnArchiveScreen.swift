import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// **El archivo de probados**: todo lo que te has probado, de todos los
/// conjuntos, lo último primero.
///
/// Cada prueba ya se guardaba dentro de su outfit, pero para volver a verla
/// había que acordarse de qué outfit era y abrir su probador. Aquí están
/// todas juntas: se miran, se comparten y se borran.
struct TryOnArchiveScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(sort: \TryOnResult.createdAt, order: .reverse)
    private var results: [TryOnResult]

    @Query(sort: \BodyProfile.createdAt)
    private var profiles: [BodyProfile]

    /// Una sola hoja: la prueba abierta o el perfil que se edita.
    @State private var sheet: Sheet?

    private enum Sheet: Identifiable {
        case result(TryOnResult)
        /// `nil` = uno nuevo.
        case profile(BodyProfile?)

        var id: String {
            switch self {
            case let .result(result): "result-\(result.id)"
            case let .profile(profile): "profile-\(profile?.id.uuidString ?? "new")"
            }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: WK.Spacing.m)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WK.Spacing.xl) {
                profilesSection
                historySection
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.vertical, WK.Spacing.m)
        }
        .background(WK.Palette.canvas.ignoresSafeArea())
        // "Probador virtual" y no "Probados": aquí están quiénes se prueban
        // la ropa **y** lo que se han probado.
        .navigationTitle("Probador virtual")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { which in
            switch which {
            case let .result(result):
                TryOnViewer(result: result, store: appEnvironment.imageStore) {
                    sheet = nil
                    remove(result)
                }
            case let .profile(profile):
                // Editar uno que ya existe: la hoja con todo a la vista. Crear
                // uno nuevo: el flujo de pasos.
                if let profile {
                    ProfileEditSheet(profile: profile)
                } else {
                    TryOnProfileSheet(profile: nil)
                }
            }
        }
        .animation(WKAnimation.content, value: results.count)
        .animation(WKAnimation.content, value: profiles.count)
    }

    // MARK: Perfiles

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.m) {
            SectionTitle(title: "Perfiles", detail: "Quién se prueba la ropa. Toca uno para editarlo.")
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: WK.Spacing.m) {
                    ForEach(profiles) { profile in
                        Button { sheet = .profile(profile) } label: {
                            ProfileCard(profile: profile, store: appEnvironment.imageStore)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { sheet = .profile(profile) } label: {
                                Label("Editar", systemImage: "pencil")
                            }
                            Button(role: .destructive) { remove(profile) } label: {
                                Label("Borrar perfil", systemImage: "trash")
                            }
                        }
                    }
                    if profiles.count < BodyProfile.maximumProfiles {
                        Button { sheet = .profile(nil) } label: { NewProfileCard() }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, WK.Spacing.xs)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    // MARK: Historial

    @ViewBuilder
    private var historySection: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.m) {
            SectionTitle(title: "Historial", detail: "Lo que te has probado, lo último primero.")
            if results.isEmpty {
                Text("Abre un outfit y toca el probador: lo que te pruebes se queda aquí.")
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(WK.Spacing.m)
                    .background(WK.Palette.shelf, in: .rect(cornerRadius: WK.Radius.medium, style: .continuous))
            } else {
                LazyVGrid(columns: columns, spacing: WK.Spacing.m) {
                    ForEach(results) { result in
                        Button { sheet = .result(result) } label: {
                            TryOnTile(result: result, store: appEnvironment.imageStore)
                        }
                        .buttonStyle(WKPressStyle())
                        .contextMenu {
                            Button(role: .destructive) { remove(result) } label: {
                                Label("Borrar", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    /// Borra la prueba y su imagen.
    private func remove(_ result: TryOnResult) {
        let key = result.imageKey
        modelContext.delete(result)
        try? modelContext.save()
        Task { try? await appEnvironment.imageStore.delete(key: key) }
    }

    /// Borrar un perfil **es revocar el permiso**: se van la foto y la fecha
    /// con él. Lo que se probó con él se queda.
    private func remove(_ profile: BodyProfile) {
        let key = profile.imageKey
        modelContext.delete(profile)
        try? modelContext.save()
        if !key.isEmpty { Task { try? await appEnvironment.imageStore.delete(key: key) } }
        DiagnosticsLog.record("PROBADOR", "perfil borrado desde el probador virtual")
    }
}

private struct SectionTitle: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(WK.Font.shelfTitle)
                .foregroundStyle(WK.Palette.primaryText)
            Text(detail)
                .font(WK.Font.caption)
                .foregroundStyle(WK.Palette.secondaryText)
        }
    }
}

/// Un perfil: su foto en grande, el nombre y cómo se describe.
private struct ProfileCard: View {
    let profile: BodyProfile
    let store: ImageStore

    var body: some View {
        VStack(spacing: WK.Spacing.s) {
            Group {
                if profile.hasPhoto {
                    StoredImage(key: profile.imageKey, variant: .thumb, store: store)
                        .scaledToFill()
                } else {
                    ToneIcon("person.fill", tone: .at(abs(profile.id.hashValue)), size: 84)
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(.circle)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WK.Palette.primaryText)
                    .frame(width: 28, height: 28)
                    .adaptiveGlass(in: .circle)
            }

            VStack(spacing: 2) {
                Text(profile.label.isEmpty ? "Sin nombre" : profile.label)
                    .font(WK.Font.captionMedium)
                    .foregroundStyle(WK.Palette.primaryText)
                    .lineLimit(1)
                Text(profile.described)
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 120)
        }
        .padding(WK.Spacing.m)
        // Cristal **interactivo**: la tarjeta es un botón.
        .adaptiveGlassInteractive(in: .rect(cornerRadius: WK.Radius.large, style: .continuous))
    }
}

private struct NewProfileCard: View {
    var body: some View {
        VStack(spacing: WK.Spacing.s) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(WK.Palette.primaryText)
                .frame(width: 84, height: 84)
                .adaptiveGlassInteractive(in: .circle)
            Text("Nuevo perfil")
                .font(WK.Font.captionMedium)
                .foregroundStyle(WK.Palette.secondaryText)
                .frame(width: 120)
        }
        .padding(WK.Spacing.m)
    }
}

/// Una prueba en la rejilla: **dos tarjetas superpuestas** —el outfit detrás,
/// inclinado a la izquierda, y la foto delante, a la derecha— y la fecha.
///
/// Juntas dicen lo que es: esta ropa, puesta. Una sola foto no decía de qué
/// outfit era.
private struct TryOnTile: View {
    let result: TryOnResult
    let store: ImageStore

    var body: some View {
        VStack(spacing: WK.Spacing.s) {
            ZStack {
                if let outfit = result.outfit {
                    LookCanvasView(
                        garments: outfit.garments,
                        store: store,
                        backdrop: PlanFeedScreen.backdrop(of: outfit),
                        outfit: outfit,
                        showsBorder: true
                    )
                    .frame(width: 104)
                    .rotationEffect(.degrees(-7))
                    .offset(x: -26, y: 6)
                    .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
                    .allowsHitTesting(false)
                }
                Color.clear
                    .frame(width: 108)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        StoredImage(key: result.imageKey, variant: .thumb, store: store)
                            .scaledToFill()
                    }
                    .background(WK.Palette.shelf)
                    .clipShape(.rect(cornerRadius: WK.Radius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
                            .stroke(WK.Palette.ink(0.10), lineWidth: 1)
                    }
                    .rotationEffect(.degrees(5))
                    .offset(x: result.outfit == nil ? 0 : 22)
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 170)

            Text(result.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(WK.Font.captionMedium)
                .foregroundStyle(WK.Palette.secondaryText)
        }
        .padding(.vertical, WK.Spacing.s)
    }
}

/// Una prueba en grande: **la foto y el outfit**, de lado a lado, para
/// compartirla o borrarla. El outfit se ve tal cual y no se edita: es el que
/// se probó.
private struct TryOnViewer: View {
    let result: TryOnResult
    let store: ImageStore
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isConfirmingDelete = false
    @State private var page: Int? = 0

    private var pageCount: Int { result.outfit == nil ? 1 : 2 }

    var body: some View {
        NavigationStack {
            VStack(spacing: WK.Spacing.m) {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        StoredImage(key: result.imageKey, variant: .display, store: store)
                            .aspectRatio(contentMode: .fit)
                            // Sin fondo: sobre el papel del outfit, como en el
                            // probador. Ver `TryOnPaper`.
                            .background {
                                if result.sceneRaw == TryOnScene.none.rawValue {
                                    TryOnPaper(outfit: result.outfit)
                                }
                            }
                            .overlay(alignment: .bottomTrailing) { SnazzyWatermark() }
                            .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
                            .padding(.horizontal, WK.Spacing.screenInset)
                            .containerRelativeFrame(.horizontal)
                            .id(0)
                        if let outfit = result.outfit {
                            // Solo para ver: sin toques ni doble toque.
                            LookCanvasView(
                                garments: outfit.garments,
                                store: store,
                                backdrop: PlanFeedScreen.backdrop(of: outfit),
                                outfit: outfit,
                                showsBorder: true
                            )
                            .allowsHitTesting(false)
                            .padding(.horizontal, WK.Spacing.screenInset)
                            .containerRelativeFrame(.horizontal)
                            .id(1)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                .scrollIndicators(.hidden)

                if pageCount > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            Capsule()
                                .fill(index == (page ?? 0) ? WK.Palette.primaryText : WK.Palette.ink(0.18))
                                .frame(width: index == (page ?? 0) ? 18 : 6, height: 6)
                        }
                    }
                    .animation(WKAnimation.selection, value: page)
                }
            }
            .padding(.vertical, WK.Spacing.m)
            .frame(maxHeight: .infinity)
            .background(WK.Palette.canvas.ignoresSafeArea())
            .navigationTitle(result.createdAt.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { isConfirmingDelete = true } label: { Image(systemName: "trash") }
                        .tint(.red)
                }
                if let image {
                    ToolbarItem(placement: .topBarTrailing) {
                        let shared = SnazzyExport.tryOn(
                            image,
                            paper: result.sceneRaw == TryOnScene.none.rawValue
                                ? result.outfit.map { UIColor(PlanFeedScreen.backdrop(of: $0)) } ?? UIColor(WK.Palette.canvas)
                                : nil
                        )
                        ShareLink(item: Image(uiImage: shared), preview: .init("Probado", image: Image(uiImage: shared))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .tint(WK.Palette.primaryText)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(WK.Palette.primaryText)
                }
            }
            .alert("¿Borrar esta prueba?", isPresented: $isConfirmingDelete) {
                Button("Borrar", role: .destructive, action: onDelete)
                Button("Cancelar", role: .cancel) {}
            }
        }
        .task {
            if let cgImage = try? await store.image(for: result.imageKey, variant: .display) {
                image = UIImage(cgImage: cgImage)
            }
        }
    }
}
