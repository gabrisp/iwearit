import SwiftData
import SwiftUI
import UIKit
import WKCore
import WKDesign

/// Solo existe para una cosa: recibir el aviso de que hay cambios en iCloud.
///
/// `NSPersistentCloudKitContainer` se suscribe él solo a los cambios del otro
/// dispositivo, pero el aviso llega como notificación remota silenciosa y
/// SwiftUI no tiene dónde recogerla. Sin esto, los cambios del iPad no llegan
/// al iPhone hasta que el iPhone se abre — que es justo lo contrario de
/// sincronizar rápido sin hacer polling.
///
/// No hace nada más. Ni pide permiso de notificaciones (estas son silenciosas y
/// no lo necesitan) ni las enseña.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // El contenedor ya está escuchando: lo único que hay que hacer es no
        // morir antes de que termine de importar. `.newData` es lo que le dice
        // al sistema que esta app usa bien sus avisos y que siga mandándolos.
        DiagnosticsLog.record("ICLOUD", "aviso de cambios remotos")
        completion(.newData)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Pasa en el simulador y sin perfil de aprovisionamiento. No es fatal:
        // sin avisos, la sincronización sigue ocurriendo, solo que al abrir la
        // app en vez de al momento.
        DiagnosticsLog.record(
            "ICLOUD",
            "sin avisos remotos: \(error.localizedDescription)",
            isProblem: true
        )
    }
}

@main
struct iWearItApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

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
                // **iCloud que aparece más tarde.**
                //
                // Si al arrancar no había sesión, la app se abrió en local. En
                // cuanto la hay se pregunta, porque encenderla significa volver
                // a abrir el store: se reconstruye el entorno entero —mismo
                // fichero, mismos datos— y la app sigue.
                .alert(
                    "Se ha detectado iCloud",
                    isPresented: Binding(
                        get: { environment.sync.canEnableNow },
                        set: { if !$0 { environment.sync.dismissEnablePrompt() } }
                    )
                ) {
                    Button("Ahora no", role: .cancel) {
                        environment.sync.dismissEnablePrompt()
                    }
                    Button("Sincronizar") {
                        environment = AppEnvironment.live()
                    }
                } message: {
                    Text("Tu armario puede copiarse a tus otros dispositivos. Nada sale de este iPhone hasta que lo actives.")
                }
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
