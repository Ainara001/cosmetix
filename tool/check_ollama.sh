#!/usr/bin/env bash
# Checks that the Ollama server (on the other laptop) is reachable from this
# machine and that both models answer.  Usage:
#   tool/check_ollama.sh http://192.168.1.50:11434 [text-model] [vision-model]
set -u
URL="${1:?usage: $0 http://<ip>:11434 [text-model] [vision-model]}"
TEXT="${2:-llama3.2}"
VISION="${3:-llava}"

echo "== server: $URL"
curl -sf -m 4 "$URL/api/tags" >/dev/null || { echo "FAIL: cannot reach $URL/api/tags (OLLAMA_HOST=0.0.0.0? firewall? same Wi-Fi?)"; exit 1; }
echo "OK: server reachable"
for m in "$TEXT" "$VISION"; do
  if curl -sf -m 4 "$URL/api/tags" | grep -q "\"name\":\"${m%%:*}"; then echo "OK: model '$m' installed"; else echo "WARN: model '$m' not installed (ollama pull $m)"; fi
done
echo "== text model answer"
curl -sf -m 90 "$URL/api/chat" -d "{\"model\":\"$TEXT\",\"stream\":false,\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the single word: ready\"}]}" \
  | sed -e 's/.*"content":"\([^"]*\)".*/\1/' || echo "FAIL: text model did not answer"
