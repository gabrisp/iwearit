import Foundation
import Observation
import SwiftUI
import WKCore
import WKDesign

/// Los pasos del onboarding, en orden.
///
/// La secuencia no es arbitraria: primero aspiración (qué quieres), después
/// dolor (qué te lo impide), después prueba de que a otros les funcionó, y solo
/// entonces la solución. Invertir ese orden convierte el flujo en un folleto.
enum OnboardingStep: Int, CaseIterable, WKFlowStep, Hashable {
    case welcome
    /// v2: las primeras preguntas como conversación. Ver `ConversationStep`.
    case conversation
    case goal
    case pain
    case statements
    case spend
    case wardrobeSize
    case socialProof
    /// v2: el dinero con la rueda de cifras. Ver `RevealStep`.
    case reveal
    case calculating
    case savings
    case comparison
    case photoPermission
    case scanning
    /// "+X prendas, más de N outfits", con las prendas desfilando. Ver
    /// `ScanFoundStep`.
    case scanFound
    case scanReview
    case scanSummary
    case paywall

    var flowDepth: Int { rawValue }

    /// La bienvenida no cuenta para la barra: enseñarla al 0% de 14 pasos
    /// asusta antes de empezar.
    // var progressIndex: Int { max(0, rawValue) }

    /// Dónde va en la barra, contando solo los pasos de su versión.
    func progressIndex(in variant: OnboardingVariant) -> Int {
        OnboardingStep.allCases.filter { !variant.skips($0) && $0.rawValue < rawValue }.count
    }
}

/// **Dos onboardings para comparar**, que se eligen desde Ajustes ("Repetir
/// v1 / v2"). La v1 es la de siempre, paso a paso; la v2 hace las primeras
/// preguntas como conversación y enseña el dinero con la rueda de cifras.
/// Los pasos de las dos conviven: cada versión se salta los de la otra.
enum OnboardingVariant: String, CaseIterable {
    case v1, v2

    static let storageKey = "onboarding.variant"

    static var current: OnboardingVariant {
        OnboardingVariant(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .v2
    }

    func skips(_ step: OnboardingStep) -> Bool {
        switch self {
        // Las frases a deslizar (`StatementsStep`), fuera en las dos por
        // ahora.
        // case .v1: [.conversation, .reveal, .statements].contains(step)
        // case .v2: [.goal, .pain, .spend, .wardrobeSize, .calculating, .savings, .statements].contains(step)
        // Y fuera también, en las dos, "No eres la única" con las
        // valoraciones (`SocialProofStep`), y "+X prendas" como pantalla
        // aparte (`ScanFoundStep`): ahora es el final del propio escaneo, en
        // el mismo lienzo. Ver `ScanningStep`.
        // "Desliza y compara" (`ComparisonStep`), también fuera por ahora.
        case .v1: [.conversation, .reveal, .statements, .socialProof, .scanFound, .comparison].contains(step)
        // En la v2 el dinero va dentro de la conversación: `RevealStep`,
        // fuera.
        // case .v2: [.goal, .pain, .spend, .wardrobeSize, .calculating, .savings, .statements, .socialProof, .scanFound, .comparison].contains(step)
        // Y el permiso de fotos, también dentro de la conversación.
        // case .v2: [.goal, .pain, .spend, .wardrobeSize, .calculating, .savings, .statements, .socialProof, .scanFound, .comparison, .reveal].contains(step)
        // Y el escaneo: también en la conversación.
        // case .v2: [.goal, .pain, .spend, .wardrobeSize, .calculating, .savings, .statements, .socialProof, .scanFound, .comparison, .reveal, .photoPermission].contains(step)
        // Sin la revisión de lo encontrado: "Más adelante podrás revisarlas".
        // Y "Tu armario, ya dentro": lo dice la conversación.
        case .v2: [.goal, .pain, .spend, .wardrobeSize, .calculating, .savings, .statements, .socialProof, .scanFound, .comparison, .reveal, .photoPermission, .scanning, .scanReview, .scanSummary].contains(step)
        }
    }

    /// Los pasos que se ven, para el total de la barra.
    var visibleCount: Int { OnboardingStep.allCases.filter { !skips($0) }.count }
}

/// Estado del onboarding.
///
/// Las respuestas se guardan porque alimentan tres cosas: el cálculo de ahorro,
/// la personalización de la pantalla de solución, y las baldas que tendrá
/// sentido crear después. Preguntar y no usar la respuesta el usuario lo nota.
@MainActor
@Observable
final class OnboardingModel {

    var step: OnboardingStep = OnboardingModel.launchStep

    /// `-onboardingStep scanning` arranca en ese paso, para probar el escaneo
    /// y la revisión sin recorrer las diez pantallas de antes. Solo depuración.
    private static var launchStep: OnboardingStep {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-onboardingStep"),
           arguments.indices.contains(index + 1),
           let step = OnboardingStep.allCases.first(where: { "\($0)" == arguments[index + 1] }) {
            return step
        }
        #endif
        return .welcome
    }

    /// Lo que el escaneo ha encontrado y **todavía no ha guardado**.
    ///
    /// El escaneo recorre la galería entera; decidir qué entra al armario es
    /// del usuario. Hasta ahora se insertaba todo de golpe y el armario nacía
    /// con doscientas prendas que había que borrar a mano una por una.
    var harvest: [GarmentDraft] = []
    private(set) var isGoingBack = false

    // Respuestas
    /// Qué armario: `men` o `women`. Se guarda también en `UserDefaults`
    /// (`onboarding.closet`) para lo que venga después.
    var closetKind: String? {
        didSet { UserDefaults.standard.set(closetKind, forKey: "onboarding.closet") }
    }
    var goal: String?
    var pains: Set<String> = []
    var agreedStatements: Set<String> = []
    /// Euros al mes en ropa.
    var monthlySpend: Double = 60
    /// Prendas que el usuario cree tener.
    var wardrobeSize: Double = 80

    // MARK: - Navegación

    /// La versión de este recorrido. Ver `OnboardingVariant`.
    let variant = OnboardingVariant.current

    func advance() {
        // El siguiente **de esta versión**: los de la otra se saltan.
        var raw = step.rawValue + 1
        while let candidate = OnboardingStep(rawValue: raw), variant.skips(candidate) { raw += 1 }
        guard let next = OnboardingStep(rawValue: raw) else { return }
        move(to: next)
    }

    /// Ir a un paso concreto, con su paso de página.
    func go(to target: OnboardingStep) {
        move(to: target)
    }

    func goBack() {
        var raw = step.rawValue - 1
        while let candidate = OnboardingStep(rawValue: raw), variant.skips(candidate) { raw -= 1 }
        guard let previous = OnboardingStep(rawValue: raw) else { return }
        move(to: previous)
    }

    /// **Lo que hace atrás un paso, si quiere hacer algo suyo**: devuelve
    /// `true` si lo ha hecho. La conversación rebobina. Ver `ConversationStep`.
    var backHandler: (() -> Bool)?

    /// La pantalla que está saliendo, mientras sale. Ver `OnboardingFlow`.
    private(set) var outgoing: OnboardingStep?
    /// De 0 a 1: cuánto ha avanzado el paso de página.
    private(set) var pageProgress: Double = 0

    private func move(to next: OnboardingStep) {
        // Una a la vez: a mitad de un paso de página, otro toque dejaría tres
        // pantallas en el aire.
        guard outgoing == nil, next != step else { return }
        isGoingBack = next.flowDepth < step.flowDepth

        // **A mano y no con `.transition`.** El sistema de transiciones no le
        // aplicaba el efecto a la pantalla que salía —se quedaba a pantalla
        // completa, vacía, tapando el fondo— y la tarjeta que se encogía
        // enseñaba franjas blancas. Así las dos pantallas se pintan a la vez y
        // un solo progreso las mueve a las dos. Ver `OnboardingFlow`.
        //
        // Primero, sin animar: la nueva aparece fuera de la pantalla y la
        // vieja sigue en su sitio. En la vuelta siguiente, a correr.
        outgoing = step
        pageProgress = 0
        step = next
        Task { @MainActor in
            // El cambio en el lienzo: la de antes se disuelve en la primera
            // mitad y las piezas nuevas se posan después. Ver
            // `CanvasPageEffect`.
            // withAnimation(WKPageCardTransition.animation) {
            withAnimation(.easeOut(duration: 0.55)) {
                pageProgress = 1
            } completion: {
                self.outgoing = nil
                self.pageProgress = 0
            }
        }
    }

    // var transition: AnyTransition { .wkSlide(fromLeading: isGoingBack) }
    /// Las pantallas pasan como tarjetas: la que se va encoge y sale hacia un
    /// lado, la nueva entra por el otro y crece.
    func transition(insets: EdgeInsets) -> AnyTransition {
        WKPageCardTransition.transition(
            isGoingBack: isGoingBack, insets: insets, background: WK.Palette.canvas
        )
    }

    // MARK: - El cálculo

    /// Fracción del armario que no se llega a usar.
    ///
    /// Es una estimación, y se presenta como tal. Inventar un porcentaje con
    /// dos decimales y atribuirlo a un estudio que no se ha leído es la forma
    /// más rápida de perder la confianza del usuario el día que lo comprueba.
    static let unwornFraction = 0.7

    /// Precio medio por prenda, deducido de lo que el usuario dice gastar.
    ///
    /// Se deduce en vez de preguntarlo: nadie sabe cuánto le cuesta de media
    /// una prenda, pero todo el mundo tiene una idea de lo que gasta al mes.
    var averageGarmentPrice: Double {
        let yearlySpend = monthlySpend * 12
        // Suponiendo que renueva en torno a un tercio del armario al año.
        let garmentsPerYear = max(1, wardrobeSize / 3)
        return max(12, min(120, yearlySpend / garmentsPerYear))
    }

    /// Dinero parado en ropa que no se usa.
    var idleValue: Double {
        wardrobeSize * Self.unwornFraction * averageGarmentPrice
    }

    /// Ahorro anual si se aprovecha lo que ya hay.
    ///
    /// Un tercio del gasto, no la mitad: prometer que dejará de comprar del
    /// todo no se lo cree nadie, y una cifra que suena exagerada resta en lugar
    /// de sumar.
    var yearlySaving: Double {
        monthlySpend * 12 * 0.33
    }

    /// Combinaciones posibles con lo que ya tiene.
    ///
    /// Un reparto grueso del armario en torso / abajo / calzado. Se topa en 99
    /// porque a partir de ahí el número deja de ser información y pasa a ser
    /// ruido: "muchísimas" y "99+" comunican lo mismo.
    func outfitIdeas(garmentCount: Int) -> Int {
        let tops = max(1, garmentCount / 3)
        let bottoms = max(1, garmentCount / 4)
        let shoes = max(1, garmentCount / 8)
        return min(99, tops * bottoms * shoes)
    }

    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    func money(_ value: Double) -> String {
        Self.currency.string(from: NSNumber(value: value)) ?? "\(Int(value)) €"
    }
}
