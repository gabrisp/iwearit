import SwiftData
import SwiftUI
import WKDesign
import WKPersistence
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
    /// **Varias**, no una: en una tienda se mira un producto detrás de otro y
    /// cerrar el navegador por cada uno obliga a repetir la búsqueda entera.
    let onCapture: ([CGImage]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var model = WebCaptureModel()
    @FocusState private var isTyping: Bool
    /// Lo capturado en esta visita, en orden.
    @State private var captures: [WebCapture] = []

    /// Tope por visita. Es el mismo que el de la galería, y por lo mismo: diez
    /// prendas ya son un rato de análisis, y más de una tanda así se revisa
    /// peor de lo que se importa.
    private static let maximumCaptures = 10

    var body: some View {
        NavigationStack {
            WebCaptureView(model: model)
                // **Solo por abajo.** Llevándola también hasta arriba, los
                // controles que la página pone en su cabecera quedaban debajo
                // de la barra y no se podían tocar. La franja de arriba es el
                // sitio de nuestra barra, no de la web.
                .ignoresSafeArea(edges: .bottom)
                // **Todo en la barra, y sin superficie propia.**
                //
                // La barra puesta a mano de antes traía su propio cristal
                // flotando sobre la web, y encima tapaba el pie de las
                // páginas. En la barra del sistema el contenido se difumina
                // por debajo como en cualquier otra pantalla de la app, y no
                // hay nada que reservar ni que tapar.
                .navigationBarTitleDisplayMode(.inline)
                // **Sin fondo en la barra.** Encima de una web, cualquier
                // superficie nuestra es una franja de otra app pegada sobre la
                // página: la web ya trae su propia cabecera y su propio color,
                // y dos cabeceras seguidas no se leen como una.
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                .toolbarBackgroundVisibility(.hidden, for: .bottomBar)
                .toolbar {
                    // Atrás y adelante, a la izquierda. En un navegador son la
                    // mitad de la navegación: entras en un producto, no es,
                    // vuelves.
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { model.goBack() } label: {
                            Image(systemName: "chevron.left")
                        }
                        .tint(WK.Palette.primaryText)
                        .disabled(!model.canGoBack)

                        Button { model.goForward() } label: {
                            Image(systemName: "chevron.right")
                        }
                        .tint(WK.Palette.primaryText)
                        .disabled(!model.canGoForward)
                    }

                    // La dirección **es** el título: decir "Desde la web"
                    // encima de una web no añade nada, y saber en qué página
                    // estás sí.
                    ToolbarItem(placement: .principal) {
                        // En cristal y centrado, como el buscador de una
                        // balda: sobre una web, un campo sin superficie se
                        // confunde con el texto de la página.
                        TextField("Buscar o escribir enlace", text: $model.address)
                            .textFieldStyle(.plain)
                            .font(WK.Font.caption)
                            .foregroundStyle(WK.Palette.primaryText)
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.webSearch)
                            .submitLabel(.go)
                            .focused($isTyping)
                            // **Sin cristal ni alto puestos a mano.** Eso lo
                            // pone la barra: forzarlo daba un campo que no
                            // casaba con sus vecinos por mucho que se ajustara
                            // el número.
                            // .padding(.horizontal, WK.Spacing.s)
                            // .frame(width: 210, height: 40)
                            // .adaptiveGlassInteractive(in: .capsule)
                            .frame(minWidth: 160)
                            .onSubmit {
                                model.go(to: model.address)
                                isTyping = false
                            }
                            // Mientras escribes, la barra es tuya: si la
                            // navegación siguiera actualizándola, te borraría
                            // lo tecleado a mitad de palabra.
                            .onChange(of: isTyping) { _, typing in
                                model.isEditing = typing
                            }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .tint(WK.Palette.primaryText)
                    }

                    // La foto va abajo, con lo capturado al lado. Ver
                    // `captureBar`.
                    // ToolbarItem(placement: .bottomBar) { … }
                }
                // **Abajo, como en el selector de crear outfit**: a la
                // izquierda lo que llevas capturado y a la derecha los
                // botones. Así se recorren cinco productos seguidos y se
                // importan de una vez.
                // **Arriba, bajo la dirección**: las tiendas de siempre son por
                // dónde se empieza, no algo que se hace al final. Abajo queda
                // lo capturado y los botones.
                .adaptiveSafeAreaBar(edge: .top) {
                    WebSiteBar(current: model.currentURL) { shortcut in
                        model.go(to: shortcut.urlString)
                    }
                    .padding(.bottom, WK.Spacing.xs)
                }
                .adaptiveSafeAreaBar(edge: .bottom) { captureBar }
                // Lo visitado se recuerda: las tres últimas salen en la fila.
                .task(id: model.currentURL) {
                    guard let url = model.currentURL else { return }
                    await WebSiteStore(context: modelContext).visited(url)
                }
        }
        // Se cierra arrastrando, como cualquier otra hoja. Estaba desactivado
        // por los arrastres de la web, pero se sale de aquí más veces de las
        // que se recorre una página hasta el borde.
        // .interactiveDismissDisabled()
    }

    /// Lo capturado y los dos botones: hacer la foto y terminar.
    private var captureBar: some View {
        HStack(spacing: WK.Spacing.m) {
            WebCaptureStrip(captures: captures) { capture in
                withAnimation(WKAnimation.selection) {
                    captures.removeAll { $0.id == capture.id }
                }
            }

            Spacer(minLength: 0)

            Button {
                Task {
                    guard captures.count < Self.maximumCaptures,
                          let image = await model.capture() else { return }
                    withAnimation(WKAnimation.content) {
                        captures.append(WebCapture(image: image))
                    }
                }
            } label: {
                // Una cámara, sin el recuadro del visor, y del mismo tamaño
                // que el visto de al lado: son dos botones de la misma fila.
                Image(systemName: "camera")
                    .font(WK.Font.headline)
                    .foregroundStyle(WK.Palette.primaryText)
                    .frame(width: 56, height: 56)
                    .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())
            .adaptiveGlassInteractive(in: .circle)
            .disabled(!model.hasPage || captures.count >= Self.maximumCaptures)
            .opacity(captures.count >= Self.maximumCaptures ? 0.4 : 1)

            Button {
                // **Sin `dismiss()`.** Quien presenta esta hoja la cambia por
                // la de revisar en cuanto llegan las imágenes; cerrarla aquí
                // cancelaba ese cambio, y por eso desaparecía sin volver nada.
                onCapture(captures.map(\.image))
            } label: {
                Image(systemName: "checkmark")
                    .font(WK.Font.headline)
                    .frame(width: 56, height: 56)
                    .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())
            .adaptiveGlassProminent(tint: WK.Palette.accent, in: .circle)
            .disabled(captures.isEmpty)
            .opacity(captures.isEmpty ? 0.4 : 1)
            .animation(WKAnimation.selection, value: captures.isEmpty)
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .padding(.bottom, WK.Spacing.s)
    }
}

/// El montón de capturas de esta visita, a la izquierda de los botones.
///
/// Se solapan como fotos apiladas: con cinco productos en fila ocuparían media
/// pantalla, y lo que hace falta saber es **cuántas** llevas y que la última es
/// la que acabas de hacer. Tocar una la quita.
private struct WebCaptureStrip: View {
    let captures: [WebCapture]
    let onRemove: (WebCapture) -> Void

    var body: some View {
        HStack(spacing: -18) {
            ForEach(captures.suffix(4)) { capture in
                Button { onRemove(capture) } label: {
                    Image(decorative: capture.image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 52)
                        .clipShape(.rect(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.white.opacity(0.9), lineWidth: 2)
                        }
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                }
                .buttonStyle(WKPressStyle())
                .transition(.scale.combined(with: .opacity))
            }

            if captures.count > 4 {
                Text("+\(captures.count - 4)")
                    .font(WK.Font.captionMedium)
                    .foregroundStyle(WK.Palette.secondaryText)
                    .padding(.leading, 24)
            }
        }
    }
}

/// Una captura de esta visita.
struct WebCapture: Identifiable {
    let id = UUID()
    let image: CGImage
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
    /// Dónde se está. Para recordar la tienda y para poder fijarla.
    private(set) var currentURL: URL?
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }

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
        currentURL = url
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
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
        // **Que lo tomen por un navegador, porque lo es.**
        //
        // Por defecto, una `WKWebView` se presenta como algo que no es Safari
        // y sin una sola cookie, y eso es exactamente el perfil que los
        // buscadores marcan como robot: aparecía el "confirma que eres
        // humano" antes de llegar a ningún resultado.
        //
        // Dos cosas lo arreglan y las dos son decir la verdad: una firma de
        // Safari —el motor **es** el de Safari— y el almacén normal, para que
        // el consentimiento que aceptas una vez no haya que volver a
        // aceptarlo en cada búsqueda.
        configuration.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"

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
