// Webhook de paiement (recharge du solde chauffeur). Le FOURNISSEUR N'EST PAS CHOISI (voir replica/backend.md).
// Ce code fait ce qui est commun à tous : vérifier la signature, refuser les rejeux, créditer une seule fois.
// Adapter `parse()` au format du fournisseur retenu. Il attend ce format neutre :
//   en-tête  x-signature : hex(HMAC-SHA256(PSP_WEBHOOK_SECRET, corps brut))
//   corps    { "id": "evt_...", "type": "payment.succeeded", "reference": "...", "driver_id": "<uuid>", "amount": 5000 }
import { adminClient, env, fail, json } from "../_shared/http.ts";

const encoder = new TextEncoder();

function toHex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Comparaison en temps constant. */
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function sign(secret: string, raw: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return toHex(await crypto.subtle.sign("HMAC", key, encoder.encode(raw)));
}

interface TopupEvent { eventId: string; reference: string; driverId: string; amount: number; type: string }

export function parse(raw: string): TopupEvent | null {
  let b: Record<string, unknown>;
  try { b = JSON.parse(raw); } catch { return null; }
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (typeof b.id !== "string" || typeof b.type !== "string" || typeof b.reference !== "string") return null;
  if (typeof b.driver_id !== "string" || !uuid.test(b.driver_id)) return null;
  if (typeof b.amount !== "number" || !Number.isInteger(b.amount)) return null;
  return { eventId: b.id, reference: b.reference, driverId: b.driver_id, amount: b.amount, type: b.type };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return fail("method_not_allowed", 405);
  const raw = await req.text();
  if (raw.length > 20_000) return fail("payload_too_large", 413);

  const expected = await sign(env("PSP_WEBHOOK_SECRET"), raw);
  const given = (req.headers.get("x-signature") ?? "").toLowerCase();
  if (!safeEqual(expected, given)) return fail("invalid_signature", 401);

  const ev = parse(raw);
  if (!ev) return fail("invalid_payload", 400);
  if (ev.type !== "payment.succeeded") return json({ ignored: ev.type });   // 200 : le fournisseur ne doit pas réessayer

  const { data, error } = await adminClient().rpc("credit_topup", {
    p_provider: Deno.env.get("PSP_NAME") ?? "psp",
    p_event_id: ev.eventId,
    p_driver: ev.driverId,
    p_amount: ev.amount,
    p_external_ref: ev.reference,
    p_payload: JSON.parse(raw),
  });
  if (error) {
    console.error("psp-webhook", error.message);
    return fail("processing_failed", 500);   // 5xx : le fournisseur réessaiera, l'idempotence protège
  }
  return json({ result: data });
});
