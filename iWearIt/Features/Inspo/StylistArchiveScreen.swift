import SwiftUI
import WKCore
import WKDesign

/// El archivo del estilista: **las conversaciones, tal cual**.
///
/// ## Qué hay aquí y qué no
///
/// Aquí están los chats: lo que pediste, lo que te contestó y los conjuntos
/// que propuso, con sus tarjetas dentro. Lo que **guardaste** de ellos no está
/// —eso es un outfit y vive en favoritos, como cualquier otro—. Son dos cosas
/// distintas y mezclarlas hacía que el archivo pareciera una segunda lista de
/// favoritos con menos cosas.
///
/// ## Por qué se empuja y no se abre como hoja
///
/// Porque el estilista ya es una hoja. Otra encima dejaba la conversación a
/// dos alturas de donde se escribe, y para volver al chat había que cerrar dos
/// veces. Empujado en esta misma pila, entrar y volver es un gesto.
struct StylistArchiveScreen: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var chat: StylistChat

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Las que tienen algo dentro. Una conversación en blanco no es un
    /// recuerdo de nada.
    private var saved: [StylistConversation] {
        // Ordenadas aquí y no al guardar: reordenar la lista en cada mensaje
        // era una escritura observada, y con ella un repintado del hilo entero
        // mientras escribías.
        chat.conversations
            .filter { !$0.messages.isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        Group {
            if saved.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "inspo.stylistarchivescreen.youHavenTTalkedTo", defaultValue: "You haven't talked to it yet"), systemImage: "archivebox")
                } description: {
                    Text(String(localized: "inspo.stylistarchivescreen.whatYouAskForAnd", defaultValue: "What you ask for and what it suggests stays here."))
                }
            } else {
                list
            }
        }
        .background(WK.Palette.canvas.ignoresSafeArea())
        .navigationTitle(String(localized: "inspo.stylistarchivescreen.archive", defaultValue: "Archive"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: WK.Spacing.l) {
                WKSection(String(localized: "inspo.stylistarchivescreen.conversations", defaultValue: "Conversations")) {
                    ForEach(Array(saved.enumerated()), id: \.element.id) { index, conversation in
                        WKRow(showsSeparator: index < saved.count - 1) {
                            open(conversation)
                        } leading: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conversation.title)
                                    .font(WK.Font.rowTitle)
                                    .foregroundStyle(WK.Palette.primaryText)
                                    .lineLimit(1)

                                Text(subtitle(for: conversation))
                                    .font(WK.Font.caption)
                                    .foregroundStyle(WK.Palette.secondaryText)
                            }
                        } trailing: {
                            if conversation.id == chat.activeID {
                                // La de ahora, dicha sin palabras: es a la que
                                // vuelves al cerrar esto.
                                Image(systemName: "bubble.left.fill")
                                    .font(.caption)
                                    .foregroundStyle(WK.Palette.accent)
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                withAnimation(WKAnimation.content) { chat.delete(conversation.id) }
                            } label: {
                                Label(String(localized: "common.delete", defaultValue: "Delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, WK.Spacing.screenInset)
            .padding(.bottom, WK.Spacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    /// Cuándo fue y qué salió de ella.
    private func subtitle(for conversation: StylistConversation) -> String {
        let when = Self.stamp.string(from: conversation.updatedAt)
        guard conversation.lookCount > 0 else { return when }
        let looks = conversation.lookCount == 1 ? String(localized: "inspo.stylistarchivescreen.1Outfit", defaultValue: "1 outfit") : String(localized: "inspo.stylistarchivescreen.outfits", defaultValue: "\(String(describing: conversation.lookCount)) outfits")
        return "\(when) · \(looks)"
    }

    /// Retomarla es volver al chat con ella puesta, no abrir otra pantalla: la
    /// conversación se lee donde se escribe.
    private func open(_ conversation: StylistConversation) {
        chat.open(conversation.id)
        dismiss()
    }
}
