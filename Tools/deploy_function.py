#!/usr/bin/env python3
"""Crea o actualiza la Function de Appwrite que resuelve prendas.

    Tools/.venv/bin/python Tools/deploy_function.py

Idempotente: se puede correr las veces que haga falta. Si la función ya existe
la actualiza, y si la variable de entorno ya está puesta la reescribe.

## Dónde vive la clave

`OPENROUTER_API_KEY` se lee de `Tools/.env` —que está en `.gitignore` y con
permisos 600— y se sube **como variable de entorno de la función**. No aparece
en el código de la función, no aparece en la app, y no vuelve a salir de
Appwrite: la API de variables solo devuelve el nombre, nunca el valor.

## Quién puede ejecutarla

`users`, no `any`. La app abre una sesión anónima al arrancar —sin pantalla de
login, sin pedir nada— y con eso ya no es un endpoint abierto a todo el que
sepa el id del proyecto. No es autenticación de verdad; es la diferencia entre
una puerta cerrada y una puerta abierta.
"""
from __future__ import annotations

import io
import pathlib
import sys
import tarfile
import urllib.request
import uuid

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from appwrite_client import Appwrite  # noqa: E402

FUNCTION_ID = "resolve-garment"
SOURCE = pathlib.Path(__file__).resolve().parent / "functions" / "resolve-garment"
# Node 20 y no 22: es lo que tiene instalado **este** servidor. La lista de
# runtimes depende de cómo se desplegó Appwrite, no de su versión, y pedir uno
# que no está da un 404 que no se parece en nada a la causa.
RUNTIME = "node-20.0"


def packaged(source: pathlib.Path) -> bytes:
    """Empaqueta el código como `.tar.gz`, que es lo que espera el endpoint.

    Con las rutas relativas a la raíz del paquete: Appwrite busca
    `package.json` en el primer nivel, y un tar con un directorio por encima
    despliega una función que no arranca y no dice por qué.
    """
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        for path in sorted(source.rglob("*")):
            if path.is_dir() or "node_modules" in path.parts:
                continue
            archive.add(path, arcname=str(path.relative_to(source)))
    return buffer.getvalue()


def main() -> int:
    if not SOURCE.exists():
        sys.exit(f"No existe {SOURCE}")

    client = Appwrite()
    key = client.env.get("OPENROUTER_API_KEY")
    if not key:
        sys.exit("Falta OPENROUTER_API_KEY en Tools/.env")

    status, payload = client.request("GET", f"/functions/{FUNCTION_ID}")
    exists = status == 200

    body = {
        "functionId": FUNCTION_ID,
        "name": "Resolver prenda",
        "runtime": RUNTIME,
        "execute": ["users"],
        "entrypoint": "src/main.js",
        # 120 y no 30: describir una prenda son 1,5 s, pero **generar** su
        # versión de catálogo son decenas. Con el tope por defecto la petición
        # moría a medias y el error que llegaba era un timeout de red, que no
        # se parece en nada a la causa.
        "timeout": 120,
        "logging": True,
    }

    if exists:
        print("La función ya existe: actualizando…")
        # Sin `functionId` ni `runtime` en el cuerpo: el endpoint de
        # actualización los rechaza por inmutables.
        update = {k: v for k, v in body.items() if k not in {"functionId", "runtime"}}
        status, payload = client.request("PUT", f"/functions/{FUNCTION_ID}", update)
    else:
        print("Creando la función…")
        status, payload = client.request("POST", "/functions", body)

    if status not in (200, 201):
        sys.exit(f"  ERROR {status}: {payload.get('message', payload)}")

    print("Publicando OPENROUTER_API_KEY como variable de entorno…")
    status, variables = client.request("GET", f"/functions/{FUNCTION_ID}/variables")
    existing = {v["key"]: v["$id"] for v in variables.get("variables", [])}
    for name, value in [
        ("OPENROUTER_API_KEY", key),
        ("OPENROUTER_MODEL", "google/gemini-2.5-flash-lite"),
        ("OPENROUTER_IMAGE_MODEL", "google/gemini-3.1-flash-lite-image"),
    ]:
        if name in existing:
            status, payload = client.request(
                "PUT", f"/functions/{FUNCTION_ID}/variables/{existing[name]}",
                {"key": name, "value": value},
            )
        else:
            status, payload = client.request(
                "POST", f"/functions/{FUNCTION_ID}/variables",
                {"key": name, "value": value},
            )
        if status not in (200, 201):
            sys.exit(f"  ERROR {status}: {payload.get('message', payload)}")
        print(f"  {name} ✓")

    print("Subiendo el código…")
    code = packaged(SOURCE)
    print(f"  {len(code) / 1024:.1f} KB")

    boundary = uuid.uuid4().hex
    parts = []
    for name, value in [("entrypoint", "src/main.js"), ("activate", "true")]:
        parts.append(
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n"
            .encode()
        )
    parts.append(
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"code\"; filename=\"code.tar.gz\"\r\n"
        "Content-Type: application/gzip\r\n\r\n".encode()
    )
    parts.append(code)
    parts.append(f"\r\n--{boundary}--\r\n".encode())

    request = urllib.request.Request(
        f"{client.endpoint}/functions/{FUNCTION_ID}/deployments",
        data=b"".join(parts),
        method="POST",
        headers={
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            # El User-Agent de urllib se lo come Cloudflare con un 403
            # "error code: 1010" que no tiene nada que ver con Appwrite.
            "User-Agent": "iWearIt-Tools/1.0",
            "X-Appwrite-Project": client.project,
            "X-Appwrite-Key": client.key,
        },
    )
    try:
        # Con el contexto del cliente: el Python de python.org no usa el
        # llavero del sistema y sin esto la subida se cae por certificado.
        with urllib.request.urlopen(request, timeout=300, context=client.context) as response:
            print(f"  desplegado ({response.status})")
    except urllib.error.HTTPError as cause:
        sys.exit(f"  ERROR {cause.code}: {cause.read().decode()[:400]}")

    print(f"\nListo. La app la llamará en /functions/{FUNCTION_ID}/executions")
    print("La clave vive solo aquí: no está en el repositorio ni en la app.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
