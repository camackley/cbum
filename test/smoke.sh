#!/usr/bin/env bash
# smoke.sh — verifica la REST API de CBUM end-to-end contra un worker corriendo.
# Uso:
#   BASE_URL=http://localhost:8788 API_TOKEN=dev-local-token ./test/smoke.sh
#   (o contra producción: BASE_URL=https://<worker>.workers.dev API_TOKEN=<secret>)
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8788}"
API_TOKEN="${API_TOKEN:-dev-local-token}"
AUTH="Authorization: Bearer ${API_TOKEN}"
CT="Content-Type: application/json"

pass=0; fail=0
ok()   { echo "  ✅ $1"; pass=$((pass+1)); }
bad()  { echo "  ❌ $1"; fail=$((fail+1)); }
# check <descripcion> <valor_real> <esperado>
check() { if [[ "$2" == "$3" ]]; then ok "$1 ($2)"; else bad "$1 → got '$2' expected '$3'"; fi; }

# ids estables para probar idempotencia
MEAL_ID="11111111-1111-4111-8111-111111111111"
GROUP_ID="22222222-2222-4222-8222-222222222222"
WORKOUT_ID="33333333-3333-4333-8333-333333333333"
S1="44444444-4444-4444-8444-444444444401"
S2="44444444-4444-4444-8444-444444444402"
S3="44444444-4444-4444-8444-444444444403"
M1="55555555-5555-4555-8555-555555555501"
M2="55555555-5555-4555-8555-555555555502"

echo "== Auth =="
code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/api/health")
check "health sin token → 401" "$code" "401"
code=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH" "$BASE_URL/api/health")
check "health con token → 200" "$code" "200"

echo "== POST /api/meals (con per_100g para recálculo) =="
MEAL_BODY=$(cat <<JSON
{"meals":[{"id":"$MEAL_ID","ts":"2026-07-14T08:30:00-05:00","date":"2026-07-14",
  "meal_group_id":"$GROUP_ID","name":"Pechuga a la plancha","quantity_g":200,
  "kcal":330,"protein_g":62,"carbs_g":0,"fat_g":7.2,"fiber_g":0,
  "per_100g":{"kcal":165,"protein_g":31,"carbs_g":0,"fat_g":3.6,"fiber_g":0},
  "source":"label","confidence":0.95,"portion_basis":"weighed"}]}
JSON
)
n=$(curl -s -H "$AUTH" -H "$CT" -X POST "$BASE_URL/api/meals" -d "$MEAL_BODY" | jq '.upserted')
check "upserted 1 meal" "$n" "1"
# idempotencia: repetir mismo body
n=$(curl -s -H "$AUTH" -H "$CT" -X POST "$BASE_URL/api/meals" -d "$MEAL_BODY" | jq '.upserted')
check "re-POST idempotente" "$n" "1"
# cuenta solo ESTE meal (robusto ante otros datos en la misma fecha)
total=$(curl -s -H "$AUTH" "$BASE_URL/api/meals?from=2026-07-14&to=2026-07-14" | jq --arg id "$MEAL_ID" '[.meals[] | select(.id==$id)] | length')
check "GET meals no duplica" "$total" "1"

echo "== PATCH /api/meals/:id (recalcula porción) =="
kcal=$(curl -s -H "$AUTH" -H "$CT" -X PATCH "$BASE_URL/api/meals/$MEAL_ID" -d '{"quantity_g":100}' | jq '.kcal')
check "recalculo kcal 200g→100g = 165" "$kcal" "165"
prot=$(curl -s -H "$AUTH" "$BASE_URL/api/meals?from=2026-07-14&to=2026-07-14" | jq --arg id "$MEAL_ID" '.meals[] | select(.id==$id) | .protein_g')
check "recalculo protein = 31" "$prot" "31"

echo "== POST /api/workouts (3 sets, e1rm server-side) =="
W_BODY=$(cat <<JSON
{"workout":{"id":"$WORKOUT_ID","ts_start":"2026-07-14T17:00:00-05:00","ts_end":"2026-07-14T18:00:00-05:00",
  "date":"2026-07-14","program_day_id":"upper_a","notes":"prueba",
  "sets":[
    {"id":"$S1","exercise_id":"barbell-bench-press","set_number":1,"weight_kg":60,"reps":10,"rir":3,"is_warmup":1},
    {"id":"$S2","exercise_id":"barbell-bench-press","set_number":2,"weight_kg":100,"reps":8,"rir":2,"is_warmup":0},
    {"id":"$S3","exercise_id":"barbell-bench-press","set_number":3,"weight_kg":60,"reps":12,"rir":3,"is_warmup":0}
  ]}}
JSON
)
RESP=$(curl -s -H "$AUTH" -H "$CT" -X POST "$BASE_URL/api/workouts" -d "$W_BODY")
e1_warm=$(echo "$RESP" | jq '.sets[0].e1rm_kg')
check "e1rm de warmup = null" "$e1_warm" "null"
e1_work=$(echo "$RESP" | jq '.sets[1].e1rm_kg')
check "e1rm 100x8@2 = 133.3" "$e1_work" "133.3"
e1_oob=$(echo "$RESP" | jq '.sets[2].e1rm_kg')
check "e1rm 60x12@3 (15>12) = null" "$e1_oob" "null"

echo "== POST /api/body-metrics (2 métricas, upsert por type,ts,source) =="
BM_BODY=$(cat <<JSON
{"metrics":[
  {"id":"$M1","ts":"2026-07-14T06:00:00-05:00","date":"2026-07-14","type":"weight_kg","value":82.1,"source":"healthkit"},
  {"id":"$M2","ts":"2026-07-14T23:00:00-05:00","date":"2026-07-14","type":"steps","value":8500,"source":"healthkit"}
]}
JSON
)
n=$(curl -s -H "$AUTH" -H "$CT" -X POST "$BASE_URL/api/body-metrics" -d "$BM_BODY" | jq '.upserted')
check "upserted 2 metrics" "$n" "2"
# re-post idempotente (dedup por type,ts,source)
curl -s -H "$AUTH" -H "$CT" -X POST "$BASE_URL/api/body-metrics" -d "$BM_BODY" > /dev/null
cnt=$(curl -s -H "$AUTH" "$BASE_URL/api/body-metrics?type=weight_kg&from=2026-07-14&to=2026-07-14" | jq '.metrics | length')
check "weight_kg no duplica" "$cnt" "1"

echo "== PUT /api/days/:date =="
ok_flag=$(curl -s -H "$AUTH" -H "$CT" -X PUT "$BASE_URL/api/days/2026-07-14" -d '{"logging_complete":true}' | jq '.ok')
check "marca día completo" "$ok_flag" "true"

echo "== GET /api/changes (cursor incremental) =="
C1=$(curl -s -H "$AUTH" "$BASE_URL/api/changes?since=0")
CUR1=$(echo "$C1" | jq '.cursor')
mc=$(echo "$C1" | jq '.meals | length')
[[ "$mc" -ge 1 ]] && ok "changes since=0 trae meals ($mc)" || bad "changes since=0 sin meals"
# nada nuevo desde el cursor actual
sleep 1
C2=$(curl -s -H "$AUTH" "$BASE_URL/api/changes?since=$CUR1")
mc2=$(echo "$C2" | jq '.meals | length')
check "changes since=cursor → 0 meals" "$mc2" "0"
CUR2=$(echo "$C2" | jq '.cursor')
[[ "$CUR2" -ge "$CUR1" ]] && ok "cursor incremental ($CUR1 → $CUR2)" || bad "cursor no incremental"

echo "== Validaciones 422 =="
# meal photo sin fdc/off
code=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH" -H "$CT" -X POST "$BASE_URL/api/meals" \
  -d '{"meals":[{"id":"x","ts":"2026-07-14T08:30:00-05:00","date":"2026-07-14","name":"foto","kcal":1,"protein_g":1,"carbs_g":1,"fat_g":1,"source":"photo","confidence":0.5,"portion_basis":"estimated"}]}')
check "meal photo sin fdc/off → 422" "$code" "422"
# confidence fuera de rango
code=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH" -H "$CT" -X POST "$BASE_URL/api/meals" \
  -d '{"meals":[{"id":"x","ts":"2026-07-14T08:30:00-05:00","date":"2026-07-14","name":"a","kcal":1,"protein_g":1,"carbs_g":1,"fat_g":1,"source":"manual","confidence":1.5,"portion_basis":"estimated"}]}')
check "confidence>1 → 422" "$code" "422"
# rir fuera de rango
code=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH" -H "$CT" -X POST "$BASE_URL/api/workouts" \
  -d "{\"workout\":{\"id\":\"w2\",\"ts_start\":\"2026-07-14T17:00:00-05:00\",\"date\":\"2026-07-14\",\"sets\":[{\"id\":\"s\",\"exercise_id\":\"barbell-bench-press\",\"set_number\":1,\"weight_kg\":60,\"reps\":8,\"rir\":9}]}}")
check "rir=9 → 422" "$code" "422"
# exercise inexistente
code=$(curl -s -o /dev/null -w "%{http_code}" -H "$AUTH" -H "$CT" -X POST "$BASE_URL/api/workouts" \
  -d "{\"workout\":{\"id\":\"w3\",\"ts_start\":\"2026-07-14T17:00:00-05:00\",\"date\":\"2026-07-14\",\"sets\":[{\"id\":\"s\",\"exercise_id\":\"no-existe\",\"set_number\":1,\"weight_kg\":60,\"reps\":8,\"rir\":2}]}}")
check "exercise_id inexistente → 422" "$code" "422"
# shape del error
err=$(curl -s -H "$AUTH" -H "$CT" -X POST "$BASE_URL/api/meals" \
  -d '{"meals":[{"id":"x","ts":"bad","date":"2026-07-14","name":"a","kcal":1,"protein_g":1,"carbs_g":1,"fat_g":1,"source":"manual","confidence":0.5,"portion_basis":"estimated"}]}' | jq -r '.error.code')
check "error tiene .error.code" "$err" "validation_error"

echo
echo "== RESULTADO: $pass ok, $fail fail =="
[[ "$fail" -eq 0 ]] || exit 1
