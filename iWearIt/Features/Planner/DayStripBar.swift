import SwiftUI
import WKCanvas
import WKDesign

/// Tira horizontal de días. Tocar el título abre el calendario.
struct DayStripBar: View {
    let anchorDay: Date
    @Binding var selectedOffset: Int
    let onOpenCalendar: () -> Void
    /// Revista o rejilla. Va **aquí arriba**, junto al calendario: es un
    /// ajuste de cómo se mira el plan, igual que el día, y no una acción sobre
    /// el outfit que se está viendo.
    let layoutSymbol: String
    let onToggleLayout: () -> Void

    var body: some View {
        HStack(spacing: WK.Spacing.s) {
            DayStripCapsule(
                anchorDay: anchorDay,
                selectedOffset: $selectedOffset,
                onOpenCalendar: onOpenCalendar
            )
            .padding(.leading, WK.Spacing.m)
            // **Un círculo, no un óvalo.** Tenía el alto de la cápsula de al
            // lado y el ancho de un icono, así que salía estirado: dos formas
            // distintas fingiendo ser la misma. Con el lado igual al alto es
            // un círculo de verdad, y un botón de un solo icono es redondo.
            Button(action: onToggleLayout) {
                Image(systemName: layoutSymbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WK.Palette.primaryText)
                    .frame(width: 56, height: 56)
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .contentShape(.circle)
            }
            .buttonStyle(WKPressStyle())
            .adaptiveGlassInteractive(in: .circle)
            .padding(.trailing, WK.Spacing.m)
        }
    }
}

/// La cápsula de la tira: el calendario, los días y el taco de hoy.
///
/// Suelta del botón de revista/rejilla porque no siempre van juntos: flotando
/// sobre el lienzo son una sola pieza, y dentro de una barra son dos elementos
/// hermanos, cada uno con el fondo que la barra les dé.
struct DayStripCapsule: View {
    let anchorDay: Date
    @Binding var selectedOffset: Int
    let onOpenCalendar: () -> Void
    /// Si se pinta su propio cristal.
    ///
    /// Encendido **también dentro de la barra de navegación**: los botones de
    /// los lados reciben cristal del sistema, pero lo del centro no, y sin él
    /// los días flotaban sueltos sin forma.
    var hasBackground = true
    /// Dentro de la barra de navegación: chips más bajos para no estirarla.
    var isInBar = false

    /// Cuántos días a cada lado se materializan. Suficiente para que el scroll
    /// nunca llegue al borde, sin construir un calendario infinito.
    private static let radius = 180
    private var offsets: [Int] { Array(-Self.radius...Self.radius) }

    var body: some View {
        // Una cápsula flotando **sobre** el lienzo, no una barra que lo corta.
        // El papel de puntos tiene que seguir por debajo: en cuanto la tira
        // ocupa todo el ancho con su propio fondo, la pantalla deja de ser una
        // hoja y pasa a ser dos zonas.
        HStack(spacing: 0) {
            StripIcon(symbol: "calendar", action: onOpenCalendar)

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: WK.Spacing.xs) {
                        ForEach(offsets, id: \.self) { offset in
                            DayChip(
                                date: date(for: offset),
                                isSelected: offset == selectedOffset,
                                isToday: offset == 0,
                                isCompact: isInBar
                            )
                            .id(offset)
                            .onTapGesture { selectedOffset = offset }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                // Se desvanece en los extremos en vez de cortarse a hueso:
                // sin esto el día que pasa por debajo del icono queda partido
                // a la mitad y se lee como un número equivocado.
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.06),
                            .init(color: .black, location: 0.94),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .onChange(of: selectedOffset) {
                    withAnimation(.snappy) { proxy.scrollTo(selectedOffset, anchor: .center) }
                }
                .onAppear { proxy.scrollTo(selectedOffset, anchor: .center) }
            }

            // **Hoy, no "atrás".**
            //
            // La flecha de deshacer decía lo que no era: volver al día de hoy
            // no es retroceder —desde la semana pasada es ir hacia delante— y
            // una flecha de vuelta en una tira que se mueve en los dos
            // sentidos apunta a cualquier sitio menos al que lleva.
            //
            // El taco de calendario sí lo dice, y además dice **a qué día**:
            // lleva el número de hoy dentro. Es la misma pieza que el sticker
            // de fecha del lienzo, con los mismos colores, a tamaño de icono.
            TodayButton(date: today) { selectedOffset = 0 }
                .opacity(selectedOffset == 0 ? 0.3 : 1)
                .disabled(selectedOffset == 0)
        }
        .frame(height: isInBar ? 44 : 56)
        .clipShape(.capsule)
        // Cristal interactivo: flota sobre el lienzo y lo deja verse por
        // debajo. Una cápsula opaca sobre papel de puntos corta el papel.
        // El cristal, solo cuando flota sobre el lienzo. Dentro de una
        // barra lo pone la barra, y dos cristales uno encima de otro se ven
        // como un parche más oscuro con forma de cápsula.
        .modifier(StripBackground(isOn: hasBackground))
    }


    /// Hoy es el ancla: la tira se indexa por desplazamiento respecto a él.
    private var today: Date { anchorDay }

    private func date(for offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: anchorDay) ?? anchorDay
    }
}

/// El cristal de la cápsula, o nada.
private struct StripBackground: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.adaptiveGlassInteractive(in: .capsule)
        } else {
            content
        }
    }
}

/// Un día de la tira. POD: solo fecha y dos banderas, así que se difunde con
/// `memcmp` y cambiar de día no reevalúa los 361 chips.
struct DayChip: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    /// Más bajo, para caber dentro de una barra de navegación sin estirarla.
    var isCompact = false

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()

    var body: some View {
        VStack(spacing: 2) {
            Text(Self.weekday.string(from: date))
                .font(.caption2)
                // También sobre el acento: la inicial del día se quedaba en
                // gris secundario encima de la cápsula negra y no se leía. El
                // relleno y la etiqueta se deciden **siempre juntos**.
                .foregroundStyle(isSelected ? WK.Palette.onAccent.opacity(0.75) : WK.Palette.secondaryText)
            Text(Self.day.string(from: date))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(isSelected ? WK.Palette.onAccent : WK.Palette.primaryText)
        }
        .frame(width: isCompact ? 36 : 42, height: isCompact ? 38 : 46)
        .background {
            if isSelected {
                Capsule().fill(WK.Palette.accent)
            } else if isToday {
                Capsule().strokeBorder(WK.Palette.accent, lineWidth: 1.5)
            }
        }
        .contentShape(.capsule)
    }
}

/// Salto rápido a una fecha.
///
/// Sin barra de navegación, sin "Ir a" y sin "Listo": elegir un día **es** la
/// acción, así que confirmarla después es un paso de más. La hoja se cierra
/// sola al tocar una fecha.
struct CalendarJumpSheet: View {
    @Binding var selection: Date
    @Environment(\.dismiss) private var dismiss

    /// Estático: crear un formateador en cada `body` es una asignación por
    /// frame para nada.
    private static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.m) {
            // **El mes, una sola vez.** Lo escribía aquí arriba y el calendario
            // lo escribe otra vez en su propia cabecera —con su selector de
            // mes, que además es el que funciona—, así que se leía dos veces
            // el mismo dato y el de arriba no hacía nada.
            //
            // La cabecera de antes se queda comentada: si algún día el picker
            // gráfico estorba, esto es lo que había.
            //
            // Text(Self.month.string(from: selection).sentenceCased)
            // .font(WK.Font.title)
            // .foregroundStyle(WK.Palette.primaryText)
            // .monospacedDigit()
            // .contentTransition(.numericText())
            // .animation(WKAnimation.content, value: selection)
            // .frame(maxWidth: .infinity, alignment: .leading)

            DatePicker("", selection: $selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(WK.Palette.accent)
                // La tipografía de la app dentro del calendario del sistema.
                // Lo que se pueda: el picker gráfico dibuja parte de su
                // contenido con UIKit y ahí `font` no llega, pero lo que sí
                // respeta el entorno deja de desentonar.
                .environment(\.font, WK.Font.body)
                .onChange(of: selection) { dismiss() }
        }
        .padding(.horizontal, WK.Spacing.screenInset)
        .wkDynamicSheet()
    }
}


/// El taco de calendario del extremo derecho: vuelve a hoy.
private struct TodayButton: View {
    let date: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // El mismo gris que el icono del otro extremo, pero puesto como
            // color macizo y opacidad aparte: con un gris que ya lleva
            // transparencia, el marco y la banda se sumaban donde se tocan.
            // Ver `DatePadGlyph`.
            DatePadGlyph(date: date, size: 18, opacity: 0.55)
                .foregroundStyle(WK.Palette.primaryText)
                .frame(width: 44, height: 56)
                .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}

/// Un icono de los extremos de la cápsula.
/// El icono de la tira. Compartido con la barra del plan nuevo: el calendario
/// se abre con **este** botón y no con otro parecido.
struct StripIcon: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(WK.Palette.secondaryText)
                .frame(width: 44, height: 56)
                .contentShape(.rect)
        }
        .buttonStyle(WKPressStyle())
    }
}
