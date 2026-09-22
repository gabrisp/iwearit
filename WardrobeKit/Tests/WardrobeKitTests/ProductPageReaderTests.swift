import Foundation
import Testing
import WKCore
@testable import WKVision

@Suite("Ficha del producto")
struct ProductPageReaderTests {

    private func line(_ text: String, height: Double = 0.02) -> ProductPageReader.Line {
        .init(text: text, confidence: 0.95, height: height)
    }

    @Test func webCaptureGivesTitleTypeMaterialAndBrand() {
        let page = ProductPageReader.parse([
            line("ZARA", height: 0.03),
            line("CAMISETA OVERSIZE ALGODÓN", height: 0.035),
            line("29,95 EUR"),
            line("AÑADIR A LA CESTA"),
            line("Guía de tallas"),
        ])
        #expect(page.title == "Camiseta oversize algodón")
        #expect(page.type == "Camiseta")
        #expect(page.kind == .upperBody)
        #expect(page.material == "Algodón")
        #expect(page.brandEvidence.first?.brand == "Zara")
    }

    @Test func englishTitlesMapToTheVocabulary() {
        #expect(ProductPageReader.type(in: "Relaxed Fit Jeans") == "Vaqueros")
        #expect(ProductPageReader.type(in: "Hooded Sweatshirt") == "Sudadera")
        #expect(ProductPageReader.type(in: "Cotton T-Shirt") == "Camiseta")
        #expect(ProductPageReader.type(in: "Oxford Shirt") == "Camisa")
        #expect(ProductPageReader.type(in: "Merino wool sweater") == "Jersey")
        #expect(ProductPageReader.material(in: "Merino wool sweater") == "Lana")
    }

    @Test func wholeWordsOnly() {
        // "tee" dentro de "steel" o "cap" dentro de "capri" no son prendas.
        #expect(ProductPageReader.type(in: "Steel grey") == nil)
        #expect(ProductPageReader.type(in: "Pantalón capri") == "De vestir")
    }

    @Test func shopButtonsAreNotTitles() {
        let page = ProductPageReader.parse([
            line("Add to bag", height: 0.05),
            line("Linen shirt", height: 0.03),
        ])
        #expect(page.title == "Linen shirt")
        #expect(page.type == "Camisa")
    }

    @Test func pricesAreStrippedFromTheTitle() {
        #expect(ProductPageReader.cleanTitle("Vestido midi satinado 49,99 €") == "Vestido midi satinado")
        #expect(ProductPageReader.cleanTitle("€35 Polo piqué") == "Polo piqué")
    }
}

@Suite("Ficha del producto: solo el nombre")
struct ProductPageReaderNameOnlyTests {
    private func line(_ text: String, height: Double = 0.03) -> ProductPageReader.Line {
        .init(text: text, confidence: 0.95, height: height)
    }

    @Test func aSingleLineWithTheTypeIsTheName() {
        let page = ProductPageReader.parse([line("Sudadera capucha básica")])
        #expect(page.title == "Sudadera capucha básica")
        #expect(page.type == "Sudadera")
    }

    @Test func onAProductShotAnUntypedLineIsStillTheName() {
        let page = ProductPageReader.parse([line("Air Force 1 '07")], isProductShot: true)
        #expect(page.title == "Air Force 1 '07")
        #expect(page.type == nil)
    }

    @Test func onAStreetPhotoAnUntypedSignIsNotAName() {
        let page = ProductPageReader.parse([line("FARMACIA")], isProductShot: false)
        #expect(page.title == nil)
    }

    @Test func theBrandAloneIsNotTheName() {
        let page = ProductPageReader.parse([line("NIKE")], isProductShot: true)
        #expect(page.title == nil)
        #expect(page.brandEvidence.first?.brand == "Nike")
    }
}
