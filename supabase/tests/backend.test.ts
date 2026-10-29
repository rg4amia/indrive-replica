// Tests d'intégration contre la pile Supabase locale (vrais comptes, vrais JWT, vraies règles d'accès).
//   supabase db reset && supabase functions serve --env-file supabase/.env.local   (dans un autre terminal)
//   eval "$(supabase status -o env | sed 's/^/export /')" ; deno test --allow-net --allow-env supabase/tests/backend.test.ts
// Les clés viennent de l'environnement et ne sont jamais affichées.

const URL_ = Deno.env.get("API_URL")!.replace(/"/g, "");
const ANON = Deno.env.get("ANON_KEY")!.replace(/"/g, "");
const SERVICE = Deno.env.get("SERVICE_ROLE_KEY")!.replace(/"/g, "");
const WEBHOOK_SECRET = "local-test-webhook-secret";

const ZONE = "00000000-0000-0000-0000-0000000000f1";
const PICKUP = { lng: -4.0, lat: 5.35 };
const DROP = { lng: -3.95, lat: 5.4 };

interface Session { id: string; jwt: string; refresh: string }

async function call(path: string, opts: { method?: string; key?: string; jwt?: string; body?: unknown; headers?: Record<string, string>; raw?: BodyInit } = {}) {
  const res = await fetch(`${URL_}${path}`, {
    method: opts.method ?? (opts.body !== undefined || opts.raw !== undefined ? "POST" : "GET"),
    headers: {
      apikey: opts.key ?? ANON,
      Authorization: `Bearer ${opts.jwt ?? opts.key ?? ANON}`,
      ...(opts.body !== undefined ? { "Content-Type": "application/json" } : {}),
      ...opts.headers,
    },
    body: opts.raw ?? (opts.body !== undefined ? JSON.stringify(opts.body) : undefined),
  });
  const text = await res.text();
  let data: any = text;
  try { data = JSON.parse(text); } catch { /* texte brut */ }
  return { status: res.status, data };
}

const rpc = (fn: string, s: Session | null, args: Record<string, unknown> = {}) =>
  call(`/rest/v1/rpc/${fn}`, { body: args, jwt: s?.jwt });
const rest = (path: string, s: Session | null, init: { method?: string; body?: unknown; prefer?: string } = {}) =>
  call(`/rest/v1/${path}`, { method: init.method, body: init.body, jwt: s?.jwt, headers: init.prefer ? { Prefer: init.prefer } : {} });
const service = (path: string, init: { method?: string; body?: unknown } = {}) =>
  call(`/rest/v1/${path}`, { key: SERVICE, method: init.method, body: init.body, headers: { Prefer: "return=representation" } });

function ok(cond: unknown, msg: string) { if (!cond) throw new Error(`ÉCHEC : ${msg}`); }
function eq(a: unknown, b: unknown, msg: string) { if (a !== b) throw new Error(`ÉCHEC : ${msg} (obtenu ${JSON.stringify(a)}, attendu ${JSON.stringify(b)})`); }
function errMsg(r: { data: any }): string { return String(r.data?.message ?? r.data?.error ?? JSON.stringify(r.data)); }
function failsWith(r: { status: number; data: any }, code: string, msg: string) {
  ok(r.status >= 400, `${msg} : devait échouer, statut ${r.status}`);
  ok(errMsg(r).includes(code), `${msg} : message attendu « ${code} », obtenu « ${errMsg(r)} »`);
}
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** Connexion par téléphone avec un numéro de test déclaré dans config.toml (aucun SMS réel). */
async function login(phoneDigits: string): Promise<Session> {
  const phone = `+${phoneDigits}`;
  const otp = await call("/auth/v1/otp", { body: { phone } });
  ok(otp.status < 300, `envoi du code : ${errMsg(otp)}`);
  const v = await call("/auth/v1/verify", { body: { type: "sms", phone, token: "123456" } });
  ok(v.status < 300 && v.data.access_token, `vérification du code : ${errMsg(v)}`);
  await sleep(5200);   // Supabase limite l'envoi de code à un par 5 s et par numéro
  return { id: v.data.user.id, jwt: v.data.access_token, refresh: v.data.refresh_token };
}

/** Nouveau JWT sans nouveau SMS : reprend les claims à jour (app_metadata) après une modification côté serveur. */
async function refresh(s: Session): Promise<Session> {
  const r = await call("/auth/v1/token?grant_type=refresh_token", { body: { refresh_token: s.refresh } });
  ok(r.status < 300, `rafraîchissement : ${errMsg(r)}`);
  return { id: s.id, jwt: r.data.access_token, refresh: r.data.refresh_token };
}

Deno.test("backend", async (t) => {
  let riderA!: Session, riderB!: Session, driver!: Session, admin!: Session;
  let catConfort = "", catCourse = "";
  const docIds: string[] = [];
  let vehicleId = "";

  await t.step("connexion par téléphone : 4 comptes, profils créés par le serveur", async () => {
    riderA = await login("22507000001");
    riderB = await login("22507000002");
    driver = await login("22507000003");
    const adm = await login("22507000004");
    // le rôle admin ne se pose que côté serveur (app_metadata), puis on se reconnecte pour obtenir le JWT à jour
    const set = await call(`/auth/v1/admin/users/${adm.id}`, { method: "PUT", key: SERVICE, body: { app_metadata: { role: "admin" } } });
    ok(set.status < 300, `pose du rôle admin : ${errMsg(set)}`);
    admin = await refresh(adm);
    const p = await rest(`profiles?id=eq.${riderA.id}&select=id,status`, riderA);
    eq(p.data.length, 1, "le profil du passager A existe");
    eq(p.data[0].status, "active", "profil actif par défaut");
    const cats = await rest("ride_categories?select=id,code", riderA);
    catConfort = cats.data.find((c: any) => c.code === "confort").id;
    catCourse = cats.data.find((c: any) => c.code === "course").id;
  });

  await t.step("accès : anonyme et second utilisateur n'ont rien", async () => {
    failsWith(await rpc("create_ride_request", null, {}), "", "un anonyme ne peut pas commander");
    const anon = await call("/rest/v1/profiles?select=id");
    ok(anon.status >= 400 || (Array.isArray(anon.data) && anon.data.length === 0), "un anonyme ne lit aucun profil");
    const other = await rest(`profiles?id=eq.${riderA.id}&select=id`, riderB);
    eq(other.data.length, 0, "le passager B ne voit pas le profil du passager A");
    const settings = await rest("app_settings?select=*", riderA);
    ok(settings.status >= 400, "app_settings est illisible côté client");
    const w = await rest("wallet_entries", riderA, { method: "POST", body: { driver_id: riderA.id, kind: "topup", amount: 999999 } });
    ok(w.status >= 400, "écrire dans le journal du solde est interdit");
    const upd = await rest(`profiles?id=eq.${riderB.id}`, riderA, { method: "PATCH", body: { full_name: "Pirate" }, prefer: "return=representation" });
    ok(Array.isArray(upd.data) ? upd.data.length === 0 : upd.status >= 400, "A ne modifie pas le profil de B");
    const status = await rest(`profiles?id=eq.${riderA.id}`, riderA, { method: "PATCH", body: { status: "blocked" } });
    ok(status.status >= 400, "un utilisateur ne peut pas changer son propre statut");
    const mine = await rest(`profiles?id=eq.${riderA.id}`, riderA, { method: "PATCH", body: { full_name: "Awa Test" }, prefer: "return=representation" });
    eq(mine.data[0]?.full_name, "Awa Test", "il modifie son propre nom");
  });

  await t.step("inscription chauffeur : dossier incomplet refusé, catégorie imposée, validation par l'administrateur", async () => {
    const d = await rpc("become_driver", driver, { p_zone: ZONE });
    eq(d.data.verification_status, "draft", "dossier en brouillon");
    failsWith(await rpc("submit_driver_application", driver), "document_missing", "dossier sans documents");

    const v = await rest("vehicles", driver, { body: { driver_id: driver.id, category_id: catConfort, make: "Suzuki", model: "Dzire", plate: "AB 123 CD" }, prefer: "return=representation" });
    ok(v.status < 300, `ajout du véhicule : ${errMsg(v)}`);
    vehicleId = v.data[0].id;
    eq(v.data[0].category_id, catCourse, "un chauffeur ne peut pas s'attribuer la catégorie Confort");
    const up = await rest(`vehicles?id=eq.${vehicleId}`, driver, { method: "PATCH", body: { category_id: catConfort }, prefer: "return=representation" });
    eq(up.data[0].category_id, catCourse, "ni la modifier ensuite");

    for (const type of ["id_card", "licence", "vehicle_registration", "selfie", "vehicle_photo"]) {
      const r = await rest("driver_documents", driver, { body: { driver_id: driver.id, type, file_path: `${driver.id}/${type}.png` }, prefer: "return=representation" });
      ok(r.status < 300, `document ${type} : ${errMsg(r)}`);
      docIds.push(r.data[0].id);
    }
    const forged = await rest("driver_documents", driver, { body: { driver_id: driver.id, type: "id_card", file_path: "x.png", status: "approved" } });
    ok(forged.status >= 400, "un chauffeur ne peut pas insérer un document déjà approuvé");

    const sub = await rpc("submit_driver_application", driver);
    eq(sub.data.verification_status, "pending", "dossier soumis");
    failsWith(await rpc("admin_review_driver", driver, { p_driver: driver.id, p_approve: true }), "forbidden", "un chauffeur ne se valide pas lui-même");
    failsWith(await rpc("admin_review_driver", admin, { p_driver: driver.id, p_approve: true }), "documents_not_all_approved", "validation sans documents approuvés");
    failsWith(await rpc("admin_review_document", admin, { p_doc: docIds[0], p_approve: false }), "reason_required", "rejet sans motif");

    for (const id of docIds) ok((await rpc("admin_review_document", admin, { p_doc: id, p_approve: true })).status < 300, "approbation d'un document");
    const approved = await rpc("admin_review_driver", admin, { p_driver: driver.id, p_approve: true });
    eq(approved.data.verification_status, "approved", "chauffeur approuvé");
    const n = await rest("notifications?select=title", driver);
    ok(n.data.some((x: any) => x.title.includes("validé")), "le chauffeur est prévenu");
  });

  await t.step("colonnes privées : solde, priorité et commission invisibles des autres", async () => {
    const own = await rpc("my_driver_state", driver);
    eq(own.data[0].verification_status, "approved", "le chauffeur lit son état");
    eq(own.data[0].commission_rate_bps, 1000, "le chauffeur vérifié voit le taux");
    const denied = await rest(`driver_profiles?user_id=eq.${driver.id}&select=balance`, riderA);
    ok(denied.status >= 400, "le solde d'un chauffeur n'est pas lisible par un tiers");
    const prio = await rest(`driver_profiles?user_id=eq.${driver.id}&select=priority_score`, driver);
    ok(prio.status >= 400, "même le chauffeur ne lit pas sa priorité par l'API de table (passe par my_driver_state)");
    const fakeBal = await rest(`driver_profiles?user_id=eq.${driver.id}`, driver, { method: "PATCH", body: { balance: 9999999 } });
    ok(fakeBal.status >= 400, "le chauffeur ne peut pas modifier son solde");
    failsWith(await rpc("my_commission_rate", riderA), "driver_not_approved", "un passager ne lit pas le taux");
  });

  let requestId = "", offerId = "", rideId = "";
  await t.step("boucle complète : demande, offre, choix, « Je suis là », commission", async () => {
    ok((await rpc("set_driver_online", driver, { p_online: true })).status < 300, "chauffeur en ligne");
    ok((await rpc("update_driver_location", driver, { p_lng: PICKUP.lng, p_lat: PICKUP.lat })).status < 300, "position envoyée");

    const outside = await rpc("create_ride_request", riderA, {
      p_category: catCourse, p_pickup_lng: 2.35, p_pickup_lat: 48.85, p_pickup_address: "Paris", p_pickup_hint: null,
      p_dropoff_lng: 2.36, p_dropoff_lat: 48.86, p_dropoff_address: "Paris", p_distance_m: 5000, p_duration_s: 600, p_price: 3000,
    });
    failsWith(outside, "zone_not_served", "départ hors zone");

    const args = {
      p_category: catCourse, p_pickup_lng: PICKUP.lng, p_pickup_lat: PICKUP.lat, p_pickup_address: "Cocody", p_pickup_hint: "Porte d'entrée",
      p_dropoff_lng: DROP.lng, p_dropoff_lat: DROP.lat, p_dropoff_address: "Angré", p_distance_m: 8000, p_duration_s: 900, p_price: 3000,
    };
    failsWith(await rpc("create_ride_request", riderA, { ...args, p_price: 100 }), "price_too_low", "prix trop bas");
    const req = await rpc("create_ride_request", riderA, args);
    ok(req.status < 300, `demande : ${errMsg(req)}`);
    requestId = req.data.id;
    eq(req.data.recommended_price, 2500, "prix recommandé calculé par le serveur");
    failsWith(await rpc("create_ride_request", riderA, args), "request_already_open", "deuxième demande ouverte");

    const seenByDriver = await rpc("nearby_open_requests", driver);
    eq(seenByDriver.data.length, 1, "le chauffeur proche voit la demande");
    const seenByB = await rest(`ride_requests?id=eq.${requestId}&select=id`, riderB);
    eq(seenByB.data.length, 0, "un autre passager ne voit pas la demande");

    failsWith(await rpc("submit_offer", driver, { p_request: requestId, p_price: 9000, p_eta_seconds: 120, p_vehicle: vehicleId }), "price_out_of_band", "contre-offre hors bande");
    const offer = await rpc("submit_offer", driver, { p_request: requestId, p_price: 3300, p_eta_seconds: 120, p_vehicle: vehicleId });
    ok(offer.status < 300, `offre : ${errMsg(offer)}`);
    offerId = offer.data.id;
    eq(offer.data.kind, "counter", "contre-offre");

    const cards = await rpc("list_offers", riderA, { p_request: requestId });
    eq(cards.data.length, 1, "le passager voit l'offre");
    eq((await rpc("list_offers", riderB, { p_request: requestId })).data.length, 0, "B ne voit pas les offres de A");
    failsWith(await rpc("choose_offer", riderB, { p_offer: offerId }), "forbidden", "B ne choisit pas l'offre de A");

    const ride = await rpc("choose_offer", riderA, { p_offer: offerId });
    ok(ride.status < 300, `choix : ${errMsg(ride)}`);
    rideId = ride.data.id;
    failsWith(await rpc("choose_offer", riderA, { p_offer: offerId }), "offer_not_available", "second choix");

    const asRider = await rest(`rides?id=eq.${rideId}&select=id,agreed_price`, riderA);
    eq(asRider.data[0].agreed_price, 3300, "le passager lit sa course");
    const com = await rest(`rides?id=eq.${rideId}&select=commission`, riderA);
    ok(com.status >= 400, "la commission n'est pas lisible côté passager");
    eq((await rest(`rides?id=eq.${rideId}&select=id`, riderB)).data.length, 0, "B ne voit pas la course");

    eq(Number((await rpc("my_balance", driver)).data), 0, "solde nul avant la commission");
    ok((await rpc("driver_arrived", driver, { p_ride: rideId })).status < 300, "« Je suis là »");
    failsWith(await rpc("driver_arrived", driver, { p_ride: rideId }), "ride_not_in_pickup", "rejeu de « Je suis là »");
    eq(Number((await rpc("my_balance", driver)).data), -330, "commission de 10 % prélevée une seule fois");
    const led = await rest("wallet_entries?select=kind,amount", driver);
    eq(led.data.filter((x: any) => x.kind === "commission").length, 1, "une seule ligne de commission");
    eq((await rest("wallet_entries?select=kind", riderA)).data.length, 0, "le passager ne voit aucun solde");
  });

  await t.step("position : seul le chauffeur de la course l'enregistre, avec limite de débit", async () => {
    failsWith(await rpc("record_position", riderA, { p_ride: rideId, p_lng: -4.0, p_lat: 5.35 }), "ride_not_active", "le passager n'envoie pas de position");
    failsWith(await rpc("record_position", driver, { p_ride: rideId, p_lng: 999, p_lat: 5.35 }), "invalid_position", "position invalide");
    ok((await rpc("record_position", driver, { p_ride: rideId, p_lng: -3.99, p_lat: 5.36 })).status < 300, "position enregistrée");
    await rpc("record_position", driver, { p_ride: rideId, p_lng: -3.99, p_lat: 5.361 });   // dans les 2 s : ignorée
    const pts = await rest(`ride_positions?ride_id=eq.${rideId}&select=id`, riderA);
    eq(pts.data.length, 1, "la seconde position rapprochée est ignorée");
    eq((await rest(`ride_positions?ride_id=eq.${rideId}&select=id`, riderB)).data.length, 0, "B ne voit pas le tracé");
  });

  await t.step("annulation par le passager avant « je viens » : remboursement en attente", async () => {
    ok((await rpc("cancel_ride", riderA, { p_ride: rideId, p_reason: "changed_mind" })).status < 300, "annulation");
    const e = await rest("wallet_entries?select=kind,amount,status&order=created_at", driver);
    const refund = e.data.find((x: any) => x.kind === "refund");
    eq(refund?.status, "pending", "remboursement en attente");
    eq(Number((await rpc("my_balance", driver)).data), -330, "solde inchangé avant l'échéance");
    // on avance l'échéance (service_role) puis on laisse la tâche planifiée horaire ou on l'appelle
    await service(`wallet_entries?kind=eq.refund`, { method: "PATCH", body: { available_at: new Date(Date.now() - 60_000).toISOString() } });
    ok((await call("/rest/v1/rpc/settle_refunds", { key: SERVICE, body: {} })).status < 300, "règlement des remboursements");
    eq(Number((await rpc("my_balance", driver)).data), 0, "remboursé");
    const drift = await call("/rest/v1/rpc/balance_drift", { key: SERVICE, body: {} });
    eq(drift.data.length, 0, "le solde en cache égale le journal");
    failsWith(await rpc("balance_drift", driver), "", "balance_drift n'est pas appelable par un utilisateur");
  });

  await t.step("expiration : la tâche planifiée ferme les demandes dépassées", async () => {
    const args = {
      p_category: catCourse, p_pickup_lng: PICKUP.lng, p_pickup_lat: PICKUP.lat, p_pickup_address: "Cocody", p_pickup_hint: null,
      p_dropoff_lng: DROP.lng, p_dropoff_lat: DROP.lat, p_dropoff_address: "Angré", p_distance_m: 8000, p_duration_s: 900, p_price: 3000,
    };
    const r = await rpc("create_ride_request", riderB, args);
    ok(r.status < 300, `demande de B : ${errMsg(r)}`);
    await service(`ride_requests?id=eq.${r.data.id}`, { method: "PATCH", body: { expires_at: new Date(Date.now() - 1000).toISOString() } });
    let status = "open";
    for (let i = 0; i < 8 && status === "open"; i++) {
      await sleep(5000);
      status = (await rest(`ride_requests?id=eq.${r.data.id}&select=status`, riderB)).data[0].status;
    }
    eq(status, "expired", "pg_cron a expiré la demande dans les 40 s");
  });

  await t.step("documents : stockage privé, dossier personnel, images seulement", async () => {
    const png = Uint8Array.from(atob("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="), (c) => c.charCodeAt(0));
    const up = (s: Session, path: string, type = "image/png", body: BodyInit = png) =>
      call(`/storage/v1/object/driver-docs/${path}`, { jwt: s.jwt, raw: body, headers: { "Content-Type": type } });
    ok((await up(driver, `${driver.id}/id.png`)).status < 300, "dépôt dans son dossier");
    ok((await up(riderA, `${driver.id}/pirate.png`)).status >= 400, "dépôt dans le dossier d'un autre refusé");
    ok((await up(driver, `${driver.id}/x.pdf`, "application/pdf", "pdf")).status >= 400, "un PDF est refusé");
    const own = await call(`/storage/v1/object/driver-docs/${driver.id}/id.png`, { jwt: driver.jwt });
    eq(own.status, 200, "lecture de son document");
    ok((await call(`/storage/v1/object/driver-docs/${driver.id}/id.png`, { jwt: riderA.jwt })).status >= 400, "un autre utilisateur ne le lit pas");
    eq((await call(`/storage/v1/object/driver-docs/${driver.id}/id.png`, { jwt: admin.jwt })).status, 200, "l'administrateur le lit");
    ok((await call(`/storage/v1/object/public/driver-docs/${driver.id}/id.png`)).status >= 400, "aucun accès public");
  });

  await t.step("Edge Functions : authentification, validation, itinéraire réel, webhook signé", async () => {
    const fn = (name: string, s: Session | null, body: unknown) => call(`/functions/v1/${name}`, { jwt: s?.jwt, body });
    ok((await fn("places-autocomplete", null, { q: "bonoua" })).status === 401, "adresses : anonyme refusé");
    eq((await fn("places-autocomplete", riderA, { q: "b" })).status, 400, "adresses : saisie trop courte");
    const places = await fn("places-autocomplete", riderA, { q: "bonoua", lat: 5.34, lng: -4.02 });
    eq(places.status, 200, `adresses : ${errMsg(places)}`);
    ok(places.data.results.length > 0, "Bonoua trouvé par Photon");

    eq((await fn("route-estimate", riderA, { from: { lat: 999, lng: 0 }, to: { lat: 5, lng: -4 } })).status, 400, "itinéraire : coordonnées invalides");
    eq((await fn("route-estimate", riderA, { from: { lat: 48.85, lng: 2.35 }, to: { lat: 48.86, lng: 2.36 } })).status, 422, "itinéraire : départ hors zone");
    const route = await fn("route-estimate", riderA, { from: { lat: 5.356, lng: -3.989 }, to: { lat: 5.273, lng: -3.593 }, category: "course" });
    eq(route.status, 200, `itinéraire : ${errMsg(route)}`);
    ok(route.data.distanceM > 45000 && route.data.distanceM < 75000, `distance Cocody-Bonoua plausible (${route.data.distanceM} m)`);
    ok(route.data.recommendedPrice > 10000, "prix recommandé renvoyé");
    ok(route.data.path.length > 2 && route.data.path.length <= 201, "tracé échantillonné");

    // webhook : signature obligatoire, rejeu sans double crédit
    const payload = JSON.stringify({ id: "evt_1", type: "payment.succeeded", reference: "ref_1", driver_id: driver.id, amount: 5000 });
    const sign = async (body: string, secret = WEBHOOK_SECRET) => {
      const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
      return [...new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body)))].map((b) => b.toString(16).padStart(2, "0")).join("");
    };
    const hook = (body: string, sig: string) => call("/functions/v1/psp-webhook", { raw: body, headers: { "Content-Type": "application/json", "x-signature": sig } });
    eq((await hook(payload, "00")).status, 401, "webhook : mauvaise signature");
    eq((await hook(payload, await sign(payload, "autre-secret"))).status, 401, "webhook : mauvais secret");
    const good = await hook(payload, await sign(payload));
    eq(good.data.result, "credited", `webhook : crédit (${errMsg(good)})`);
    eq((await hook(payload, await sign(payload))).data.result, "duplicate", "webhook : rejeu sans second crédit");
    eq(Number((await rpc("my_balance", driver)).data), 5000, "solde crédité une seule fois");
    const bad = JSON.stringify({ id: "evt_2", type: "payment.succeeded", reference: "r", driver_id: "pas-un-uuid", amount: 5000 });
    eq((await hook(bad, await sign(bad))).status, 400, "webhook : charge invalide");
    const neg = JSON.stringify({ id: "evt_3", type: "payment.succeeded", reference: "r3", driver_id: driver.id, amount: -50 });
    ok((await hook(neg, await sign(neg))).status >= 400, "webhook : montant négatif refusé");
    eq(Number((await rpc("my_balance", driver)).data), 5000, "solde intact après les charges invalides");
    eq((await call("/functions/v1/push-dispatch", { body: { user_id: driver.id, title: "x" } })).status, 401, "push : secret partagé obligatoire");
  });

  await t.step("suppression de compte : bloquée pendant une course, puis anonymisation complète", async () => {
    const del = (s: Session) => call("/functions/v1/delete-account", { jwt: s.jwt, body: {} });
    eq((await del(riderA)).status, 200, "le passager A supprime son compte");
    const gone = await call(`/auth/v1/admin/users/${riderA.id}`, { key: SERVICE });
    ok(gone.status === 404 || gone.status >= 400, "l'identité n'existe plus");
    const prof = await service(`profiles?id=eq.${riderA.id}&select=*`);
    ok(prof.data.length === 0 || prof.data[0].full_name === null, "le nom est effacé");
    const kept = await service(`rides?id=eq.${rideId}&select=id,agreed_price`);
    eq(kept.data.length, 1, "la course reste pour la comptabilité");
    eq((await del(driver)).status, 409, "le chauffeur avec un solde positif ne peut pas supprimer");
    eq((await call("/functions/v1/delete-account", { body: {} })).status, 401, "suppression anonyme refusée");
  });
});
