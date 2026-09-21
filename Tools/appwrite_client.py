"""Cliente mínimo de Appwrite sobre urllib.

Deliberadamente sin el SDK oficial: la app no lo usa (habla REST con
`URLSession`), y añadir una dependencia solo para las herramientas sería
mantener dos formas distintas de hablar con el mismo servidor.
"""
from __future__ import annotations

import json
import mimetypes
import pathlib
import ssl
import sys
import urllib.error
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parent

# Appwrite parte los ficheros grandes en trozos de 5 MB. Cualquier cosa por
# encima de ese tamaño hay que subirla con Content-Range o la rechaza.
CHUNK_SIZE = 5 * 1024 * 1024


def _ssl_context() -> ssl.SSLContext:
    """Cadena de confianza que exista de verdad.

    El Python de python.org no usa el llavero del sistema. **Nunca** se
    desactiva la verificación: estas peticiones llevan la API key.
    """
    try:
        import certifi

        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        pass
    for candidate in ("/etc/ssl/cert.pem", "/private/etc/ssl/cert.pem"):
        if pathlib.Path(candidate).exists():
            return ssl.create_default_context(cafile=candidate)
    sys.exit("Sin cadena de certificados. Instala certifi.")


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
    return env


class Appwrite:
    def __init__(self) -> None:
        env = load_env()
        self.endpoint = env["APPWRITE_ENDPOINT"].rstrip("/")
        self.project = env["APPWRITE_PROJECT_ID"]
        self.key = env["APPWRITE_API_KEY"]
        # El `.env` entero, para lo que no es de Appwrite —como la clave de
        # OpenRouter, que hay que **publicar en el servidor** sin que pase por
        # el repositorio ni por la app.
        self.env = env
        self.context = _ssl_context()

    def _headers(self) -> dict[str, str]:
        return {
            # Cloudflare responde 403 "error code: 1010" al User-Agent de
            # urllib. No es Appwrite rechazando la clave.
            "User-Agent": "iWearIt-Tools/1.0",
            "X-Appwrite-Project": self.project,
            "X-Appwrite-Key": self.key,
        }

    def request(self, method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(self.endpoint + path, data=data, method=method)
        for name, value in self._headers().items():
            request.add_header(name, value)
        request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=60, context=self.context) as response:
                return response.status, json.loads(response.read().decode() or "{}")
        except urllib.error.HTTPError as error:
            raw = error.read().decode() or "{}"
            try:
                return error.code, json.loads(raw)
            except json.JSONDecodeError:
                return error.code, {"message": raw}

    # MARK: Storage

    def upload_file(self, bucket: str, file_id: str, path: pathlib.Path, on_progress=None) -> dict:
        """Sube un fichero, troceado si hace falta.

        Devuelve el documento del fichero. Si ya existe con ese id, lo borra
        primero: reintentar una subida a medias dejaría un fichero corrupto con
        el sha256 correcto en el manifiesto, que es la peor combinación posible.
        """
        self.request("DELETE", f"/storage/buckets/{bucket}/files/{file_id}")

        total = path.stat().st_size
        mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        offset = 0
        result: dict = {}

        # Un fichero que cabe en un chunk se sube de una vez y **sin**
        # Content-Range: Appwrite responde 500 si se lo mandas para una subida
        # que no está troceada.
        if total <= CHUNK_SIZE:
            with path.open("rb") as handle:
                result = self._upload_chunk(
                    bucket, file_id, path.name, mime, handle.read(), None, None, total
                )
            if on_progress:
                on_progress(total, total)
            return result

        with path.open("rb") as handle:
            while offset < total:
                chunk = handle.read(CHUNK_SIZE)
                end = offset + len(chunk) - 1
                result = self._upload_chunk(
                    bucket, file_id, path.name, mime, chunk, offset, end, total
                )
                offset = end + 1
                if on_progress:
                    on_progress(offset, total)
        return result

    def _upload_chunk(
        self, bucket: str, file_id: str, filename: str, mime: str,
        chunk: bytes, start: int | None, end: int | None, total: int,
    ) -> dict:
        boundary = uuid.uuid4().hex
        parts = [
            f"--{boundary}\r\n".encode(),
            b'Content-Disposition: form-data; name="fileId"\r\n\r\n',
            file_id.encode(), b"\r\n",
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'.encode(),
            f"Content-Type: {mime}\r\n\r\n".encode(),
            chunk, b"\r\n",
            f"--{boundary}--\r\n".encode(),
        ]
        body = b"".join(parts)

        request = urllib.request.Request(
            f"{self.endpoint}/storage/buckets/{bucket}/files", data=body, method="POST"
        )
        for name, value in self._headers().items():
            request.add_header(name, value)
        request.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
        if start is not None and end is not None:
            # Appwrite identifica la subida en curso por este id; sin él, cada
            # chunk crearía un fichero distinto.
            request.add_header("x-appwrite-id", file_id)
            request.add_header("Content-Range", f"bytes {start}-{end}/{total}")

        try:
            with urllib.request.urlopen(request, timeout=300, context=self.context) as response:
                return json.loads(response.read().decode() or "{}")
        except urllib.error.HTTPError as error:
            where = f"[{start}-{end}]" if start is not None else "[completo]"
            raise RuntimeError(
                f"Fallo subiendo {filename} {where}: "
                f"{error.code} {error.read().decode()[:300]}"
            ) from error
