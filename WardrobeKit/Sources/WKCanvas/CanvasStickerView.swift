import SwiftUI
import WKCore
import WKDesign
import WKPersistence

/// Lo que se dibuja dentro de un `CanvasItem` que no lleva prenda.
///
/// Separado del contenedor a propósito: `CanvasItemView` no sabe —ni tiene por
/// qué— qué hay dentro. Mueve, gira, escala y apila una caja; lo que se pinta
/// en esa caja se decide aquí. Por eso un sticker se manipula exactamente
/// igual que una prenda sin duplicar una sola línea de gestos.
struct CanvasStickerView: View {
    let sticker: CanvasSticker
    let store: ImageStore

    var body: some View {
        switch sticker {
        case let .date(value):
            DateStickerView(date: value)
        case let .text(value):
            TextStickerView(sticker: value)
        case let .photo(key):
            StoredImage(key: key, variant: .display, store: store)
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
        case let .weather(snapshot):
            WeatherStickerView(snapshot: snapshot)
        }
    }
}

/// Los colores del taco de calendario, en un sitio.
///
/// Los usan el sticker del lienzo y el botón de "hoy" de la tira de días, y
/// tienen que ser **los mismos**: son la misma cosa a dos tamaños, y en cuanto
/// cada uno escribe su propio rojo dejan de parecerlo.
public enum DatePadPalette {
    /// La cabecera.
    public static let header = Color(red: 0.62, green: 0.24, blue: 0.19)
    /// El papel.
    public static let paper = Color(red: 0.98, green: 0.97, blue: 0.95)
    /// La tinta del número.
    public static let ink = Color.black.opacity(0.85)
    /// Y la del mes, más apagada.
    public static let secondaryInk = Color.black.opacity(0.7)
}

/// El mismo taco de calendario, **a tamaño de icono, sin el mes y sin color**.
///
/// ## Por qué sin color
///
/// Porque va en una barra de iconos y ahí el color significa algo: marca lo
/// seleccionado, lo destacado o lo peligroso. Un taco rojo entre iconos grises
/// se lee como "esto está activo" o como una alerta, y no es ni una cosa ni la
/// otra: es un botón más. El sticker del lienzo sí lleva su rojo, porque allí
/// es un objeto y no un control.
///
/// ## Por qué sin el mes
///
/// A 18 puntos son tres letras en algo que mide menos que una uña, y lo único
/// que consiguen es robarle sitio al número, que es el dato.
///
/// ## Por qué dibujado
///
/// `calendar` no lleva el día dentro, y los que llevan insignia no dicen
/// **qué** día. Aquí el dato es el número. Se dibuja con el trazo hueco y las
/// proporciones de un símbolo del sistema, y toma el color de quien lo pone,
/// así que entre iconos pasa por uno más.
public struct DatePadGlyph: View {
    private let date: Date
    private let size: CGFloat
    /// Cuánto se baja el taco entero, **después** de dibujarlo. Ver el cuerpo.
    private let opacity: Double

    public init(date: Date, size: CGFloat = 18, opacity: Double = 1) {
        self.date = date
        self.size = size
        self.opacity = opacity
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()

    public var body: some View {
        let line = max(1, size * 0.085)
        let corner = size * 0.2
        let header = size * 0.28
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)

        // **Opaco por dentro, translúcido por fuera.**
        //
        // El marco y la banda se tocan, y pintados los dos con un color que ya
        // lleva opacidad la zona donde se cruzan sale al doble de tinta: un
        // borrón en la esquina de arriba. Dibujados **opacos** y aplanados con
        // `compositingGroup`, la transparencia se aplica una sola vez sobre el
        // resultado, así que el taco es de una tinta entera.
        //
        // Por eso la opacidad es un parámetro y no viene en el color: quien lo
        // use pasa un color macizo y dice cuánto quiere bajarlo.
        ZStack {
            shape.strokeBorder(lineWidth: line)

            // La cabecera del taco, **maciza**. Como raya fina no se leía a
            // este tamaño: parecía un borde mal dibujado en vez de la banda
            // del calendario. Recortada con la misma forma para que no se
            // salga por las esquinas redondeadas.
            VStack(spacing: 0) {
                Rectangle().frame(height: header)
                Spacer(minLength: 0)
            }
            .clipShape(shape)

            VStack(spacing: 0) {
                Color.clear.frame(height: header)
                Text(Self.day.string(from: date))
                    .font(.system(size: size * 0.46, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: size * 0.88, height: size)
        .compositingGroup()
        .opacity(opacity)
    }

}

/// El sticker de calendario: cabecera roja, mes y día.
///
/// Dibujado y no un emoji ni una captura: tiene que escalar con el canvas sin
/// pixelarse y respetar el idioma del dispositivo.
public struct DateStickerView: View {
    private let date: Date

    public init(date: Date) { self.date = date }

    /// Estáticos. Crear un `DateFormatter` dentro de `body` lo reconstruye en
    /// cada render, y aquí hay uno por sticker en un canvas que se arrastra.
    private static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()

    public var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width, proxy.size.height)
            VStack(spacing: 0) {
                DatePadPalette.header
                    .frame(height: unit * 0.16)

                VStack(spacing: -unit * 0.04) {
                    Text(Self.month.string(from: date).uppercased())
                        .font(.system(size: unit * 0.17, weight: .semibold))
                        .foregroundStyle(DatePadPalette.secondaryInk)
                    Text(Self.day.string(from: date))
                        .font(.system(size: unit * 0.44, weight: .bold))
                        .foregroundStyle(DatePadPalette.ink)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DatePadPalette.paper)
            }
            .clipShape(.rect(cornerRadius: unit * 0.12, style: .continuous))
        }
    }
}

/// Texto puesto en el canvas, con o sin caja detrás.
struct TextStickerView: View {
    let sticker: TextSticker

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height) * 0.28
            Text(sticker.string)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Color(hex: sticker.colorHex) ?? .white)
                .multilineTextAlignment(sticker.alignment.textAlignment)
                .padding(size * 0.35)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background {
                    if let hex = sticker.backgroundHex, let color = Color(hex: hex) {
                        RoundedRectangle(cornerRadius: size * 0.4, style: .continuous)
                            .fill(color)
                    }
                }
        }
    }
}

extension TextSticker.Alignment {
    var textAlignment: TextAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

extension Color {
    /// `#RRGGBB`. Devuelve `nil` si no lo es, en vez de pintar negro: un color
    /// mal escrito que sale negro es indistinguible de un negro querido.
    init?(hex: String) {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// El tiempo de un día, en una tarjeta.
///
/// Máxima y mínima juntas: la máxima sola no decide nada para vestirse —un día
/// de 22 que amanece a 6 pide chaqueta y uno de 22 que amanece a 18 no.
public struct WeatherStickerView: View {
    private let snapshot: WeatherSnapshot

    public init(snapshot: WeatherSnapshot) { self.snapshot = snapshot }

    public var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width, proxy.size.height)
            VStack(spacing: unit * 0.05) {
                Image(systemName: snapshot.condition.symbolName)
                    .font(.system(size: unit * 0.34))
                    // Multicolor: el sol amarillo y la nube gris se distinguen
                    // de un vistazo en un collage lleno de ropa; en monocromo
                    // hay que pararse a mirar cuál es cuál.
                    .symbolRenderingMode(.multicolor)

                Text(Self.degrees(snapshot.highCelsius))
                    .font(.system(size: unit * 0.26, weight: .bold))
                    .foregroundStyle(.black.opacity(0.85))

                Text(String(localized: "wkcanvas.canvasstickerview.min", defaultValue: "min \(String(describing: Self.degrees(snapshot.lowCelsius)))", bundle: .module))
                    .font(.system(size: unit * 0.11, weight: .medium))
                    .foregroundStyle(.black.opacity(0.5))

                if let place = snapshot.place {
                    Text(place)
                        .font(.system(size: unit * 0.1))
                        .foregroundStyle(.black.opacity(0.45))
                        .lineLimit(1)
                        .padding(.horizontal, unit * 0.08)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.98, green: 0.97, blue: 0.95))
            .clipShape(.rect(cornerRadius: unit * 0.14, style: .continuous))
        }
    }

    /// En la unidad del sistema. El dato se guarda en Celsius y se convierte
    /// al mostrarlo: al revés, cambiar de región reescribiría stickers viejos.
    static func degrees(_ celsius: Double) -> String {
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
        return measurement.formatted(
            .measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))
        )
    }
}
