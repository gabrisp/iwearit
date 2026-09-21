#!/usr/bin/env python3
"""Convierte SegFormer-clothes a Core ML.

    Tools/.venv/bin/python Tools/convert_segformer.py [--variant b3|b2] [--size 512]

## Por qué este modelo

`sayeed99/segformer_b3_clothes` declara **MIT** en su model card, así que se
puede publicar en la App Store sin dudas. Es la misma cabeza de 18 clases de
ATR que el B2, con un backbone más grande: acierta más en fotos de calle, que
es donde el B2 se despistaba.

**Por qué ya no es el B2.** `mattmdjaga/segformer_b2_clothes` —el que se usaba
antes— anuncia `license: other` en Hugging Face, no MIT. Este script llegó a
escribir "MIT" en los metadatos del `.mlpackage`, que es exactamente el tipo de
afirmación que no se puede sostener al publicar. Se queda como variante para
comparar, pero con su licencia real.

Los modelos de moda más citados siguen sin servir: DeepFashion2 y ModaNet son
CC BY-NC (no comercial) y Ultralytics/YOLO es AGPL-3.0, que para una app
cerrada exige licencia de pago.

## Qué resuelve

Segmentación **por píxel** con 18 clases del dataset ATR, incluidas clases
explícitas de piel, pelo y cara. Eso es justo lo que el modo degradado no puede
hacer: `GenerateForegroundInstanceMaskRequest` levanta la persona entera como un
solo sujeto, así que devuelve una "prenda" que es una persona.

Las clases de piel y pelo se descartan por construcción, que es lo que evita que
se cuelen caras y brazos en el armario.

## Lo que NO distingue

Chaqueta de camiseta: ambas son `Upper-clothes`. Esa decisión la toma MobileCLIP
sobre el recorte ya hecho.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent
OUTPUT_DIR = ROOT / "build"

# Las 18 clases de ATR, en el orden que produce el modelo.
LABELS = [
    "background", "hat", "hair", "sunglasses", "upper-clothes", "skirt",
    "pants", "dress", "belt", "left-shoe", "right-shoe", "face",
    "left-leg", "right-leg", "left-arm", "right-arm", "bag", "scarf",
]

# Solo modelos con la cabeza de **18 clases de ATR**, que es la que asume
# `ClothesSegmenter.Label` en la app.
#
# `sayeed99/segformer-b3-fashion` no está aquí a propósito: es otro dataset con
# 46 clases y otro orden, así que convertirlo con estas etiquetas produciría un
# `.mlpackage` que dice "pantalón" donde el modelo dice otra cosa. Para usarlo
# habría que reescribir el mapeo de clases del lado de Swift.
REPOS = {
    "b3": ("sayeed99/segformer_b3_clothes", "MIT"),
    "b2": ("mattmdjaga/segformer_b2_clothes", "other (ver model card)"),
}
DEFAULT_VARIANT = "b3"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", default=DEFAULT_VARIANT, choices=sorted(REPOS))
    parser.add_argument("--size", type=int, default=512)
    parser.add_argument(
        "--quantize",
        default="palettize6",
        choices=["none", "fp16", "palettize6", "palettize4"],
        help="palettize6 baja el B3 de ~190 MB a ~45 MB, que es lo que hace que "
             "la descarga sea razonable por Wi-Fi.",
    )
    args = parser.parse_args()

    try:
        import coremltools as ct
        import numpy as np
        import torch
        from transformers import SegformerForSemanticSegmentation
    except ImportError as error:
        sys.exit(f"Falta una dependencia: {error}\nInstala con Tools/.venv/bin/pip install -r Tools/requirements.txt")

    repo, license_name = REPOS[args.variant]
    print(f"Descargando {repo} ({license_name})…")
    model = SegformerForSemanticSegmentation.from_pretrained(repo)
    model.eval()

    size = args.size

    class Wrapped(torch.nn.Module):
        """Devuelve directamente el mapa de clases, a tamaño de entrada.

        El modelo saca logits a 1/4 de resolución. Hacer el `argmax` y el
        reescalado **dentro** del grafo ahorra mover a la app un tensor de
        18 canales en float y reimplementar ahí la misma lógica — que es donde
        aparecen las discrepancias entre lo que valida el script y lo que hace
        el dispositivo.
        """

        def __init__(self, model: torch.nn.Module, size: int) -> None:
            super().__init__()
            self.model = model
            self.size = size

        def forward(self, pixel_values: torch.Tensor) -> torch.Tensor:
            logits = self.model(pixel_values=pixel_values).logits
            upsampled = torch.nn.functional.interpolate(
                logits, size=(self.size, self.size), mode="bilinear", align_corners=False
            )
            return upsampled.argmax(dim=1, keepdim=True).to(torch.float32)

    wrapped = Wrapped(model, size).eval()
    example = torch.rand(1, 3, size, size)

    print("Trazando…")
    with torch.no_grad():
        traced = torch.jit.trace(wrapped, example)

    print("Convirtiendo a Core ML…")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, size, size),
                # Normalización de ImageNet, la misma con la que se entrenó.
                # Va dentro del modelo para que la app no tenga que replicarla:
                # un scale mal puesto degrada la máscara sin dar ningún error.
                scale=1 / (0.226 * 255.0),
                bias=[-0.485 / 0.226, -0.456 / 0.226, -0.406 / 0.226],
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name="classMap")],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16 if args.quantize != "none" else ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.iOS18,
    )

    mlmodel.short_description = "SegFormer clothes segmentation (ATR, 18 clases)"
    mlmodel.input_description["image"] = f"Foto RGB {size}x{size}"
    mlmodel.output_description["classMap"] = "Índice de clase por píxel"
    mlmodel.user_defined_metadata["labels"] = json.dumps(LABELS)
    mlmodel.user_defined_metadata["license"] = license_name
    mlmodel.user_defined_metadata["source"] = repo

    if args.quantize.startswith("palettize"):
        bits = int(args.quantize[-1])
        print(f"Palettizando a {bits} bits…")
        from coremltools.optimize.coreml import (
            OpPalettizerConfig, OptimizationConfig, palettize_weights,
        )

        config = OptimizationConfig(
            global_config=OpPalettizerConfig(mode="kmeans", nbits=bits)
        )
        mlmodel = palettize_weights(mlmodel, config)

    OUTPUT_DIR.mkdir(exist_ok=True)
    package = OUTPUT_DIR / f"ClothesSegmenter-{args.variant}-{size}.mlpackage"
    if package.exists():
        shutil.rmtree(package)
    mlmodel.save(str(package))

    size_mb = sum(f.stat().st_size for f in package.rglob("*") if f.is_file()) / 1024 / 1024
    print(f"\nGuardado: {package}")
    print(f"Tamaño:   {size_mb:.1f} MB")
    print(f"Clases:   {len(LABELS)}")
    print(f"Licencia: {license_name}")
    if size_mb > 28:
        print("\nPor encima de 28 MB: upload_model.py lo subirá partido en trozos.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
