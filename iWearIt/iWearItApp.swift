import SwiftData
import SwiftUI
import WKDesign

@main
struct iWearItApp: App {
    init() {
        // Antes de que se dibuje nada: una vista construida antes del registro
        // se queda con la fuente del sistema hasta que se reevalúe.
        WKFonts.register()
    }

    /// Composition root. Es lo único que sabe qué implementación concreta de
    /// cada servicio se está usando; nada más en la app lo sabe.
    @State private var environment = AppEnvironment.live()

    /// Los avisos viven en la raíz: una hoja que se cierra al guardar no puede
    /// enseñar su propia confirmación, porque desaparece antes de que se lea.
    @State private var toasts = WKToastCenter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .modelContainer(environment.container)
                .environment(toasts)
                .wkToastLayer(toasts)
                .task { await environment.bootstrap() }
                #if DEBUG
                // `probe-toast` enseña un aviso al arrancar, para poder
                // capturarlo sin tener que recorrer una importación entera.
                .task {
                    guard ProcessInfo.processInfo.arguments.contains("probe-toast") else { return }
                    try? await Task.sleep(for: .seconds(2))
                    toasts.show(WKToast("Prenda guardada"))
                }
                #endif
        }
    }
}

/// Raíz de la jerarquía.
///
/// En Debug acepta el argumento `gallery` para arrancar directamente en la
/// galería de modificadores adaptativos, lo que permite capturar pantalla de
/// las dos ramas (iOS 18 / iOS 26) sin navegar a mano.
private struct RootView: View {
    /// Si el onboarding ya se completó.
    ///
    /// En `AppStorage` y no en SwiftData a propósito: es una preferencia del
    /// dispositivo, no un dato del armario, y tiene que poder leerse antes de
    /// que el contenedor esté abierto.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("onboarding") {
            // Fuerza el onboarding aunque ya esté hecho, para poder revisarlo
            // sin borrar la app.
            OnboardingFlow { hasCompletedOnboarding = true }
        } else if ProcessInfo.processInfo.arguments.contains("gallery") {
            NavigationStack {
                AdaptiveGallery()
                    .navigationTitle("Adaptativos")
                    .navigationBarTitleDisplayMode(.inline)
            }
        } else if hasCompletedOnboarding {
            RootTabView()
        } else {
            OnboardingFlow { hasCompletedOnboarding = true }
        }
        #else
        if hasCompletedOnboarding {
            RootTabView()
        } else {
            OnboardingFlow { hasCompletedOnboarding = true }
        }
        #endif
    }
}
