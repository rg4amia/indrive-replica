#!/usr/bin/env bash
# Remet la base à zéro, relance les Edge Functions, puis exécute les tests d'intégration.
# Prérequis : Docker démarré et `supabase start` déjà lancé. Durée : environ 1 à 2 minutes.
set -euo pipefail
cd "$(dirname "$0")/../.."
LOG="${TMPDIR:-/tmp}/fn_serve.log"

supabase db reset >/dev/null 2>&1
pkill -f "[s]upabase functions serve" 2>/dev/null || true
: >"$LOG"
(cd supabase && exec supabase functions serve --env-file .env.local >"$LOG" 2>&1 </dev/null) &
SERVE_PID=$!
trap 'kill $SERVE_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 40); do grep -q "Serving functions" "$LOG" 2>/dev/null && break; sleep 1; done
sleep 4   # le temps que l'environnement d'exécution charge les fonctions

eval "$(supabase status -o env 2>/dev/null | sed 's/^/export /')"
deno test --allow-net --allow-env --no-check supabase/tests/backend.test.ts
