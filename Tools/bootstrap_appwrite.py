#!/usr/bin/env python3
"""Crea en Appwrite lo que la app necesita para descargar modelos.

Idempotente: se puede ejecutar tantas veces como haga falta. Lo que ya existe
se deja como está, y los permisos se corrigen si han cambiado.

    python3 Tools/bootstrap_appwrite.py

Lee las credenciales de Tools/.env, que está en .gitignore. La API key **solo**
se usa aquí y en upload_model.py, desde tu Mac. La app nunca la ve: usa el
project id público con lectura anónima.
"""
from __future__ import annotations

import json
import pathlib
import ssl
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent


def ssl_context() -> ssl.SSLContext:
    """Contexto TLS con una cadena de confianza que exista de verdad.

    El Python de python.org no usa el llavero del sistema y trae su propio
    bundle, que a menudo está sin instalar — de ahí el
    CERTIFICATE_VERIFY_FAILED aunque `curl` funcione.

    Se prueba `certifi` y, si no, el bundle del sistema. **Nunca** se desactiva
    la verificación: esta petición lleva la API key, y mandarla por un canal sin
    verificar la expone a cualquiera que se interponga.
    """
    try:
        import certifi

        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        pass

    for candidate in ("/etc/ssl/cert.pem", "/private/etc/ssl/cert.pem"):
        if pathlib.Path(candidate).exists():
            return ssl.create_default_context(cafile=candidate)

    raise SystemExit(
        "No se encontró ninguna cadena de certificados de confianza.\n"
        "Instala certifi con:  python3 -m pip install certifi"
    )


SSL_CONTEXT = ssl_context()

BUCKET_ID = "ml-models"

# Tope por fichero del servidor. Medido, no supuesto: cualquier valor superior
# lo rechaza con "Value must be a valid range between 1 and 30,000,000".
MAX_FILE_SIZE = 30_000_000
DATABASE_ID = "wardrobe"
COLLECTION_ID = "model_manifest"

# Atributos del manifiesto. El orden importa: Appwrite los crea de uno en uno.
ATTRIBUTES: list[dict] = [
    {"key": "modelId", "type": "string", "size": 64, "required": True},
    {"key": "task", "type": "enum", "elements": ["segmentation", "embedding", "promptBank"], "required": True},
    {"key": "version", "type": "integer", "required": True},
    {"key": "fileId", "type": "string", "size": 64, "required": True},
    {"key": "sha256", "type": "string", "size": 64, "required": True},
    {"key": "sizeBytes", "type": "integer", "required": False, "default": 0},
    {"key": "minIOSVersion", "type": "string", "size": 8, "required": False, "default": "18.0"},
    {"key": "minDeviceTier", "type": "enum", "elements": ["a12", "a14", "a17"], "required": False, "default": "a12"},
    {"key": "inputWidth", "type": "integer", "required": False, "default": 512},
    {"key": "inputHeight", "type": "integer", "required": False, "default": 512},
    # 1024 y no 8192: Appwrite tiene un tope de tamaño de fila y 8 KB en un
# solo atributo lo agotan. Las 18 clases de SegFormer ocupan ~300 caracteres.
    {"key": "labelsJSON", "type": "string", "size": 1024, "required": False, "default": "[]"},
    {"key": "isActive", "type": "boolean", "required": False, "default": False},
    # Despliegue escalonado: la app decide por hash de su id de instalación.
    {"key": "rolloutPercent", "type": "integer", "required": False, "default": 100},
    # Modelos partidos. `fileId` sigue siendo el primer trozo, para que un
    # modelo de un solo fichero no necesite nada especial.
    {"key": "partsJSON", "type": "string", "size": 4096, "required": False, "default": "[]"},
    {"key": "partCount", "type": "integer", "required": False, "default": 1},
]

INDEXES = [
    {"key": "unique_model_version", "type": "unique", "attributes": ["modelId", "version"]},
    {"key": "active_by_task", "type": "key", "attributes": ["task", "isActive"]},
]


def load_env() -> dict[str, str]:
    path = ROOT / ".env"
    if not path.exists():
        sys.exit("Falta Tools/.env. Copia Tools/.env.example y rellénalo.")
    env = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, value = line.partition("=")
            env[key.strip()] = value.strip()
    for required in ("APPWRITE_ENDPOINT", "APPWRITE_PROJECT_ID", "APPWRITE_API_KEY"):
        if not env.get(required):
            sys.exit(f"Falta {required} en Tools/.env")
    return env


ENV = load_env()


def call(method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
    url = ENV["APPWRITE_ENDPOINT"].rstrip("/") + path
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    # Cloudflare responde 403 con "error code: 1010" al User-Agent por defecto
    # de urllib (`Python-urllib/3.x`). No es Appwrite rechazando la clave: es el
    # filtro de integridad de navegador del proxy que hay delante.
    request.add_header("User-Agent", "iWearIt-Tools/1.0")
    request.add_header("Content-Type", "application/json")
    request.add_header("X-Appwrite-Project", ENV["APPWRITE_PROJECT_ID"])
    request.add_header("X-Appwrite-Key", ENV["APPWRITE_API_KEY"])
    try:
        with urllib.request.urlopen(request, timeout=30, context=SSL_CONTEXT) as response:
            raw = response.read().decode() or "{}"
            return response.status, json.loads(raw)
    except urllib.error.HTTPError as error:
        raw = error.read().decode() or "{}"
        try:
            return error.code, json.loads(raw)
        except json.JSONDecodeError:
            return error.code, {"message": raw}


def ensure(label: str, method: str, path: str, body: dict) -> bool:
    """Crea algo y trata "ya existe" como éxito."""
    status, payload = call(method, path, body)
    # Appwrite responde 202 a la creación de atributos e índices: se crean de
    # forma asíncrona. Contarlo como error hacía parecer roto algo que funciona.
    if status in (200, 201, 202):
        print(f"  creado   {label}")
        return True
    if status == 409:
        print(f"  ya está  {label}")
        return True
    print(f"  ERROR    {label}: {status} {payload.get('message', payload)}")
    return False


def main() -> int:
    print(f"Appwrite: {ENV['APPWRITE_ENDPOINT']}  proyecto: {ENV['APPWRITE_PROJECT_ID']}")

    print("\nBucket de modelos")
    ok = ensure(
        f"bucket {BUCKET_ID}", "POST", "/storage/buckets",
        {
            "bucketId": BUCKET_ID,
            "name": "ML models",
            # Lectura para cualquiera: la app descarga sin autenticarse. No hay
            # escritura para nadie — solo la API key de estas herramientas.
            "permissions": ['read("any")'],
            "fileSecurity": False,
            "enabled": True,
            # Límite del servidor, comprobado: rechaza cualquier valor por
            # encima de 30.000.000. Por eso los modelos grandes van partidos
            # (ver PART_SIZE_BYTES en upload_model.py).
            "maximumFileSize": MAX_FILE_SIZE,
            # Los .mlpackage van zipeados: comprimir otra vez no gana nada.
            "compression": "none",
            # No son secretos y el cifrado encarece la descarga.
            "encryption": False,
            "antivirus": False,
        },
    )

    print("\nBase de datos")
    ok &= ensure(
        f"database {DATABASE_ID}", "POST", "/databases",
        {"databaseId": DATABASE_ID, "name": "Wardrobe", "enabled": True},
    )

    print("\nColección del manifiesto")
    ok &= ensure(
        f"collection {COLLECTION_ID}", "POST", f"/databases/{DATABASE_ID}/collections",
        {
            "collectionId": COLLECTION_ID,
            "name": "Model manifest",
            "permissions": ['read("any")'],
            "documentSecurity": False,
            "enabled": True,
        },
    )

    print("\nAtributos")
    base = f"/databases/{DATABASE_ID}/collections/{COLLECTION_ID}/attributes"
    for attribute in ATTRIBUTES:
        kind = attribute["type"]
        body = {"key": attribute["key"], "required": attribute["required"]}
        if not attribute["required"] and "default" in attribute:
            body["default"] = attribute["default"]
        if kind == "string":
            body["size"] = attribute["size"]
        if kind == "enum":
            body["elements"] = attribute["elements"]
        ensure(attribute["key"], "POST", f"{base}/{kind}", body)

    print("\nÍndices")
    index_base = f"/databases/{DATABASE_ID}/collections/{COLLECTION_ID}/indexes"
    for index in INDEXES:
        ensure(
            index["key"], "POST", index_base,
            {
                "key": index["key"],
                "type": index["type"],
                "attributes": index["attributes"],
                "orders": ["ASC"] * len(index["attributes"]),
            },
        )

    print("\nListo." if ok else "\nTerminado con errores.")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
