import Foundation

/// Tabla de colores con nombre.
///
/// - Note: los nombres son **claves de localización**, no texto traducido: la
///   tabla es la misma en todos los idiomas y se traduce al mostrarla.
///
/// - TODO: en F7 cada entrada llevará forma masculina y femenina, para que el
///   nombrado de respaldo pueda concordar ("Cazadora negra" y no "Cazadora
///   negro"). Hoy el nombrado usa la construcción con "en", que evita el
///   problema sin necesitar la tabla completa.
public enum NamedColorTable {

    struct Entry {
        let key: String
        let lab: SIMD3<Double>
    }

    static let entries: [Entry] = [
        ("negro",      0.05, 0.05, 0.06),
        ("gris",       0.52, 0.52, 0.54),
        ("gris claro", 0.78, 0.78, 0.79),
        ("blanco",     0.97, 0.97, 0.96),
        ("crema",      0.93, 0.90, 0.83),
        ("beige",      0.85, 0.78, 0.66),
        ("camel",      0.70, 0.56, 0.36),
        ("marrón",     0.40, 0.28, 0.18),
        ("chocolate",  0.25, 0.16, 0.11),
        ("granate",    0.45, 0.13, 0.16),
        ("rojo",       0.78, 0.15, 0.15),
        ("rosa",       0.92, 0.62, 0.68),
        ("fucsia",     0.82, 0.18, 0.52),
        ("morado",     0.45, 0.22, 0.58),
        ("lila",       0.72, 0.62, 0.82),
        ("azul marino",0.13, 0.18, 0.34),
        ("azul",       0.20, 0.38, 0.68),
        ("celeste",    0.58, 0.76, 0.90),
        ("turquesa",   0.20, 0.68, 0.68),
        ("verde",      0.22, 0.52, 0.30),
        ("oliva",      0.36, 0.38, 0.24),
        ("verde menta",0.62, 0.84, 0.72),
        ("amarillo",   0.94, 0.84, 0.28),
        ("mostaza",    0.78, 0.64, 0.18),
        ("naranja",    0.92, 0.52, 0.20),
        ("teja",       0.72, 0.36, 0.24),
        ("vaquero",    0.34, 0.44, 0.60),
        ("caqui",      0.66, 0.60, 0.44),
    ].map { name, r, g, b in
        Entry(key: name, lab: ColorExtractor.rgbToLab(r, g, b))
    }

    /// Nombre más cercano en Lab.
    ///
    /// Se pondera la luminosidad a la baja (0,6) porque el ojo perdona mejor un
    /// error de claridad que uno de tono: una camiseta azul un poco más oscura
    /// sigue siendo "azul", pero llamarla "verde" es un error que salta.
    public static func closestName(toLab lab: SIMD3<Double>) -> String {
        var best = entries[0]
        var bestDistance = Double.infinity
        for entry in entries {
            let delta = lab - entry.lab
            let distance = 0.6 * delta.x * delta.x + delta.y * delta.y + delta.z * delta.z
            if distance < bestDistance {
                bestDistance = distance
                best = entry
            }
        }
        return best.key
    }
}
