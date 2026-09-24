import Foundation
import Observation
import SwiftData
import UIKit
import WKCanvas
import WKCore
import WKPersistence
import WKVision

/// Probarse un outfit: la foto tuya con esa ropa puesta.
///
/// ## Qué sale del teléfono y con qué permiso
///
/// Una foto tuya y los recortes de las prendas. Nada más — ni nombre, ni
/// armario, ni de quién es la cuenta. Y **no sale sin que lo digas**: la
/// primera vez hay que aceptar, la fecha se guarda en el `BodyProfile`, y
/// quitar la foto lo revoca. Es el único sitio de la app donde una foto de una
/// persona viaja a un servidor, así que se trata como lo que es.
///
/// ## Por qué en servidor
///
/// Porque los modelos que saben vestir a alguien son de difusión clase SDXL:
/// dos gigas en disco, picos de tres de memoria y cuarenta segundos por imagen
/// en el mejor iPhone. On-device no es "más lento", es que no cabe.
@MainActor
@Observable
final class TryOnModel {

    enum State: Equatable {
        case idle
        case working
        case done
        case failed(String)
    }

    private(set) var state: State = .idle
    /// La imagen generada, mientras la hoja viva. No se guarda sola: guardarla
    /// es una decisión tuya, y una foto tuya menos en el disco es una foto
    /// tuya menos que perder.
    private(set) var result: UIImage?

    private let resolver: (any ClothingResolving)?
    private let imageStore: ImageStore

    init(resolver: (any ClothingResolving)?, imageStore: ImageStore) {
        self.resolver = resolver
        self.imageStore = imageStore
    }

    var canGenerate: Bool { resolver != nil }

    #if DEBUG
    /// Para mirar la animación de "vistiéndote" sin pagar una prueba:
    /// `-fakeTryOn`. Se queda trabajando hasta que se cierra la hoja.
    func simulateWorking() {
        state = .working
        result = nil
    }
    #endif

    /// Genera la prueba.
    ///
    /// - Parameters:
    ///   - profile: tu foto, con el consentimiento ya aceptado.
    ///   - garments: las prendas del conjunto, de arriba abajo.
    /// - Returns: `true` si salió algo, para que quien llama apunte el gasto.
    @discardableResult
    func generate(
        for profile: BodyProfile,
        garments: [Garment],
        direction: TryOnDirection = TryOnDirection(scene: TryOnScene.none.rawValue, pose: TryOnPose.standing.rawValue)
    ) async -> Bool {
        guard let resolver else {
            state = .failed(String(localized: "tryon.tryonmodel.thisNeedsAConnectionTo", defaultValue: "This needs a connection to the server."))
            return false
        }
        // **El permiso solo hace falta si hay foto.** Un perfil descrito no
        // lleva nada tuyo: es una estatura y una complexión.
        if profile.hasPhoto, !profile.canLeaveDevice {
            state = .failed(String(localized: "tryon.tryonmodel.youStillNeedToAllow", defaultValue: "You still need to allow the photo to leave the phone."))
            return false
        }
        guard !garments.isEmpty else {
            state = .failed(String(localized: "tryon.tryonmodel.thisOutfitHasNoClothes", defaultValue: "This outfit has no clothes."))
            return false
        }

        state = .working
        result = nil

        var personJPEG: Data?
        if profile.hasPhoto {
            guard
                let person = try? await imageStore.image(for: profile.imageKey, variant: .display),
                let encoded = Self.jpeg(from: person, maxSide: 1024)
            else {
                state = .failed(String(localized: "tryon.tryonmodel.couldnTPrepareYourPhoto", defaultValue: "Couldn't prepare your photo."))
                return false
            }
            personJPEG = encoded
        }

        var pieces: [Data] = []
        for garment in garments.prefix(6) {
            guard
                let image = try? await imageStore.image(
                    for: garment.normalizedImageKey, variant: .display
                ),
                let png = Self.png(from: image)
            else { continue }
            pieces.append(png)
        }
        guard !pieces.isEmpty else {
            state = .failed(String(localized: "tryon.tryonmodel.couldnTPrepareTheClothes", defaultValue: "Couldn't prepare the clothes."))
            return false
        }

        do {
            let data = try await resolver.tryOn(
                personJPEG: personJPEG,
                personDescription: profile.described,
                garmentsPNG: pieces,
                direction: direction
            )
            guard let generated = UIImage(data: data)?.cgImage else {
                state = .failed(String(localized: "tryon.tryonmodel.theServerReturnedSomethingThat", defaultValue: "The server returned something that isn't an image."))
                return false
            }
            // **La transparencia la pone el teléfono.**
            //
            // Un modelo de imagen no devuelve canal alfa — devuelve píxeles, y
            // cuando le pides "fondo transparente" lo que pinta es el tablero
            // de cuadros. Así que se le pide un fondo liso y aquí se levanta
            // el sujeto, que es la única forma de tener un PNG de verdad. Ver
            // `SubjectCutout`.
            let isPlain = direction.scene == TryOnScene.none.rawValue
            let final = isPlain ? (await SubjectCutout.lift(generated) ?? generated) : generated
            result = UIImage(cgImage: final)
            state = .done
            DiagnosticsLog.record("PROBADOR", "listo · \(pieces.count) prenda(s)")
            return true
        } catch {
            DiagnosticsLog.record("PROBADOR", "falla: \(error)", isProblem: true)
            state = .failed(Self.describe(error))
            return false
        }
    }

    /// **El recorte va en PNG**, que es lo único que conserva el alfa: en JPEG
    /// la prenda llegaría dentro de un rectángulo blanco y el modelo lo
    /// pintaría como parte de la ropa.
    ///
    /// **Y reducido a 640 px.** A 1024 cada prenda eran 1-1,5 MB, y con tres o
    /// cuatro el encargo pasaba del tope del servidor: el probador contestaba
    /// "demasiado grande" antes de intentar nada. Para vestir a alguien sobra.
    private static func png(from image: CGImage) -> Data? {
        let maxSide: CGFloat = 640
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maxSide else { return UIImage(cgImage: image).pngData() }
        let scale = maxSide / longest
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let drawn = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }
        return drawn.pngData()
    }

    /// Tu foto, **sin cuadrarla**.
    ///
    /// El encoder de las prendas encaja en un cuadrado, que para un recorte
    /// está bien y para una persona no: la deformaría. Aquí se reduce por el
    /// lado largo y se guarda la proporción.
    private static func jpeg(from image: CGImage, maxSide: Int) -> Data? {
        let longest = max(image.width, image.height)
        let scale = longest > maxSide ? Double(maxSide) / Double(longest) : 1
        let size = CGSize(
            width: Double(image.width) * scale,
            height: Double(image.height) * scale
        )
        // **A escala 1.** Por defecto el renderer dibuja a la escala de la
        // pantalla —×3 en un iPhone—, así que "1024 px" salían 3072 y la foto
        // sola se comía el tope del servidor.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let drawn = renderer.image { context in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
            _ = context
        }
        return drawn.jpegData(compressionQuality: 0.9)
    }

    private static func describe(_ error: Error) -> String {
        guard let resolverError = error as? ClothingResolverError else {
            return String(localized: "tryon.tryonmodel.couldnTGenerateTheTry", defaultValue: "Couldn't generate the try-on.")
        }
        switch resolverError {
        case .rateLimited:
            return String(localized: "tryon.tryonmodel.theServerIsBusyTry", defaultValue: "The server is busy. Try again in a minute.")
        case let .badResponse(reason) where reason.contains("no_image"):
            return String(localized: "tryon.tryonmodel.theModelRefusedToGenerate", defaultValue: "The model refused to generate this image.")
        case .notConfigured:
            return String(localized: "tryon.tryonmodel.thisNeedsAConnectionTo", defaultValue: "This needs a connection to the server.")
        case let .transport(reason):
            return String(localized: "tryon.tryonmodel.couldnTConnect", defaultValue: "Couldn't connect: \(String(describing: reason))")
        case .badResponse:
            return String(localized: "tryon.tryonmodel.couldnTGenerateTheTry", defaultValue: "Couldn't generate the try-on.")
        }
    }
}


/// Dónde te pones.
///
/// ## Por qué el fondo va en el encargo
///
/// Porque pedir la ropa y luego cambiar el fondo deja la luz de un sitio sobre
/// una persona iluminada de otro, y eso se ve a la primera. Diciéndoselo de
/// una, la sombra cae donde toca.
///
/// `none` es el que devuelve un PNG recortado: se pide fondo liso y el recorte
/// lo hace el teléfono, que es la única forma de tener alfa de verdad.
enum TryOnScene: String, CaseIterable, Identifiable, Sendable {
    case none = "plain"
    case studio
    case street
    case beach
    case office
    case night
    case gym
    /// Uno descrito por ti. Ver `TryOnDirectionPicker`.
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: String(localized: "tryon.tryonmodel.noBackground", defaultValue: "No background")
        case .studio: String(localized: "tryon.tryonmodel.studio", defaultValue: "Studio")
        case .street: String(localized: "tryon.tryonmodel.street", defaultValue: "Street")
        case .beach: String(localized: "common.beach", defaultValue: "Beach")
        case .office: String(localized: "tryon.tryonmodel.office", defaultValue: "Office")
        case .night: String(localized: "tryon.tryonmodel.night", defaultValue: "Night")
        case .gym: String(localized: "tryon.scene.gym", defaultValue: "Gym")
        case .custom: String(localized: "tryon.scene.custom", defaultValue: "Your own")
        }
    }

    var symbol: String {
        switch self {
        case .none: "square.dashed"
        case .studio: "camera"
        case .street: "building.2"
        case .beach: "beach.umbrella"
        case .office: "briefcase"
        case .night: "moon.stars"
        case .gym: "dumbbell.fill"
        case .custom: "pencil.and.scribble"
        }
    }
}

/// **En qué postura.** Como el sitio, va en el encargo: la postura decide cómo
/// cae la ropa, y no se arregla después.
enum TryOnPose: String, CaseIterable, Identifiable, Sendable {
    case standing
    case walking
    case posing
    case sitting
    case mirror
    /// Una descrita por ti. Ver `TryOnDirectionPicker`.
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standing: String(localized: "tryon.pose.standing", defaultValue: "Standing")
        case .walking: String(localized: "tryon.pose.walking", defaultValue: "Walking")
        case .posing: String(localized: "tryon.pose.posing", defaultValue: "Posing")
        case .sitting: String(localized: "tryon.pose.sitting", defaultValue: "Sitting")
        case .mirror: String(localized: "tryon.pose.mirror", defaultValue: "Mirror")
        case .custom: String(localized: "tryon.pose.custom", defaultValue: "Your own")
        }
    }

    var symbol: String {
        switch self {
        case .standing: "figure.stand"
        case .walking: "figure.walk"
        case .posing: "figure.dance"
        case .sitting: "figure.seated.side.left"
        case .mirror: "camera.viewfinder"
        case .custom: "pencil.and.scribble"
        }
    }
}

/// **Una prueba como sticker del propio outfit**: sin fondo, la persona
/// recortada; con escena, la foto entera. La usan el probador y el historial.
@MainActor
enum TryOnSticker {
    /// Ancho con el que entra en el lienzo, en puntos de lienzo.
    static let width: CGFloat = 520

    static func add(key: String, imageSize: CGSize, to outfit: Outfit, context: ModelContext) {
        let ratio = imageSize.width > 0 ? imageSize.height / imageSize.width : 4.0 / 3.0
        _ = CanvasEditing.insert(
            sticker: .photo(key: key),
            size: CGSize(width: width, height: width * ratio),
            in: outfit,
            context: context
        )
        try? context.save()
        DiagnosticsLog.record("PROBADOR", "prueba añadida al outfit como sticker")
    }
}
