#!/usr/bin/env python3
"""Crea o actualiza la función `account`, la colección de regalos y los avisos.

    Tools/.venv/bin/python Tools/deploy_account.py

Idempotente. Hace:

1. La base `snazzy` y la colección `grants` (los regalos que se crean a mano
   en el panel de Appwrite: userId, currency MEJ|PRU, amount, message).
2. La función `account`: identidad estable, bienvenida, reclamar regalos, y el
   aviso por push al crear un regalo.
3. El proveedor de push (APNs), **si** en Tools/.env están `APNS_KEY_ID`,
   `APPLE_TEAM_ID` y `APNS_KEY_PATH` (el .p8 de Keys → Apple Push
   Notifications, en developer.apple.com).

Las claves no se imprimen nunca.
"""
from __future__ import annotations

import pathlib
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from appwrite_client import Appwrite  # noqa: E402
import deploy_function as common  # noqa: E402

FUNCTION_ID = "account"
SOURCE = pathlib.Path(__file__).resolve().parent / "functions" / "account"
DATABASE = "snazzy"
GRANTS = "grants"
PROVIDER = "apns"
BUNDLE_ID = "com.gabrisp.iWearIt"


def check(status: int, payload: dict, what: str, ok=(200, 201, 202, 204, 409)) -> None:
    if status not in ok:
        sys.exit(f"  ERROR {what} {status}: {payload.get('message', payload)}")


def ensure_grants(client: Appwrite) -> None:
    status, payload = client.request("GET", f"/databases/{DATABASE}")
    if status == 404:
        status, payload = client.request("POST", "/databases", {"databaseId": DATABASE, "name": "Snazzy"})
        check(status, payload, "base")
    status, payload = client.request("GET", f"/databases/{DATABASE}/collections/{GRANTS}")
    if status == 404:
        # Sin permisos: solo el servidor lee y escribe. Tú los creas desde el
        # panel, que va con tu sesión de administrador.
        status, payload = client.request("POST", f"/databases/{DATABASE}/collections", {
            "collectionId": GRANTS, "name": "Regalos", "permissions": [], "documentSecurity": False,
        })
        check(status, payload, "colección")
    base = f"/databases/{DATABASE}/collections/{GRANTS}/attributes"
    for kind, body in [
        ("string", {"key": "userId", "size": 36, "required": True}),
        ("enum", {"key": "currency", "elements": ["MEJ", "PRU"], "required": True}),
        ("integer", {"key": "amount", "required": True, "min": 1, "max": 1000}),
        ("string", {"key": "message", "size": 300, "required": False}),
        ("enum", {"key": "status", "elements": ["pending", "claimed"], "required": False, "default": "pending"}),
        ("datetime", {"key": "claimedAt", "required": False}),
    ]:
        status, payload = client.request("POST", f"{base}/{kind}", body)
        check(status, payload, f"atributo {body['key']}")
    # Los atributos se crean en segundo plano: el índice espera a que estén.
    for _ in range(20):
        status, payload = client.request("GET", base)
        if all(a.get("status") == "available" for a in payload.get("attributes", [])):
            break
        time.sleep(1)
    status, payload = client.request("POST", f"/databases/{DATABASE}/collections/{GRANTS}/indexes", {
        "key": "user_status", "type": "key", "attributes": ["userId", "status"],
    })
    check(status, payload, "índice")
    print(f"  colección {DATABASE}/{GRANTS} ✓")


def ensure_push_provider(client: Appwrite) -> None:
    key_id = client.env.get("APNS_KEY_ID")
    team = client.env.get("APPLE_TEAM_ID")
    path = client.env.get("APNS_KEY_PATH")
    if not (key_id and team and path):
        print("  (sin APNS_KEY_ID / APPLE_TEAM_ID / APNS_KEY_PATH: sin avisos push todavía)")
        return
    auth_key = pathlib.Path(path).expanduser().read_text()
    body = {
        "name": "APNs", "authKey": auth_key, "authKeyId": key_id, "teamId": team,
        "bundleId": BUNDLE_ID, "enabled": True,
        # Desarrollo mientras la app vaya firmada para desarrollo; en la App
        # Store, producción. Ver `APNS_SANDBOX`.
        "sandbox": client.env.get("APNS_SANDBOX", "true") == "true",
    }
    status, _ = client.request("GET", f"/messaging/providers/{PROVIDER}")
    if status == 200:
        status, payload = client.request("PATCH", f"/messaging/providers/apns/{PROVIDER}", body)
    else:
        status, payload = client.request("POST", "/messaging/providers/apns", {"providerId": PROVIDER, **body})
    check(status, payload, "proveedor APNs")
    print("  proveedor APNs ✓")


def main() -> int:
    client = Appwrite()
    ensure_grants(client)
    ensure_push_provider(client)

    body = {
        "functionId": FUNCTION_ID,
        "name": "Cuenta",
        "runtime": common.RUNTIME,
        # `any`: `auth` se llama **antes** de tener sesión. Las acciones con
        # dinero comprueban que la haya.
        "execute": ["any"],
        "entrypoint": "src/main.js",
        "timeout": 30,
        "logging": True,
        "events": [f"databases.{DATABASE}.collections.{GRANTS}.documents.*.create"],
        "scopes": ["users.read", "users.write", "documents.read", "documents.write", "messages.write", "targets.read"],
    }
    status, _ = client.request("GET", f"/functions/{FUNCTION_ID}")
    if status == 200:
        update = {k: v for k, v in body.items() if k not in {"functionId", "runtime"}}
        status, payload = client.request("PUT", f"/functions/{FUNCTION_ID}", update)
    else:
        status, payload = client.request("POST", "/functions", body)
    check(status, payload, "función", ok=(200, 201))
    print("  función account ✓")

    status, variables = client.request("GET", f"/functions/{FUNCTION_ID}/variables")
    existing = {v["key"]: v["$id"] for v in variables.get("variables", [])}
    values = [("PUBLIC_API_ENDPOINT", client.endpoint)] + [
        (name, client.env[name]) for name in ("REVENUECAT_SECRET_KEY", "REVENUECAT_PROJECT_ID") if client.env.get(name)
    ]
    for name, value in values:
        if name in existing:
            status, payload = client.request("PUT", f"/functions/{FUNCTION_ID}/variables/{existing[name]}", {"key": name, "value": value})
        else:
            status, payload = client.request("POST", f"/functions/{FUNCTION_ID}/variables", {"key": name, "value": value})
        check(status, payload, name, ok=(200, 201))
        print(f"  {name} ✓")
    if not client.env.get("REVENUECAT_SECRET_KEY"):
        print("  (sin REVENUECAT_SECRET_KEY: sin bienvenida ni regalos reclamables)")

    common.upload(client, FUNCTION_ID, SOURCE)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
