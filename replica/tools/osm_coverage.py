#!/usr/bin/env python3
"""Test de couverture Photon (adresses) et OSRM (itinéraires), sans clé. Bibliothèque standard seulement.

    SSL_CERT_FILE=/etc/ssl/cert.pem python3 osm_coverage.py
    python3 osm_coverage.py --only photon | osrm | search

Mêmes lieux et mêmes références que yandex_coverage.py (importés de là), pour comparer à égalité.
Ce sont des services publics de démonstration : 1 requête par seconde, ~20 requêtes au total.
Ne servent pas à la production (voir « Que faire ensuite » dans les conclusions du test).
"""
import argparse, json, os, sys, time, urllib.parse, urllib.request, urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from yandex_coverage import PLACES, ROUTES, SUGGEST_QUERIES, km  # noqa: E402

PHOTON = "https://photon.komoot.io/api/"
OSRM = "https://router.project-osrm.org"
UA = "replica-coverage-test/0.1 (contact: voir le dépôt)"


def get(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=25) as r:
            return json.load(r), None
    except urllib.error.HTTPError as e:
        return None, "HTTP %s %s" % (e.code, e.read().decode("utf-8", "replace")[:120])
    except Exception as e:
        return None, "%s: %s" % (type(e).__name__, str(e)[:120])
    finally:
        time.sleep(1)


def label_of(props):
    parts = [props.get(k) for k in ("name", "street", "district", "city", "county", "state", "country")]
    seen, out = set(), []
    for p in parts:
        if p and p not in seen:
            seen.add(p); out.append(p)
    return ", ".join(out)


def photon(results, near):
    print("\n== Photon : le lieu saisi est-il retrouvé au bon endroit ? ==")
    found = {}
    for label, text, lat, lon, tol in PLACES:
        q = urllib.parse.urlencode({"q": text, "limit": 3, "lat": near[0], "lon": near[1]})
        data, err = get(PHOTON + "?" + q)
        if err:
            print(" ?? %-30s non vérifié (%s)" % (label, err)); results.append(("photon", label, None)); continue
        feats = data.get("features", [])
        if not feats:
            print(" KO %-30s aucun résultat" % label); results.append(("photon", label, False)); continue
        best = min(feats, key=lambda f: km((lat, lon), (f["geometry"]["coordinates"][1], f["geometry"]["coordinates"][0])))
        lo, la = best["geometry"]["coordinates"]
        d = km((lat, lon), (la, lo))
        ok = d <= tol
        print(" %s %-30s écart %.1f km (tol. %.0f) : %s" % ("OK" if ok else "KO", label, d, tol, label_of(best["properties"])))
        results.append(("photon", label, ok)); found[label] = (la, lo)
    return found


def search(results, near):
    print("\n== Photon, recherche en saisie (ce que verrait le passager) ==")
    for qtxt in SUGGEST_QUERIES:
        q = urllib.parse.urlencode({"q": qtxt, "limit": 5, "lat": near[0], "lon": near[1]})
        data, err = get(PHOTON + "?" + q)
        if err:
            print(" ?? %-18s non vérifié (%s)" % (qtxt, err)); results.append(("search", qtxt, None)); continue
        feats = data.get("features", [])
        ci = [f for f in feats if f["properties"].get("countrycode") == "CI"]
        ok = len(ci) > 0
        names = " | ".join(label_of(f["properties"]) for f in ci[:2]) or "-"
        print(" %s %-18s %d résultats, %d en Côte d'Ivoire : %s" % ("OK" if ok else "KO", qtxt, len(feats), len(ci), names))
        results.append(("search", qtxt, ok))


def osrm(results, coords):
    print("\n== OSRM : distance par la route plausible ? (durée sans trafic) ==")
    ref = {p[0]: (p[2], p[3]) for p in PLACES}
    for a, b, expect, tol in ROUTES:
        pa, pb = coords.get(a, ref[a]), coords.get(b, ref[b])
        url = "%s/route/v1/driving/%f,%f;%f,%f?overview=false" % (OSRM, pa[1], pa[0], pb[1], pb[0])
        data, err = get(url)
        name = "%s > %s" % (a, b)
        if err:
            print(" ?? %-42s non vérifié (%s)" % (name, err)); results.append(("osrm", name, None)); continue
        if data.get("code") != "Ok" or not data.get("routes"):
            print(" KO %-42s %s" % (name, data.get("code"))); results.append(("osrm", name, False)); continue
        r = data["routes"][0]
        dist, dur = r["distance"] / 1000.0, r["duration"] / 60.0
        gap = abs(dist - expect) / expect * 100
        ok = gap <= tol
        print(" %s %-42s %.1f km, %.0f min (référence %.0f km, écart %.0f %%)" % ("OK" if ok else "KO", name, dist, dur, expect, gap))
        results.append(("osrm", name, ok))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", choices=["photon", "search", "osrm"])
    a = ap.parse_args()
    results, coords, near = [], {}, (5.34, -4.02)
    if a.only in (None, "photon"): coords = photon(results, near)
    if a.only in (None, "search"): search(results, near)
    if a.only in (None, "osrm"): osrm(results, coords)
    ok = sum(r[2] is True for r in results); ko = sum(r[2] is False for r in results); nv = sum(r[2] is None for r in results)
    print("\nRésumé : %d OK, %d KO, %d non vérifiés sur %d tests." % (ok, ko, nv, len(results)))
    return 1 if ko else 0


if __name__ == "__main__":
    sys.exit(main())
