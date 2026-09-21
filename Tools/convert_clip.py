#!/usr/bin/env python3
"""Convierte el codificador de imagen de TinyCLIP y genera el prompt bank.

    Tools/.venv/bin/python Tools/convert_clip.py

## Por qué TinyCLIP y no MobileCLIP

MobileCLIP era la elección obvia —es de Apple y está pensado para el ANE— pero
su licencia (`apple-amlr`) dice literalmente *"exclusively for Research
Purposes... non-commercial scientific research"*. **No se puede publicar en la
App Store.** Comprobado leyendo el LICENSE, no supuesto.

`wkcn/TinyCLIP-ViT-40M-32-Text-19M-LAION400M` es **MIT**, tiene 39M parámetros
en la torre de visión (28 MB palettizado a 6 bits, que cabe en un solo fichero
del servidor) y su embedding es de 512 dimensiones.

## Por qué las dos cosas en un script

Los vectores del prompt bank y el codificador de imagen **tienen que salir del
mismo checkpoint**. Si se generan por separado y uno se actualiza sin el otro,
los cosenos dejan de significar nada y la clasificación se degrada en silencio,
sin ningún error que lo delate.

## Por qué el codificador de texto no se embarca

Son 19M parámetros más que solo harían falta para codificar texto **nuevo** en
el dispositivo. Los prompts los conocemos de antemano, así que se codifican aquí
una vez y se embarca la tabla resultante: unos cientos de KB en lugar de decenas
de MB.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import pathlib
import shutil
import sys

import certifi

os.environ.setdefault("SSL_CERT_FILE", certifi.where())
os.environ.setdefault("REQUESTS_CA_BUNDLE", certifi.where())
os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")

ROOT = pathlib.Path(__file__).resolve().parent
OUTPUT_DIR = ROOT / "build"
# **El de moda, no el genérico.**
#
# TinyCLIP está entrenado con LAION: distingue una camiseta de un coche, pero
# no una bomber de una cazadora ni unos chinos de unos vaqueros — y eso es
# exactamente lo que esta app le pregunta. `fashion-clip` es el mismo CLIP
# ViT-B/32 afinado con 800.000 fichas de catálogo de moda, es **MIT**
# (comprobado en la API de Hugging Face, no supuesto) y proyecta a **512
# dimensiones igual que TinyCLIP**: el banco de prompts, los centroides de las
# baldas y el detector de duplicados siguen valiendo tal cual.
#
# El anterior se queda comentado como alternativa ligera: es la mitad de
# grande y para un armario pequeño puede bastar.
#
#     REPO = "wkcn/TinyCLIP-ViT-40M-32-Text-19M-LAION400M"
#
# Y si algún día hiciera falta más precisión, `Marqo/marqo-fashionSigLIP`
# (Apache-2.0) es mejor en los benchmarks de moda — pero proyecta a 768
# dimensiones y usa otro tokenizador, así que obliga a regenerar todo lo que
# hoy es de 512.
REPO = "patrickjohncyh/fashion-clip"

# CLIP responde mucho mejor a una frase que a una palabra suelta. Las prendas
# entran ya recortadas sobre fondo transparente, así que la plantilla describe
# justo eso.
TEMPLATE = "a product photo of {}, isolated on a white background"

# Cada entrada: clave en español (lo que ve el usuario) → descripción en inglés
# (lo que entiende el modelo).
SUBCATEGORIES: dict[str, list[tuple[str, str]]] = {
    # La distinción que SegFormer **no** puede hacer: todo esto es
    # `upper-clothes` para él, y aquí se separa capa interior de exterior.
    "upperBody": [
        ("camiseta", "a t-shirt"),
        ("camisa", "a button-up shirt"),
        ("blusa", "a blouse"),
        ("polo", "a polo shirt"),
        ("top", "a crop top"),
        ("jersey", "a knitted sweater"),
        ("sudadera", "a hoodie sweatshirt"),
        ("chaleco", "a vest"),
    ],
    "outerLayer": [
        ("chaqueta", "a jacket"),
        ("cazadora", "a bomber jacket"),
        ("abrigo", "a long winter coat"),
        ("gabardina", "a trench coat"),
        ("chaqueta vaquera", "a denim jacket"),
        ("chaqueta de cuero", "a leather jacket"),
        ("blazer", "a blazer"),
        ("plumífero", "a puffer jacket"),
    ],
    "lowerBody": [
        ("vaqueros", "a pair of blue jeans"),
        ("pantalón", "a pair of trousers"),
        ("chinos", "a pair of chino trousers"),
        ("shorts", "a pair of shorts"),
        ("falda", "a skirt"),
        ("leggings", "a pair of leggings"),
        ("pantalón de chándal", "a pair of jogger sweatpants"),
    ],
    "wholeBody": [
        ("vestido", "a dress"),
        ("vestido largo", "a long maxi dress"),
        ("mono", "a jumpsuit"),
        ("peto", "a pair of dungarees"),
    ],
    "feet": [
        ("zapatillas", "a pair of sneakers"),
        ("botas", "a pair of boots"),
        ("zapatos", "a pair of formal leather shoes"),
        ("sandalias", "a pair of sandals"),
        ("bailarinas", "a pair of ballet flats"),
        ("botines", "a pair of ankle boots"),
    ],
    "head": [
        ("gorra", "a baseball cap"),
        ("gorro", "a knitted beanie hat"),
        ("sombrero", "a wide brim hat"),
        ("gafas de sol", "a pair of sunglasses"),
        ("diadema", "a headband"),
    ],
    "bag": [
        ("bolso", "a handbag"),
        ("mochila", "a backpack"),
        ("bandolera", "a crossbody bag"),
        ("tote", "a tote bag"),
    ],
    "other": [
        ("bufanda", "a scarf"),
        ("cinturón", "a belt"),
        ("corbata", "a necktie"),
        ("guantes", "a pair of gloves"),
    ],
}

ATTRIBUTES: dict[str, list[tuple[str, str]]] = {
    "material": [
        ("algodón", "a cotton garment"),
        ("vaquero", "a denim garment"),
        ("cuero", "a leather garment"),
        ("lana", "a wool knitted garment"),
        ("lino", "a linen garment"),
        ("seda", "a silk garment"),
        ("punto", "a ribbed knit garment"),
        ("sintético", "a nylon synthetic garment"),
    ],
    "pattern": [
        ("liso", "a plain solid colour garment"),
        ("rayas", "a striped garment"),
        ("cuadros", "a checked plaid garment"),
        ("flores", "a floral print garment"),
        ("lunares", "a polka dot garment"),
        ("estampado", "a graphic print garment"),
        ("animal print", "an animal print garment"),
    ],
    "style": [
        ("casual", "a casual everyday outfit item"),
        ("formal", "a formal business outfit item"),
        ("deportivo", "a sporty athletic outfit item"),
        ("elegante", "an elegant evening outfit item"),
        ("streetwear", "a streetwear outfit item"),
        ("bohemio", "a bohemian outfit item"),
        ("minimalista", "a minimalist outfit item"),
        ("vintage", "a vintage retro outfit item"),
    ],
    "season": [
        ("verano", "a lightweight summer garment"),
        ("invierno", "a heavy warm winter garment"),
        ("entretiempo", "a mid-season garment"),
    ],
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--quantize", default="palettize6",
                        choices=["none", "fp16", "palettize6"])
    # **Qué checkpoint.**
    #
    # Por defecto el de moda: la torre genérica entrenada con LAION distingue
    # "camiseta" de "coche" sin problema, pero no "bomber" de "cazadora" ni
    # "chinos" de "vaqueros", que es justo lo que esta app pregunta. Un
    # codificador afinado con catálogo de moda acierta esas y usa **las mismas
    # 512 dimensiones**, así que el banco de prompts, los centroides de las
    # baldas y el detector de duplicados siguen valiendo — siempre que se
    # regeneren juntos, que es lo que hace este script.
    parser.add_argument("--checkpoint", default=REPO)
    args = parser.parse_args()
    repo = args.checkpoint

    import coremltools as ct
    import numpy as np
    import torch
    from transformers import CLIPModel, CLIPTokenizer

    print(f"Cargando {repo}…")
    model = CLIPModel.from_pretrained(repo).eval()
    tokenizer = CLIPTokenizer.from_pretrained(repo)

    size = model.config.vision_config.image_size
    print(f"  entrada {size}x{size}, embedding {model.config.projection_dim}d")

    OUTPUT_DIR.mkdir(exist_ok=True)

    # ---------------------------------------------------------------- imagen
    class ImageEncoder(torch.nn.Module):
        """Devuelve el embedding **ya normalizado**.

        Normalizar dentro del grafo evita que la app tenga que hacerlo, y sobre
        todo evita que lo haga de forma distinta a como se generó el prompt
        bank — que es un fallo silencioso: los cosenos salen plausibles pero
        mal ordenados.
        """

        def __init__(self, clip: torch.nn.Module) -> None:
            super().__init__()
            self.clip = clip

        def forward(self, pixel_values: torch.Tensor) -> torch.Tensor:
            # Torre de visión y proyección por separado, en vez de
            # `get_image_features`: en transformers 5 ese método devuelve un
            # objeto en lugar de un tensor, y esto no depende de la versión.
            pooled = self.clip.vision_model(pixel_values=pixel_values).pooler_output
            features = self.clip.visual_projection(pooled)
            return features / features.norm(dim=-1, keepdim=True)

    encoder = ImageEncoder(model).eval()
    example = torch.rand(1, 3, size, size)
    print("Trazando…")
    with torch.no_grad():
        traced = torch.jit.trace(encoder, example)

    # Normalización de CLIP. Va dentro del modelo por el mismo motivo: si la app
    # usara otros números, todo seguiría "funcionando" con peores resultados.
    mean = [0.48145466, 0.4578275, 0.40821073]
    std = [0.26862954, 0.26130258, 0.27577711]

    print("Convirtiendo a Core ML…")
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(
            name="image",
            shape=(1, 3, size, size),
            scale=1 / (255.0 * float(np.mean(std))),
            bias=[-m / float(np.mean(std)) for m in mean],
            color_layout=ct.colorlayout.RGB,
        )],
        outputs=[ct.TensorType(name="embedding")],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS18,
    )
    mlmodel.short_description = "TinyCLIP image encoder (MIT)"
    mlmodel.user_defined_metadata["license"] = "MIT"
    mlmodel.user_defined_metadata["source"] = REPO
    mlmodel.user_defined_metadata["embeddingDim"] = str(model.config.projection_dim)

    if args.quantize == "palettize6":
        print("Palettizando a 6 bits…")
        from coremltools.optimize.coreml import (
            OpPalettizerConfig, OptimizationConfig, palettize_weights,
        )
        mlmodel = palettize_weights(
            mlmodel,
            OptimizationConfig(global_config=OpPalettizerConfig(mode="kmeans", nbits=6)),
        )

    package = OUTPUT_DIR / f"GarmentEmbedder-{size}.mlpackage"
    if package.exists():
        shutil.rmtree(package)
    mlmodel.save(str(package))
    megabytes = sum(f.stat().st_size for f in package.rglob("*") if f.is_file()) / 1024 / 1024
    print(f"  guardado {package.name}  {megabytes:.1f} MB")

    # ----------------------------------------------------------- prompt bank
    print("\nGenerando prompt bank…")
    entries: list[dict] = []
    vectors: list[np.ndarray] = []

    def encode(group: str, key: str, english: str, kind: str | None) -> None:
        text = TEMPLATE.format(english)
        tokens = tokenizer([text], padding=True, return_tensors="pt")
        with torch.no_grad():
            pooled = model.text_model(**tokens).pooler_output
            features = model.text_projection(pooled)
            features = features / features.norm(dim=-1, keepdim=True)
        vectors.append(features[0].numpy().astype(np.float16))
        entries.append({"group": group, "key": key, "kind": kind, "prompt": text})

    for kind, items in SUBCATEGORIES.items():
        for key, english in items:
            encode("subcategory", key, english, kind)
    for group, items in ATTRIBUTES.items():
        for key, english in items:
            encode(group, key, english, None)

    matrix = np.stack(vectors)
    bank = {
        "dim": int(matrix.shape[1]),
        "count": int(matrix.shape[0]),
        "source": REPO,
        "license": "MIT",
        "entries": entries,
        # fp16 en base64: en JSON plano estos vectores ocuparían ~10 veces más
        # y habría que parsear 130.000 floats en el arranque.
        "vectorsBase64": base64.b64encode(matrix.tobytes()).decode(),
    }
    bank_path = OUTPUT_DIR / "PromptBank.json"
    bank_path.write_text(json.dumps(bank))
    print(f"  {matrix.shape[0]} prompts, {bank_path.stat().st_size / 1024:.0f} KB")

    print("\nListo.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
