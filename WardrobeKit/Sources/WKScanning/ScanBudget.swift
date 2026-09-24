import Foundation

/// Cuánto trabajo en paralelo puede soportar el dispositivo **ahora mismo**.
///
/// Escanear miles de fotos con visión es el trabajo más caro que hace la app.
/// A concurrencia fija pasa una de dos cosas: o va lento en un iPhone nuevo, o
/// calienta un iPhone viejo hasta que iOS le baja la frecuencia y acaba yendo
/// más lento **y** gastando más batería.
///
/// Así que la ventana se mide en cada lote en vez de decidirse una vez.
public struct ScanBudget: Sendable, Equatable {
    /// Fotos en vuelo a la vez.
    public let concurrency: Int
    /// Si conviene parar del todo y esperar.
    public let shouldPause: Bool
    public let reason: String?

    /// Memoria por debajo de la cual se baja a una sola foto en vuelo.
    ///
    /// Cada foto en proceso son varios buffers a resolución completa; con poco
    /// margen, cuatro a la vez es exactamente cómo el sistema mata el proceso.
    static let lowMemoryThreshold = 120 * 1024 * 1024

    public static func current(
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState,
        isLowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled,
        availableMemory: Int = Int(os_proc_available_memory())
    ) -> ScanBudget {
        if thermalState == .critical {
            return ScanBudget(
                concurrency: 0, shouldPause: true,
                reason: String(localized: "wkscanning.scanbudget.yourIphoneIsVeryHot", defaultValue: "Your iPhone is very hot. We'll carry on once it cools down.", bundle: .module)
            )
        }
        if isLowPower {
            // Modo de bajo consumo es una petición explícita del usuario, no una
            // condición del sistema: se respeta aunque haya margen de sobra.
            return ScanBudget(concurrency: 1, shouldPause: false, reason: String(localized: "wkscanning.scanbudget.lowPowerMode", defaultValue: "Low Power Mode", bundle: .module))
        }
        if availableMemory > 0, availableMemory < lowMemoryThreshold {
            return ScanBudget(concurrency: 1, shouldPause: false, reason: String(localized: "wkscanning.scanbudget.lowMemoryAvailable", defaultValue: "Low memory available", bundle: .module))
        }

        let concurrency = switch thermalState {
        case .nominal: 4
        case .fair: 3
        case .serious: 1
        default: 1
        }
        return ScanBudget(concurrency: concurrency, shouldPause: false, reason: nil)
    }
}
