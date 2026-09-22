import Foundation
import SwiftUI
import WKDesign
import WKPersistence

import SwiftData

/// Las tiendas del navegador, **en la base y sincronizadas**.
///
/// Estaban en `UserDefaults`: se quedaban en un aparato y se perdían al
/// reinstalar. Ahora son `WebShortcut`, que viaja con el armario a iCloud.
///
/// Lo que se guarda es **el enlace entero**, con su ruta y sus parámetros: el
/// atajo que sirve es la página en la que estabas, no su dominio. El dominio
/// solo se escribe en la píldora.
@MainActor
struct WebSiteStore {
    let context: ModelContext

    /// Cuántas recientes se recuerdan, además de las fijadas.
    static let recentLimit = 3
    /// Y cuántas píldoras caben en la fila.
    static let shownLimit = 4

    /// Lo que se enseña: primero lo fijado y detrás lo reciente.
    func shown(from all: [WebShortcut]) -> [WebShortcut] {
        let pinned = all.filter(\.isPinned)
        let recents = all.filter { !$0.isPinned }.prefix(Self.recentLimit)
        return Array((pinned + recents).prefix(Self.shownLimit))
    }

    /// Se ha navegado: esa página pasa a ser la más reciente de su dominio.
    ///
    /// **A una fijada no se le toca el enlace.** Si fijaste la sección de
    /// hombre, pasar por la portada no debe cambiarte el atajo; lo que sí se
    /// actualiza es la fecha y, si faltaba, el icono.
    func visited(_ url: URL) async {
        guard let host = Self.host(of: url) else { return }
        let all = (try? context.fetch(FetchDescriptor<WebShortcut>.webShortcuts())) ?? []

        if let existing = all.first(where: { $0.host == host }) {
            existing.lastVisitedAt = Date()
            if !existing.isPinned { existing.urlString = url.absoluteString }
            if existing.iconData == nil { existing.iconData = await Self.favicon(for: host) }
        } else {
            let icon = await Self.favicon(for: host)
            context.insert(WebShortcut(urlString: url.absoluteString, host: host, iconData: icon))
        }

        // Las recientes de más se caen; las fijadas se quedan siempre.
        let recents = ((try? context.fetch(FetchDescriptor<WebShortcut>.webShortcuts())) ?? [])
            .filter { !$0.isPinned }
        for extra in recents.dropFirst(Self.recentLimit) { context.delete(extra) }
        try? context.save()
    }

    func pin(_ shortcut: WebShortcut) {
        shortcut.isPinned = true
        try? context.save()
    }

    /// Deja de estar fijada. **Se queda** mientras siga entre las recientes, y
    /// se va si ya no lo estaba: lo fijado es lo que guardas tú y lo reciente
    /// es por dónde has pasado.
    func unpin(_ shortcut: WebShortcut, all: [WebShortcut]) {
        shortcut.isPinned = false
        let recents = all.filter { !$0.isPinned && $0.persistentModelID != shortcut.persistentModelID }
        if recents.count >= Self.recentLimit { context.delete(shortcut) }
        try? context.save()
    }

    /// "www.zara.com/es/…" → "zara.com". El "www" no distingue nada y ocupa.
    static func host(of url: URL) -> String? {
        guard var host = url.host() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }

    /// El favicon del propio sitio.
    ///
    /// Al dominio que se está visitando y a nadie más: pedírselo a un servicio
    /// de iconos contaría a un tercero por qué tiendas pasas.
    static func favicon(for host: String) async -> Data? {
        guard let url = URL(string: "https://\(host)/favicon.ico") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            !data.isEmpty,
            data.count < 200_000,
            UIImage(data: data) != nil
        else { return nil }
        return data
    }
}

/// La fila de webs, en píldoras de cristal.
///
/// **Todas llevan su chincheta**, no solo la que se está viendo: la tienda que
/// quieres guardar es casi siempre la de la que acabas de volver.
struct WebSiteBar: View {
    /// Dónde se está. Solo para marcar cuál es. `nil` = no hay página.
    let current: URL?
    let onOpen: (WebShortcut) -> Void

    @Query(FetchDescriptor<WebShortcut>.webShortcuts())
    private var shortcuts: [WebShortcut]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let store = WebSiteStore(context: modelContext)
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.xs) {
                ForEach(store.shown(from: shortcuts)) { shortcut in
                    WebSitePill(
                        shortcut: shortcut,
                        isCurrent: shortcut.host == currentHost
                    ) {
                        onOpen(shortcut)
                    } onPinToggle: {
                        withAnimation(WKAnimation.selection) {
                            if shortcut.isPinned {
                                store.unpin(shortcut, all: shortcuts)
                            } else {
                                store.pin(shortcut)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .animation(WKAnimation.selection, value: shortcuts.count)
    }

    /// El dominio en el que se está: se marca un poco más.
    private var currentHost: String? {
        current.flatMap(WebSiteStore.host(of:))
    }
}

/// Una web: su favicon y su dominio.
private struct WebSitePill: View {
    @Bindable var shortcut: WebShortcut
    /// La página en la que se está: se marca un poco más.
    let isCurrent: Bool
    let onOpen: () -> Void
    let onPinToggle: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onOpen) {
                HStack(spacing: 6) {
                    icon
                    Text(shortcut.host)
                        .font(WK.Font.caption)
                        .foregroundStyle(WK.Palette.primaryText)
                        .lineLimit(1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(WKPressStyle())

            // **El "+" dentro de la píldora**, no suelto al final de la fila:
            // así se ve **cuál** se está fijando. Al tocarlo se convierte en la
            // chincheta, que es la misma información dicha después. En todas,
            // no solo en la actual.
            Button(action: onPinToggle) {
                    Image(systemName: shortcut.isPinned ? "pin.fill" : "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(shortcut.isPinned ? WK.Palette.primaryText : WK.Palette.secondaryText)
                        .contentTransition(.symbolEffect(.replace.downUp))
                        .frame(width: 22, height: 22)
                        .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())
        }
        .padding(.horizontal, WK.Spacing.s)
        .frame(height: 36)
        .adaptiveGlassInteractive(in: .capsule)
        .animation(WKAnimation.selection, value: shortcut.isPinned)
        .opacity(isCurrent ? 1 : 0.85)
    }

    @ViewBuilder
    private var icon: some View {
        if let data = shortcut.iconData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .clipShape(.rect(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: "globe")
                .font(.system(size: 12))
                .foregroundStyle(WK.Palette.secondaryText)
                .frame(width: 16, height: 16)
        }
    }
}
