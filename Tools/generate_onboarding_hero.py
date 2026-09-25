"""Genera las dos fotos de la primera página del onboarding: la misma pareja
mal vestida y vestida con Snazzy. Ver `BeforeAfterHero`.

    set -a; . Tools/.env; set +a; Tools/.venv/bin/python Tools/generate_onboarding_hero.py

Las deja en el catálogo como `OnboardingBefore` y `OnboardingAfter`.
"""
import base64, json, os, pathlib, sys, urllib.request, ssl
key = os.environ["OPENROUTER_API_KEY"]
ctx = ssl.create_default_context()
try:
    import certifi; ctx = ssl.create_default_context(cafile=certifi.where())
except Exception: pass

def call(content, out):
    body = {
        "model": "google/gemini-3.1-flash-image",
        "modalities": ["image", "text"],
        "image_config": {"aspect_ratio": "9:16"},
        "messages": [{"role": "user", "content": content}],
    }
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json", "User-Agent": "snazzy-tools"})
    with urllib.request.urlopen(req, timeout=240, context=ctx) as r:
        d = json.load(r)
    url = d["choices"][0]["message"]["images"][0]["image_url"]["url"]
    data = base64.b64decode(url.split(",", 1)[1])
    open(out, "wb").write(data)
    print(out, len(data) // 1024, "KB")
    return url

BEFORE = """Fotografía realista, de moda, vertical. Un HOMBRE y una MUJER de unos 30 años, de pie uno al lado del otro, de CUERPO ENTERO de la cabeza a los pies, mirando DE FRENTE a cámara, postura neutra y relajada, expresión neutra. Fondo de estudio LISO y UNIFORME gris claro (#E6E6E6), sin suelo visible, sin sombras proyectadas y sin objetos: solo las dos personas, bien separadas del fondo (se recortarán). Luz suave de estudio.
VAN MAL VESTIDOS, de forma creíble y cotidiana (no disfraz ni caricatura):
- Él: camiseta gris desgastada y grande con un estampado descolorido, sudadera con cremallera abierta de otro color que no pega, pantalón chino beige demasiado ancho y arrugado, cinturón marrón viejo, zapatillas de deporte blancas sucias y voluminosas, calcetines blancos a la vista.
- Ella: blusa de estampado floral chillón que choca con una rebeca de punto mostaza dada de sí, vaqueros de tiro alto mal ajustados y arrugados, zapatillas grises gastadas, bolso de tela sin forma.
Colores que no combinan, tallas que no son la suya, arrugas. Pelo algo descuidado. Encuadre centrado, con aire por encima de la cabeza y bajo los pies."""

AFTER = """Edita ESTA foto: son LAS MISMAS DOS PERSONAS. Mantén EXACTAMENTE sus caras, su pelo (más arreglado pero el mismo corte y color), su tono de piel, su complexión, su postura, su posición en el encuadre, el fondo gris, la luz y el encuadre de cuerpo entero mirando de frente. Solo cambia la ROPA y el acabado:
AHORA VAN IMPECABLES, estilo editorial minimalista y actual, todo de su talla:
- Él: polo de punto fino color crema bien ajustado, pantalón de pinzas color carbón con caída recta, cinturón de piel fino, mocasines de piel marrón oscuro, reloj discreto.
- Ella: blazer oversize bien cortado color camel, camiseta blanca de algodón, pantalón recto de lana gris claro, mocasines negros de piel, bolso pequeño de piel negro, pendientes de aro dorados finos.
Paleta armónica de neutros. Tejidos que caen bien, sin arrugas. Fotografía realista de moda, sin texto ni logotipos."""

ASSETS = pathlib.Path(__file__).resolve().parent.parent / "iWearIt" / "Assets.xcassets"

def install(name, png):
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{name}.png").write_bytes(pathlib.Path(png).read_bytes())
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2))
    print(f"  {name} ✓")

tmp = pathlib.Path("/tmp/snazzy-hero"); tmp.mkdir(exist_ok=True)
# **El después sale del antes**: misma foto editada, para que caras, postura
# y encuadre coincidan al arrastrar la línea.
before = call([{"type": "text", "text": BEFORE}], str(tmp / "before.png"))
call([{"type": "text", "text": AFTER}, {"type": "image_url", "image_url": {"url": before}}], str(tmp / "after.png"))
# **Transparentes**: solo las personas. El modelo no da alfa, así que se
# recortan aquí con Vision, sin recortar el lienzo para que sigan alineadas.
import subprocess
tools = pathlib.Path(__file__).resolve().parent
for name in ("before", "after"):
    subprocess.run(["swift", str(tools / "cutout.swift"), str(tmp / f"{name}.png"), str(tmp / f"{name}-cut.png")], check=True)
install("OnboardingBefore", tmp / "before-cut.png")
install("OnboardingAfter", tmp / "after-cut.png")
