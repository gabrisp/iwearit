import SwiftUI
import WKDesign
import WKServices

/// **El aviso grande**, en el centro: cristal, un icono que se transforma sin
/// parar mientras espera, y lo que ha pasado. Un regalo se queda hasta que se
/// reclama; una prueba fallida se lee y se va. Ver `NoticeCenter`.
struct NoticeOverlay: View {
    let center: NoticeCenter

    var body: some View {
        ZStack {
            if let notice = center.current {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        // El regalo no se va tocando fuera: hay que reclamarlo.
                        if case .refunded = notice { center.dismiss() }
                    }
                NoticeCard(notice: notice, center: center)
                    .id(notice.id)
                    .padding(.horizontal, WK.Spacing.xl)
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.3), value: center.current?.id)
    }
}

private struct NoticeCard: View {
    let notice: NoticeCenter.Notice
    let center: NoticeCenter

    /// El icono va cambiando de forma mientras espera. Ver `symbols`.
    @State private var step = 0

    var body: some View {
        VStack(spacing: WK.Spacing.l) {
            Image(systemName: symbol)
                .font(.system(size: 54, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating))
                .frame(width: 96, height: 96)
                .adaptiveGlass(tint: tint.opacity(0.25), in: .circle)

            VStack(spacing: WK.Spacing.s) {
                Text(title)
                    .font(WK.Font.title)
                    .foregroundStyle(WK.Palette.primaryText)
                    .contentTransition(.numericText())
                Text(message)
                    .font(WK.Font.callout)
                    .foregroundStyle(WK.Palette.secondaryText)
            }
            .multilineTextAlignment(.center)

            switch notice {
            case .grant:
                WKPrimaryButton(
                    center.didClaim
                        ? String(localized: "notice.claimed", defaultValue: "Claimed")
                        : String(localized: "notice.claim", defaultValue: "Claim"),
                    systemImage: center.didClaim ? "checkmark" : "gift",
                    surface: .glass
                ) {
                    Task { await center.claim() }
                }
                .allowsHitTesting(!center.isClaiming && !center.didClaim)
                .opacity(center.isClaiming ? 0.6 : 1)
            case .refunded:
                WKPrimaryButton(String(localized: "common.ok", defaultValue: "OK"), surface: .glass) {
                    center.dismiss()
                }
            }
        }
        .padding(WK.Spacing.xl)
        .frame(maxWidth: 360)
        .adaptiveGlass(in: .rect(cornerRadius: 36, style: .continuous))
        .sensoryFeedback(.success, trigger: center.didClaim)
        .animation(.smooth(duration: 0.45), value: center.didClaim)
        .task {
            // Un cambio de forma cada poco, mientras esté en pantalla.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.smooth(duration: 0.5)) { step += 1 }
            }
        }
    }

    private var symbols: [String] {
        switch notice {
        case .grant: ["gift.fill", "sparkles", "star.fill", "heart.fill"]
        case .refunded: ["arrow.uturn.backward.circle.fill", "creditcard.fill", "checkmark.shield.fill"]
        }
    }

    private var symbol: String {
        if center.didClaim { return "checkmark.circle.fill" }
        return symbols[step % symbols.count]
    }

    private var tint: Color {
        switch notice {
        case .grant: Color(red: 0.95, green: 0.55, blue: 0.35)
        case .refunded: Color(red: 0.4, green: 0.55, blue: 0.95)
        }
    }

    private var title: String {
        switch notice {
        case let .grant(grant):
            grant.currency == StoreIDs.Currency.tryOns.rawValue
                ? String(localized: "notice.grant.tryOns", defaultValue: "\(String(describing: grant.amount)) try-ons for you")
                : String(localized: "notice.grant.improvements", defaultValue: "\(String(describing: grant.amount)) enhancements for you")
        case .refunded:
            String(localized: "notice.refunded.title", defaultValue: "It didn't work out")
        }
    }

    private var message: String {
        switch notice {
        case let .grant(grant):
            grant.message ?? String(localized: "notice.grant.message", defaultValue: "A gift from Snazzy. Claim it and it's yours.")
        case let .refunded(currency):
            currency == .tryOns
                ? String(localized: "notice.refunded.tryOn", defaultValue: "The try-on failed and you weren't charged: your coin is back.")
                : String(localized: "notice.refunded.improvement", defaultValue: "The enhancement failed and you weren't charged: your coin is back.")
        }
    }
}
