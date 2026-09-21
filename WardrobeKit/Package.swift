// swift-tools-version: 6.0
import PackageDescription

/// Capas de `iWearIt`. El grafo de dependencias es unidireccional y se verifica al compilar:
///
///     WKCore  ←  WKPersistence / WKServices / WKVision
///     WKCore  ←  WKCanvas  →  WKDesign
///
/// `WKCore` y `WKDesign` no dependen de nadie. Solo `WKDesign` y `WKCanvas` importan SwiftUI.
let package = Package(
    name: "WardrobeKit",
    defaultLocalization: "es",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "WKCore", targets: ["WKCore"]),
        .library(name: "WKDesign", targets: ["WKDesign"]),
        .library(name: "WKPersistence", targets: ["WKPersistence"]),
        .library(name: "WKServices", targets: ["WKServices"]),
        .library(name: "WKVision", targets: ["WKVision"]),
        .library(name: "WKCanvas", targets: ["WKCanvas"]),
        .library(name: "WKScanning", targets: ["WKScanning"]),
    ],
    targets: [
        .target(name: "WKCore"),
        .target(name: "WKDesign"),
        .target(name: "WKPersistence", dependencies: ["WKCore", "WKDesign"]),
        .target(name: "WKServices", dependencies: ["WKCore"]),
        .target(name: "WKVision", dependencies: ["WKCore"]),
        .target(name: "WKCanvas", dependencies: ["WKCore", "WKDesign", "WKPersistence"]),
        // La capa que compone: escanear la galería necesita PhotoKit
        // (WKServices), el pipeline (WKVision) y dónde guardar (WKPersistence).
        // Tiene su propio target para no obligar a ninguno de los tres a
        // conocer a los otros dos.
        .target(
            name: "WKScanning",
            dependencies: ["WKCore", "WKVision", "WKPersistence", "WKServices"]
        ),
        .testTarget(
            name: "WardrobeKitTests",
            dependencies: ["WKCore", "WKPersistence", "WKCanvas", "WKVision", "WKScanning"]
        ),
    ]
)
