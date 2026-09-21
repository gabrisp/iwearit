import CoreGraphics
import SwiftUI
import Testing
import WKCore
@testable import WKCanvas

private func square(at x: Double, _ y: Double, side: Double = 100) -> ItemTransform {
    ItemTransform(x: x, y: y, baseWidth: side, baseHeight: side)
}

@Suite("Matemática del canvas")
struct CanvasMathTests {

    @Test("El ancla central es el propio centro")
    func centreAnchorIsCentre() {
        let transform = square(at: 500, 700)
        let pivot = CanvasMath.anchorInCanvas(of: transform, anchor: .center)

        #expect(abs(pivot.x - 500) < 1e-9)
        #expect(abs(pivot.y - 700) < 1e-9)
    }

    @Test("El ancla en una esquina cae donde toca")
    func cornerAnchor() {
        let transform = square(at: 500, 700, side: 100)
        let pivot = CanvasMath.anchorInCanvas(of: transform, anchor: .topLeading)

        #expect(abs(pivot.x - 450) < 1e-9)
        #expect(abs(pivot.y - 650) < 1e-9)
    }

    /// Lo que hace que la prenda parezca estar bajo los dedos: el punto anclado
    /// **no se mueve** por mucho que escales o gires.
    @Test("El punto anclado no se mueve al escalar")
    func anchorStaysPutWhileScaling() {
        let start = square(at: 500, 700)
        let anchor = UnitPoint.topLeading
        let pivotBefore = CanvasMath.anchorInCanvas(of: start, anchor: anchor)

        let end = CanvasMath.applying(
            scale: 2.5, rotation: 0, drag: .zero, about: anchor, to: start
        )
        let pivotAfter = CanvasMath.anchorInCanvas(of: end, anchor: anchor)

        #expect(abs(pivotAfter.x - pivotBefore.x) < 1e-6)
        #expect(abs(pivotAfter.y - pivotBefore.y) < 1e-6)
        #expect(abs(end.scale - 2.5) < 1e-9)
    }

    @Test("El punto anclado no se mueve al girar")
    func anchorStaysPutWhileRotating() {
        let start = square(at: 420, 610)
        let anchor = UnitPoint(x: 0.2, y: 0.85)
        let pivotBefore = CanvasMath.anchorInCanvas(of: start, anchor: anchor)

        let end = CanvasMath.applying(
            scale: 1, rotation: .pi / 3, drag: .zero, about: anchor, to: start
        )
        let pivotAfter = CanvasMath.anchorInCanvas(of: end, anchor: anchor)

        #expect(abs(pivotAfter.x - pivotBefore.x) < 1e-6)
        #expect(abs(pivotAfter.y - pivotBefore.y) < 1e-6)
    }

    @Test("Arrastrar mueve el centro exactamente lo arrastrado")
    func dragTranslatesExactly() {
        let start = square(at: 500, 700)
        let end = CanvasMath.applying(
            scale: 1, rotation: 0, drag: CGSize(width: -37.5, height: 12.25),
            about: .center, to: start
        )

        #expect(end.x == 462.5)
        #expect(end.y == 712.25)
        #expect(end.rotation == 0, "arrastrar no debe introducir rotación")
    }

    /// El requisito de los 32,56°: la rotación se acumula sin redondear.
    @Test("La rotación se acumula con precisión completa")
    func rotationAccumulatesExactly() {
        let step = 32.56 * .pi / 180
        var transform = square(at: 500, 700)
        transform = CanvasMath.applying(scale: 1, rotation: step, drag: .zero, about: .center, to: transform)

        #expect(transform.rotation.bitPattern == step.bitPattern)
        #expect(abs(transform.rotationDegrees - 32.56) < 1e-9)
    }

    @Test("El punto tocado vuelve al espacio de la prenda")
    func unitPointRoundTrip() {
        let transform = ItemTransform(
            x: 500, y: 700, baseWidth: 200, baseHeight: 300,
            scale: 1.5, rotation: .pi / 5
        )
        let anchor = UnitPoint(x: 0.3, y: 0.7)
        let canvasPoint = CanvasMath.anchorInCanvas(of: transform, anchor: anchor)
        let back = CanvasMath.unitPoint(ofCanvasPoint: canvasPoint, in: transform)

        #expect(abs(back.x - anchor.x) < 1e-9)
        #expect(abs(back.y - anchor.y) < 1e-9)
    }
}
