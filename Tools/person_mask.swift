// La silueta de la persona de una foto, en blanco sobre negro y del mismo
// tamaño. Para las zonas de prenda del onboarding. Ver
// `Tools/onboarding_read_masks.py`.
//
//     swift Tools/person_mask.swift entrada.png salida.png
import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
guard args.count == 3, let image = NSImage(contentsOfFile: args[1]),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("uso: person_mask entrada salida")
}
let request = VNGeneratePersonSegmentationRequest()
request.qualityLevel = .accurate
let handler = VNImageRequestHandler(cgImage: cg)
try handler.perform([request])
guard let mask = request.results?.first?.pixelBuffer else { fatalError("sin persona") }
var ci = CIImage(cvPixelBuffer: mask)
ci = ci.transformed(by: CGAffineTransform(scaleX: CGFloat(cg.width) / ci.extent.width, y: CGFloat(cg.height) / ci.extent.height))
let context = CIContext()
guard let out = context.createCGImage(ci, from: CGRect(x: 0, y: 0, width: cg.width, height: cg.height)) else { fatalError("sin imagen") }
let rep = NSBitmapImageRep(cgImage: out)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("silueta:", args[2])
