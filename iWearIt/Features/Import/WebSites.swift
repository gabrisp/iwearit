import Foundation
import SwiftUI
import WKDesign

/// Una web del navegador de importar: su dominio y su icono.
///
/// El dominio y no el título de la página: "zara.com" cabe en una píldora y
/// dice a dónde vas; "Camiseta oversize | ZARA España" no cabe y además cambia
/// con cada producto.
struct WebSite: Codable, Identifiable, Hashable {
    let host: String
    let url: URL
    /// El favicon ya descargado. Se guarda con el sitio para que la fila no
    /// tenga que pedir nada al abrirse.
    var iconData: Data?

    var id: String { host }
}

/// Las webs recientes y las fijadas.
///
/// ## Por qué se guardan
///
/// La ropa se importa de las mismas cuatro tiendas una y otra vez, y cada vez
/// había que volver a escribir el dominio o buscarlo en Google. Las últimas
/// tres salen solas; lo que se toca a diario se fija con el "+" y se queda.
///
/// En `UserDefaults` y no en la base: es una preferencia de este dispositivo
/// —dónde compras— y no parte del armario.
@MainActor
@Observable
final class WebSiteStore {
    private(set) var pinned: [WebSite] = []
    private(set) var recents: [WebSite] = []

    /// Cuántas recientes se recuerdan.
    static let recentLimit = 3
    /// Y cuántas píldoras caben en la fila, fijadas incluidas.
    static let shownLimit = 4

    private static let pinnedKey = "web.pinned"
    private static let recentsKey = "web.recents"

    init() {
        pinned = Self.load(Self.pinnedKey)
        recents = Self.load(Self.recentsKey)
    }

    /// Lo que se enseña: primero lo fijado, y detrás las recientes que no
    /// estén ya fijadas.
    var shown: [WebSite] {
        let pinnedHosts = Set(pinned.map(\.host))
        return Array((pinned + recents.filter { !pinnedHosts.contains($0.host) }).prefix(Self.shownLimit))
    }

    func isPinned(_ host: String) -> Bool { pinned.contains { $0.host == host } }

    /// Se ha navegado a una página: su dominio pasa a ser el más reciente.
    func visited(_ url: URL) async {
        guard let host = Self.host(of: url) else { return }
        var site = WebSite(host: host, url: url, iconData: icon(for: host))
        if site.iconData == nil {
            site.iconData = await Self.favicon(for: host)
        }

        recents.removeAll { $0.host == host }
        recents.insert(site, at: 0)
        if recents.count > Self.recentLimit { recents.removeLast(recents.count - Self.recentLimit) }
        Self.save(recents, to: Self.recentsKey)

        // Si estaba fijada, se le refresca el enlace y el icono: una tienda que
        // cambia de dominio no debería quedarse fijada apuntando al viejo.
        if let index = pinned.firstIndex(where: { $0.host == host }) {
            pinned[index] = site
            Self.save(pinned, to: Self.pinnedKey)
        }
    }

    /// Fija la página que se está viendo.
    func pin(_ url: URL) async {
        guard let host = Self.host(of: url), !isPinned(host) else { return }
        var site = WebSite(host: host, url: url, iconData: icon(for: host))
        if site.iconData == nil {
            site.iconData = await Self.favicon(for: host)
        }
        pinned.append(site)
        Self.save(pinned, to: Self.pinnedKey)
    }

    func unpin(_ host: String) {
        pinned.removeAll { $0.host == host }
        Self.save(pinned, to: Self.pinnedKey)
    }

    func forget(_ host: String) {
        recents.removeAll { $0.host == host }
        Self.save(recents, to: Self.recentsKey)
    }

    /// El icono que ya se tenga de ese dominio, venga de donde venga.
    private func icon(for host: String) -> Data? {
        (pinned + recents).first { $0.host == host && $0.iconData != nil }?.iconData
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

    private static func load(_ key: String) -> [WebSite] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let sites = try? JSONDecoder().decode([WebSite].self, from: data)
        else { return [] }
        return sites
    }

    private static func save(_ sites: [WebSite], to key: String) {
        guard let data = try? JSONEncoder().encode(sites) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// La fila de webs, en píldoras de cristal.
struct WebSiteBar: View {
    let store: WebSiteStore
    /// Si la que se está viendo se puede fijar. `nil` = no hay página.
    let current: URL?
    let onOpen: (WebSite) -> Void
    let onPin: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.xs) {
                ForEach(store.shown) { site in
                    WebSitePill(site: site, isPinned: store.isPinned(site.host)) {
                        onOpen(site)
                    } onPinToggle: {
                        if store.isPinned(site.host) {
                            store.unpin(site.host)
                        } else {
                            onPin()
                        }
                    }
                }

                if canPinCurrent {
                    Button(action: onPin) {
                        Image(systemName: "plus")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(WK.Palette.primaryText)
                            .frame(width: 36, height: 36)
                            .contentShape(.circle)
                    }
                    .buttonStyle(WKPressStyle())
                    .adaptiveGlassInteractive(in: .circle)
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .animation(WKAnimation.selection, value: store.shown)
    }

    /// El "+" solo cuando hay algo que fijar y no está ya fijado.
    private var canPinCurrent: Bool {
        guard let current, let host = WebSiteStore.host(of: current) else { return false }
        return !store.isPinned(host)
    }
}

/// Una web: su favicon y su dominio.
private struct WebSitePill: View {
    let site: WebSite
    let isPinned: Bool
    let onOpen: () -> Void
    let onPinToggle: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                icon
                Text(site.host)
                    .font(WK.Font.caption)
                    .foregroundStyle(WK.Palette.primaryText)
                    .lineLimit(1)
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(WK.Palette.tertiaryText)
                }
            }
            .padding(.horizontal, WK.Spacing.s)
            .frame(height: 36)
            .contentShape(.capsule)
        }
        .buttonStyle(WKPressStyle())
        .adaptiveGlassInteractive(in: .capsule)
        .contextMenu {
            Button(
                isPinned ? "No fijar" : "Fijar",
                systemImage: isPinned ? "pin.slash" : "pin",
                action: onPinToggle
            )
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let data = site.iconData, let image = UIImage(data: data) {
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
