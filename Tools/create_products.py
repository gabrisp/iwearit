#!/usr/bin/env python3
"""Crea en App Store Connect las suscripciones de Snazzy.

    Tools/.venv/bin/python Tools/create_products.py            # solo mira
    Tools/.venv/bin/python Tools/create_products.py --apply    # crea

Idempotente: lo que ya existe —grupo, suscripción, texto, precio— se deja como
está. Sin `--apply` no escribe nada: enseña lo que haría.

Hace, por este orden:

1. El grupo de suscripción "Snazzy Pro", con su nombre en español.
2. Las tres suscripciones —seis meses, mensual, semanal— con los mismos
   identificadores que usan la app y RevenueCat.
3. El nombre y la descripción de cada una en español.
4. El precio en España y, a partir de él, el equivalente de Apple en todos los
   demás países.
5. Disponible en todos los países.

**Sin prueba gratis**: no se crea ninguna oferta de introducción.

Lo que la API no hace y queda para la web: la captura de pantalla para la
revisión de cada suscripción, que Apple pide antes de mandarlas a revisar.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from asc_client import ASC  # noqa: E402

BUNDLE_ID = "com.gabrisp.iWearIt"
GROUP_NAME = "Snazzy Pro"
LOCALE = "es-ES"
BASE_TERRITORY = "ESP"

# Del más largo al más corto: en un grupo, el nivel 1 es el "mejor" plan, y
# pasarse a uno de nivel más alto es una mejora que se aplica al momento.
PRODUCTS = [
    {
        "productId": "com.gabrisp.iWearIt.pro.sixmonth",
        "name": "Snazzy Pro · 6 meses",
        "period": "SIX_MONTHS",
        "level": 1,
        "price": "44.99",
        "display": "Pro · 6 meses",
        "description": "Todo Snazzy sin límites durante seis meses.",
    },
    {
        "productId": "com.gabrisp.iWearIt.pro.monthly",
        "name": "Snazzy Pro · mensual",
        "period": "ONE_MONTH",
        "level": 2,
        "price": "11.99",
        "display": "Pro · mensual",
        "description": "Todo Snazzy sin límites, mes a mes.",
    },
    {
        "productId": "com.gabrisp.iWearIt.pro.weekly",
        "name": "Snazzy Pro · semanal",
        "period": "ONE_WEEK",
        "level": 3,
        "price": "4.99",
        "display": "Pro · semanal",
        "description": "Todo Snazzy sin límites, semana a semana.",
    },
]


def main() -> int:
    apply = "--apply" in sys.argv
    asc = ASC()
    print("MODO:", "crear" if apply else "solo mirar (añade --apply para crear)")

    status, apps = asc.request("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID})
    if status != 200 or not apps.get("data"):
        print(f"No existe la app {BUNDLE_ID} en App Store Connect. Créala en la web primero.")
        return 1
    app_id = apps["data"][0]["id"]
    print(f"App: {apps['data'][0]['attributes']['name']} ({app_id})")

    # 1. Grupo
    status, groups = asc.request(
        "GET", f"/v1/apps/{app_id}/subscriptionGroups", params={"include": "subscriptions", "limit": 50}
    )
    group = next((g for g in groups.get("data", []) if g["attributes"]["referenceName"] == GROUP_NAME), None)
    existing = {s["attributes"]["productId"]: s for s in groups.get("included", []) if s["type"] == "subscriptions"}

    if group:
        print(f"Grupo '{GROUP_NAME}' ya existe")
    elif apply:
        status, created = asc.request("POST", "/v1/subscriptionGroups", {
            "data": {
                "type": "subscriptionGroups",
                "attributes": {"referenceName": GROUP_NAME},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        })
        if status >= 300:
            print("  ERROR grupo:", ASC.errors(created))
            return 1
        group = created["data"]
        print(f"Grupo '{GROUP_NAME}' creado")
        status, loc = asc.request("POST", "/v1/subscriptionGroupLocalizations", {
            "data": {
                "type": "subscriptionGroupLocalizations",
                "attributes": {"locale": LOCALE, "name": "Snazzy Pro"},
                "relationships": {"subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": group["id"]}}},
            }
        })
        print("  nombre del grupo:", "ok" if status < 300 else ASC.errors(loc))
    else:
        print(f"Crearía el grupo '{GROUP_NAME}'")

    territories = None
    for product in PRODUCTS:
        pid = product["productId"]
        print(f"\n{pid}")
        subscription = existing.get(pid)

        # 2. Suscripción
        if subscription:
            print("  ya existe:", subscription["attributes"].get("state"))
        elif apply:
            status, created = asc.request("POST", "/v1/subscriptions", {
                "data": {
                    "type": "subscriptions",
                    "attributes": {
                        "name": product["name"],
                        "productId": pid,
                        "subscriptionPeriod": product["period"],
                        "groupLevel": product["level"],
                        "familySharable": False,
                        "reviewNote": "Desbloquea todo Snazzy: prendas y maletas sin límite, escaneo completo y probador virtual.",
                    },
                    "relationships": {"group": {"data": {"type": "subscriptionGroups", "id": group["id"]}}},
                }
            })
            if status >= 300:
                print("  ERROR:", ASC.errors(created))
                continue
            subscription = created["data"]
            print("  creada")
        else:
            print(f"  crearía: {product['name']} · {product['period']} · {product['price']} €")
            continue

        sid = subscription["id"]

        # 3. Texto en español
        status, locs = asc.request("GET", f"/v1/subscriptions/{sid}/subscriptionLocalizations")
        if any(l["attributes"]["locale"] == LOCALE for l in locs.get("data", [])):
            print("  texto: ya está")
        elif apply:
            status, loc = asc.request("POST", "/v1/subscriptionLocalizations", {
                "data": {
                    "type": "subscriptionLocalizations",
                    "attributes": {"locale": LOCALE, "name": product["display"], "description": product["description"]},
                    "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}}},
                }
            })
            print("  texto:", "ok" if status < 300 else ASC.errors(loc))

        # 4. Precio: España y sus equivalentes
        status, prices = asc.request("GET", f"/v1/subscriptions/{sid}/prices", params={"limit": 1})
        if prices.get("data"):
            print("  precio: ya está")
        elif apply:
            status, points = asc.request(
                "GET", f"/v1/subscriptions/{sid}/pricePoints",
                params={"filter[territory]": BASE_TERRITORY, "limit": 8000},
            )
            point = next(
                (p for p in points.get("data", []) if p["attributes"]["customerPrice"] == product["price"]),
                None,
            )
            if not point:
                print(f"  ERROR: no hay punto de precio de {product['price']} € en España")
                continue
            status, equal = asc.request(
                "GET", f"/v1/subscriptionPricePoints/{point['id']}/equalizations",
                params={"limit": 8000, "include": "territory"},
            )
            all_points = [point] + equal.get("data", [])
            failures = 0
            for price_point in all_points:
                status, created = asc.request("POST", "/v1/subscriptionPrices", {
                    "data": {
                        "type": "subscriptionPrices",
                        "attributes": {"preserveCurrentPrice": False},
                        "relationships": {
                            "subscription": {"data": {"type": "subscriptions", "id": sid}},
                            "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": price_point["id"]}},
                        },
                    }
                })
                if status >= 300:
                    failures += 1
            print(f"  precio: {product['price']} € en España y {len(all_points) - 1} países más · fallos {failures}")

        # 5. Todos los países
        status, availability = asc.request("GET", f"/v1/subscriptions/{sid}/subscriptionAvailability")
        if availability.get("data"):
            print("  países: ya está")
        elif apply:
            if territories is None:
                status, terr = asc.request("GET", "/v1/territories", params={"limit": 200})
                territories = [{"type": "territories", "id": t["id"]} for t in terr.get("data", [])]
            status, created = asc.request("POST", "/v1/subscriptionAvailabilities", {
                "data": {
                    "type": "subscriptionAvailabilities",
                    "attributes": {"availableInNewTerritories": True},
                    "relationships": {
                        "subscription": {"data": {"type": "subscriptions", "id": sid}},
                        "availableTerritories": {"data": territories},
                    },
                }
            })
            print(f"  países: {len(territories)}", "ok" if status < 300 else ASC.errors(created))

    print("\nFalta, en la web: la captura de revisión de cada suscripción.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
