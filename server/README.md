# Cosmetix AI proxy

Minimal backend for the AI consultant. The mobile app never talks to an AI
provider directly and never contains an API key: it calls this proxy, the proxy
calls **Gemini** ([Google AI Studio](https://aistudio.google.com/apikey)) or the
[Claude API](https://docs.anthropic.com/) with a key from **environment
variables**.

```
Cosmetix app  ──HTTP──▶  proxy (this folder)  ──HTTPS──▶  Gemini or Claude API
                         key, limits, budget
```

## Run

```bash
cd server
cp .env.example .env     # .env is git-ignored; put GEMINI_API_KEY (or ANTHROPIC_API_KEY) there
node index.js            # Node 20+, no dependencies
```

The provider is chosen by the key: `GEMINI_API_KEY` → Gemini, `ANTHROPIC_API_KEY`
→ Claude (Claude wins if both are set; force one with `AI_PROVIDER=gemini|claude`).
Without any key it starts in **MOCK mode**: answers are plain text
that begins with `[ТЕСТОВЫЙ РЕЖИМ …]` and structured (JSON) requests are
refused, so nothing looks like a real AI answer. `GET /health` shows
`"mode": "mock"`, `"gemini"` or `"claude"`.

## API

* `GET /health` → `{ ok, mode: "gemini" | "claude" | "mock", model }`
* `POST /v1/chat` →
  `{ system?, messages: [{ role: "user" | "assistant", content, images?: [base64] }], json?, temperature?, maxTokens? }`
  returns `{ text, mock, usage: { inputTokens, outputTokens } }`

Errors are JSON `{ error, message }`: `400 bad_request`, `401 unauthorized`,
`413 too_long`, `415 bad_image`, `429 rate_limited | budget_exceeded |
upstream_rate_limited` (with `Retry-After`), `502 upstream_auth |
upstream_bad_response`, `503 upstream_unavailable | mock_no_structured`,
`504 upstream_timeout`.

## Safety and cost control

| Setting | Default | Meaning |
| --- | --- | --- |
| `MAX_OUTPUT_TOKENS` | 600 | hard cap on the answer length |
| `RATE_LIMIT_PER_MIN` | 20 | requests per minute per client |
| `DAILY_TOKEN_BUDGET` | 200000 | input + output tokens per day, then `429` |
| `UPSTREAM_TIMEOUT_MS` | 45000 | request timeout to the AI provider |
| `UPSTREAM_RETRY_MS` | 800 | pause before retrying Gemini's "high demand" (503), up to 2 retries |
| `APP_TOKEN` | empty | if set, the app must send it as `x-app-token` |
| `GEMINI_MODEL` | `gemini-3.1-flash-lite` | cheap and fast; model names change often, list yours with `GET /v1beta/models` |
| `GEMINI_FALLBACK_MODEL` | `gemini-flash-lite-latest` | used when `GEMINI_MODEL` keeps answering 503; empty disables the fallback |
| `CLAUDE_MODEL` | `claude-haiku-5-5` | cheap and good enough; change freely |

Input limits: 20 messages, 6 000 characters per message, 24 000 in total, 2 JPEG /
PNG / WebP images. Request bodies, photos and the key are never logged and the
key is never returned to the client.

Run it on a machine you control (or any host that supports Node) and put it
behind HTTPS when it is reachable from the internet. In the app set the address
in **Кабинет → Настройки → ИИ-ассистент** or build with
`--dart-define=AI_BASE_URL=https://your-host`.

## Tests

```bash
cd server && node --test
```

They use a fake Anthropic API, so they cost nothing and need no key.
