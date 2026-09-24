import SwiftUI

/// Piezas reutilizables del onboarding.
///
/// El flujo tiene catorce pantallas y casi todas son la misma forma: una
/// pregunta, una lista de opciones y un botón. Escribirlas una a una daría
/// catorce ficheros parecidos que se desincronizan en cuanto cambia el diseño,
/// así que aquí está cada arquetipo **una vez**.

// MARK: - Progreso

/// Barra de progreso del flujo.
///
/// Visible desde la primera pantalla: saber cuánto queda es lo que evita el
/// abandono a mitad. Un onboarding sin barra se percibe infinito.
public struct OnboardingProgressBar: View {
    private let step: Int
    private let total: Int

    public init(step: Int, total: Int) {
        self.step = step
        self.total = total
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WK.Palette.ink(0.10))
                Capsule()
                    .fill(WK.Palette.accent)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 4)
        .animation(.snappy(duration: 0.35), value: step)
        .accessibilityLabel("Paso \(step) de \(total)")
    }

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(step) / Double(total)))
    }
}

// MARK: - Opciones

/// Una opción de una pregunta.
public struct OnboardingOption: Identifiable, Hashable, Sendable {
    public let id: String
    // Los emojis, fuera: ver `ToneIcon`.
    // public let emoji: String
    /// SF Symbol de la opción.
    public let symbol: String
    /// El tono de tela de su baldosa. Ver `OnboardingTone`.
    public let tone: OnboardingTone
    public let label: String
    /// Matiz opcional bajo la etiqueta.
    public let detail: String?

    public init(id: String, symbol: String, tone: OnboardingTone, label: String, detail: String? = nil) {
        self.id = id
        self.symbol = symbol
        self.tone = tone
        self.label = label
        self.detail = detail
    }
}

/// Lista de selección única.
///
/// Elegir un objetivo es el primer compromiso psicológico del flujo: a partir
/// de ahí el usuario siente que la app le debe una solución a *eso* que ha
/// dicho. Por eso va antes que cualquier otra cosa.
public struct SingleSelectList: View {
    private let options: [OnboardingOption]
    @Binding private var selection: String?

    public init(options: [OnboardingOption], selection: Binding<String?>) {
        self.options = options
        _selection = selection
    }

    public var body: some View {
        VStack(spacing: WK.Spacing.s + 4) {
            ForEach(options) { option in
                OptionRow(option: option, isSelected: selection == option.id) {
                    selection = option.id
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Lista de selección múltiple.
public struct MultiSelectList: View {
    private let options: [OnboardingOption]
    @Binding private var selection: Set<String>

    public init(options: [OnboardingOption], selection: Binding<Set<String>>) {
        self.options = options
        _selection = selection
    }

    public var body: some View {
        VStack(spacing: WK.Spacing.s + 4) {
            ForEach(options) { option in
                OptionRow(option: option, isSelected: selection.contains(option.id), isCheckbox: true) {
                    if selection.contains(option.id) {
                        selection.remove(option.id)
                    } else {
                        selection.insert(option.id)
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Fila de opción. Una sola vista para los dos tipos de lista: la diferencia
/// entre única y múltiple es el glifo, no el diseño.
private struct OptionRow: View {
    let option: OnboardingOption
    let isSelected: Bool
    var isCheckbox = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WK.Spacing.m) {
                // Text(option.emoji).font(.title3)
                // La baldosa se llena del tono al marcarla: se ve qué está
                // elegido sin tener que buscar el círculo de la derecha.
                ToneIcon(option.symbol, tone: option.tone, isFilled: isSelected)

                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.body)
                        .foregroundStyle(WK.Palette.primaryText)
                        .multilineTextAlignment(.leading)
                    if let detail = option.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(WK.Palette.secondaryText)
                    }
                }
                Spacer(minLength: WK.Spacing.s)

                Image(systemName: glyph)
                    .font(.title3)
                    .foregroundStyle(isSelected ? option.tone.color : WK.Palette.ink(0.22))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, WK.Spacing.m - 4)
            .padding(.vertical, WK.Spacing.s + 2)
            // .background(WK.Palette.shelf, in: .rect(cornerRadius: WK.Radius.medium, style: .continuous))
            // .overlay(
            //     RoundedRectangle(cornerRadius: WK.Radius.medium, style: .continuous)
            //         .stroke(isSelected ? WK.Palette.accent : .clear, lineWidth: 2)
            // )
            .contentShape(.rect(cornerRadius: WK.Radius.medium, style: .continuous))
        }
        // **Cristal interactivo**, como todo lo que se toca en el onboarding:
        // el propio cristal responde al dedo, así que el estilo del botón es
        // plano —el encogido de `WKPressStyle` encima se sumaba al del cristal
        // y la fila daba dos respuestas a un solo toque—.
        .buttonStyle(.plain)
        .adaptiveGlassInteractive(in: .rect(cornerRadius: WK.Radius.medium, style: .continuous))
        // El borde de la selección **por fuera** del cristal, separado: dentro
        // se montaba sobre el canto del cristal y se leían dos bordes, uno
        // encima del otro. El radio crece lo mismo que la separación para
        // que las esquinas sigan siendo paralelas.
        .overlay {
            RoundedRectangle(cornerRadius: WK.Radius.medium + 4, style: .continuous)
                .stroke(isSelected ? option.tone.color : .clear, lineWidth: 2)
                .padding(-4)
        }
        .animation(.snappy(duration: 0.18), value: isSelected)
    }

    private var glyph: String {
        if isCheckbox {
            isSelected ? "checkmark.square.fill" : "square"
        } else {
            isSelected ? "checkmark.circle.fill" : "circle"
        }
    }
}

// MARK: - Prueba social

public struct Testimonial: Identifiable, Hashable, Sendable {
    public let id: String
    public let initials: String
    public let name: String
    /// "Compra compulsiva", "Poco tiempo" — tiene que casar con los segmentos
    /// que el usuario acaba de elegir.
    public let tag: String
    public let text: String
    public let stars: Int
    /// El color del avatar.
    public let tone: OnboardingTone

    public init(
        id: String, initials: String, name: String, tag: String, text: String,
        stars: Int = 5, tone: OnboardingTone = .camel
    ) {
        self.id = id
        self.initials = initials
        self.name = name
        self.tag = tag
        self.text = text
        self.stars = stars
        self.tone = tone
    }
}

public struct TestimonialCard: View {
    private let testimonial: Testimonial

    public init(_ testimonial: Testimonial) {
        self.testimonial = testimonial
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: WK.Spacing.s) {
            HStack(spacing: WK.Spacing.s) {
                // Cada persona con su tono: tres avatares negros iguales se
                // leían como el mismo usuario repetido.
                Text(testimonial.initials)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(testimonial.tone.color, in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(testimonial.name).font(.subheadline.weight(.medium))
                    Text(testimonial.tag)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(testimonial.tone.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(testimonial.tone.soft, in: .capsule)
                }
                Spacer()
                StarRow(count: testimonial.stars)
            }
            Text(testimonial.text)
                .font(.subheadline)
                .foregroundStyle(WK.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(WK.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WK.Palette.shelf, in: .rect(cornerRadius: WK.Radius.card, style: .continuous))
    }
}

public struct StarRow: View {
    private let count: Int
    public init(count: Int) { self.count = count }

    public var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<max(0, min(5, count)), id: \.self) { _ in
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(OnboardingTone.camel.color)
            }
        }
    }
}

// MARK: - Comparativa

public struct ComparisonRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// Tabla con/sin. Hace visceral el contraste sin necesidad de argumentar.
public struct ComparisonTable: View {
    private let rows: [ComparisonRow]
    private let withTitle: String
    private let withoutTitle: String

    public init(rows: [ComparisonRow], withTitle: String, withoutTitle: String) {
        self.rows = rows
        self.withTitle = withTitle
        self.withoutTitle = withoutTitle
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                // La columna buena, marcada con su tono: el ojo va ahí primero.
                Text(withTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OnboardingTone.oliva.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(OnboardingTone.oliva.soft, in: .capsule)
                    .frame(width: 72)
                Text(withoutTitle).font(.caption).foregroundStyle(WK.Palette.secondaryText).frame(width: 64)
            }
            .padding(.horizontal, WK.Spacing.m)
            .padding(.bottom, WK.Spacing.s)

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack {
                    Text(row.label)
                        .font(.subheadline)
                        .foregroundStyle(WK.Palette.primaryText)
                    Spacer(minLength: WK.Spacing.s)
                    // Image(systemName: "checkmark").foregroundStyle(.green).frame(width: 64)
                    // Image(systemName: "xmark").foregroundStyle(.red.opacity(0.75)).frame(width: 64)
                    // Verde y rojo de sistema chillaban contra la paleta; el
                    // "no" en gris dice lo mismo sin gritar.
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(OnboardingTone.oliva.color)
                        .frame(width: 72)
                    Image(systemName: "xmark.circle")
                        .font(.title3)
                        .foregroundStyle(WK.Palette.ink(0.22))
                        .frame(width: 64)
                }
                .padding(.horizontal, WK.Spacing.m)
                .padding(.vertical, WK.Spacing.m - 4)
                .background(index.isMultiple(of: 2) ? WK.Palette.ink(0.03) : .clear)
            }
        }
        .background(WK.Palette.shelf, in: .rect(cornerRadius: WK.Radius.card, style: .continuous))
    }
}
