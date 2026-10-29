// POST {} -> supprime le compte de l'appelant : anonymise les données, efface les fichiers, supprime l'identité.
// Les courses et le journal financier restent (obligation comptable), sans nom ni photo.
import { adminClient, corsHeaders, fail, json, rateLimited, requireUser } from "../_shared/http.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return fail("method_not_allowed", 405);

  const user = await requireUser(req);
  if (!user) return fail("unauthorized", 401);
  if (rateLimited(`delete:${user.id}`, 3, 3_600_000)) return fail("rate_limited", 429);

  const admin = adminClient();
  const { data: paths, error } = await admin.rpc("anonymize_account", { p_user: user.id });
  if (error) {
    const known: Record<string, [number, string]> = {
      ride_active: [409, "Terminez ou annulez votre course en cours avant de supprimer votre compte."],
      balance_not_zero: [409, "Votre solde doit être réglé avec l'assistance avant la suppression."],
    };
    for (const [k, [status, msg]] of Object.entries(known)) if (error.message.includes(k)) return fail(k, status, msg);
    console.error("delete-account", error.message);
    return fail("deletion_failed", 500);
  }

  if (Array.isArray(paths) && paths.length > 0) {
    const { error: rmErr } = await admin.storage.from("driver-docs").remove(paths as string[]);
    if (rmErr) console.error("delete-account storage", rmErr.message);   // ne bloque pas : l'identité est supprimée ensuite
  }
  const { error: delErr } = await admin.auth.admin.deleteUser(user.id);
  if (delErr) {
    console.error("delete-account auth", delErr.message);
    return fail("auth_deletion_failed", 500);
  }
  return json({ deleted: true });
});
