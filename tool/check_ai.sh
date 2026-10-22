#!/usr/bin/env bash
# Checks that the Cosmetix AI proxy (server/) is reachable and whether it talks
# to the real Claude or runs in test mode.  Usage:
#   tool/check_ai.sh http://192.168.1.50:8787 [app-token]
set -u
URL="${1:?usage: $0 http://<host>:8787 [app-token]}"
TOKEN="${2:-}"

echo "== proxy: $URL"
health=$(curl -sf -m 4 "$URL/health") || { echo "FAIL: cannot reach $URL/health (is 'node server/index.js' running? same Wi-Fi? firewall?)"; exit 1; }
echo "OK: proxy reachable: $health"
case "$health" in
  *'"mode":"mock"'*) echo "NOTE: test mode (no ANTHROPIC_API_KEY on the server): answers are marked as fake" ;;
  *'"mode":"claude"'*) echo "OK: real Claude API" ;;
esac
echo "== test question (costs a few tokens in Claude mode)"
curl -sf -m 60 "$URL/v1/chat" -H 'content-type: application/json' ${TOKEN:+-H "x-app-token: $TOKEN"} \
  -d '{"messages":[{"role":"user","content":"Ответь одним словом: готов"}],"maxTokens":20}' \
  || echo "FAIL: the proxy did not answer the test question"
echo
