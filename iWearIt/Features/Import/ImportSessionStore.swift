import Observation

/// La importación que se quedó a medias.
///
/// Cerrar la hoja de revisión sin guardar no puede tirar veinte segundos de
/// análisis por foto y las correcciones hechas a mano: se guarda aquí, y el
/// "+" del armario ofrece seguir donde se dejó.
///
/// **En memoria, no en disco.** Dura lo que dura la app abierta: son fotos a
/// resolución completa y prendas sin guardar, y lo que se quiere es poder
/// retomar al momento, no una bandeja de borradores que haya que vaciar.
@MainActor
@Observable
final class ImportSessionStore {
    private(set) var pending: ImportModel?

    var hasPending: Bool { pending != nil }

    /// Se guarda solo si hay algo que retomar: una revisión con prendas.
    func stash(_ model: ImportModel) {
        guard case .review = model.phase, !model.candidates.isEmpty else { return }
        pending = model
    }

    /// La sesión, y se olvida: a partir de aquí es de la hoja que la abre.
    func take() -> ImportModel? {
        defer { pending = nil }
        return pending
    }

    func clear() { pending = nil }
}
