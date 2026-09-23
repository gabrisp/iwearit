#!/usr/bin/env python3
"""Regala (o quita) monedas a uno o a muchos.

    Tools/.venv/bin/python Tools/gift_currency.py --user <app_user_id> --mej 10
    Tools/.venv/bin/python Tools/gift_currency.py --users ids.txt --mej 5 --pru 2
    Tools/.venv/bin/python Tools/gift_currency.py --user <id> --mej -3   # quitar

## Para qué

Para lo que no cabe en una regla del panel: compensar a alguien a quien le
falló una mejora, regalar por un lanzamiento, o darle un puñado a quien escribe
pidiendo probar. Las reglas fijas —cuántas monedas da cada plan— se atan al
producto en el panel y no hacen falta aquí.

## Y para gastarlas

El mismo endpoint con cantidades **negativas**. Es, de hecho, la única forma de
gastar: RevenueCat no deja que la app descuente saldo por su cuenta —lo dice su
documentación— porque cualquiera con el teléfono en la mano podría regalarse
monedas. Cuando el gasto se cobre de verdad, la función de Appwrite llamará
aquí con `-1` antes de pedirle la imagen al modelo. Ver `Store.note` en la app.

## La clave

`REVENUECAT_SECRET_KEY` y `REVENUECAT_PROJECT_ID`, de `Tools/.env` —gitignorado
y 600—. Nunca se imprime.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

BASE = "https://api.revenuecat.com/v2"


def load_env() -> dict[str, str]:
    path = Path(__file__).with_name(".env")
    if not path.exists():
        sys.exit("Falta Tools/.env con REVENUECAT_SECRET_KEY y REVENUECAT_PROJECT_ID")
    env: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        env[name.strip()] = value.strip().strip('"').strip("'")
    return env


def adjust(key: str, project: str, user: str, adjustments: dict[str, int]) -> tuple[int, str]:
    url = f"{BASE}/projects/{project}/customers/{user}/virtual_currencies/transactions"
    data = json.dumps({"adjustments": adjustments}).encode()
    request = urllib.request.Request(url, data=data, method="POST")
    request.add_header("Authorization", f"Bearer {key}")
    request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, ""
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode(errors="replace")


def main() -> None:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--user", help="app user id de RevenueCat")
    group.add_argument("--users", help="fichero con un app user id por línea")
    parser.add_argument("--mej", type=int, default=0, help="mejoras (negativo para quitar)")
    parser.add_argument("--pru", type=int, default=0, help="pruebas (negativo para quitar)")
    args = parser.parse_args()

    adjustments = {code: value for code, value in (("MEJ", args.mej), ("PRU", args.pru)) if value}
    if not adjustments:
        sys.exit("Nada que ajustar: pon --mej y/o --pru")

    env = load_env()
    key = env.get("REVENUECAT_SECRET_KEY")
    project = env.get("REVENUECAT_PROJECT_ID")
    if not key or not project:
        sys.exit("Faltan REVENUECAT_SECRET_KEY o REVENUECAT_PROJECT_ID en Tools/.env")

    if args.user:
        users = [args.user]
    else:
        users = [line.strip() for line in Path(args.users).read_text().splitlines() if line.strip()]

    print(f"{adjustments} → {len(users)} usuario(s)")
    failures = 0
    for user in users:
        status, error = adjust(key, project, user, adjustments)
        mark = "✓" if status < 300 else "✗"
        print(f"  {mark} {user}" + (f" · {status} {error}" if status >= 300 else ""))
        failures += status >= 300
    if failures:
        sys.exit(f"{failures} fallo(s)")


if __name__ == "__main__":
    main()
