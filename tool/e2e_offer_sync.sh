#!/usr/bin/env bash
# Real end-to-end check of the price pipeline:
#   admin adds a verified offer in PostgreSQL -> real server API -> Flutter sync
#   -> SQLite -> price on the card -> link -> price change -> resync without
#   duplicates -> revoke -> disappears -> server gone -> last copy with its date.
#
# It needs a PostgreSQL you may write to, and creates (and finally drops) its own
# throw-away database; it never touches another database. The offer is TEST DATA.
#
#   PG_URL_BASE=postgres://user@127.0.0.1:5432 tool/e2e_offer_sync.sh
#
# Optional: PG_BIN (folder with createdb/dropdb), E2E_PORT (default 8799).
set -u -o pipefail
cd "$(dirname "$0")/.."
: "${PG_URL_BASE:?set PG_URL_BASE, for example postgres://user@127.0.0.1:5432}"
PG_BIN=${PG_BIN:-$(dirname "$(command -v createdb)")}
PORT=${E2E_PORT:-8799}
NAME="cx_e2e_$$"
TMP=$(mktemp -d)
export DATABASE_URL="$PG_URL_BASE/$NAME"
export ADMIN_PASSWORD="e2e-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 20)"
SERVER_PID=""
fail=0

cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
  [ -n "$SERVER_PID" ] && wait "$SERVER_PID" 2>/dev/null
  "$PG_BIN/dropdb" --maintenance-db="$PG_URL_BASE/postgres" --if-exists "$NAME" >/dev/null 2>&1
  rm -rf "$TMP"
}
trap cleanup EXIT

"$PG_BIN/createdb" --maintenance-db="$PG_URL_BASE/postgres" "$NAME" || exit 2
(cd server && node db/cli.js migrate && node db/cli.js seed && node db/cli.js create-admin e2eadmin) >"$TMP/setup.log" 2>&1 \
  || { cat "$TMP/setup.log"; exit 2; }

if curl -s -o /dev/null "http://127.0.0.1:$PORT/"; then
  echo "port $PORT is already in use; set E2E_PORT"; exit 2
fi
# exec: the PID is the server's own, so the trap can stop exactly this process
(cd server && PORT=$PORT HOST=127.0.0.1 exec node index.js >"$TMP/server.log" 2>&1) &
SERVER_PID=$!
for _ in $(seq 1 40); do
  curl -sf "http://127.0.0.1:$PORT/v1/catalog/offers" >/dev/null 2>&1 && break
  sleep 0.5
done
curl -sf "http://127.0.0.1:$PORT/v1/catalog/offers" >/dev/null || { echo "server did not start"; cat "$TMP/server.log"; exit 2; }

JAR="$TMP/jar"
curl -sS -c "$JAR" -H 'content-type: application/json' \
  -d "{\"username\":\"e2eadmin\",\"password\":\"$ADMIN_PASSWORD\"}" \
  "http://127.0.0.1:$PORT/admin/api/login" -o "$TMP/login.json" -w '%{http_code}' >"$TMP/login.code" 2>&1
[ "$(cat "$TMP/login.code")" = 200 ] || { echo "admin login failed: $(cat "$TMP/login.code") $(cat "$TMP/login.json")"; cat "$TMP/setup.log"; exit 2; }

offer() { # price oldPrice verification
  local old=${2:-null}
  curl -sf -b "$JAR" -X PUT -H 'content-type: application/json' -H 'x-requested-with: cosmetix-admin' \
    -d "{\"productId\":12,\"storeId\":2,\"price\":$1,\"oldPrice\":$old,\"availability\":\"in_stock\",
         \"url\":\"https://shop.example.test/p/niacinamide\",\"urlKind\":\"product\",
         \"source\":\"TEST DATA: e2e script, not a real price\",\"method\":\"manual_visit\",
         \"verification\":\"$3\"}" \
    "http://127.0.0.1:$PORT/admin/api/offers" >/dev/null
}

DB="$TMP/app.db"
step() { # name expect_sync expect_price [expect_old] [expect_link]
  local label=$1
  shift
  E2E_STEP="$label" E2E_SERVER="http://127.0.0.1:$PORT" E2E_DB="$DB" E2E_EXPECT_SYNC=$1 \
    E2E_EXPECT_PRICE=$2 E2E_EXPECT_OLD=${3:-} E2E_EXPECT_LINK=${4:-0} \
    flutter test test/e2e_offer_sync_test.dart --reporter expanded >"$TMP/step.log" 2>&1
  if grep -q "All tests passed" "$TMP/step.log"; then
    echo "PASS  $label  $(grep -o 'E2E [^|]*offers=[^ ]* price=[^ ]*' "$TMP/step.log" | head -1)"
  else
    echo "FAIL  $label"; tail -30 "$TMP/step.log"; fail=1
  fi
}

step "0 empty catalog: no offer"                           ok none
offer 4100 5000 verified
step "1 verified offer -> price card + link"               ok 4100 5000 1
offer 3900 null verified
step "2 price changed -> resync, no duplicate"             ok 3900
step "3 repeat sync -> still one row"                      ok 3900
offer 3900 null unverified
step "4 revoked on the server -> disappears"               ok none
offer 3900 null verified
step "5 verified again -> back"                            ok 3900
kill "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""
step "6 server unreachable -> last copy stays (offline)"   fail 3900

[ $fail -eq 0 ] && echo "ALL STEPS PASSED" || echo "SOME STEPS FAILED"
exit $fail
