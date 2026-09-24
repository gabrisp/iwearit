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
    defaultLocalization: "en",
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
        .target(name: "WKCore", resources: [.process("Resources")]),
        .target(name: "WKDesign", resources: [.process("Resources")]),
        .target(name: "WKPersistence", dependencies: ["WKCore", "WKDesign"], resources: [.process("Resources")]),
        .target(name: "WKServices", dependencies: ["WKCore"], resources: [.process("Resources")]),
        .target(name: "WKVision", dependencies: ["WKCore"], resources: [.process("Resources")]),
        .target(name: "WKCanvas", dependencies: ["WKCore", "WKDesign", "WKPersistence"], resources: [.process("Resources")]),
        // La capa que compone: escanear la galería necesita PhotoKit
        // (WKServices), el pipeline (WKVision) y dónde guardar (WKPersistence).
        // Tiene su propio target para no obligar a ninguno de los tres a
        // conocer a los otros dos.
        .target(
            name: "WKScanning",
            dependencies: ["WKCore", "WKVision", "WKPersistence", "WKServices"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "WardrobeKitTests",
            dependencies: ["WKCore", "WKPersistence", "WKCanvas", "WKVision", "WKScanning"]
        ),
    ]
)
