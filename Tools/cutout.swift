// Recorta a las personas de una foto y deja el fondo transparente, **sin
// recortar el lienzo**: el antes y el después tienen que seguir alineados.
//
//     swift Tools/cutout.swift entrada.png salida.png
import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
guard args.count == 3, let image = NSImage(contentsOfFile: args[1]),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("uso: cutout entrada salida")
}
let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(cgImage: cg)
try handler.perform([request])
guard let result = request.results?.first else { fatalError("no hay sujeto") }
let buffer = try result.generateMaskedImage(
    ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false
)
let ci = CIImage(cvPixelBuffer: buffer)
let context = CIContext()
guard let out = context.createCGImage(ci, from: ci.extent) else { fatalError("sin imagen") }
let rep = NSBitmapImageRep(cgImage: out)
try rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("recortado:", args[2], "· \(result.allInstances.count) sujeto(s)")
