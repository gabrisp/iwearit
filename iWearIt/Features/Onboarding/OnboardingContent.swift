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

    /// Qué armario es el tuyo.
    static let closets: [OnboardingOption] = [
        .init(id: "men", symbol: "figure.stand", tone: .denim,
              label: String(localized: "chat.closet.men", defaultValue: "Men's")),
        .init(id: "women", symbol: "figure.stand.dress", tone: .granate,
              label: String(localized: "chat.closet.women", defaultValue: "Women's")),
    ]

    static let goals: [OnboardingOption] = [
        .init(id: "faster", symbol: "timer", tone: .denim,
              label: String(localized: "onboarding.onboardingcontent.getDressedFaster", defaultValue: "Get dressed faster"),
              detail: String(localized: "onboarding.onboardingcontent.stopDecidingInFrontOf", defaultValue: "Stop deciding in front of the closet")),
        .init(id: "save", symbol: "banknote", tone: .oliva,
              label: String(localized: "onboarding.onboardingcontent.stopOverbuying", defaultValue: "Stop overbuying"),
              detail: String(localized: "onboarding.onboardingcontent.makeTheMostOfWhat", defaultValue: "Make the most of what I have")),
        .init(id: "see", symbol: "eye", tone: .camel,
              label: String(localized: "onboarding.onboardingcontent.seeEverythingIOwn", defaultValue: "See everything I own"),
              detail: String(localized: "onboarding.onboardingcontent.withoutEmptyingTheDrawers", defaultValue: "Without emptying the drawers")),
        .init(id: "combine", symbol: "paintpalette", tone: .granate,
              label: String(localized: "onboarding.onboardingcontent.matchBetter", defaultValue: "Match better"),
              detail: String(localized: "onboarding.onboardingcontent.getTheMostOutOf", defaultValue: "Get the most out of every piece")),
        .init(id: "travel", symbol: "suitcase.rolling", tone: .salvia,
              label: String(localized: "onboarding.onboardingcontent.planTripsStressFree", defaultValue: "Plan trips stress-free")),
    ]

    static let pains: [OnboardingOption] = [
        .init(id: "nothing", symbol: "hanger", tone: .granate,
              label: String(localized: "onboarding.onboardingcontent.myClosetIsFullAnd", defaultValue: "My closet is full and I have nothing to wear")),
        .init(id: "forget", symbol: "eye.slash", tone: .lavanda,
              label: String(localized: "onboarding.onboardingcontent.iForgetTheClothesAt", defaultValue: "I forget the clothes at the back")),
        .init(id: "duplicate", symbol: "square.on.square", tone: .camel,
              label: String(localized: "onboarding.onboardingcontent.iBuyThingsSimilarTo", defaultValue: "I buy things similar to what I already have")),
        .init(id: "time", symbol: "hourglass", tone: .denim,
              label: String(localized: "onboarding.onboardingcontent.iWasteTimeEveryMorning", defaultValue: "I waste time every morning")),
        .init(id: "packing", symbol: "suitcase", tone: .salvia,
              label: String(localized: "onboarding.onboardingcontent.packingStressesMeOut", defaultValue: "Packing stresses me out")),
        .init(id: "combine", symbol: "puzzlepiece", tone: .terracota,
              label: String(localized: "onboarding.onboardingcontent.iDonTKnowHow", defaultValue: "I don't know how to combine what I have")),
    ]

    /// En primera persona a propósito: asentir a "yo hago esto" compromete de
    /// una forma que asentir a "la gente hace esto" no.
    static let statements: [SwipeStatement] = [
        .init(id: "same", text: String(localized: "onboarding.onboardingcontent.iAlwaysWearTheSame", defaultValue: "I always wear the same clothes"), symbol: "arrow.triangle.2.circlepath"),
        .init(id: "bought", text: String(localized: "onboarding.onboardingcontent.iBoughtSomethingAndThen", defaultValue: "I bought something and then realised I already had one just like it"), symbol: "bag"),
        .init(id: "forgot", text: String(localized: "onboarding.onboardingcontent.iHaveClothesWithThe", defaultValue: "I have clothes with the tag still on"), symbol: "tag"),
        .init(id: "morning", text: String(localized: "onboarding.onboardingcontent.iChangeTwiceBeforeLeaving", defaultValue: "I change twice before leaving the house"), symbol: "arrow.uturn.backward"),
        .init(id: "suitcase", text: String(localized: "onboarding.onboardingcontent.iPackThingsINever", defaultValue: "I pack things I never end up wearing"), symbol: "suitcase"),
    ]

    /// - Note: testimonios de ejemplo hasta que haya reseñas reales. Publicar
    ///   una app con testimonios inventados presentados como reales es engañoso
    ///   y además está prohibido en la App Store.
    static let testimonials: [Testimonial] = [
        .init(id: "1", initials: "MG", name: String(localized: "onboarding.onboardingcontent.marA", defaultValue: "María"), tag: String(localized: "onboarding.onboardingcontent.impulseBuyer", defaultValue: "Impulse buyer"),
              text: String(localized: "onboarding.onboardingcontent.iRealisedIHadFour", defaultValue: "I realised I had four almost identical white shirts. I haven't bought anything in three months."),
              tone: .granate),
        .init(id: "2", initials: "JL", name: String(localized: "onboarding.onboardingcontent.javi", defaultValue: "Javi"), tag: String(localized: "onboarding.onboardingcontent.shortOnTime", defaultValue: "Short on time"),
              text: String(localized: "onboarding.onboardingcontent.iPlanTheWeekS", defaultValue: "I plan the week's outfits on Sunday. In the morning I don't have to think."),
              tone: .denim),
        .init(id: "3", initials: "AR", name: String(localized: "onboarding.onboardingcontent.ana", defaultValue: "Ana"), tag: String(localized: "onboarding.onboardingcontent.travelsOften", defaultValue: "Travels often"),
              text: String(localized: "onboarding.onboardingcontent.packingWasWhatIHated", defaultValue: "Packing was what I hated most. Now I do it in ten minutes."),
              tone: .oliva),
    ]

    /// La comparativa del deslizador: lo mismo dicho con y sin la app, en el
    /// mismo orden para que cada fila se transforme en su pareja.
    static let comparisonPairs: [ComparisonPair] = [
        .init(id: "see", symbol: "eye", tone: .camel,
              with: String(localized: "onboarding.onboardingcontent.youSeeEverythingYouOwn", defaultValue: "You see everything you own"), without: String(localized: "onboarding.onboardingcontent.theBackOfTheCloset", defaultValue: "The back of the closet doesn't exist")),
        .init(id: "combine", symbol: "paintpalette", tone: .granate,
              with: String(localized: "onboarding.onboardingcontent.youKnowWhatGoesWith", defaultValue: "You know what goes with what"), without: String(localized: "onboarding.onboardingcontent.alwaysTheSameThreeCombinations", defaultValue: "Always the same three combinations")),
        .init(id: "repeat", symbol: "square.on.square", tone: .denim,
              with: String(localized: "onboarding.onboardingcontent.youStopBuyingDuplicates", defaultValue: "You stop buying duplicates"), without: String(localized: "onboarding.onboardingcontent.anotherAlmostIdenticalWhiteShirt", defaultValue: "Another almost identical white shirt")),
        .init(id: "plan", symbol: "calendar", tone: .oliva,
              with: String(localized: "onboarding.onboardingcontent.theWeekAlreadyPlanned", defaultValue: "The week, already planned"), without: String(localized: "onboarding.onboardingcontent.decidingEveryMorningInA", defaultValue: "Deciding every morning in a rush")),
        .init(id: "pack", symbol: "suitcase", tone: .salvia,
              with: String(localized: "onboarding.onboardingcontent.theSuitcasePackedWithoutThinking", defaultValue: "The suitcase, packed without thinking"), without: String(localized: "onboarding.onboardingcontent.aSuitcaseFullOfThings", defaultValue: "A suitcase full of things you don't use")),
    ]

    static let comparison: [ComparisonRow] = [
        .init(id: "see", label: String(localized: "onboarding.onboardingcontent.youSeeEverythingYouOwn", defaultValue: "You see everything you own")),
        .init(id: "combine", label: String(localized: "onboarding.onboardingcontent.youKnowWhatGoesWith", defaultValue: "You know what goes with what")),
        .init(id: "repeat", label: String(localized: "onboarding.onboardingcontent.youAvoidBuyingDuplicates", defaultValue: "You avoid buying duplicates")),
        .init(id: "plan", label: String(localized: "onboarding.onboardingcontent.yourWeekIsPlanned", defaultValue: "Your week is planned")),
        .init(id: "pack", label: String(localized: "onboarding.onboardingcontent.theSuitcasePackedWithoutThinking", defaultValue: "The suitcase, packed without thinking")),
    ]
}
