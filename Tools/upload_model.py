#!/usr/bin/env python3
"""Empaqueta un .mlpackage, lo sube a Appwrite y publica su manifiesto.

    Tools/.venv/bin/python Tools/upload_model.py \
        --package Tools/build/ClothesSegmenter-b2-512.mlpackage \
        --model-id clothes-seg --task segmentation

Empaqueta con **Apple Archive** (`aa`, que viene con macOS) y no con zip: iOS no
sabe descomprimir zip sin dependencias externas, y Apple Archive es nativo en
las dos puntas.

Si el paquete supera el límite del servidor se sube partido, y el manifiesto
guarda los trozos en orden. El sha256 es siempre del archivo **entero**: lo que
tiene que cuadrar es el modelo, no cada pedazo.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import urllib.parse

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from appwrite_client import Appwrite  # noqa: E402

BUCKET_ID = "ml-models"
DATABASE_ID = "wardrobe"
COLLECTION_ID = "model_manifest"

# Tope del servidor, medido: rechaza por encima de 30.000.000 bytes exactos.
# Se deja un margen pequeño para la cabecera multipart y no un megabyte entero,
# que obligaba a partir archivos que cabían de sobra.
MAX_PART_BYTES = 29_500_000


def sha256_of(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def archive(package: pathlib.Path, destination: pathlib.Path) -> pathlib.Path:
    """Empaqueta con `aa` un .mlpackage o un fichero suelto.

    Se copia lo que sea a un directorio propio y se archiva **ese** directorio,
    de modo que el contenido quede en la raíz del archivo — que es donde lo
    busca el descargador. `aa` no sabe archivar un fichero suelto: `-subdir`
    exige un directorio.
    """
    staging = destination / "payload"
    staging.mkdir(parents=True, exist_ok=True)
    target = staging / package.name
    if package.is_dir():
        shutil.copytree(package, target)
    else:
        shutil.copy2(package, target)

    output = destination / "package.aar"
    result = subprocess.run(
        ["aa", "archive", "-d", str(staging), "-o", str(output), "-a", "lzfse"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        sys.exit(f"`aa archive` falló:\n{result.stderr}")
    return output


def split(path: pathlib.Path, destination: pathlib.Path) -> list[pathlib.Path]:
    size = path.stat().st_size
    if size <= MAX_PART_BYTES:
        return [path]

    parts: list[pathlib.Path] = []
    with path.open("rb") as handle:
        index = 0
        while True:
            chunk = handle.read(MAX_PART_BYTES)
            if not chunk:
                break
            part = destination / f"part-{index:03d}"
            part.write_bytes(chunk)
            parts.append(part)
            index += 1
    return parts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", required=True, type=pathlib.Path)
    parser.add_argument("--model-id", required=True)
    parser.add_argument("--task", required=True,
                        choices=["segmentation", "embedding", "promptBank"])
    parser.add_argument("--size", type=int, default=512)
    parser.add_argument("--min-ios", default="18.0")
    parser.add_argument("--activate", action="store_true", default=True)
    args = parser.parse_args()

    package: pathlib.Path = args.package
    if not package.exists():
        sys.exit(f"No existe {package}")

    client = Appwrite()

    with tempfile.TemporaryDirectory() as raw:
        workspace = pathlib.Path(raw)

        print("Empaquetando…")
        archive_path = archive(package, workspace)
        total = archive_path.stat().st_size
        digest = sha256_of(archive_path)
        print(f"  {total / 1024 / 1024:.1f} MB  sha256 {digest[:16]}…")

        parts = split(archive_path, workspace)
        if len(parts) > 1:
            print(f"  partido en {len(parts)} trozos de <= {MAX_PART_BYTES // 1024 // 1024} MB")

        # Versión siguiente, mirando lo que ya hay publicado.
        # La consulta va url-encoded: el JSON lleva espacios y comillas, y
        # meterlos crudos en la URL revienta con "control characters".
        query = urllib.parse.quote(
            json.dumps({"method": "equal", "attribute": "modelId", "values": [args.model_id]})
        )
        status, payload = client.request(
            "GET",
            f"/databases/{DATABASE_ID}/collections/{COLLECTION_ID}/documents?queries[]={query}",
        )
        existing = payload.get("documents", []) if status == 200 else []
        version = max((doc.get("version", 0) for doc in existing), default=0) + 1
        print(f"Versión {version}")

        file_ids: list[str] = []
        for index, part in enumerate(parts):
            file_id = f"{args.model_id}-v{version}-p{index:03d}"
            print(f"Subiendo {file_id} ({part.stat().st_size / 1024 / 1024:.1f} MB)…")
            client.upload_file(
                BUCKET_ID, file_id, part,
                on_progress=lambda done, size: print(
                    f"\r  {done * 100 // size}%", end="", flush=True
                ),
            )
            print("\r  100%")
            file_ids.append(file_id)

    labels: list[str] = []
    manifest_path = package / "Manifest.json" if package.is_dir() else package
    if package.is_dir() and manifest_path.exists():
        # Las etiquetas las dejó ahí el script de conversión, en los metadatos
        # del modelo. Leerlas de aquí evita tener que repetirlas a mano.
        try:
            import coremltools as ct

            model = ct.models.MLModel(str(package), skip_model_load=True)
            labels = json.loads(model.user_defined_metadata.get("labels", "[]"))
        except Exception as error:  # noqa: BLE001
            print(f"  (no se pudieron leer las etiquetas: {error})")

    document = {
        "modelId": args.model_id,
        "task": args.task,
        "version": version,
        "fileId": file_ids[0],
        "sha256": digest,
        "sizeBytes": total,
        "minIOSVersion": args.min_ios,
        "inputWidth": args.size,
        "inputHeight": args.size,
        "labelsJSON": json.dumps(labels),
        "partsJSON": json.dumps(file_ids if len(file_ids) > 1 else []),
        "partCount": len(file_ids),
        "isActive": args.activate,
        "rolloutPercent": 100,
    }

    print("Publicando manifiesto…")
    status, payload = client.request(
        "POST",
        f"/databases/{DATABASE_ID}/collections/{COLLECTION_ID}/documents",
        {"documentId": f"{args.model_id}-v{version}", "data": document},
    )
    if status not in (200, 201):
        sys.exit(f"  ERROR {status}: {payload.get('message', payload)}")

    # Desactivar versiones anteriores: la app pide solo lo activo, y dos activas
    # del mismo modelo harían que descargara una u otra según el orden.
    if args.activate:
        for doc in existing:
            if doc.get("isActive"):
                client.request(
                    "PATCH",
                    f"/databases/{DATABASE_ID}/collections/{COLLECTION_ID}/documents/{doc['$id']}",
                    {"data": {"isActive": False}},
                )
                print(f"  desactivada v{doc.get('version')}")

    print(f"\nListo. {args.model_id} v{version} activo.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
