import Foundation
import Observation
import WKCore

/// La conversación con el estilista, **fuera de la hoja que la enseña**.
///
/// ## Por qué no vive en la vista
///
/// Porque vivía ahí y cerrar el estilista la borraba entera: lo que habías
/// pedido, lo que te había propuesto y las prendas que habías adjuntado. Abrir
/// y cerrar una hoja no es terminar una conversación — y menos cuando cerrarla
/// es justo lo que hay que hacer para abrir el editor y seguir con lo que
/// estabas mirando.
///
/// ## Qué guarda y qué no
///
/// Lo de esta sesión: el hilo, el encargo vivo, lo adjuntado y qué propuestas
/// ya has guardado. **No se persiste**: una conversación de hace tres días no
/// dice nada del armario de hoy, y lo que sí quieres conservar de ella —un
/// conjunto— se guarda como outfit, que es lo que hace el corazón.
@MainActor
@Observable
final class StylistChat {

    var thread: [StylistMessage] = []
    var draft = ""
    /// Los conjuntos de la última petición.
    var results: [StylistLook] = []
    /// El encargo vivo: cada frase se apila sobre la anterior, para que "y sin
    /// negro" siga valiendo cuando la siguiente diga "algo más abrigado".
    var brief: StylistBrief?
    /// Las prendas adjuntas, que van puestas en todo lo que se proponga.
    var attached: Set<UUID> = []
    /// Lo ya guardado, para que el corazón lo diga sin preguntar a la base.
    var saved: Set<UUID> = []
    var isThinking = false

    var isEmpty: Bool { thread.isEmpty && results.isEmpty }

    /// Borrón y cuenta nueva. Lo que se había guardado sigue guardado.
    func clear() {
        thread.removeAll()
        results.removeAll()
        brief = nil
        attached.removeAll()
        draft = ""
    }
}

/// Un mensaje del hilo.
struct StylistMessage: Identifiable, Hashable {
    enum Role { case user, stylist }
    let id = UUID()
    let role: Role
    let text: String
    /// Las prendas que iban con él.
    ///
    /// El mensaje enviado las enseña: sin eso, adjuntar tres prendas y
    /// escribir "algo para el trabajo" dejaba en el hilo una frase suelta, y
    /// dos preguntas después ya no se sabía con qué se había pedido.
    var attachments: [UUID] = []
}
