import SwiftUI
import WKCore
import WKDesign
import WKPersistence

// Las piezas del probador: el escenario con la prueba y el outfit, lo que se
// ve mientras se genera, las escenas y el perfil. Ver `TryOnSheet`.

/// **El escenario**: el outfit detrás, inclinado, y delante tu foto —o la
/// prueba, cuando la hay—.
///
/// Las dos a la vez porque es lo que se está comparando: esta ropa, puesta en
/// ti. El outfit se ve tal cual y no se toca: es el que se va a probar.
struct TryOnStage: View {
    let outfit: Outfit
    let profile: BodyProfile?
    let result: UIImage?
    let showing: TryOnResult?
    let isWorking: Bool
    let isPlainScene: Bool
    let store: ImageStore

    var body: some View {
        GeometryReader { proxy in
            let photoWidth = min(proxy.size.width * 0.78, proxy.size.height * 0.75)
            ZStack {
                // Detrás, a la izquierda: el outfit.
                LookCanvasView(
                    garments: outfit.garments,
                    store: store,
                    backdrop: PlanFeedScreen.backdrop(of: outfit),
                    outfit: outfit,
                    showsBorder: true
                )
                .frame(width: photoWidth * 0.66)
                .rotationEffect(.degrees(-9))
                .offset(x: -proxy.size.width * 0.28, y: proxy.size.height * 0.08)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                .allowsHitTesting(false)
                .zIndex(0)

                // Delante: la prueba, o tu foto mientras no la hay.
                photoCard
                    .frame(width: photoWidth, height: photoWidth * 4 / 3)
                    .rotationEffect(.degrees(isWorking ? 0 : 2))
                    .offset(x: proxy.size.width * 0.06)
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
                    .zIndex(1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.spring(duration: 0.5, bounce: 0.2), value: isWorking)
        }
    }

    /// El tamaño lo pone el fondo, y la imagen va **encima**: dentro de un
    /// `ZStack`, una imagen que rellena ensanchaba la tarjeta antes de
    /// recortarse y se salía de la pantalla.
    private var photoCard: some View {
        WK.Palette.shelf
            .overlay { photoContent }
            .overlay {
                if isWorking {
                    TryOnGeneratingEffect()
                        .transition(.opacity)
                }
            }
            .clipShape(.rect(cornerRadius: WK.Radius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WK.Radius.large, style: .continuous)
                    .stroke(WK.Palette.ink(0.08), lineWidth: 1)
            }
            .animation(WKAnimation.content, value: result)
            .animation(WKAnimation.content, value: showing?.id)
            .animation(WKAnimation.content, value: isWorking)
    }

    @ViewBuilder
    private var photoContent: some View {
        ZStack {
            if let showing {
                StoredImage(key: showing.imageKey, variant: .display, store: store)
                    .scaledToFill()
                    .transition(.blurReplace)
            } else if let result {
                Image(uiImage: result)
                    .resizable()
                    .scaledToFill()
                    .background(isPlainScene ? WK.Palette.canvas : .clear)
                    // Aparece "revelándose": de desenfocada a nítida.
                    .transition(AnyTransition(.blurReplace).combined(with: .scale(scale: 1.04)))
            } else if let profile, profile.hasPhoto {
                StoredImage(key: profile.imageKey, variant: .display, store: store)
                    .scaledToFill()
                    .saturation(isWorking ? 0.6 : 1)
                    .blur(radius: isWorking ? 2 : 0)
            } else {
                VStack(spacing: WK.Spacing.s) {
                    ToneIcon("person.fill", tone: .camel, size: 56)
                    Text(profile?.described ?? "Crea un perfil para probarte la ropa")
                        .font(WK.Font.callout)
                        .foregroundStyle(WK.Palette.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, WK.Spacing.l)
                }
            }

        }
    }
}

/// **Lo que se ve mientras te viste**: un brillo que barre la foto en
/// diagonal, chispas que laten y frases que van cambiando.
///
/// Son veinte segundos de espera: sin nada que mirar parecen un minuto, y
/// con algo que cuenta qué está pasando se esperan.
///
/// Con `TimelineView` y no con `repeatForever`: la animación infinita no
/// siempre arranca dentro de una hoja, y esto se mueve siempre.
struct TryOnGeneratingEffect: View {
    private static let phrases = [
        "Mirando tu silueta",
        "Colocando cada prenda",
        "Ajustando caídas y tallas",
        "Igualando la luz",
        "Últimos retoques",
    ]
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start)
            GeometryReader { proxy in
                ZStack {
                    // Un velo que respira.
                    Color.black.opacity(0.12 + 0.06 * sin(elapsed * 2))

                    // El brillo, en diagonal, barriendo cada 1,6 s.
                    let sweep = CGFloat((elapsed / 1.6).truncatingRemainder(dividingBy: 1))
                    LinearGradient(
                        colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.55, height: proxy.size.height * 1.6)
                    .rotationEffect(.degrees(20))
                    .offset(x: (sweep * 2 - 1) * proxy.size.width * 1.1)
                    .blendMode(.plusLighter)

                    // Chispas que laten en sitios fijos.
                    ForEach(0..<6, id: \.self) { index in
                        let phase = elapsed * 1.4 + Double(index) * 1.1
                        Image(systemName: "sparkle")
                            .font(.system(size: CGFloat(10 + (index % 3) * 6), weight: .bold))
                            .foregroundStyle(.white)
                            .opacity(0.25 + 0.75 * max(0, sin(phase)))
                            .scaleEffect(0.6 + 0.5 * max(0, sin(phase)))
                            .position(
                                x: proxy.size.width * [0.2, 0.78, 0.35, 0.68, 0.15, 0.85][index],
                                y: proxy.size.height * [0.18, 0.26, 0.55, 0.7, 0.8, 0.5][index]
                            )
                    }

                    // Lo que está haciendo, en una píldora de cristal.
                    VStack {
                        Spacer()
                        let phrase = Self.phrases[Int(elapsed / 2.2) % Self.phrases.count]
                        HStack(spacing: WK.Spacing.s) {
                            Image(systemName: "sparkles")
                                .symbolEffect(.pulse, options: .repeating)
                            Text(phrase + "…")
                                .contentTransition(.opacity)
                                .id(phrase)
                                .transition(.blurReplace)
                        }
                        .font(WK.Font.captionMedium)
                        .foregroundStyle(WK.Palette.primaryText)
                        .padding(.horizontal, WK.Spacing.m)
                        .padding(.vertical, WK.Spacing.s)
                        .adaptiveGlass(in: .capsule)
                        .animation(.smooth(duration: 0.4), value: phrase)

                        // Un avance que nunca llega al final hasta que llega.
                        let progress = 1 - exp(-elapsed / 9)
                        Capsule()
                            .fill(.white.opacity(0.35))
                            .frame(height: 4)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(.white)
                                    .frame(width: proxy.size.width * 0.6 * CGFloat(progress))
                            }
                            .frame(width: proxy.size.width * 0.6)
                            .padding(.top, WK.Spacing.s)
                            .padding(.bottom, WK.Spacing.l)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .allowsHitTesting(false)
        .onAppear { start = Date() }
    }
}

/// **Dónde te pones**, en tarjetas que se ven: cada escena con su color y su
/// icono, y la elegida con el anillo por fuera.
///
/// Un menú escondía justo lo que hace bonita la prueba —el fondo— detrás de
/// un icono, y una fila de píldoras se leía como un formulario.
struct ScenePicker: View {
    @Binding var selection: TryOnScene

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: WK.Spacing.m) {
                ForEach(TryOnScene.allCases) { scene in
                    Button {
                        withAnimation(WKAnimation.selection) { selection = scene }
                    } label: {
                        VStack(spacing: WK.Spacing.xs) {
                            ZStack {
                                Self.fill(for: scene)
                                Image(systemName: scene.symbol)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(scene == .none ? WK.Palette.secondaryText : .white)
                                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                            }
                            .frame(width: 60, height: 76)
                            .clipShape(.rect(cornerRadius: 14, style: .continuous))
                            .overlay {
                                if scene == .none {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(WK.Palette.ink(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                }
                            }
                            .padding(3)
                            .overlay {
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .stroke(selection == scene ? WK.Palette.accent : .clear, lineWidth: 2)
                            }
                            .scaleEffect(selection == scene ? 1 : 0.94)

                            Text(scene.label)
                                .font(selection == scene ? WK.Font.captionMedium : WK.Font.caption)
                                .foregroundStyle(selection == scene ? WK.Palette.primaryText : WK.Palette.secondaryText)
                        }
                    }
                    .buttonStyle(WKPressStyle())
                    .accessibilityLabel("Fondo \(scene.label)")
                    .accessibilityAddTraits(selection == scene ? .isSelected : [])
                }
            }
            .padding(.vertical, WK.Spacing.xs)
        }
        .contentMargins(.horizontal, WK.Spacing.screenInset, for: .scrollContent)
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selection)
    }

    /// El color de cada escena: lo que sugiere su fondo, no una foto.
    @ViewBuilder
    static func fill(for scene: TryOnScene) -> some View {
        switch scene {
        case .none:
            WK.Palette.shelf
        case .studio:
            LinearGradient(colors: [Color(white: 0.9), Color(white: 0.68)], startPoint: .top, endPoint: .bottom)
        case .street:
            LinearGradient(
                colors: [Color(red: 0.52, green: 0.6, blue: 0.68), Color(red: 0.26, green: 0.3, blue: 0.38)],
                startPoint: .top, endPoint: .bottom
            )
        case .beach:
            LinearGradient(
                colors: [Color(red: 0.55, green: 0.8, blue: 0.94), Color(red: 0.94, green: 0.84, blue: 0.62)],
                startPoint: .top, endPoint: .bottom
            )
        case .office:
            LinearGradient(
                colors: [Color(red: 0.88, green: 0.82, blue: 0.72), Color(red: 0.6, green: 0.52, blue: 0.43)],
                startPoint: .top, endPoint: .bottom
            )
        case .night:
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.14, blue: 0.34), Color(red: 0.38, green: 0.2, blue: 0.46)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

/// **Quién se prueba la ropa**, en una pastilla de cristal arriba: su foto y
/// su nombre. Tocarla abre el menú para cambiar de perfil, editarlo o crear
/// otro.
struct ProfileSwitcher: View {
    let profiles: [BodyProfile]
    let selected: BodyProfile?
    let canAddMore: Bool
    let store: ImageStore
    let onSelect: (BodyProfile) -> Void
    let onEdit: (BodyProfile) -> Void
    let onNew: () -> Void

    var body: some View {
        Menu {
            if !profiles.isEmpty {
                Section("Perfil") {
                    ForEach(profiles) { profile in
                        Button { onSelect(profile) } label: {
                            if profile.id == selected?.id {
                                Label(profile.label, systemImage: "checkmark")
                            } else {
                                Text(profile.label)
                            }
                        }
                    }
                }
            }
            if let selected {
                Button { onEdit(selected) } label: {
                    Label("Editar \(selected.label)", systemImage: "pencil")
                }
            }
            if canAddMore {
                Button(action: onNew) {
                    Label("Nuevo perfil", systemImage: "plus")
                }
            }
        } label: {
            HStack(spacing: WK.Spacing.s) {
                Group {
                    if let selected, selected.hasPhoto {
                        StoredImage(key: selected.imageKey, variant: .thumb, store: store)
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundStyle(WK.Palette.secondaryText)
                    }
                }
                .frame(width: 26, height: 26)
                .background(WK.Palette.ink(0.06))
                .clipShape(.circle)

                Text(selected?.label ?? "Probador")
                    .font(WK.Font.headline)
                    .foregroundStyle(WK.Palette.primaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WK.Palette.secondaryText)
            }
            .padding(.leading, 4)
            .padding(.trailing, WK.Spacing.m)
            .padding(.vertical, 4)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}
