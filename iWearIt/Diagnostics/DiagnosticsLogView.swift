import SwiftUI
import WKCore
import WKDesign

/// El registro, leído desde el propio iPhone.
///
/// Vive en el target de la app y no en `WKDesign` porque necesita `WKCore`
/// —de donde sale `DiagnosticsLog`— y `WKDesign` no depende de nadie. Esa
/// regla es lo que mantiene el grafo en una sola dirección.
///
/// Monoespaciada y pequeña: son líneas técnicas que se leen buscando un patrón
/// —qué etapa, cuánto tardó, dónde se cortó—, y con la tipografía del sistema
/// las columnas bailan y hay que leerlas una a una.
///
/// Se desplaza sola al final: lo que interesa de un registro que está creciendo
/// es siempre la última línea, y perseguirla a mano mientras corre el análisis
/// no hay quien lo haga.
struct DiagnosticsLogView: View {
    private let lines: [DiagnosticsLog.Line]
    private let maximumHeight: CGFloat

    init(lines: [DiagnosticsLog.Line], maximumHeight: CGFloat = 220) {
        self.lines = lines
        self.maximumHeight = maximumHeight
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        DiagnosticsLogRow(line: line).id(line.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: maximumHeight)
            .onChange(of: lines.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }
}

/// Una línea. Vista propia y no un `@ViewBuilder` repetido: es la que se
/// construye cientos de veces, y aquí es donde importa que SwiftUI pueda
/// reutilizarla.
private struct DiagnosticsLogRow: View {
    let line: DiagnosticsLog.Line

    var body: some View {
        // Hora, etapa y mensaje en la misma línea, con la hora y la etapa
        // atenuadas: lo que se busca al leer es el mensaje, y tres columnas con
        // el mismo peso obligan a saltarse dos cada vez.
        (
            Text(line.timestamp + "  ").foregroundStyle(WK.Palette.secondaryText)
                + Text(line.stage + "  ").foregroundStyle(
                    line.isProblem ? Color.red : WK.Palette.secondaryText
                )
                + Text(line.message).foregroundStyle(
                    line.isProblem ? Color.red : WK.Palette.primaryText
                )
        )
        .font(.system(size: 10, design: .monospaced))
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}
