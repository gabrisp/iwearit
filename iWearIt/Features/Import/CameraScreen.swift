import PhotosUI
import SwiftUI
import WKCore
import WKDesign
import WKServices

/// Cámara propia para añadir una prenda.
///
/// El encuadre guía a colocar la prenda sola sobre un fondo liso, que es lo que
/// mejor funciona con la segmentación por sujeto: sin persona, el recorte es
/// casi perfecto y el usuario solo tiene que confirmar la categoría.
struct CameraScreen: View {
    /// Lo que sale de aquí: la foto hecha, o las elegidas de la galería.
    let onCapture: ([CGImage]) -> Void

    @State private var camera = CameraController()
    /// Varias, como desde el "+": el carrete de dentro de la cámara es la
    /// misma galería y tiene que dejar lo mismo.
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var isPresentingPicker = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraStateContent(camera: camera)
        }
        .overlay(alignment: .top) { CameraTopBar(camera: camera, onClose: { dismiss() }) }
        .overlay(alignment: .bottom) { shutterBar }
        .statusBarHidden()
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .photosPicker(
            isPresented: $isPresentingPicker,
            selection: $pickedItems,
            maxSelectionCount: 10,
            matching: .images,
            photoLibrary: .shared()
        )
        .task(id: pickedItems.count) { await loadPickedItems() }
    }

    /// Disparador en medio, galería a la izquierda, cambiar cámara a la
    /// derecha.
    ///
    /// La galería vive **aquí dentro** y no en un menú aparte: en el momento de
    /// añadir una prenda da igual si la foto ya existe o hay que hacerla, y
    /// obligar a decidirlo antes de ver la cámara es una bifurcación que el
    /// usuario no había pedido.
    private var shutterBar: some View {
        HStack {
            // **El carrete, siempre.** Con la cámara sin permiso, ocupada o
            // sin arrancar, es la única forma de añadir algo desde aquí; y
            // esta pantalla es a la que lleva el botón del armario vacío.
            // Sin botón de galería: esta cámara es para hacer la foto.
            // CameraBarButton(symbol: "photo.on.rectangle") { isPresentingPicker = true }
            // El hueco del botón, para que el disparador siga en el centro.
            Color.clear.frame(width: 48, height: 48)
            Spacer()
            Group {
                ShutterButton { await capture() }
                Spacer()
                CameraBarButton(symbol: "arrow.triangle.2.circlepath.camera") {
                    camera.switchCamera()
                }
            }
            .opacity(camera.state == .running ? 1 : 0)
            .allowsHitTesting(camera.state == .running)
        }
        .padding(.horizontal, WK.Spacing.xl)
        .padding(.bottom, WK.Spacing.xl)
    }

    /// `PhotosPickerItem` entrega bytes, no una imagen. Se decodifica aquí para
    /// que el pipeline solo sepa de `CGImage`, venga de donde venga.
    private func loadPickedItems() async {
        guard !pickedItems.isEmpty else { return }
        let picked = pickedItems
        // Al final y no al principio: vaciar la lista cambia el `id` de esta
        // tarea y SwiftUI la cancelaría a medio leer.
        defer { pickedItems = [] }

        DiagnosticsLog.record("CÁMARA", "\(picked.count) foto(s) elegida(s) de la galería")
        var images: [CGImage] = []
        for item in picked {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                // **Derecha antes de que la vea nadie**: los píxeles de una
                // foto vertical se guardan apaisados, y el segmentador veía a
                // una persona tumbada.
                let image = UprightImage.cgImage(from: data)
            else {
                DiagnosticsLog.record("CÁMARA", "no se pudo leer una foto", isProblem: true)
                continue
            }
            images.append(image)
        }
        guard !images.isEmpty else { return }
        hand(over: images)
    }

    private func capture() async {
        guard let image = try? await camera.capture() else {
            DiagnosticsLog.record("CÁMARA", "la captura falló", isProblem: true)
            return
        }
        DiagnosticsLog.record("CÁMARA", "capturada \(image.width)×\(image.height)")
        hand(over: [image])
    }

    /// Entrega la foto y **no cierra la hoja**.
    ///
    /// Aquí había un `dismiss()` detrás de `onCapture`, y esa era la carrera:
    /// quien nos presenta cambia de paso al recibir la foto —de cámara a
    /// revisión—, y el `dismiss()` cerraba la hoja que ese cambio acababa de
    /// rellenar. Elegías una foto y volvías al armario sin que pasara nada.
    ///
    /// Cambiar de paso ya destruye esta vista, que es lo que apaga la sesión de
    /// captura. No hace falta cerrar nada.
    private func hand(over images: [CGImage]) {
        camera.stop()
        onCapture(images)
    }
}

/// Qué se ve según el estado de la cámara. Vista aparte para que `CameraScreen`
/// no lleve un `switch` dentro del `@ViewBuilder`.
private struct CameraStateContent: View {
    let camera: CameraController

    var body: some View {
        switch camera.state {
        case .running:
            ZStack {
                CameraPreview(session: camera.session).ignoresSafeArea()
                FramingGuide()
            }
        case .idle, .preparing:
            ProgressView().tint(.white)
        case .denied:
            CameraMessage(
                icon: "camera.fill",
                title: "Sin acceso a la cámara",
                detail: "Actívalo en Ajustes › Snazzy para hacer fotos a tus prendas."
            )
        case let .failed(reason):
            CameraMessage(icon: "exclamationmark.triangle", title: "No se pudo abrir la cámara", detail: reason)
        }
    }
}

/// Guía de encuadre: marco punteado y consejo.
private struct FramingGuide: View {
    var body: some View {
        VStack {
            Spacer()
            // Sin marco: se queda solo el consejo.
            // RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
            //     .strokeBorder(.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
            //     .frame(maxWidth: .infinity)
            //     .aspectRatio(0.78, contentMode: .fit)
            //     .padding(.horizontal, WK.Spacing.xl)
            Text("Coloca la prenda sola sobre un fondo liso")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, WK.Spacing.m)
            Spacer()
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

/// Botón redondo de la barra inferior.
private struct CameraBarButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.18), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(WKPressStyle())
    }
}

private struct CameraTopBar: View {
    let camera: CameraController
    let onClose: () -> Void

    var body: some View {
        HStack {
            Button("Cerrar", systemImage: "xmark") { onClose() }
                .labelStyle(.iconOnly)
            Spacer()
            Button {
                camera.toggleFlash()
            } label: {
                Image(systemName: camera.isFlashOn ? "bolt.fill" : "bolt.slash")
            }
            .opacity(camera.state == .running ? 1 : 0)
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(WK.Spacing.l)
    }
}

private struct CameraMessage: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: WK.Spacing.m) {
            Image(systemName: icon).font(.system(size: 40))
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(WK.Spacing.xl)
    }
}

/// Disparador. Vista propia porque tiene estado de pulsación propio y no debe
/// invalidar el resto de la pantalla al animarse.
private struct ShutterButton: View {
    let action: () async -> Void
    @State private var isCapturing = false

    var body: some View {
        Button {
            guard !isCapturing else { return }
            isCapturing = true
            Task {
                await action()
                isCapturing = false
            }
        } label: {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 74, height: 74)
                Circle().fill(.white).frame(width: 60, height: 60)
                    .scaleEffect(isCapturing ? 0.85 : 1)
            }
            // El anillo exterior tiene el centro hueco: sin declarar la forma,
            // el hueco entre el borde y el círculo interior no responde.
            .frame(width: 74, height: 74)
            .contentShape(.circle)
        }
        .buttonStyle(WKPressStyle())
        .animation(.snappy(duration: 0.18), value: isCapturing)
        .sensoryFeedback(.impact(weight: .medium), trigger: isCapturing)
    }
}
