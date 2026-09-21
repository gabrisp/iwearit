#!/usr/bin/env python3
"""Pasa un segmentador ya convertido por fotos de verdad y enseña qué ve.

    Tools/.venv/bin/python Tools/validate_model.py \
        --package Tools/build/ClothesSegmenter-b3-512.mlpackage \
        --photos ~/Desktop/pruebas

Con `--compare` corre dos modelos sobre las mismas fotos y los pone uno al lado
del otro, que es la única forma honesta de decir que uno es mejor que el otro.

## Para qué sirve

La app no puede decirte por qué no detectó nada: para cuando el error llega a
la pantalla, el mapa de clases ya no existe. Esto lo vuelca a PNG en color, con
el porcentaje de píxeles de cada clase, así que se ve de un vistazo si el
problema es que el modelo no reconoce la prenda o que lo que falla viene
después — el recorte, el separador de instancias, la normalización.

**Ojo con la orientación.** Aquí se aplica el EXIF antes de nada, igual que hace
`UprightImage` en la app. Una foto de iPhone en vertical se guarda apaisada con
una etiqueta de rotación, y sin aplicarla el modelo ve a una persona tumbada —
que es exactamente el fallo que tuvimos.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
import time

SUFFIXES = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp"}

# Un color por clase de ATR. Elegidos para que las clases que se confunden
# entre sí —piel contra camiseta, falda contra pantalón— no caigan en tonos
# parecidos: si el mapa hay que leerlo a ojo, el color es la mitad del trabajo.
PALETTE = [
    (0, 0, 0),         # background
    (255, 0, 0),       # hat
    (120, 60, 30),     # hair
    (255, 0, 255),     # sunglasses
    (0, 160, 255),     # upper-clothes
    (255, 200, 0),     # skirt
    (0, 200, 60),      # pants
    (180, 0, 255),     # dress
    (255, 120, 0),     # belt
    (0, 255, 200),     # left-shoe
    (0, 200, 255),     # right-shoe
    (255, 190, 170),   # face
    (200, 150, 130),   # left-leg
    (170, 125, 105),   # right-leg
    (220, 170, 150),   # left-arm
    (190, 140, 120),   # right-arm
    (255, 255, 0),     # bag
    (140, 140, 255),   # scarf
]


def load_labels(package: pathlib.Path) -> list[str]:
    try:
        import coremltools as ct

        model = ct.models.MLModel(str(package), skip_model_load=True)
        labels = json.loads(model.user_defined_metadata.get("labels", "[]"))
        if labels:
            return labels
    except Exception:  # noqa: BLE001
        pass
    return [str(index) for index in range(len(PALETTE))]


def upright(image):
    """Aplica la orientación EXIF, como hace la app antes de segmentar."""
    from PIL import ImageOps

    return ImageOps.exif_transpose(image).convert("RGB")


def colorize(class_map, size):
    import numpy as np
    from PIL import Image

    lut = np.array(PALETTE, dtype="uint8")
    indices = np.clip(class_map.astype("int32"), 0, len(PALETTE) - 1)
    return Image.fromarray(lut[indices]).resize(size, Image.NEAREST)


def run(model, image, side: int):
    import numpy as np

    resized = image.resize((side, side))
    start = time.time()
    output = model.predict({"image": resized})
    elapsed = (time.time() - start) * 1000
    array = np.asarray(output["classMap"]).squeeze().astype("int32")
    return array, elapsed


def summarize(array, labels) -> list[tuple[str, float]]:
    import numpy as np

    total = array.size
    values, counts = np.unique(array, return_counts=True)
    rows = [
        (labels[value] if value < len(labels) else str(value), count / total)
        for value, count in zip(values, counts)
    ]
    # Sin el fondo: ocupa siempre la mayoría y no dice nada.
    rows = [row for row in rows if row[0] != "background"]
    return sorted(rows, key=lambda row: -row[1])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", required=True, type=pathlib.Path)
    parser.add_argument("--compare", type=pathlib.Path,
                        help="Otro .mlpackage para poner al lado del primero.")
    parser.add_argument("--photos", required=True, type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path, default=pathlib.Path("Tools/build/validation"))
    parser.add_argument("--size", type=int, default=512)
    args = parser.parse_args()

    try:
        import coremltools as ct
        from PIL import Image
    except ImportError as error:
        sys.exit(f"Falta una dependencia: {error}")

    photos = sorted(
        path for path in args.photos.rglob("*")
        if path.suffix.lower() in SUFFIXES
    )
    if not photos:
        sys.exit(f"No hay fotos en {args.photos}")

    models = [(args.package.stem, ct.models.MLModel(str(args.package)), load_labels(args.package))]
    if args.compare:
        models.append(
            (args.compare.stem, ct.models.MLModel(str(args.compare)), load_labels(args.compare))
        )

    args.out.mkdir(parents=True, exist_ok=True)
    timings: dict[str, list[float]] = {name: [] for name, _, _ in models}

    for photo in photos:
        try:
            image = upright(Image.open(photo))
        except Exception as error:  # noqa: BLE001
            print(f"{photo.name}: no se pudo abrir ({error})")
            continue

        print(f"\n{photo.name}  {image.width}x{image.height}")
        panels = [image.resize((args.size, args.size))]

        for name, model, labels in models:
            array, elapsed = run(model, image, args.size)
            timings[name].append(elapsed)
            rows = summarize(array, labels)
            detail = ", ".join(f"{label} {share * 100:.1f}%" for label, share in rows[:6])
            print(f"  {name}: {elapsed:.0f} ms — {detail or 'NADA (solo fondo)'}")
            panels.append(colorize(array, (args.size, args.size)))

        sheet = Image.new("RGB", (args.size * len(panels), args.size))
        for index, panel in enumerate(panels):
            sheet.paste(panel, (index * args.size, 0))
        sheet.save(args.out / f"{photo.stem}.png")

    print(f"\nMapas en {args.out}")
    for name, values in timings.items():
        if values:
            print(f"{name}: {sum(values) / len(values):.0f} ms de media sobre {len(values)} fotos")
    print("\nOjo: en el Mac corre en CPU/GPU. La latencia del iPhone con ANE es otra.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
