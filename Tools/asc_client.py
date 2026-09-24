"""Cliente mínimo de la API de App Store Connect.

La clave `.p8` vive en `~/.appstoreconnect/private_keys/` y el Issuer ID en
`Tools/.env` (`ASC_ISSUER_ID`, gitignorado). Nada de eso se imprime.
"""
from __future__ import annotations

import json
import time
from pathlib import Path

import jwt
import requests

BASE = "https://api.appstoreconnect.apple.com"
KEYS = Path.home() / ".appstoreconnect" / "private_keys"


def _env() -> dict[str, str]:
    env: dict[str, str] = {}
    for line in Path(__file__).with_name(".env").read_text().splitlines():
        if "=" in line and not line.strip().startswith("#"):
            key, value = line.split("=", 1)
            env[key.strip()] = value.strip().strip('"').strip("'")
    return env


class ASC:
    def __init__(self) -> None:
        issuer = _env().get("ASC_ISSUER_ID")
        if not issuer:
            raise SystemExit("Falta ASC_ISSUER_ID en Tools/.env")
        key_file = next(KEYS.glob("AuthKey_*.p8"))
        self.key_id = key_file.stem.removeprefix("AuthKey_")
        self.issuer = issuer
        self.private_key = key_file.read_text()
        self.session = requests.Session()

    def _token(self) -> str:
        now = int(time.time())
        return jwt.encode(
            {"iss": self.issuer, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
            self.private_key,
            algorithm="ES256",
            headers={"kid": self.key_id, "typ": "JWT"},
        )

    def request(self, method: str, path: str, body: dict | None = None, params: dict | None = None):
        response = self.session.request(
            method,
            BASE + path,
            params=params,
            data=json.dumps(body) if body is not None else None,
            headers={"Authorization": f"Bearer {self._token()}", "Content-Type": "application/json"},
            timeout=60,
        )
        try:
            payload = response.json() if response.content else {}
        except ValueError:
            payload = {"raw": response.text[:400]}
        return response.status_code, payload

    @staticmethod
    def errors(payload: dict) -> str:
        return "; ".join(
            f"{e.get('status')} {e.get('code')}: {e.get('detail') or e.get('title')}"
            for e in payload.get("errors", [])
        )
