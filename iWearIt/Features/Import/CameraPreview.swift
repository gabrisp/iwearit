import AVFoundation
import SwiftUI

/// La capa de vídeo de la cámara.
///
/// UIKit aislado en un representable mínimo: es la única forma de exponer un
/// `AVCaptureVideoPreviewLayer`, y todo lo demás de la pantalla —encuadre,
/// disparador, controles— es SwiftUI puro.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    /// `layerClass` en vez de añadir una sublayer: así la capa se redimensiona
    /// sola con la vista y no hay que sincronizar `frame` a mano en cada
    /// rotación.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
