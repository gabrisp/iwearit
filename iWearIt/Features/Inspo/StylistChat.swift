import Foundation
import Observation
import WKCore
import WKServices

/// Las conversaciones con el estilista, **fuera de la hoja que las enseña**.
///
/// ## Por qué no vive en la vista
///
/// Porque vivía ahí y cerrar el estilista la borraba entera: lo que habías
/// pedido, lo que te había propuesto y las prendas que habías adjuntado. Abrir
/// y cerrar una hoja no es terminar una conversación — y menos cuando cerrarla
/// es justo lo que hay que hacer para abrir el editor y seguir con lo que
/// estabas mirando.
///
/// ## Y ahora sí se guardan
///
/// Antes no: "una conversación de hace tres días no dice nada del armario de
/// hoy". Pero sí dice algo de **ti** —lo que pediste, lo que te propuso y lo
/// que no llegaste a guardar—, y el archivo del estilista es justo eso: los
/// chats, tal cual, con sus conjuntos dentro. Lo que se guarda son palabras e
/// identificadores; las prendas se resuelven al pintar, así que un chat que
/// habla de una prenda borrada enseña el resto y ya está.
@MainActor
@Observable
final class StylistChat {

    /// Todas las conversaciones, **la de ahora incluida**, de la más reciente
    /// a la más vieja.
    private(set) var conversations: [StylistConversation]
    /// Cuál se está enseñando.
    private(set) var activeID: UUID

    var draft = ""
    /// El encargo vivo: cada frase se apila sobre la anterior, para que "y sin
    /// negro" siga valiendo cuando la siguiente diga "algo más abrigado".
    ///
    /// En memoria y no en el archivo: es el estado de una conversación en
    /// marcha, no parte de lo hablado. Al abrir un chat viejo se empieza de
    /// cero, que es lo que pasa cuando retomas algo días después.
    var brief: StylistBrief?
    /// Las prendas adjuntas, que van puestas en todo lo que se proponga.
    var attached: Set<UUID> = []
    var isThinking = false

    /// Cuántas conversaciones se guardan. Veinte son meses de uso normal, y a
    /// partir de ahí lo viejo ya no se busca: se vuelve a preguntar.
    private static let maximum = 20
    private static let storeKey = "stylist.conversations"

    init() {
        let stored = SyncedStore.value([StylistConversation].self, forKey: Self.storeKey) ?? []
        if let first = stored.first {
            conversations = stored
            activeID = first.id
        } else {
            let fresh = StylistConversation()
            conversations = [fresh]
            activeID = fresh.id
        }
    }

    // MARK: La de ahora

    private var activeIndex: Int {
        conversations.firstIndex { $0.id == activeID } ?? 0
    }

    var thread: [StylistMessage] {
        get { conversations[safe: activeIndex]?.messages ?? [] }
        set {
            guard conversations.indices.contains(activeIndex) else { return }
            conversations[activeIndex].messages = newValue
            conversations[activeIndex].updatedAt = Date()
            persist()
        }
    }

    /// Lo ya guardado, para que el corazón lo diga sin preguntar a la base.
    ///
    /// Guardado como conjunto y no como lista: esto se lee una vez **por
    /// tarjeta y por fotograma**, y construir un `Set` en cada lectura era
    /// repartir asignaciones por todo el scroll.
    var saved: Set<UUID> {
        get { conversations[safe: activeIndex]?.saved ?? [] }
        set {
            guard conversations.indices.contains(activeIndex) else { return }
            conversations[activeIndex].saved = newValue
            persist()
        }
    }

    var isEmpty: Bool { thread.isEmpty }

    // MARK: Lo que hace el chat

    func append(_ message: StylistMessage) {
        thread.append(message)
    }

    /// Los conjuntos de una respuesta **se quedan en ella**.
    ///
    /// No hay una tira de resultados aparte: cada respuesta lleva los suyos
    /// debajo, y la siguiente pregunta va después. Así el hilo se lee como lo
    /// que pasó —pedí, me propuso seis, pedí otra cosa— en vez de enseñar solo
    /// lo último y hacer desaparecer lo anterior.
    func attachLooks(_ looks: [StylistLook], to messageID: UUID) {
        guard
            conversations.indices.contains(activeIndex),
            let index = conversations[activeIndex].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        conversations[activeIndex].messages[index].looks = looks
        conversations[activeIndex].updatedAt = Date()
        persist()
    }

    /// Fuera un conjunto de donde esté: lo que se tira no se queda en el hilo.
    func removeLook(_ lookID: UUID) {
        guard conversations.indices.contains(activeIndex) else { return }
        for index in conversations[activeIndex].messages.indices {
            conversations[activeIndex].messages[index].looks.removeAll { $0.id == lookID }
        }
        persist()
    }

    // MARK: El archivo

    /// Empieza otra. La de ahora se queda en el archivo si tiene algo dentro;
    /// si está en blanco, se reaprovecha —abrir el estilista tres veces sin
    /// escribir no debería dejar tres conversaciones vacías—.
    func startNew() {
        if conversations[safe: activeIndex]?.messages.isEmpty == true { return }
        let fresh = StylistConversation()
        conversations.insert(fresh, at: 0)
        activeID = fresh.id
        brief = nil
        attached.removeAll()
        draft = ""
        trim()
        persist()
    }

    /// Retoma una del archivo.
    func open(_ id: UUID) {
        guard conversations.contains(where: { $0.id == id }) else { return }
        activeID = id
        brief = nil
        attached.removeAll()
        draft = ""
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if conversations.isEmpty {
            let fresh = StylistConversation()
            conversations = [fresh]
            activeID = fresh.id
        } else if !conversations.contains(where: { $0.id == activeID }) {
            activeID = conversations[0].id
            brief = nil
        }
        persist()
    }

    /// Borrón y cuenta nueva **en esta**. Lo que se había guardado sigue
    /// guardado, y lo de las demás no se toca.
    func clear() {
        guard conversations.indices.contains(activeIndex) else { return }
        conversations[activeIndex].messages.removeAll()
        conversations[activeIndex].saved.removeAll()
        brief = nil
        attached.removeAll()
        draft = ""
        persist()
    }

    // MARK: Por dentro

    private func trim() {
        guard conversations.count > Self.maximum else { return }
        // Las vacías primero y las viejas después: tirar una conversación con
        // cosas dentro mientras sobra una en blanco sería tirar la buena.
        let doomed = conversations
            .filter { $0.id != activeID }
            .sorted { lhs, rhs in
                if lhs.messages.isEmpty != rhs.messages.isEmpty { return lhs.messages.isEmpty }
                return lhs.updatedAt < rhs.updatedAt
            }
            .prefix(conversations.count - Self.maximum)
            .map(\.id)
        conversations.removeAll { doomed.contains($0.id) }
    }

    /// **Se guarda al rato, no en cada tecla.**
    ///
    /// Escribir esto es codificar el archivo entero a JSON, y se llamaba en
    /// cada mensaje y en cada corazón —además de reordenar la lista, que es
    /// una escritura observada y por tanto un repintado de todo el hilo—. Se
    /// espera a que pare la mano: lo que hay que conservar es el resultado, no
    /// cada paso intermedio.
    private func persist() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, !Task.isCancelled else { return }
            SyncedStore.setValue(self.conversations, forKey: Self.storeKey)
        }
    }

    private var saveTask: Task<Void, Never>?
}

/// Un chat entero: lo dicho, lo propuesto y cuándo fue.
struct StylistConversation: Identifiable, Hashable, Codable {
    var id = UUID()
    var startedAt = Date()
    var updatedAt = Date()
    var messages: [StylistMessage] = []
    /// Los conjuntos de este chat que ya están en favoritos o en un día.
    var saved: Set<UUID> = []

    /// Cómo se llama en el archivo: lo primero que pediste.
    ///
    /// No se inventa un título ni se le pide a nadie que lo resuma: la primera
    /// frase **es** el título, porque es lo que ibas buscando.
    var title: String {
        messages.first { $0.role == .user }?.text ?? "Sin nada todavía"
    }

    var lookCount: Int {
        messages.reduce(0) { $0 + $1.looks.count }
    }
}

/// Un mensaje del hilo.
struct StylistMessage: Identifiable, Hashable, Codable {
    enum Role: String, Codable { case user, stylist }
    var id = UUID()
    let role: Role
    let text: String
    /// Las prendas que iban con él.
    ///
    /// El mensaje enviado las enseña: sin eso, adjuntar tres prendas y
    /// escribir "algo para el trabajo" dejaba en el hilo una frase suelta, y
    /// dos preguntas después ya no se sabía con qué se había pedido.
    var attachments: [UUID] = []
    /// Lo que propuso, si es una respuesta suya.
    var looks: [StylistLook] = []
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
