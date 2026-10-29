// Envoie une notification push (FCM HTTP v1) à un utilisateur. NON TESTÉ : demande un projet Firebase de l'utilisateur.
// Appelée par un webhook de base (Database Webhooks) ou par une autre fonction, jamais par l'app :
// protégée par un secret partagé PUSH_DISPATCH_SECRET.
// POST { user_id, title, body, data? }
import { adminClient, env, fail, json } from "../_shared/http.ts";

const enc = new TextEncoder();
const b64url = (b: ArrayBuffer | string) => {
  const bytes = typeof b === "string" ? enc.encode(b) : new Uint8Array(b);
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

async function accessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const head = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = b64url(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, enc.encode(`${head}.${claim}`)));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${head}.${claim}.${sig}` }),
  });
  if (!res.ok) throw new Error(`oauth_${res.status}`);
  return (await res.json()).access_token;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return fail("method_not_allowed", 405);
  if (req.headers.get("x-dispatch-secret") !== env("PUSH_DISPATCH_SECRET")) return fail("unauthorized", 401);

  let b: Record<string, any>;
  try { b = await req.json(); } catch { return fail("invalid_json", 400); }
  if (typeof b.user_id !== "string" || typeof b.title !== "string" || b.title.length > 120) return fail("invalid_payload", 400);

  const admin = adminClient();
  const { data: tokens } = await admin.from("device_tokens").select("token").eq("user_id", b.user_id);
  if (!tokens?.length) return json({ sent: 0 });

  const sa = JSON.parse(env("FCM_SERVICE_ACCOUNT_JSON"));
  const bearer = await accessToken(sa);
  let sent = 0;
  for (const { token } of tokens) {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
      body: JSON.stringify({ message: { token, notification: { title: b.title, body: b.body ?? "" }, data: b.data ?? {},
        android: { priority: "HIGH" } } }),
    });
    if (res.ok) sent++;
    else if (res.status === 404) await admin.from("device_tokens").delete().eq("token", token);   // jeton périmé
  }
  return json({ sent });
});
