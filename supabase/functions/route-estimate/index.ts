// POST { from:{lat,lng}, to:{lat,lng}, category? } -> { distanceM, durationS, rawDurationS, recommendedPrice, path }
// La durée affichée applique le coefficient de trafic de la zone (OSRM ignore la circulation).
import { corsHeaders, fail, json, num, rateLimited, requireUser, userClient } from "../_shared/http.ts";
import { haversineM, routeBetween } from "../_shared/geo.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", 405);

  const user = await requireUser(req);
  if (!user) return fail("unauthorized", 401);
  if (rateLimited(`route:${user.id}`, 20, 60_000)) return fail("rate_limited", 429);

  let body: Record<string, any>;
  try { body = await req.json(); } catch { return fail("invalid_json", 400); }
  const a = { lat: num(body.from?.lat, -90, 90), lng: num(body.from?.lng, -180, 180) };
  const b = { lat: num(body.to?.lat, -90, 90), lng: num(body.to?.lng, -180, 180) };
  if (a.lat === null || a.lng === null || b.lat === null || b.lng === null) return fail("invalid_coordinates", 400);
  const from = { lat: a.lat, lng: a.lng }, to = { lat: b.lat, lng: b.lng };
  const category = typeof body.category === "string" ? body.category : "course";

  const db = userClient(req);
  const { data: zoneId } = await db.rpc("zone_for_point", { p_lng: from.lng, p_lat: from.lat });
  if (!zoneId) return fail("zone_not_served", 422, "Le point de départ est hors de la zone desservie.");

  try {
    const route = await routeBetween(from, to);
    // une réponse incohérente (détour > 5 x le vol d'oiseau) est rejetée plutôt que facturée
    if (route.distanceM > haversineM(from, to) * 5 + 500) return fail("route_implausible", 502);

    const { data: adjusted } = await db.rpc("adjusted_duration_s", { p_zone: zoneId, p_osrm_seconds: route.durationS });
    const { data: cat } = await db.from("ride_categories").select("id").eq("code", category).eq("active", true).maybeSingle();
    let recommended: number | null = null;
    if (cat) {
      const r = await db.rpc("recommended_price", { p_zone: zoneId, p_category: cat.id, p_distance_m: route.distanceM });
      recommended = r.data ?? null;
    }
    return json({
      distanceM: route.distanceM,
      durationS: adjusted ?? route.durationS,
      rawDurationS: route.durationS,
      recommendedPrice: recommended,
      path: route.path,
    });
  } catch (e) {
    console.error("route-estimate", String(e));
    return fail("provider_unavailable", 502, "Le calcul d'itinéraire est indisponible.");
  }
});
