// POST { q, lat?, lng? } -> { results: [{ label, lat, lng }] }
// Biaisé autour de la zone du passager ; ne renvoie que des lieux de la zone desservie.
import { corsHeaders, fail, json, num, rateLimited, requireUser, str, userClient } from "../_shared/http.ts";
import { searchPlaces } from "../_shared/geo.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", 405);

  const user = await requireUser(req);
  if (!user) return fail("unauthorized", 401);
  if (rateLimited(`places:${user.id}`, 30, 60_000)) return fail("rate_limited", 429);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return fail("invalid_json", 400); }
  const q = str(body.q, 2, 120);
  if (!q) return fail("invalid_query", 400, "La recherche doit faire entre 2 et 120 caractères.");
  const lat = num(body.lat, -90, 90) ?? 5.34;
  const lng = num(body.lng, -180, 180) ?? -4.02;

  try {
    const found = await searchPlaces(q, { lat, lng });
    // lieux dans une zone desservie uniquement (la fonction SQL de la base fait foi)
    const db = userClient(req);
    const results = [];
    for (const p of found) {
      const { data } = await db.rpc("zone_for_point", { p_lng: p.lng, p_lat: p.lat });
      if (data) results.push({ label: p.label, lat: p.lat, lng: p.lng });
    }
    return json({ results });
  } catch (e) {
    console.error("places-autocomplete", String(e));
    return fail("provider_unavailable", 502, "La recherche d'adresses est indisponible.");
  }
});
