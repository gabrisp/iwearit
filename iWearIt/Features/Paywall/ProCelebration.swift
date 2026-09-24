import SwiftUI
import WKDesign

/// **¡Ya eres Pro!** El aviso de después de comprar —o de restaurar—.
///
/// Pagar es el momento en que alguien más se juega con la app, y hasta ahora
/// no pasaba nada: el paywall se cerraba y ya. Esto lo celebra —confeti con
/// los tonos de tela, lo que se acaba de desbloquear— y deja claro que ha
/// ido bien, que es lo primero que uno quiere saber después de pagar.
struct ProCelebration: View {
    let onDismiss: () -> Void

    @State private var hasAppeared = false

    private static let perks: [(symbol: String, tone: OnboardingTone, text: String)] = [
        ("infinity", .granate, "Prendas y maletas sin límite"),
        ("photo.stack", .denim, "Escaneo completo de tu galería"),
        ("person.crop.rectangle", .camel, "El probador virtual"),
        ("sparkles", .oliva, "Tus créditos, ya en tu cuenta"),
    ]

    var body: some View {
        ZStack {
            // Detrás, la app apagada y desenfocada: el momento es este.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            ConfettiBurst()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: WK.Spacing.l) {
                ZStack {
                    Circle()
                        .fill(OnboardingTone.camel.soft)
                        .frame(width: 118, height: 118)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(OnboardingTone.camel.color.gradient)
                        .symbolEffect(.bounce, value: hasAppeared)
                }
                .scaleEffect(hasAppeared ? 1 : 0.4)
                .rotationEffect(.degrees(hasAppeared ? 0 : -20))

                VStack(spacing: WK.Spacing.s) {
                    Text("¡Ya eres Pro!")
                        .font(WK.Font.largeTitle)
                        .foregroundStyle(WK.Palette.primaryText)
                    Text("Gracias por apoyar Snazzy. Esto es lo que acabas de desbloquear:")
                        .font(WK.Font.callout)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: WK.Spacing.m) {
                    ForEach(Array(Self.perks.enumerated()), id: \.offset) { index, perk in
                        HStack(spacing: WK.Spacing.m) {
                            ToneIcon(perk.symbol, tone: perk.tone, isFilled: true, size: 36)
                            Text(perk.text)
                                .font(WK.Font.headline)
                                .foregroundStyle(WK.Palette.primaryText)
                            Spacer(minLength: 0)
                        }
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(x: hasAppeared ? 0 : -16)
                        .animation(WKAnimation.arrival.delay(0.35 + Double(index) * 0.08), value: hasAppeared)
                    }
                }
                .padding(WK.Spacing.m)
                .adaptiveGlass(in: .rect(cornerRadius: WK.Radius.large, style: .continuous))

                WKPrimaryButton("¡A estrenar!", surface: .glass, action: onDismiss)
                    .opacity(hasAppeared ? 1 : 0)
                    .animation(WKAnimation.content.delay(0.7), value: hasAppeared)
            }
            .padding(WK.Spacing.l)
            .frame(maxWidth: 420)
            .scaleEffect(hasAppeared ? 1 : 0.9)
            .opacity(hasAppeared ? 1 : 0)
            .padding(.horizontal, WK.Spacing.screenInset)
        }
        .sensoryFeedback(.success, trigger: hasAppeared)
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.35)) { hasAppeared = true }
        }
    }
}

/// Confeti con los tonos de tela, saliendo de arriba y cayendo con un poco de
/// vaivén. Dura unos segundos y se va solo.
///
/// Dibujado en un `Canvas` a partir del reloj: cien trocitos como cien vistas
/// serían cien reevaluaciones por fotograma.
private struct ConfettiBurst: View {
    private struct Piece {
        let x: Double
        let delay: Double
        let speed: Double
        let sway: Double
        let spin: Double
        let size: Double
        let color: Color
        let isRound: Bool
    }

    @State private var start = Date()
    private let pieces: [Piece] = (0..<110).map { index in
        var generator = SeededGenerator(seed: UInt64(index + 1) &* 2_654_435_761)
        return Piece(
            x: Double.random(in: 0...1, using: &generator),
            delay: Double.random(in: 0...0.6, using: &generator),
            speed: Double.random(in: 0.28...0.55, using: &generator),
            sway: Double.random(in: 10...36, using: &generator),
            spin: Double.random(in: 2...7, using: &generator),
            size: Double.random(in: 6...12, using: &generator),
            color: OnboardingTone.at(index).color,
            isRound: index.isMultiple(of: 3)
        )
    }

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start)
            Canvas { canvas, size in
                // Se desvanece al final, para no cortarse en seco.
                let fade = max(0, min(1, (4.2 - elapsed) / 0.8))
                guard fade > 0 else { return }
                for piece in pieces {
                    let t = elapsed - piece.delay
                    guard t > 0 else { continue }
                    let y = -20 + t * piece.speed * size.height
                    guard y < size.height + 20 else { continue }
                    let x = piece.x * size.width + sin(t * 3 + piece.x * 10) * piece.sway
                    var context = canvas
                    context.opacity = fade
                    context.translateBy(x: x, y: y)
                    context.rotate(by: .radians(t * piece.spin))
                    let rect = CGRect(
                        x: -piece.size / 2, y: -piece.size / 4,
                        width: piece.size, height: piece.isRound ? piece.size : piece.size / 2
                    )
                    let path = piece.isRound ? Path(ellipseIn: rect) : Path(rect)
                    context.fill(path, with: .color(piece.color))
                }
            }
        }
        .onAppear { start = Date() }
    }
}

/// Un generador con semilla: el mismo confeti siempre, sin depender de nada
/// global.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
