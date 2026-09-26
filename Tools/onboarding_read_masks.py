"""Las zonas de cada prenda para el paso "Tu iPhone lee cada prenda" del
onboarding: la silueta de la persona recortada a la caja de cada prenda, con
el borde suave. Sin llamadas a nada de pago: todo en local con Vision.

    Tools/.venv/bin/python Tools/onboarding_read_masks.py

Deja `OnboardingReadMen` / `OnboardingReadWomen` (la foto) y
`OnboardingReadMen-top|bottom|shoes`, `OnboardingReadWomen-…` (las zonas).
"""
import json, pathlib, subprocess
import numpy as np
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent
ASSETS = ROOT.parent / "iWearIt" / "Assets.xcassets"
TMP = pathlib.Path("/tmp/snazzy-catalog"); TMP.mkdir(exist_ok=True)


def install(name, image):
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / f"{name}.png")
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2))
    print(f"  {name} ✓")


def zones(prefix, photo, person, boxes):
    """`person`: silueta 0-255 del tamaño de la foto. `boxes`: (x0, y0, x1, y1)
    en 0-1."""
    install(prefix, photo)
    w, h = photo.size
    for name, (x0, y0, x1, y1) in boxes.items():
        box = np.zeros((h, w), dtype=np.uint8)
        box[int(y0 * h):int(y1 * h), int(x0 * w):int(x1 * w)] = 255
        zone = np.minimum(np.array(person), box)
        alpha = Image.fromarray(zone).filter(ImageFilter.GaussianBlur(3))
        white = Image.new("RGBA", (w, h), (255, 255, 255, 0))
        white.putalpha(alpha)
        install(f"{prefix}-{name}", white)


# Él: el selfie de espejo.
selfie = Image.open(ASSETS / "OnboardingSelfie.imageset" / "OnboardingSelfie.png").convert("RGB")
selfie_path = TMP / "selfie-src.png"; selfie.save(selfie_path)
mask_path = TMP / "selfie-person.png"
subprocess.run(["swift", str(ROOT / "person_mask.swift"), str(selfie_path), str(mask_path)], check=True)
person = Image.open(mask_path).convert("L").resize(selfie.size)
zones("OnboardingReadMen", selfie.convert("RGBA"), person, {
    "top": (0.28, 0.27, 0.74, 0.56),
    "bottom": (0.34, 0.54, 0.68, 0.68),
    "shoes": (0.30, 0.80, 0.70, 0.93),
})

# Ella: su selfie de espejo, como el de él.
# (Antes: la de la derecha de la foto de la bienvenida, recortada.)
selfie = Image.open(ASSETS / "OnboardingSelfieWoman.imageset" / "OnboardingSelfieWoman.png").convert("RGB")
selfie_path = TMP / "selfie-woman-src.png"; selfie.save(selfie_path)
mask_path = TMP / "selfie-woman-person.png"
subprocess.run(["swift", str(ROOT / "person_mask.swift"), str(selfie_path), str(mask_path)], check=True)
person = Image.open(mask_path).convert("L").resize(selfie.size)
zones("OnboardingReadWomen", selfie.convert("RGBA"), person, {
    "top": (0.30, 0.35, 0.68, 0.60),
    "bottom": (0.36, 0.585, 0.64, 0.815),
    "shoes": (0.34, 0.815, 0.62, 0.875),
})
