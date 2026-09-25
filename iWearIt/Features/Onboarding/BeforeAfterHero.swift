import SwiftUI
import UIKit
import WKDesign

/// **La primera página**: la misma pareja, mal vestida y vestida con Snazzy,
/// a pantalla completa y con una línea que se arrastra para pasar de una a
/// otra. Antes de explicar nada, el resultado.
///
/// Las fotos son `OnboardingBefore` y `OnboardingAfter` del catálogo. Sin
/// ellas —mientras no estén—, un degradado en su lugar.
struct BeforeAfterHero: View {
    /// Dónde está la línea, de 0 (todo "después") a 1 (todo "antes").
    @State private var position: CGFloat = 0.5
    @State private var isDragging = false
    @State private var hasDemonstrated = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                photo("OnboardingAfter", fallback: [Color(red: 0.93, green: 0.88, blue: 0.8), Color(red: 0.78, green: 0.7, blue: 0.6)])
                    .frame(width: width, height: proxy.size.height)

                // El "antes" encima, recortado hasta la línea.
                photo("OnboardingBefore", fallback: [Color(white: 0.75), Color(white: 0.55)])
                    .frame(width: width, height: proxy.size.height)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * position)
                    }

                // Las dos etiquetas, en su lado.
                HStack {
                    label(String(localized: "onboarding.hero.before", defaultValue: "Before"))
                        .opacity(position > 0.15 ? 1 : 0)
                    Spacer()
                    label(String(localized: "onboarding.hero.after", defaultValue: "With Snazzy"))
                        .opacity(position < 0.85 ? 1 : 0)
                }
                .padding(.horizontal, WK.Spacing.screenInset)
                .frame(maxHeight: .infinity, alignment: .center)
                .offset(y: proxy.size.height * 0.12)
                .animation(.smooth(duration: 0.25), value: position > 0.15)
                .animation(.smooth(duration: 0.25), value: position < 0.85)

                // La línea y su tirador.
                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .shadow(color: .black.opacity(0.25), radius: 4)
                    .overlay {
                        Image(systemName: "chevron.left.chevron.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WK.Palette.primaryText)
                            .frame(width: 46, height: 46)
                            .adaptiveGlassInteractive(in: .circle)
                            .scaleEffect(isDragging ? 1.12 : 1)
                    }
                    .offset(x: width * position - 1)
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        position = min(max(value.location.x / width, 0), 1)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(duration: 0.3)) { isDragging = false }
                    }
            )
            .sensoryFeedback(.selection, trigger: position < 0.5)
        }
        .ignoresSafeArea()
        .task {
            // Una pasada sola al llegar, para que se vea que se arrastra.
            guard !hasDemonstrated else { return }
            hasDemonstrated = true
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.smooth(duration: 1.1)) { position = 0.18 }
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.smooth(duration: 1.1)) { position = 0.82 }
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.smooth(duration: 0.8)) { position = 0.5 }
        }
    }

    @ViewBuilder
    private func photo(_ name: String, fallback: [Color]) -> some View {
        if let image = UIImage(named: name) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            LinearGradient(colors: fallback, startPoint: .top, endPoint: .bottom)
                .overlay {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 90))
                        .foregroundStyle(.white.opacity(0.5))
                }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(WK.Font.captionMedium)
            .foregroundStyle(WK.Palette.primaryText)
            .padding(.horizontal, WK.Spacing.m)
            .padding(.vertical, WK.Spacing.s)
            .adaptiveGlass(in: .capsule)
    }
}
