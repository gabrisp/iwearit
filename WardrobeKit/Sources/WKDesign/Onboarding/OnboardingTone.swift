import SwiftUI
import UIKit

/// Los colores del onboarding: **tonos de tela**.
///
/// La regla de la app es que el color lo pone la ropa y todo lo demás es
/// neutro. El onboarding no tiene ropa todavía —es justo lo que viene a
/// buscar—, así que el color lo ponen los tejidos que la ropa suele tener:
/// granate, oliva, denim, camel. Nada de azules de sistema ni degradados de
/// app de productividad; son los mismos tonos que luego colgarán en las baldas.
public enum OnboardingTone: String, CaseIterable, Sendable, Hashable {
    case granate, oliva, denim, camel, salvia, lavanda, terracota

    /// El tono lleno: símbolos, números, bordes.
    ///
    /// Más claro en oscuro: el mismo granate sobre gris casi negro se queda
    /// sin contraste y parece marrón.
    public var color: Color {
        let (light, dark) = components
        return Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }

    /// El tono de fondo: el de las baldosas de los iconos y las tarjetas.
    public var soft: Color { color.opacity(0.15) }

    private var components: ((CGFloat, CGFloat, CGFloat), (CGFloat, CGFloat, CGFloat)) {
        switch self {
        case .granate:   ((0.55, 0.16, 0.20), (0.88, 0.45, 0.48))
        case .oliva:     ((0.40, 0.45, 0.22), (0.68, 0.74, 0.46))
        case .denim:     ((0.20, 0.33, 0.55), (0.55, 0.68, 0.92))
        case .camel:     ((0.66, 0.48, 0.26), (0.88, 0.72, 0.50))
        case .salvia:    ((0.33, 0.50, 0.44), (0.58, 0.78, 0.70))
        case .lavanda:   ((0.45, 0.37, 0.62), (0.74, 0.66, 0.90))
        case .terracota: ((0.72, 0.35, 0.22), (0.94, 0.60, 0.47))
        }
    }

    /// Un tono por posición, para repartir color en listas sin repetir el de
    /// al lado.
    public static func at(_ index: Int) -> OnboardingTone {
        allCases[((index % allCases.count) + allCases.count) % allCases.count]
    }
}

/// Un símbolo en su baldosa de color.
///
/// Sustituye a los emojis: cada plataforma los dibuja a su manera, no casan
/// con la tipografía y hacían que el onboarding pareciera una encuesta. Un SF
/// Symbol en una baldosa del tono de una tela se lee como parte de la app.
public struct ToneIcon: View {
    private let symbol: String
    private let tone: OnboardingTone
    private let isFilled: Bool
    private let size: CGFloat

    public init(_ symbol: String, tone: OnboardingTone, isFilled: Bool = false, size: CGFloat = 40) {
        self.symbol = symbol
        self.tone = tone
        self.isFilled = isFilled
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(isFilled ? Color.white : tone.color)
            .symbolEffect(.bounce, value: isFilled)
            .frame(width: size, height: size)
            .background(
                isFilled ? tone.color : tone.soft,
                in: .rect(cornerRadius: size * 0.3, style: .continuous)
            )
            .animation(WKAnimation.selection, value: isFilled)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: WK.Spacing.m) {
        HStack {
            ForEach(OnboardingTone.allCases, id: \.self) { tone in
                ToneIcon("hanger", tone: tone)
            }
        }
        HStack {
            ForEach(OnboardingTone.allCases, id: \.self) { tone in
                ToneIcon("hanger", tone: tone, isFilled: true)
            }
        }
    }
    .padding()
    .background(WK.Palette.canvas)
}
