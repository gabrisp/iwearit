import Foundation
import Observation
import os

/// Lo que va pasando por dentro, escrito donde se puede leer.
///
/// ## Por qué existe
///
/// Cuando el recorte no encuentra nada, la app dice "nada que recortar" y ahí
/// se acaba la conversación: ni qué ruta se tomó, ni si el modelo estaba
/// cargado, ni qué clases vio, ni en qué paso se cayó. Y los `NSLog` sueltos
/// que había solo se ven con el Mac enchufado y en Debug — que es justo cuando
/// no está pasando.
///
/// Esto lo escribe en tres sitios a la vez:
///
/// - **En pantalla**, para poder leerlo en el momento, en el iPhone y sin
///   cables.
/// - **En la consola** del sistema (`os.Logger`), para poder filtrar por
///   `subsystem` desde la consola de macOS.
/// - **En un texto copiable**, para poder pegarlo entero en un mensaje.
///
/// Y **no está detrás de `#if DEBUG`**: el problema que hay que mirar aparece
/// en la build que usa el usuario, no en la que uso yo.
@MainActor
@Observable
public final class DiagnosticsLog {

    public static let shared = DiagnosticsLog()

    /// Una línea.
    public struct Line: Identifiable, Sendable {
        public let id = UUID()
        public let date: Date
        /// De qué parte viene: `MODELO`, `FOTO`, `SEGMENTA`…
        public let stage: String
        public let message: String
        public let isProblem: Bool

        /// `20:14:03.412`, que es la precisión a la que se ven las cosas que
        /// tardan. Con segundos enteros, cuatro etapas seguidas parecen
        /// simultáneas.
        public var timestamp: String {
            Line.formatter.string(from: date)
        }

        private static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()
    }

    /// Cuántas líneas se guardan.
    ///
    /// Un tope y no un array que crece: durante un escaneo masivo esto recibe
    /// varias líneas por foto, y con mil fotos sería un array de decenas de
    /// miles de cadenas vivo en memoria para que nadie mire las primeras.
    private static let capacity = 400

    public private(set) var lines: [Line] = []

    private let logger = Logger(subsystem: "com.gabrisp.iWearIt", category: "pipeline")

    /// Desde el hilo que sea.
    ///
    /// El pipeline es un actor y las etapas de Vision corren donde les toca, así
    /// que exigir `await` para dejar una traza convertiría cada anotación en un
    /// punto de suspensión — y cambiaría el orden de lo que se está midiendo.
    /// Esto se puede llamar desde cualquier sitio sin ceremonia.
    public nonisolated static func record(
        _ stage: String,
        _ message: String,
        isProblem: Bool = false
    ) {
        let date = Date()
        Task { @MainActor in
            shared.append(Line(date: date, stage: stage, message: message, isProblem: isProblem))
        }
    }

    private func append(_ line: Line) {
        if isProblemLine(line) {
            logger.error("[\(line.stage, privacy: .public)] \(line.message, privacy: .public)")
        } else {
            logger.info("[\(line.stage, privacy: .public)] \(line.message, privacy: .public)")
        }
        lines.append(line)
        if lines.count > Self.capacity {
            lines.removeFirst(lines.count - Self.capacity)
        }
    }

    private func isProblemLine(_ line: Line) -> Bool { line.isProblem }

    public func clear() { lines.removeAll() }

    /// Todo el registro como texto, para pegarlo en un mensaje.
    public var transcript: String {
        lines
            .map { "\($0.timestamp)  [\($0.stage)] \($0.message)" }
            .joined(separator: "\n")
    }

    /// Las líneas desde un punto, para enseñar solo lo de esta foto.
    public func lines(since marker: Int) -> ArraySlice<Line> {
        guard marker < lines.count else { return [] }
        return lines[marker...]
    }

    /// Dónde está el final ahora mismo. Se pide antes de empezar algo para
    /// poder enseñar después solo lo que ese algo escribió.
    public var marker: Int { lines.count }
}
