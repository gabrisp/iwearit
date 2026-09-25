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
    @Environment(AppEnvironment.self) private var appEnvironment
    /// Si el historial de gastos está abierto.
    @State private var isShowingCredits = false

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
        .navigationTitle(String(localized: "profile.profilescreen.settings", defaultValue: "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        // **El saldo, arriba a la derecha.** Es lo que se viene a mirar, y
        // enterrado en una fila entre iCloud y los modelos no se encuentra.
        // Tocarlo cuenta en qué se ha ido. Ver `CreditsPill`.
        .toolbar {
            if appEnvironment.store.isReady {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowingCredits = true } label: {
                        CreditsPill(store: appEnvironment.store)
                    }
                    .buttonStyle(WKPressStyle())
                }
            }
        }
        // **Hoja y no una pantalla empujada.** Mirar en qué se fue el saldo es
        // un paréntesis: se abre, se mira y se cierra. Empujada, dejaba Ajustes
        // dos atrás y había que volver por donde se vino.
        .sheet(isPresented: $isShowingCredits) {
            NavigationStack {
                CreditsHistoryScreen(
                    store: appEnvironment.store,
                    isPro: appEnvironment.gate.isPro
                )
            }
        }
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
                Text(String(localized: "profile.profilescreen.sync", defaultValue: "Sync"))
                    .font(WK.Font.rowTitle)
            } trailing: {
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .onChange(of: isEnabled) { _, value in
                        AppConfiguration.syncsWithCloud = value
                    }
            }

            WKValueRow(String(localized: "profile.profilescreen.status", defaultValue: "Status"), value: description)

            if let last = appEnvironment.sync.lastSyncedAt {
                WKValueRow(
                    String(localized: "profile.profilescreen.lastTime", defaultValue: "Last time"),
                    value: Self.lastSync.string(from: last),
                    showsSeparator: false
                )
            }
        }
    }

    private var description: String {
        switch appEnvironment.sync.status {
        case .idle: String(localized: "profile.profilescreen.upToDate", defaultValue: "Up to date")
        case .syncing: "Sincronizando…"
        case .offline: String(localized: "profile.profilescreen.offline", defaultValue: "Offline")
        case let .unavailable(reason): reason.capitalized
        case let .failed(message): message
        }
    }

    /// Y el aviso que importa: apagarlo **no borra nada**.
    private var footer: String {
        isEnabled == appEnvironment.sync.isEnabled
            ? String(localized: "profile.profilescreen.yourClosetLivesOnThis", defaultValue: "Your closet lives on this iPhone. iCloud only copies it to your other devices.")
            : String(localized: "profile.profilescreen.itAppliesTheNextTime", defaultValue: "It applies the next time you open the app. Your data stays where it is.")
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
            WKSection(String(localized: "profile.profilescreen.devices", defaultValue: "Devices"), footer: footer) {
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
                            Button(String(localized: "common.remove", defaultValue: "Remove")) {
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
        if device === founder { text += String(localized: "profile.profilescreen.main", defaultValue: " · main") }
        if device.installationID == SyncDevice.currentInstallationID { text += String(localized: "profile.profilescreen.thisOne", defaultValue: " · this one") }
        return text
    }

    private var footer: String {
        String(localized: "profile.profilescreen.removingADeviceDeletesNothing", defaultValue: "Removing a device deletes nothing on it. If you open the app there again, it shows up again.")
    }
}

private struct SubscriptionSection: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        WKSection(String(localized: "profile.profilescreen.plan", defaultValue: "Plan")) {
            WKValueRow(String(localized: "profile.profilescreen.status", defaultValue: "Status"), value: appEnvironment.gate.isPro ? String(localized: "profile.profilescreen.pro", defaultValue: "Pro") : String(localized: "profile.profilescreen.free", defaultValue: "Free"))

            if !appEnvironment.gate.isPro {
                RemainingRow(feature: .garments, label: String(localized: "common.clothes", defaultValue: "Clothes"))
                RemainingRow(feature: .suitcases, label: String(localized: "common.suitcases", defaultValue: "Suitcases"))
                RemainingRow(feature: .customCategories, label: String(localized: "profile.profilescreen.customShelves", defaultValue: "Custom shelves"))
            }

            // El saldo ya no va aquí: vive en la píldora de la barra, que está
            // a la vista desde cualquier sitio de Ajustes. Ver `CreditsPill`.
            if appEnvironment.store.isReady {
                WKRow(showsSeparator: false) {
                    Task {
                        _ = await appEnvironment.store.restore()
                        await appEnvironment.gate.refresh()
                    }
                } leading: {
                    Text(String(localized: "profile.profilescreen.restorePurchases", defaultValue: "Restore purchases"))
                        .font(WK.Font.rowTitle)
                        .foregroundStyle(WK.Palette.primaryText)
                } trailing: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(WK.Palette.secondaryText)
                }
            }

            #if DEBUG
            if appEnvironment.gate.isDebugControllable {
                WKRow(showsSeparator: false) {
                    Text(String(localized: "profile.profilescreen.proDebugOnly", defaultValue: "Pro (debug only)"))
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
            WKValueRow(label, value: String(localized: "common.of", defaultValue: "\(String(describing: total - remaining)) of \(String(describing: total))"))
        }
    }
}

/// Sección propia con su `@Query`: el recuento invalida solo esta tarjeta.
private struct WardrobeStatsSection: View {
    @Query private var garments: [Garment]
    @Query(sort: \GarmentCategory.sortOrder) private var categories: [GarmentCategory]

    var body: some View {
        WKSection(String(localized: "profile.profilescreen.closet", defaultValue: "Closet")) {
            WKValueRow(String(localized: "common.clothes", defaultValue: "Clothes"), value: garments.count.formatted())
            WKValueRow(String(localized: "common.shelves", defaultValue: "Shelves"), value: categories.count.formatted(), showsSeparator: false)
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
        WKSection(String(localized: "profile.profilescreen.models", defaultValue: "Models"), footer: footer) {
            WKValueRow(String(localized: "profile.profilescreen.source", defaultValue: "Source"), value: appEnvironment.modelSource.rawValue)
            WKValueRow(String(localized: "profile.profilescreen.status", defaultValue: "Status"), value: appEnvironment.modelState.description)

            // Qué hay cargado **en memoria**, que no es lo mismo que qué hay
            // descargado: el fichero puede estar en disco y el modelo no haber
            // terminado de cargarse, y esa diferencia es justo la que explica
            // por qué el recorte no funciona todavía.
            WKValueRow(String(localized: "profile.profilescreen.segmenter", defaultValue: "Segmenter"), value: appEnvironment.segmenter == nil ? String(localized: "profile.profilescreen.notLoaded", defaultValue: "not loaded") : "cargado")
            WKValueRow(String(localized: "profile.profilescreen.embedder", defaultValue: "Embedder"), value: appEnvironment.embedder == nil ? String(localized: "profile.profilescreen.notLoaded", defaultValue: "not loaded") : "cargado")
            WKValueRow(String(localized: "profile.profilescreen.promptBank", defaultValue: "Prompt bank"), value: appEnvironment.promptBank == nil ? String(localized: "profile.profilescreen.notLoaded", defaultValue: "not loaded") : "cargado")

            // La segunda opinión. Se enseña porque es lo único del pipeline que
            // sale del dispositivo, y el usuario tiene derecho a saber si está
            // encendido sin leer el código.
            WKValueRow(
                String(localized: "profile.profilescreen.secondOpinion", defaultValue: "Second opinion"),
                value: appEnvironment.resolver == nil ? "desactivada" : String(localized: "profile.profilescreen.viaAppwrite", defaultValue: "via Appwrite"),
                showsSeparator: !installed.isEmpty
            )

            ForEach(Array(installed.enumerated()), id: \.element.id) { index, model in
                WKValueRow(
                    model.modelID,
                    value: String(localized: "profile.profilescreen.vPx", defaultValue: "v\(String(describing: model.version)) · \(String(describing: model.inputSize))px · \(String(describing: byteCount(model.sizeOnDisk)))"),
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
            String(localized: "profile.profilescreen.withoutAModelCroppingUses", defaultValue: "Without a model, cropping uses only the system APIs and is rougher.")
        case .loading:
            String(localized: "profile.profilescreen.whileItLoadsTheNeural", defaultValue: "While it loads, the Neural Engine is busy and system recognition doesn't respond.")
        case .ready where appEnvironment.resolver != nil:
            String(localized: "profile.profilescreen.theSecondOpinionIsOnly", defaultValue: "The second opinion is only consulted when the category is uncertain or there's a half-read brand, ")
                + String(localized: "profile.profilescreen.andOnlyThePieceS", defaultValue: "and only the piece's cutout travels: never the original photo.")
        default:
            installed.isEmpty ? String(localized: "profile.profilescreen.nothingDownloadedYet", defaultValue: "Nothing downloaded yet.") : nil
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
    /// La misma marca que lee la raíz: apagarla vuelve a enseñar el
    /// onboarding al momento. Ver `RootView`.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @State private var isConfirmingRestart = false
    /// Qué versión se va a repetir. Ver `OnboardingVariant`.
    @State private var replayVariant: OnboardingVariant = .v2

    var body: some View {
        let tips = appEnvironment.tips
        WKSection(
            String(localized: "profile.profilescreen.tutorial", defaultValue: "Tutorial"),
            footer: String(localized: "profile.profilescreen.tipsComeBackAsYou", defaultValue: "Tips come back as you enter each screen. Replaying the welcome deletes nothing: your closet, outfits and suitcases stay as they are.")
        ) {
            // **Solo la marca, nada más.** El onboarding no borra en ningún
            // paso, y el escaneo se salta lo que ya está en el armario o
            // pendiente —ver `ScanDeduper`—, así que repetirlo no duplica
            // prendas.
            // **Las dos versiones**, para compararlas. Ver `OnboardingVariant`.
            ForEach(OnboardingVariant.allCases, id: \.self) { variant in
                WKRow(action: {
                    replayVariant = variant
                    isConfirmingRestart = true
                }) {
                    Text(variant == .v1
                         ? String(localized: "profile.replay.v1", defaultValue: "Replay the welcome · v1")
                         : String(localized: "profile.replay.v2", defaultValue: "Replay the welcome · v2"))
                        .font(WK.Font.rowTitle)
                        .foregroundStyle(WK.Palette.accent)
                    Spacer()
                }
            }
            // WKRow(action: { isConfirmingRestart = true }) {
            //     Text(String(localized: "profile.profilescreen.replayTheWelcome2", defaultValue: "Replay the welcome"))
            //         .font(WK.Font.rowTitle)
            //         .foregroundStyle(WK.Palette.accent)
            //     Spacer()
            // }

            WKRow {
                Text(String(localized: "profile.profilescreen.tipsSeen", defaultValue: "Tips seen"))
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.primaryText)
                Spacer()
                Text(String(localized: "common.of", defaultValue: "\(String(describing: tips.seenCount)) of \(String(describing: WKTip.allCases.count))"))
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.secondaryText)
            }

            WKRow(action: { tips.resetAll() }) {
                Text(String(localized: "profile.profilescreen.showThemAgain", defaultValue: "Show them again"))
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.accent)
                Spacer()
            }
            .disabled(tips.seenCount == 0)
            .opacity(tips.seenCount == 0 ? 0.4 : 1)
        }
        .alert(String(localized: "profile.profilescreen.replayTheWelcome", defaultValue: "Replay the welcome?"), isPresented: $isConfirmingRestart) {
            Button(String(localized: "profile.profilescreen.redo", defaultValue: "Redo")) {
                UserDefaults.standard.set(replayVariant.rawValue, forKey: OnboardingVariant.storageKey)
                hasCompletedOnboarding = false
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "profile.profilescreen.youGoBackToThe", defaultValue: "You go back to the start of onboarding. Nothing in your closet is deleted."))
        }
    }
}

private struct DiagnosticsSection: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    private var log: DiagnosticsLog { .shared }
    @State private var isExpanded = false
    @State private var isWorking = false

    var body: some View {
        WKSection(String(localized: "profile.profilescreen.diagnostics", defaultValue: "Diagnostics"), footer: String(localized: "profile.profilescreen.linesLogged", defaultValue: "\(String(describing: log.lines.count)) lines logged.")) {
            WKRow(action: { isExpanded.toggle() }) {
                Text(isExpanded ? String(localized: "profile.profilescreen.hideLog", defaultValue: "Hide log") : String(localized: "profile.profilescreen.viewLog", defaultValue: "View log"))
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.accent)
            }

            if isExpanded {
                WKRow {
                    DiagnosticsLogView(lines: Array(log.lines.suffix(120)))
                }
            }

            WKRow(action: { UIPasteboard.general.string = log.transcript }) {
                Text(String(localized: "profile.profilescreen.copyLog", defaultValue: "Copy log"))
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(WK.Palette.accent)
            }

            WKRow(action: { log.clear() }) {
                Text(String(localized: "profile.profilescreen.clearLog", defaultValue: "Clear log"))
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
                Text(isWorking ? "Descargando…" : String(localized: "profile.profilescreen.forceModelReDownload", defaultValue: "Force model re-download"))
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
        WKSection(String(localized: "profile.profilescreen.debug", defaultValue: "Debug"), footer: lastResult) {
            NavigationLink {
                AdaptiveGallery()
                    .navigationTitle(String(localized: "profile.profilescreen.adaptive", defaultValue: "Adaptive"))
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack {
                    Text(String(localized: "profile.profilescreen.adaptiveModifiers", defaultValue: "Adaptive modifiers")).font(WK.Font.rowTitle)
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
                Text(String(localized: "profile.profilescreen.seed30Pieces", defaultValue: "Seed 30 pieces")).font(WK.Font.rowTitle)
            }
            WKRow(action: { seed(count: 300) }) {
                Text(String(localized: "profile.profilescreen.seed300Pieces", defaultValue: "Seed 300 pieces")).font(WK.Font.rowTitle)
            }
            WKRow(action: { seed(count: 12, asPending: true) }) {
                Text(String(localized: "profile.profilescreen.seed12Pending", defaultValue: "Seed 12 pending")).font(WK.Font.rowTitle)
            }
            WKRow(showsSeparator: false, action: { isConfirmingErase = true }) {
                Text(String(localized: "profile.profilescreen.factoryReset", defaultValue: "Factory reset"))
                    .font(WK.Font.rowTitle)
                    .foregroundStyle(.red)
            }
        }
        .disabled(isSeeding)
        .alert(String(localized: "profile.profilescreen.deleteEverything2", defaultValue: "Delete everything?"), isPresented: $isConfirmingErase) {
            Button(String(localized: "profile.profilescreen.deleteEverything", defaultValue: "Delete everything"), role: .destructive) { eraseEverything() }
            Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "profile.profilescreen.yourClosetOutfitsSuitcasesPhotos", defaultValue: "Your closet, outfits, suitcases, photos and everything synced to iCloud are deleted, also on your other devices. The app will close and start from scratch. This can't be undone."))
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
                lastResult = String(localized: "profile.profilescreen.deletedRecords", defaultValue: "Deleted: \(String(describing: removed)) records")
                // **Y se cierra la app.** Con todo borrado, lo que hay en
                // memoria —consultas, cachés de imágenes, la pantalla en la
                // que estás— sigue siendo lo de antes. Salir y volver a abrir
                // es la única forma de empezar de cero de verdad: onboarding
                // incluido, porque sus ajustes también se han ido.
                //
                // Solo existe en depuración: una app publicada no puede
                // cerrarse sola.
                try? await Task.sleep(for: .milliseconds(400))
                exit(0)
            } catch {
                lastResult = String(localized: "profile.profilescreen.failed", defaultValue: "Failed: \(String(describing: error))")
            }
            isSeeding = false
        }
    }

    private func seed(count: Int, asPending: Bool = false) {
        isSeeding = true
        Task {
            let start = ContinuousClock.now
            do {
                let created = try await DevSeed.populate(
                    wardrobe: appEnvironment.wardrobe,
                    imageStore: appEnvironment.imageStore,
                    count: count,
                    asPending: asPending
                )
                lastResult = String(localized: "profile.profilescreen.piecesIn", defaultValue: "\(String(describing: created)) pieces in \(String(describing: start.duration(to: .now).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2)))))")
            } catch {
                lastResult = String(localized: "profile.profilescreen.failed", defaultValue: "Failed: \(String(describing: error))")
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
