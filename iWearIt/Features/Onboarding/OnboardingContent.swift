import Foundation
import WKDesign

/// El texto del onboarding, en un sitio.
///
/// Separado de las vistas para poder revisarlo entero de una sentada: la copia
/// de un onboarding se afina muchas más veces que su layout, y buscarla repartida
/// por catorce ficheros garantiza que unas pantallas se queden desactualizadas.
enum OnboardingContent {

    // Con emojis, antes. Cada sistema los dibuja distinto y no casaban con
    // la tipografía: ver `ToneIcon`.
    // static let goals: [OnboardingOption] = [
    //     .init(id: "faster", emoji: "⏱️", label: "Vestirme más rápido",
    //           detail: "Dejar de decidir delante del armario"),
    //     .init(id: "save", emoji: "💸", label: "Dejar de comprar de más",
    //           detail: "Aprovechar lo que ya tengo"),
    //     .init(id: "see", emoji: "👀", label: "Ver todo lo que tengo",
    //           detail: "Sin vaciar los cajones"),
    //     .init(id: "combine", emoji: "🎨", label: "Combinar mejor",
    //           detail: "Sacarle partido a cada prenda"),
    //     .init(id: "travel", emoji: "🧳", label: "Preparar viajes sin agobios"),
    // ]

    // static let pains: [OnboardingOption] = [
    //     .init(id: "nothing", emoji: "🤷", label: "Tengo el armario lleno y nada que ponerme"),
    //     .init(id: "forget", emoji: "🫥", label: "Me olvido de la ropa que tengo al fondo"),
    //     .init(id: "duplicate", emoji: "👯", label: "Compro cosas parecidas a las que ya tengo"),
    //     .init(id: "time", emoji: "⌛", label: "Pierdo tiempo cada mañana"),
    //     .init(id: "packing", emoji: "🧳", label: "Hacer la maleta me estresa"),
    //     .init(id: "combine", emoji: "🧩", label: "No sé combinar lo que tengo"),
    // ]

    static let goals: [OnboardingOption] = [
        .init(id: "faster", symbol: "timer", tone: .denim,
              label: "Vestirme más rápido",
              detail: "Dejar de decidir delante del armario"),
        .init(id: "save", symbol: "banknote", tone: .oliva,
              label: "Dejar de comprar de más",
              detail: "Aprovechar lo que ya tengo"),
        .init(id: "see", symbol: "eye", tone: .camel,
              label: "Ver todo lo que tengo",
              detail: "Sin vaciar los cajones"),
        .init(id: "combine", symbol: "paintpalette", tone: .granate,
              label: "Combinar mejor",
              detail: "Sacarle partido a cada prenda"),
        .init(id: "travel", symbol: "suitcase.rolling", tone: .salvia,
              label: "Preparar viajes sin agobios"),
    ]

    static let pains: [OnboardingOption] = [
        .init(id: "nothing", symbol: "hanger", tone: .granate,
              label: "Tengo el armario lleno y nada que ponerme"),
        .init(id: "forget", symbol: "eye.slash", tone: .lavanda,
              label: "Me olvido de la ropa que tengo al fondo"),
        .init(id: "duplicate", symbol: "square.on.square", tone: .camel,
              label: "Compro cosas parecidas a las que ya tengo"),
        .init(id: "time", symbol: "hourglass", tone: .denim,
              label: "Pierdo tiempo cada mañana"),
        .init(id: "packing", symbol: "suitcase", tone: .salvia,
              label: "Hacer la maleta me estresa"),
        .init(id: "combine", symbol: "puzzlepiece", tone: .terracota,
              label: "No sé combinar lo que tengo"),
    ]

    /// En primera persona a propósito: asentir a "yo hago esto" compromete de
    /// una forma que asentir a "la gente hace esto" no.
    static let statements: [SwipeStatement] = [
        .init(id: "same", text: "Me pongo siempre la misma ropa"),
        .init(id: "bought", text: "He comprado algo y luego he visto que ya tenía uno igual"),
        .init(id: "forgot", text: "Tengo ropa con la etiqueta todavía puesta"),
        .init(id: "morning", text: "Me cambio dos veces antes de salir de casa"),
        .init(id: "suitcase", text: "Meto en la maleta cosas que luego no uso"),
    ]

    /// - Note: testimonios de ejemplo hasta que haya reseñas reales. Publicar
    ///   una app con testimonios inventados presentados como reales es engañoso
    ///   y además está prohibido en la App Store.
    static let testimonials: [Testimonial] = [
        .init(id: "1", initials: "MG", name: "María", tag: "Compra compulsiva",
              text: "Me di cuenta de que tenía cuatro camisas blancas casi iguales. Llevo tres meses sin comprar nada.",
              tone: .granate),
        .init(id: "2", initials: "JL", name: "Javi", tag: "Poco tiempo",
              text: "Dejo los outfits de la semana el domingo. Por la mañana ya no pienso.",
              tone: .denim),
        .init(id: "3", initials: "AR", name: "Ana", tag: "Viaja a menudo",
              text: "Hacer la maleta era lo que peor llevaba. Ahora la preparo en diez minutos.",
              tone: .oliva),
    ]

    static let comparison: [ComparisonRow] = [
        .init(id: "see", label: "Ves todo lo que tienes"),
        .init(id: "combine", label: "Sabes qué combina con qué"),
        .init(id: "repeat", label: "Evitas comprar repetido"),
        .init(id: "plan", label: "Dejas la semana planificada"),
        .init(id: "pack", label: "La maleta, hecha sin pensar"),
    ]
}
