#!/usr/bin/env python3
"""Deja RevenueCat configurado: derecho, monedas, productos y oferta.

    Tools/.venv/bin/python Tools/bootstrap_revenuecat.py [--dry-run]

Idempotente: se puede correr las veces que haga falta. Lo que ya existe se
deja como está y se dice; lo que falta se crea.

## Dónde vive la clave

`REVENUECAT_SECRET_KEY` y `REVENUECAT_PROJECT_ID` se leen de `Tools/.env`, que
está en `.gitignore` y con permisos 600 — igual que la de OpenRouter. La clave
secreta de RevenueCat **administra**: crea productos, ajusta saldos y lee datos
de clientes. No puede estar en el repositorio, ni en la app, ni pegada en una
conversación; aquí solo se lee para hablar con su API y nunca se imprime.

## Lo que crea

- El derecho `pro`, que es el que mira la app para saber si alguien ha pagado.
- Las dos monedas: `MEJ` (mejorar una prenda) y `PRU` (probarse un outfit).
- Los tres productos de la tienda de pruebas y la oferta que los presenta:
  seis meses, mensual y semanal. Ver `StoreIDs` en la app.

## Lo que **no** puede hacer

Conceder monedas al comprar. Eso es una regla que se ata al producto en el
panel —"grant on each renewal"— y la API v2 todavía no la expone; el script lo
dice al acabar en vez de dejarlo sin mencionar.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

BASE = "https://api.revenuecat.com/v2"

ENTITLEMENT = {"lookup_key": "pro", "display_name": "Pro"}

CURRENCIES = [
    {"code": "MEJ", "name": "Mejoras", "description": "Para mejorar una prenda"},
    {"code": "PRU", "name": "Pruebas", "description": "Para probarte un outfit"},
]

# Los tres planes. El de seis meses es el que sale a cuenta: a 7,50 € al mes
# sigue siendo un 37% más barato que el mensual **y** da para tantas monedas
# como él, que es lo que un anual a 44,99 € no podía hacer.
PRODUCTS = [
    {
        "store_identifier": "com.gabrisp.iWearIt.pro.sixmonth",
        "display_name": "iWearIt Pro · seis meses",
        "package": "$rc_six_month",
    },
    {
        "store_identifier": "com.gabrisp.iWearIt.pro.monthly",
        "display_name": "iWearIt Pro · mensual",
        "package": "$rc_monthly",
    },
    {
        "store_identifier": "com.gabrisp.iWearIt.pro.weekly",
        "display_name": "iWearIt Pro · semanal",
        "package": "$rc_weekly",
    },
]

OFFERING = {"lookup_key": "default", "display_name": "Planes de iWearIt"}


def load_env() -> dict[str, str]:
    path = Path(__file__).with_name(".env")
    if not path.exists():
        sys.exit(
            "Falta Tools/.env con REVENUECAT_SECRET_KEY y REVENUECAT_PROJECT_ID.\n"
            "Créalo con permisos 600 y no lo añadas a git."
        )
    env: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        env[name.strip()] = value.strip().strip('"').strip("'")
    return env


class RevenueCat:
    def __init__(self, key: str, project: str, dry_run: bool) -> None:
        self._key = key
        self.project = project
        self.dry_run = dry_run

    def request(self, method: str, path: str, body: dict | None = None):
        url = f"{BASE}/projects/{self.project}{path}"
        if self.dry_run and method != "GET":
            print(f"  (en seco) {method} {path} {json.dumps(body, ensure_ascii=False)}")
            return 200, {}
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", f"Bearer {self._key}")
        request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.status, json.loads(response.read() or b"{}")
        except urllib.error.HTTPError as error:
            # El cuerpo del error de RevenueCat dice exactamente qué campo
            # falta: imprimirlo entero ahorra adivinar.
            payload = error.read().decode(errors="replace")
            return error.code, {"error": payload}

    def existing(self, path: str, key: str) -> set[str]:
        status, payload = self.request("GET", path)
        if status != 200:
            print(f"  no se pudo leer {path}: {payload}")
            return set()
        return {item.get(key) for item in payload.get("items", []) if item.get(key)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="enseña sin tocar nada")
    args = parser.parse_args()

    env = load_env()
    key = env.get("REVENUECAT_SECRET_KEY")
    project = env.get("REVENUECAT_PROJECT_ID")
    if not key or not project:
        sys.exit("Faltan REVENUECAT_SECRET_KEY o REVENUECAT_PROJECT_ID en Tools/.env")

    api = RevenueCat(key, project, args.dry_run)

    print("Derecho…")
    if ENTITLEMENT["lookup_key"] in api.existing("/entitlements", "lookup_key"):
        print(f"  {ENTITLEMENT['lookup_key']} ya existe")
    else:
        status, payload = api.request("POST", "/entitlements", ENTITLEMENT)
        print(f"  {ENTITLEMENT['lookup_key']} → {status} {payload if status >= 300 else ''}")

    print("Monedas…")
    existing_currencies = api.existing("/virtual-currencies", "code")
    for currency in CURRENCIES:
        if currency["code"] in existing_currencies:
            print(f"  {currency['code']} ya existe")
            continue
        status, payload = api.request("POST", "/virtual-currencies", currency)
        print(f"  {currency['code']} → {status} {payload if status >= 300 else ''}")

    print("Productos…")
    existing_products = api.existing("/products", "store_identifier")
    for product in PRODUCTS:
        if product["store_identifier"] in existing_products:
            print(f"  {product['store_identifier']} ya existe")
            continue
        body = {
            "store_identifier": product["store_identifier"],
            "app_id": env.get("REVENUECAT_APP_ID", ""),
            "type": "subscription",
            "display_name": product["display_name"],
        }
        status, payload = api.request("POST", "/products", body)
        print(f"  {product['store_identifier']} → {status} {payload if status >= 300 else ''}")

    print("Oferta…")
    if OFFERING["lookup_key"] in api.existing("/offerings", "lookup_key"):
        print(f"  {OFFERING['lookup_key']} ya existe")
    else:
        status, payload = api.request("POST", "/offerings", OFFERING)
        print(f"  {OFFERING['lookup_key']} → {status} {payload if status >= 300 else ''}")

    print()
    print("Lo que hay que rematar en el panel (la API no lo expone):")
    print("  · Atar cada producto a su paquete de la oferta si no se ató solo.")
    print("  · Conceder monedas en cada renovación. **La misma ración al mes**")
    print("    en los tres: lo que cambia entre planes es el precio, no lo que")
    print("    te llevas. 30 mejoras y 8 pruebas al mes, o sea:")
    print("      seis meses → 180 MEJ y 48 PRU")
    print("      mensual    →  30 MEJ y  8 PRU")
    print("      semanal    →   7 MEJ y  2 PRU")
    print("  · Y, si quieres, 3 MEJ de regalo la primera vez, para probar.")
    print("  · Regalar a mano cuando haga falta: Tools/gift_currency.py.")


if __name__ == "__main__":
    main()
