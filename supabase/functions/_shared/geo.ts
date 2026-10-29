// Adresses (Photon) et itinéraires (OSRM). Les points d'accès sont configurables :
// les serveurs publics servent aux essais, pas à la production (voir replica/backend.md).

export interface PlaceResult {
  label: string;
  lat: number;
  lng: number;
  countryCode: string | null;
}

export interface RouteResult {
  distanceM: number;
  durationS: number;
  path: { lat: number; lng: number }[];
}

const PHOTON = () => Deno.env.get("PHOTON_URL") ?? "https://photon.komoot.io/api/";
const OSRM = () => Deno.env.get("OSRM_URL") ?? "https://router.project-osrm.org";
const UA = () => Deno.env.get("GEO_USER_AGENT") ?? "vtc-app-backend/0.1";

export function placeLabel(p: Record<string, unknown>): string {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const k of ["name", "street", "district", "city", "county", "state", "country"]) {
    const v = p[k];
    if (typeof v === "string" && v && !seen.has(v)) {
      seen.add(v);
      out.push(v);
    }
  }
  return out.join(", ");
}

export async function searchPlaces(query: string, near: { lat: number; lng: number }, limit = 8, f = fetch): Promise<PlaceResult[]> {
  const url = new URL(PHOTON());
  url.searchParams.set("q", query);
  url.searchParams.set("limit", String(limit));
  url.searchParams.set("lat", String(near.lat));
  url.searchParams.set("lon", String(near.lng));
  const res = await f(url, { headers: { "User-Agent": UA() }, signal: AbortSignal.timeout(8000) });
  if (!res.ok) throw new Error(`photon_${res.status}`);
  const body = await res.json();
  const out: PlaceResult[] = [];
  for (const feat of body.features ?? []) {
    const c = feat?.geometry?.coordinates;
    if (!Array.isArray(c) || c.length < 2) continue;
    out.push({
      label: placeLabel(feat.properties ?? {}),
      lat: c[1],
      lng: c[0],
      countryCode: feat.properties?.countrycode ?? null,
    });
  }
  return out;
}

/** Itinéraire par la route. Tracé échantillonné à 200 points pour alléger la réponse. */
export async function routeBetween(a: { lat: number; lng: number }, b: { lat: number; lng: number }, f = fetch): Promise<RouteResult> {
  const url = `${OSRM()}/route/v1/driving/${a.lng},${a.lat};${b.lng},${b.lat}?overview=full&geometries=geojson`;
  const res = await f(url, { headers: { "User-Agent": UA() }, signal: AbortSignal.timeout(8000) });
  if (!res.ok) throw new Error(`osrm_${res.status}`);
  const body = await res.json();
  const r = body.routes?.[0];
  if (body.code !== "Ok" || !r) throw new Error("osrm_no_route");
  const coords: [number, number][] = r.geometry?.coordinates ?? [];
  const step = Math.max(1, Math.ceil(coords.length / 200));
  const path = coords.filter((_, i) => i % step === 0 || i === coords.length - 1).map(([lng, lat]) => ({ lat, lng }));
  return { distanceM: Math.round(r.distance), durationS: Math.round(r.duration), path };
}

export function haversineM(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const R = 6371000, rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad, dLng = (b.lng - a.lng) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}
