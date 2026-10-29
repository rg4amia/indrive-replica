#!/usr/bin/env python3
"""Test de couverture de Yandex pour Abidjan et Bonoua. Bibliothèque standard seulement.

    export YANDEX_GEOCODER_KEY=...     # clé « JavaScript API et HTTP Geocoder » (YANDEX_GEOCODER_API_KEY marche aussi)
    export YANDEX_SUGGEST_KEY=...      # clé « Geosuggest API » (peut être la même selon votre contrat)
    export YANDEX_ROUTER_KEY=...       # clé « Router API »
    python3 yandex_coverage.py                 # tout
    python3 yandex_coverage.py --only geocode  # geocode | suggest | route
    python3 yandex_coverage.py --dry-run       # affiche les requêtes sans les envoyer

Les clés ne sont lues que dans l'environnement et jamais affichées. Une requête par ligne de test,
avec une pause de 1 s : c'est un test, pas une collecte. Les points de référence sont approximatifs
(±1 km) ; le verdict mesure l'écart, pas la vérité absolue. Les adresses viennent de vos captures.
Les points d'accès et paramètres ci-dessous sont à confirmer dans la documentation Yandex de votre
contrat : une erreur HTTP est affichée telle quelle et comptée comme « non vérifié », pas comme un échec de couverture.
"""
import argparse, json, math, os, sys, time, urllib.parse, urllib.request, urllib.error

GEOCODER = "https://geocode-maps.yandex.ru/1.x/"
SUGGEST = "https://suggest-maps.yandex.ru/v1/suggest"
ROUTER = "https://api.routing.yandex.net/v2/route"

# (libellé, texte saisi, lat, lon attendus approximatifs, tolérance km)
PLACES = [
    ("Cocody, 7e Tranche", "Cocody 7e Tranche, Abidjan", 5.3560, -3.9890, 3.0),
    ("Bonoua", "Bonoua, Côte d'Ivoire", 5.2730, -3.5930, 4.0),
    ("Treichville", "Treichville, Abidjan", 5.2930, -4.0050, 3.0),
    ("Yopougon", "Yopougon, Abidjan", 5.3360, -4.0870, 4.0),
    ("Gare de Bassam, Treichville", "Gare de Bassam, Treichville, Abidjan", 5.2870, -4.0050, 3.0),
    ("CHU d'Angré", "Centre Hospitalier Universitaire d'Angré, Abidjan", 5.4000, -3.9840, 3.0),
]
# Trajets : (départ, arrivée, distance PAR LA ROUTE de référence en km, tolérance en %)
# Les distances de la liste de recherche de l'app originale (45,3 km pour Bonoua...) sont à vol d'oiseau :
# elles ne servent pas de référence. Ces valeurs sont mes estimations de la distance routière (autoroute du
# Sud pour Bonoua) : ordre de grandeur à ±15 %, pas une mesure. Vérifiez-les sur une carte avant de conclure.
ROUTES = [
    ("Cocody, 7e Tranche", "Bonoua", 58.0, 25),
    ("Cocody, 7e Tranche", "Treichville", 13.0, 35),
    ("Cocody, 7e Tranche", "Yopougon", 15.0, 35),
]
SUGGEST_QUERIES = ["bonoua", "treichville", "cosmos yopougon", "angré", "7e tranche", "rue l98 cocody"]


def km(a, b):
    r = 6371.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp, dl = p2 - p1, math.radians(b[1] - a[1])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def call(url, params, key_name, dry):
    key = os.environ.get(key_name, "")
    if not key and key_name == "YANDEX_GEOCODER_KEY":
        key = os.environ.get("YANDEX_GEOCODER_API_KEY", "")  # nom utilisé dans APP YANGO
    shown = dict(params, apikey="***")
    full = url + "?" + urllib.parse.urlencode(dict(params, apikey=key))
    if dry:
        print("   [dry-run]", url + "?" + urllib.parse.urlencode(shown))
        return None, "dry-run"
    if not key:
        return None, "clé %s absente (export dans CE terminal, avec export)" % key_name
    try:
        with urllib.request.urlopen(urllib.request.Request(full, headers={"User-Agent": "coverage-test"}), timeout=20) as r:
            return json.load(r), None
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:200].replace(key, "***")
        return None, "HTTP %s %s" % (e.code, body)
    except Exception as e:
        return None, "%s: %s" % (type(e).__name__, str(e).replace(key, "***"))
    finally:
        time.sleep(1)


def run_geocode(dry, results):
    print("\n== Geocoder : le lieu saisi est-il retrouvé au bon endroit ? ==")
    found = {}
    for label, text, lat, lon, tol in PLACES:
        data, err = call(GEOCODER, {"geocode": text, "format": "json", "results": 1, "lang": "en_US"}, "YANDEX_GEOCODER_KEY", dry)
        if err:
            print(" ?? %-30s non vérifié (%s)" % (label, err)); results.append(("geocode", label, None)); continue
        try:
            m = data["response"]["GeoObjectCollection"]["featureMember"][0]["GeoObject"]
            lon_g, lat_g = (float(x) for x in m["Point"]["pos"].split())
            d = km((lat, lon), (lat_g, lon_g))
            name = m["metaDataProperty"]["GeocoderMetaData"].get("text", "")
            kind = m["metaDataProperty"]["GeocoderMetaData"].get("kind", "")
            ok = d <= tol
            print(" %s %-30s écart %.1f km (tolérance %.0f) [%s] %s" % ("OK" if ok else "KO", label, d, tol, kind, name))
            results.append(("geocode", label, ok)); found[label] = (lat_g, lon_g)
        except (KeyError, IndexError):
            print(" KO %-30s aucun résultat" % label); results.append(("geocode", label, False))
    return found


def run_suggest(dry, results):
    print("\n== Suggest : propose-t-il des lieux pertinents près d'Abidjan ? ==")
    for q in SUGGEST_QUERIES:
        data, err = call(SUGGEST, {"text": q, "lang": "fr", "ll": "-4.02,5.34", "spn": "0.5,0.5", "results": 5, "print_address": 1}, "YANDEX_SUGGEST_KEY", dry)
        if err:
            print(" ?? %-18s non vérifié (%s)" % (q, err)); results.append(("suggest", q, None)); continue
        items = data.get("results", [])
        titles = [i.get("title", {}).get("text", "?") for i in items]
        ci = sum(1 for i in items if any(w in json.dumps(i, ensure_ascii=False).lower() for w in ("abidjan", "ivoire", "ivory", "bonoua")))
        ok = len(items) > 0 and ci > 0
        print(" %s %-18s %d résultats dont %d en Côte d'Ivoire : %s" % ("OK" if ok else "KO", q, len(items), ci, " | ".join(titles[:3])))
        results.append(("suggest", q, ok))


def run_route(dry, results, coords):
    print("\n== Router : distance par la route plausible ? (durée sans trafic, à ne pas comparer à l'écran de l'app) ==")
    ref = {p[0]: (p[2], p[3]) for p in PLACES}
    for a, b, expect, tol in ROUTES:
        pa, pb = coords.get(a, ref[a]), coords.get(b, ref[b])
        data, err = call(ROUTER, {"waypoints": "%f,%f|%f,%f" % (pa[0], pa[1], pb[0], pb[1]), "mode": "driving"}, "YANDEX_ROUTER_KEY", dry)
        label = "%s > %s" % (a, b)
        if err:
            print(" ?? %-42s non vérifié (%s)" % (label, err)); results.append(("route", label, None)); continue
        try:
            leg = data["route"]["legs"][0]["steps"]
            dist = sum(s["length"] for s in leg) / 1000.0
            dur = sum(s.get("duration", 0) for s in leg) / 60.0
        except (KeyError, IndexError, TypeError):
            print(" KO %-42s réponse sans itinéraire : %s" % (label, json.dumps(data)[:120])); results.append(("route", label, False)); continue
        gap = abs(dist - expect) / expect * 100
        ok = gap <= tol
        print(" %s %-42s %.1f km, %.0f min (référence %.0f km, écart %.0f %%)" % ("OK" if ok else "KO", label, dist, dur, expect, gap))
        results.append(("route", label, ok))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", choices=["geocode", "suggest", "route"])
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    results, coords = [], {}
    if a.only in (None, "geocode", "route"):
        coords = run_geocode(a.dry_run, results) if a.only != "route" else {}
    if a.only in (None, "suggest"):
        run_suggest(a.dry_run, results)
    if a.only in (None, "route"):
        run_route(a.dry_run, results, coords)
    ok = sum(1 for r in results if r[2] is True); ko = sum(1 for r in results if r[2] is False); nv = sum(1 for r in results if r[2] is None)
    print("\nRésumé : %d OK, %d KO, %d non vérifiés sur %d tests." % (ok, ko, nv, len(results)))
    if nv:
        print("Des tests non vérifiés ne disent rien de la couverture : corrigez la clé, l'URL ou les paramètres d'abord.")
    elif ko == 0 and not a.dry_run:
        print("Couverture correcte sur ces lieux. Ce n'est pas une preuve pour toute la ville : élargissez la liste avec vos adresses réelles.")
    elif ko and not nv:
        print("Écarts constatés : regardez les lignes KO avant de vous engager sur Yandex.")
    return 1 if ko else 0


if __name__ == "__main__":
    sys.exit(main())
