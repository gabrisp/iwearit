import SwiftData
import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Perfil: plan, armario, modelos y depuración.
///
/// Listas propias y no `List`: el sistema trae su fondo, sus separadores y sus
/// márgenes, y pelearse con ellos acaba en una pila de `listRow*` que se
/// comporta distinto en cada versión de iOS.
struct ProfileScreen: View {
    var body: some View {
        // **Sin `NavigationStack` propia.** Ajustes es ahora una pantalla que
        // se empuja sobre la del armario; creando aquí otra pila, la pantalla
        // quedaba dentro de una navegación que nadie estaba usando —con su
        // barra escondida encima de la de verdad— y el contenido no llegaba a
        // dibujarse. La barra la pone quien empuja.
        ScrollView {
            VStack(spacing: WK.Spacing.l) {
                SubscriptionSection()
                SyncSection()
                DevicesSection()
                WardrobeStatsSection()
                ModelSection()
                TipsSection()
                DiagnosticsSection()
                #if DEBUG
                DebugSection()
                #endif
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WK.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background(WK.Palette.canvas.ignoresSafeArea())
        .adaptiveScrollEdge(.top)
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Qué pasa con iCloud.
///
/// Lo justo y **sin inventar progreso**: CloudKit no dice cuánto queda de una
/// importación, así que un "63% sincronizado" sería una animación mintiendo.
/// Lo que sí se puede decir con verdad es si está trabajando, si no hay sesión,
/// si no hay red y cuándo fue la última vez que terminó algo.
private struct SyncSection: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var isEnabled = AppConfiguration.syncsWithCloud

    private static let lastSync: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        WKSection("iCloud", footer: footer) {
            WKRow {
                Text("Sincronizar")
                    .font(WK.Font.rowTitle)
            } trailing: {
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .onChange(of: isEnabled) { _, value in
                        AppConfiguration.syncsWithCloud = value
                    }
            }

            WKValueRow("Estado", value: description)

            if let last = appEnvironment.sync.lastSyncedAt {
                WKValueRow(
                    "Última vez",
                    value: Self.lastSync.string(from: last),
                    showsSeparator: false
                )
            }
        }
    }

    private var description: String {
        switch appEnvironment.sync.status {
        case .idle: "Al día"
        case .syncing: "Sincronizando…"
        case .offline: "Sin conexión"
        case let .unavailable(reason): reason.capitalized
        case let .failed(message): message
        }
    }

    /// Y el aviso que importa: apagarlo **no borra nada**.
    private var footer: String {
        isEnabled == appEnvironment.sync.isEnabled
            ? "Tu armario está en este iPhone. iCloud solo lo copia a tus otros dispositivos."
            : "Se aplica al abrir la app otra vez. Tus datos se quedan donde están."
    }
}

/// Los dispositivos que comparten este armario.
///
/// ## Qué se puede hacer aquí y qué no
///
/// Se puede **quitar** uno de la lista, y quitarlo no borra ni un dato suyo:
/// deja de contarse, nada más. Si vuelves a abrir la app en él, vuelve solo.
///
/// Lo que no se puede es quitar el primero. No por capricho: es el que creó el
/// armario, y dejar la lista sin ninguno es el camino corto a que una limpieza
/// futura crea que no hay nadie a quien esperar.
private struct DevicesSection: View {
    @Query(sort: [SortDescriptor(\SyncDevice.firstSeenAt)])
    private var devices: [SyncDevice]

    @Environment(\.modelContext) private var modelContext

    private var active: [SyncDevice] { devices.filter(\.isActive) }
    /// El primero que se registró. Computado y no guardado: así no puede
    /// quedarse apuntando a una fila que ya no está.
    private var founder: SyncDevice? { active.first }

    private static let seen: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        if !active.isEmpty {
            WKSection("Dispositivos", footer: footer) {
                ForEach(Array(active.enumerated()), id: \.element.installationID) { index, device in
                    WKRow(showsSeparator: index < active.count - 1) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(label(for: device))
                                .font(WK.Font.rowTitle)
                                .foregroundStyle(WK.Palette.primaryText)
                            Text(Self.seen.localizedString(for: device.lastSeenAt, relativeTo: Date()))
                                .font(WK.Font.caption)
                                .foregroundStyle(WK.Palette.tertiaryText)
                        }
                    } trailing: {
                        if device !== founder {
                            Button("Quitar") {
                                withAnimation(WKAnimation.content) { device.removedAt = Date() }
                            }
                            .font(WK.Font.caption)
                            .foregroundStyle(.red)
                            .buttonStyle(WKPressStyle())
                        }
                    }
                }
            }
        }
    }

    private func label(for device: SyncDevice) -> String {
        var text = device.name
        if device === founder { text += " · principal" }
        if device.installationID == SyncDevice.currentInstallationID { text += " · este" }
        return text
    }

    private var footer: String {
        "Quitar un dispositivo no borra nada suyo. Si vuelves a abrir la app en él, aparece otra vez."
    }
}

private struct SubscriptionSection: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        WKSection("Plan") {
            WKValueRow("Estado", value: appEnvironment.gate.isPro ? "Pro" : "Gratis")

            if !appEnvironment.gate.isPro {
                RemainingRow(feature: .garments, label: "Prendas")
                RemainingRow(feature: .suitcases, label: "Maletas")
                RemainingRow(feature: .customCategories, label: "Baldas propias")
            }

            #if DEBUG
            if appEnvironment.gate.isDebugControllable {
                WKRow(showsSeparator: false) {
                    Text("Pro (solo depuración)")
                        .font(WK.Font.rowTitle)
                } trailing: {
                    Toggle("", isOn: Binding(
                        get: { appEnvironment.gate.isPro },
                        set: { value in Task { await appEnvironment.gate.setDebugPro(value) } }
                    ))
                    .labelsHidden()
                }
            }
            #endif
        }
    }
}

/// Cuánto queda de un tope. Vista propia: cada fila consulta su propio
/// recuento, así que cambiar una no reevalúa las otras.
private struct RemainingRow: View {
    let feature: Feature
    let label: String
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        if case let .limited(remaining, total) = appEnvironment.gate.access(feature) {
            WKValueRow(label, value: "\(total - remaining) de \(total)")
        }
    }
}

/// Sección propia con su `@Query`: el recuento invalida solo esta tarjeta.
private struct WardrobeStatsSection: View {
    @Query private var garments: [Garment]
    @Query(sort: \GarmentCategory.sortOrder) private var categories: [GarmentCategory]

    var body: some View {
        WKSection("Armario") {
            WKValueRow("Prendas", value: garments.count.formatted())
            WKValueRow("Baldas", value: categories.count.formatted(), showsSeparator: false)
        }
    }
}

private struct ModelSection: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    /// Lo que hay en disco. Se pide al aparecer y después de cada descarga: es
    /// una lectura del sistema de ficheros, no algo que se pueda observar.
    @State private var installed: [AppEnvironment.InstalledModelInfo] = []
    @State private var isWorking = false

    var body: some View {
        WKSection("Modelos", footer: footer) {
            WKValueRow("Origen", value: appEnvironment.modelSource.rawValue)
            WKValueRow("Estado", value: appEnvironment.modelState.description)

            // Qué hay cargado **en memoria**, que no es lo mismo que qué hay
            // descargado: el fichero puede estar en disco y el modelo no haber
            // terminado de cargarse, y esa diferencia es justo la que explica
            // por qué el recorte no funciona todavía.
            WKValueRow("Segmentador", value: appEnvironment.segmenter == nil ? "no cargado" : "cargado")
            WKValueRow("Embedder", value: appEnvironment.embedder == nil ? "no cargado" : "cargado")
            WKValueRow("Banco de prompts", value: appEnvironment.promptBank == nil ? "no cargado" : "cargado")

            // La segunda opinión. Se enseña porque es lo único del pipeline que
            // sale del dispositivo, y el usuario tiene derecho a saber si está
            // encendido sin leer el código.
            WKValueRow(
                "Segunda opinión",
                value: appEnvironment.resolver == nil ? "desactivada" : "vía Appwrite",
                showsSeparator: !installed.isEmpty
            )

            ForEach(Array(installed.enumerated()), id: \.element.id) { index, model in
                WKValueRow(
                    model.modelID,
                    value: "v\(model.version) · \(model.inputSize)px · \(byteCount(model.sizeOnDisk))",
                    showsSeparator: index < installed.count - 1
                )
            }
        }
        .task { await refresh() }
        .onChange(of: appEnvironment.modelState) { _, _ in Task { await refresh() } }
    }

    private func refresh() async {
        installed = await appEnvironment.installedModels()
    }

    private var footer: String? {
        switch appEnvironment.modelState {
        case .unavailable:
            "Sin modelo, el recorte usa solo las APIs del sistema y es más tosco."
        case .loading:
            "Mientras carga, el Neural Engine está ocupado y el reconocimiento del sistema no responde."
        case .ready where appEnvironment.resolver != nil:
            "La segunda opinión solo se consulta cuando la categoría es dudosa o hay una marca a medio leer, "
                + "y solo viaja el recorte de la prenda: nunca la foto original."
        default:
            installed.isEmpty ? "Nada descargado todavía." : nil
        }
    }

    private func byteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// El registro de lo que va pasando, dentro de la app.
///
/// Está fuera de `#if DEBUG` a propósito: el fallo que hay que mirar aparece en
/// la build que usa el usuario, con su galería y su iPhone, no en la mía.
/// Los avisos de la app: cuántos se han visto y volver a verlos.
///
/// **Un interruptor y no veinte.** Todo lo visto vive en una sola entrada de
/// ajustes —ver `WKTipCenter`—, así que "empezar de cero" es una fila y no una
/// lista de casillas que hay que acordarse de mantener cuando se añade un
/// aviso nuevo.
private struct TipsSection: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        let tips = appEnvironment.tips
        WKSection(
            "Tutorial",
            footer: "Los avisos vuelven a salir según entres en cada pantalla."
        ) {
            WKRow {
                Text("Avisos vistos")
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.primaryText)
                Spacer()
                Text("\(tips.seenCount) de \(WKTip.allCases.count)")
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.secondaryText)
            }

            WKRow(action: { tips.resetAll() }) {
                Text("Volver a enseñarlos")
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.accent)
                Spacer()
            }
            .disabled(tips.seenCount == 0)
            .opacity(tips.seenCount == 0 ? 0.4 : 1)
        }
    }
}

private struct DiagnosticsSection: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    private var log: DiagnosticsLog { .shared }
    @State private var isExpanded = false
    @State private var isWorking = false

    var body: some View {
        WKSection("Diagnóstico", footer: "\(log.lines.count) líneas registradas.") {
            WKRow(action: { isExpanded.toggle() }) {
                Text(isExpanded ? "Ocultar registro" : "Ver registro")
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.accent)
            }

            if isExpanded {
                WKRow {
                    DiagnosticsLogView(lines: Array(log.lines.suffix(120)))
                }
            }

            WKRow(action: { UIPasteboard.general.string = log.transcript }) {
                Text("Copiar registro")
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.accent)
            }

            WKRow(action: { log.clear() }) {
                Text("Vaciar registro")
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.secondaryText)
            }

            WKRow(showsSeparator: false, action: {
                guard !isWorking else { return }
                isWorking = true
                Task {
                    await appEnvironment.redownloadModels()
                    isWorking = false
                }
            }) {
                Text(isWorking ? "Descargando…" : "Forzar redescarga de modelos")
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(isWorking ? WK.Palette.secondaryText : .red)
            }
        }
    }
}

#if DEBUG
private struct DebugSection: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var isSeeding = false
    @State private var isConfirmingErase = false
    @State private var lastResult: String?

    var body: some View {
        WKSection("Depuración", footer: lastResult) {
            NavigationLink {
                AdaptiveGallery()
                    .navigationTitle("Adaptativos")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack {
                    Text("Modificadores adaptativos").font(WK.Font.rowTitle)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(WK.Palette.tertiaryText)
                }
                .padding(.horizontal, WK.Spacing.cardInset)
                .padding(.vertical, WK.Spacing.m - 2)
                .contentShape(.rect)
            }
            .buttonStyle(WKRowButtonStyle())

            Rectangle()
                .fill(WK.Palette.ink(0.07))
                .frame(height: 1)
                .padding(.leading, WK.Spacing.cardInset)

            WKRow(action: { seed(count: 30) }) {
                Text("Sembrar 30 prendas").font(WK.Font.rowTitle)
            }
            WKRow(action: { seed(count: 300) }) {
                Text("Sembrar 300 prendas").font(WK.Font.rowTitle)
            }
            WKRow(showsSeparator: false, action: { isConfirmingErase = true }) {
                Text("Restablecer de fábrica")
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(.red)
            }
        }
        .disabled(isSeeding)
        .alert("¿Borrar todo?", isPresented: $isConfirmingErase) {
            Button("Borrar todo", role: .destructive) { eraseEverything() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borran el armario, los outfits, las maletas, las fotos y lo sincronizado en iCloud, también en tus otros dispositivos. No se puede deshacer.")
        }
    }

    /// Deja la app como recién instalada: datos, imágenes, iCloud y ajustes.
    private func eraseEverything() {
        isSeeding = true
        Task {
            do {
                let removed = try await appEnvironment.wardrobe.eraseEverything()
                // Las imágenes, todas y sin margen: no queda nada que las use.
                try? await appEnvironment.imageStore.garbageCollect(keeping: [], grace: 0)
                // Y los ajustes: avisos vistos, preferencias, todo.
                if let domain = Bundle.main.bundleIdentifier {
                    UserDefaults.standard.removePersistentDomain(forName: domain)
                }
                appEnvironment.tips.resetAll()
                lastResult = "Borrado: \(removed) registros"
            } catch {
                lastResult = "Falló: \(error)"
            }
            isSeeding = false
        }
    }

    private func seed(count: Int) {
        isSeeding = true
        Task {
            let start = ContinuousClock.now
            do {
                let created = try await DevSeed.populate(
                    wardrobe: appEnvironment.wardrobe,
                    imageStore: appEnvironment.imageStore,
                    count: count
                )
                lastResult = "\(created) prendas en \(start.duration(to: .now).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2))))"
            } catch {
                lastResult = "Falló: \(error)"
            }
            isSeeding = false
        }
    }
}
#endif

#Preview {
    ProfileScreen()
        .environment(AppEnvironment.live())
        .modelContainer(try! WardrobeStore.makeContainer(inMemory: true))
}
