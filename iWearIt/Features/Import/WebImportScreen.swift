import SwiftUI
import WKDesign
import WebKit

/// Meter una prenda **desde la tienda**.
///
/// ## Por qué un navegador dentro de la app
///
/// Porque la foto que quieres casi nunca está en tu carrete: está en la ficha
/// del producto, sobre fondo blanco y bien recortada — que es exactamente la
/// foto con la que el recorte funciona mejor. Hoy eso obliga a salir, buscar,
/// hacer una captura, volver e importarla del carrete, y por el camino se
/// queda una captura basura en las fotos del usuario.
///
/// Aquí el recorrido es el mismo pero sin salir ni dejar rastro: buscas, abres
/// el producto y tocas capturar. Lo que se lleva es la imagen, no la captura.
///
/// ## Qué **no** hace
///
/// No descarga la imagen del producto ni lee el HTML de la página. Hace una
/// foto de lo que se está viendo, igual que harías tú. Es la diferencia entre
/// mirar una web y raspar una web, y también la que evita traerse una imagen
/// protegida sin saberlo.
struct WebImportScreen: View {
    let onCapture: (CGImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model = WebCaptureModel()
    @FocusState private var isTyping: Bool

    var body: some View {
        NavigationStack {
            WebCaptureView(model: model)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Desde la web")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .tint(WK.Palette.primaryText)
                    }
                }
                .safeAreaInset(edge: .bottom) { bar }
        }
        // **No se cierra arrastrando.** Una web se recorre con el dedo de
        // arriba abajo, y con el gesto de descartar puesto la mitad de los
        // arrastres cerraban la pantalla en vez de mover la página. Se sale
        // por la X, que además está donde se espera.
        .interactiveDismissDisabled()
    }

    private var bar: some View {
        HStack(spacing: WK.Spacing.s) {
            TextField("Busca o pega un enlace", text: $model.address)
                .textFieldStyle(.plain)
                .font(WK.Font.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .focused($isTyping)
                .onSubmit {
                    model.go(to: model.address)
                    isTyping = false
                }
                // Mientras escribes, la barra es tuya: si la navegación
                // siguiera actualizándola, te borraría lo que llevas tecleado
                // a mitad de palabra.
                .onChange(of: isTyping) { _, typing in model.isEditing = typing }
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.s + 2)
                .adaptiveGlass(in: .capsule)

            Button {
                Task {
                    guard let image = await model.capture() else { return }
                    // **Sin `dismiss()`.** Quien presenta esta hoja la cambia
                    // por la de revisar en cuanto llega la imagen; cerrarla
                    // aquí además cancelaba ese cambio, y por eso la hoja
                    // desaparecía sin que volviera nada.
                    onCapture(image)
                }
            } label: {
                // Una cámara y no "Capturar": el botón vive al lado de un
                // campo de texto y una palabra más lo estrecharía hasta no
                // poder escribir.
                Image(systemName: "camera.viewfinder")
                    .font(WK.Font.headline)
                    .frame(width: 52, height: 52)
                    .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())
            .adaptiveGlassProminent(tint: WK.Palette.accent, in: .circle)
            .disabled(!model.hasPage)
            .opacity(model.hasPage ? 1 : 0.4)
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.s)
    }
}

/// El navegador y la foto que se le hace.
@MainActor
@Observable
final class WebCaptureModel {
    /// Lo que se ve en la barra: la dirección de la página, o lo que estés
    /// escribiendo encima.
    var address = ""
    /// Mientras el campo tiene el cursor, la navegación no lo toca.
    var isEditing = false
    /// Hay algo cargado que fotografiar.
    private(set) var hasPage = false

    /// Dónde se empieza.
    ///
    /// Google y no la página de una tienda: buscar es lo que se hace primero,
    /// y arrancar en una tienda concreta sería elegir por el usuario a qué
    /// marca compra.
    static let home = URL(string: "https://www.google.com")!

    /// La vista real. Débil: la crea y la destruye SwiftUI, no esto.
    @ObservationIgnored weak var webView: WKWebView?

    /// Adónde ir con lo que se ha escrito.
    ///
    /// Un enlace si lo parece, y si no, una búsqueda. Distinguirlos por el
    /// punto y el espacio es tosco y acierta siempre en la práctica: nadie
    /// busca "zara.com" queriendo buscar, ni escribe un enlace con espacios.
    func go(to text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let target: URL?
        if trimmed.contains(" ") || !trimmed.contains(".") {
            var components = URLComponents(string: "https://www.google.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
            target = components?.url
        } else if trimmed.hasPrefix("http") {
            target = URL(string: trimmed)
        } else {
            target = URL(string: "https://" + trimmed)
        }

        guard let target else { return }
        webView?.load(URLRequest(url: target))
    }

    /// La página ha cambiado: la barra sigue a la navegación.
    func pageChanged(to url: URL?) {
        hasPage = url != nil
        guard !isEditing, let url else { return }
        address = url.absoluteString
    }

    /// Una foto de lo que se está viendo.
    ///
    /// `takeSnapshot` y no un render de la capa: es la API que WebKit expone
    /// para esto y devuelve lo que de verdad está pintado, con su contenido
    /// compuesto. Dibujar la capa a mano da páginas a medio cargar y, en
    /// contenido acelerado, huecos en blanco.
    func capture() async -> CGImage? {
        guard let webView else { return nil }
        let configuration = WKSnapshotConfiguration()
        // Solo lo visible: es lo que el usuario ha encuadrado, y una captura
        // de la página entera traería el menú, el pie y tres banners.
        configuration.rect = webView.bounds
        let image = try? await webView.takeSnapshot(configuration: configuration)
        return image?.cgImage
    }
}

private struct WebCaptureView: UIViewRepresentable {
    let model: WebCaptureModel

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // **Sin dejar rastro.** El dato que interesa es la foto, no la
        // sesión: un almacén efímero evita quedarse con las cookies de la
        // tienda y con la sesión iniciada de nadie.
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        model.webView = webView
        webView.load(URLRequest(url: WebCaptureModel.home))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    /// Mantiene la barra al día con la navegación: pinchar un resultado, un
    /// producto o volver atrás tiene que verse en la dirección, o la barra
    /// deja de decir dónde estás.
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let model: WebCaptureModel

        init(model: WebCaptureModel) { self.model = model }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            model.pageChanged(to: webView.url)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.pageChanged(to: webView.url)
        }
    }
}
