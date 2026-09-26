"""Genera las imágenes de catálogo del onboarding: una hoja con doce prendas
—que se recortan una a una— y un selfie de espejo para enseñar cómo se leen
las prendas de una foto. Ver `ConversationStep` (la prueba social y el
escaneo explicado por pasos).

    set -a; . Tools/.env; set +a; Tools/.venv/bin/python Tools/generate_onboarding_catalog.py

Deja en el catálogo `OnboardingGarment01`…`12` (recortadas, fondo
transparente) y `OnboardingSelfie` (la foto tal cual).
"""
import base64, json, os, pathlib, subprocess, ssl, urllib.request

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

key = os.environ["OPENROUTER_API_KEY"]
ctx = ssl.create_default_context()
try:
    import certifi; ctx = ssl.create_default_context(cafile=certifi.where())
except Exception:
    pass

ROOT = pathlib.Path(__file__).resolve().parent
ASSETS = ROOT.parent / "iWearIt" / "Assets.xcassets"
TMP = pathlib.Path("/tmp/snazzy-catalog"); TMP.mkdir(exist_ok=True)


def call(prompt, out, aspect):
    body = {
        "model": "google/gemini-3.1-flash-image",
        "modalities": ["image", "text"],
        "image_config": {"aspect_ratio": aspect},
        "messages": [{"role": "user", "content": [{"type": "text", "text": prompt}]}],
    }
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions", data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json", "User-Agent": "snazzy-tools"},
    )
    with urllib.request.urlopen(req, timeout=240, context=ctx) as r:
        d = json.load(r)
    url = d["choices"][0]["message"]["images"][0]["image_url"]["url"]
    out.write_bytes(base64.b64decode(url.split(",", 1)[1]))
    print(out, out.stat().st_size // 1024, "KB")


SHEET = """Fotografía de producto de catálogo, vista cenital (flat lay), sobre fondo BLANCO PURO y liso (#FFFFFF), sin sombras, sin textura, sin texto, sin logotipos, sin maniquí ni personas.
DOCE prendas SEPARADAS en una rejilla de 4 columnas por 3 filas, con MUCHO espacio en blanco entre cada una: ninguna se toca ni se solapa, cada una entera dentro de su hueco, del mismo tamaño aparente.
Fila 1: camisa de manga corta de cuello abierto a rayas azul claro y blancas; camiseta de tirantes blanca de canalé; camisa oxford de manga larga a rayas grises finas; chaquetón cruzado largo azul marino.
Fila 2: bermudas chinas azul marino; pantalón de pinzas negro de caída recta; vaquero recto de lavado claro; jersey gris de punto con media cremallera.
Fila 3: zapatillas deportivas grises voluminosas (el par, juntas); zapatos derby negros de piel con suela gruesa (el par, juntos); gorra de béisbol verde botella; bolso bandolera pequeño verde oliva.
Luz suave uniforme, colores fieles, prendas planchadas, estilo minimalista y actual."""

SELFIE = """Foto REALISTA hecha con un iPhone: selfie en el espejo de cuerpo entero de un chico de unos 25 años en el recibidor luminoso de un piso (puerta blanca a un lado, suelo de madera, una planta y una lámpara de mimbre al fondo). Sostiene el móvil a la altura de la cara, que se ve de medio lado. De CUERPO ENTERO, de la cabeza a los pies, centrado.
Lleva: camisa de manga corta de cuello abierto a rayas azul claro y blancas, abierta, sobre una camiseta de tirantes blanca; bermudas chinas azul marino; zapatillas deportivas grises voluminosas.
Luz natural, colores naturales, sin texto ni marcas. Encuadre vertical."""


def install(name, png_path):
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{name}.png").write_bytes(pathlib.Path(png_path).read_bytes())
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2))
    print(f"  {name} ✓")


def split_garments(cutout_png, expected=12):
    """Separa las prendas de la hoja recortada: cada mancha opaca es una."""
    image = Image.open(cutout_png).convert("RGBA")
    alpha = np.array(image)[:, :, 3]
    solid = alpha > 40
    # Une huecos pequeños dentro de una prenda (los ojales de un zapato, el
    # hueco de una gorra) para que no salgan en trozos.
    solid = ndimage.binary_closing(solid, iterations=6)
    labels, count = ndimage.label(solid)
    sizes = ndimage.sum(solid, labels, range(1, count + 1))
    keep = sorted(range(1, count + 1), key=lambda i: -sizes[i - 1])[:expected]
    boxes = []
    for label in keep:
        ys, xs = np.where(labels == label)
        boxes.append((label, xs.min(), ys.min(), xs.max(), ys.max()))
    # En orden de lectura: por filas, y en cada fila de izquierda a derecha.
    height = alpha.shape[0]
    boxes.sort(key=lambda b: (round(((b[2] + b[4]) / 2) / (height / 3)), (b[1] + b[3]) / 2))
    out = []
    for index, (label, x0, y0, x1, y1) in enumerate(boxes, start=1):
        pad = 12
        x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
        x1, y1 = min(alpha.shape[1], x1 + pad), min(height, y1 + pad)
        piece = image.crop((x0, y0, x1, y1))
        # Solo esta prenda: lo de otras que entre en el recorte, fuera.
        own = (labels[y0:y1, x0:x1] == label)
        own = ndimage.binary_dilation(own, iterations=3)
        mask = Image.fromarray((own * 255).astype("uint8")).filter(ImageFilter.GaussianBlur(1))
        channels = piece.split()
        piece = Image.merge("RGBA", (*channels[:3], Image.fromarray(np.minimum(np.array(channels[3]), np.array(mask)))))
        path = TMP / f"garment{index:02d}.png"
        piece.save(path)
        out.append(path)
    print(f"{len(out)} prendas separadas")
    return out


def cut_cells(sheet_png, columns=4, rows=3):
    sheet = Image.open(sheet_png).convert("RGB")
    width, height = sheet.size
    out = []
    for row in range(rows):
        for column in range(columns):
            index = row * columns + column + 1
            box = (column * width // columns, row * height // rows,
                   (column + 1) * width // columns, (row + 1) * height // rows)
            cell = TMP / f"cell{index:02d}.png"
            cut = TMP / f"cell{index:02d}-cut.png"
            sheet.crop(box).save(cell)
            subprocess.run(["swift", str(ROOT / "cutout.swift"), str(cell), str(cut)], check=True,
                           stdout=subprocess.DEVNULL)
            piece = Image.open(cut).convert("RGBA")
            bbox = piece.getchannel("A").point(lambda a: 255 if a > 20 else 0).getbbox()
            if bbox:
                pad = 8
                piece = piece.crop((max(0, bbox[0] - pad), max(0, bbox[1] - pad),
                                    min(piece.width, bbox[2] + pad), min(piece.height, bbox[3] + pad)))
            path = TMP / f"garment{index:02d}.png"
            piece.save(path)
            out.append(path)
    print(f"{len(out)} prendas recortadas")
    return out


SHEET_WOMEN = """Fotografía de producto de catálogo de moda de MUJER, vista cenital (flat lay), sobre fondo BLANCO PURO y liso (#FFFFFF), sin sombras, sin textura, sin texto, sin logotipos, sin maniquí ni personas.
DOCE prendas SEPARADAS en una rejilla de 4 columnas por 3 filas, con MUCHO espacio en blanco entre cada una: ninguna se toca ni se solapa, cada una entera dentro de su hueco, del mismo tamaño aparente.
Fila 1: camisa de mujer de manga larga a rayas azules y blancas; top de tirantes finos blanco de canalé; camisa blanca oversize de popelín; blazer de mujer color camel.
Fila 2: falda midi plisada negra; pantalón de pinzas gris claro de pierna recta; vaquero recto de lavado claro; jersey de punto color crema.
Fila 3: zapatillas blancas de piel minimalistas (el par, juntas); mocasines negros de piel (el par, juntos); gafas de sol de pasta negras; bolso de hombro pequeño de piel negro.
Luz suave uniforme, colores fieles, prendas planchadas, estilo minimalista y actual."""


def women():
    """Las doce de mujer, en los mismos huecos que las de hombre:
    `OnboardingWomanGarment01`…`12`."""
    sheet = TMP / "sheet-women.png"
    if not sheet.exists():
        call(SHEET_WOMEN, sheet, "4:3")
    for index, path in enumerate(cut_cells(sheet), start=1):
        install(f"OnboardingWomanGarment{index:02d}", path)


if __name__ == "__main__" and "--women" in __import__("sys").argv:
    women()
    raise SystemExit(0)

if __name__ == "__main__":
    sheet = TMP / "sheet.png"
    selfie = TMP / "selfie.png"
    if not sheet.exists():
        call(SHEET, sheet, "4:3")
    if not selfie.exists():
        call(SELFIE, selfie, "9:16")
    # **Celda a celda**: con la hoja entera, Vision se queda en diez sujetos
    # y los zapatos no salían. La rejilla es limpia, así que cada celda es una
    # prenda: se recorta sola y se ajusta a lo opaco.
    # cut = TMP / "sheet-cut.png"
    # subprocess.run(["swift", str(ROOT / "cutout.swift"), str(sheet), str(cut)], check=True)
    # for index, path in enumerate(split_garments(cut), start=1):
    #     install(f"OnboardingGarment{index:02d}", path)
    for index, path in enumerate(cut_cells(sheet), start=1):
        install(f"OnboardingGarment{index:02d}", path)
    install("OnboardingSelfie", selfie)
