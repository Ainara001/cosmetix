# Cosmetix server

One Node process with three parts: the **AI proxy** (`/v1/chat`), the **catalog
and profile API** on PostgreSQL (`/v1/...`) and a small **admin panel**
(`/admin`). The database part is optional: without `DATABASE_URL` only the AI
proxy runs. See [PostgreSQL, catalog API and admin panel](#postgresql-catalog-api-and-admin-panel).

## AI proxy

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

## PostgreSQL, catalog API and admin panel

Needs PostgreSQL 13+ (`gen_random_uuid()` is built in) and `npm install` once
(the only dependency is `pg`). `pg` is loaded only when `DATABASE_URL` is set:
the AI proxy alone still starts without `npm install`, exactly as before; with
`DATABASE_URL` set and no `npm install` the server stops with a message saying so.

```bash
cd server
npm install
createdb cosmetix                                  # or any empty database
echo 'DATABASE_URL=postgres://user:password@localhost:5432/cosmetix' >> .env
npm run migrate                                    # creates the tables (migrations/*.sql)
npm run seed                                       # loads the app catalog, only into an empty catalog
npm run create-admin -- yourname                   # asks for a password (12+ characters)
npm start                                          # then open http://localhost:8787/admin
```

`npm start` also applies new migrations by itself (`AUTO_MIGRATE=0` turns that
off). `.env` is git-ignored; keys and passwords never go into the repository.
Without `ADMIN_PASSWORD` in the environment, `create-admin` asks for the
password in the terminal without echoing it; running it again for the same name
changes the password and signs that admin out everywhere.

### What is in the database

| Table | Content |
| --- | --- |
| `products`, `brands`, `categories` | the catalog; `products.inci` is the full ingredient list, `products.source_url` the page it came from, `products.country` the manufacturer's country (**empty until somebody fills it in**) |
| `ingredients`, `product_ingredients` | the ingredients the app explains (risk, allergens) and which product contains them |
| `product_traits` | what a product suits: skin type, colour type, undertone, concern, tag |
| `stores`, `prices` | shops (position and where it comes from) and the price / stock of a product in each shop |
| `app_users` | anonymous devices: random id, token **hash**, **year** of birth, skin profile. No e-mail, password, name or exact date of birth |
| `reactions` | reaction diary entries (severity 1–5) synced from the app |
| `activity_events` | activity events; type `app_open` is a sign-in to the app |
| `admins`, `admin_sessions`, `admin_audit` | admin accounts (scrypt hashes), sessions (token hash), and a log of every product change with old and new values |

**Demo data is marked.** The catalog is exported from the app's built-in seed
(`lib/database/seed_data.dart`, SQLite schema version 13). It was compared with
a fresh export from `main` at commit `67a1e14` (PR #15 merged): the data is the
same, only the version number differs. Its prices (`products.price`, every row of `prices`) are placeholder
values from the app, not real shop prices: they carry `source = 'demo'`
(`price_source` on the product), the API returns it as `priceSource`, and the
admin panel shows a «демо» tag. A price edited in the panel becomes
`price_source = 'admin'`. Shop positions come from OpenStreetMap or, for one
chain, from public job ads and are marked as unverified in `stores.source`.

The seed file `seed/catalog.json` is generated, not written by hand:

```bash
flutter test tool/export_server_seed.dart          # from the repository root
```

Export again, and read the diff, whenever the app's catalog changes (for example
when the catalog moves to JSON files or gets a manufacturer country). The seed is
loaded only into an empty database, so an existing server keeps its data: new
catalog fields reach it through a new migration, not through the seed.

### API for the app

Every `/v1/...` route needs the `x-app-token` header when `APP_TOKEN` is set.
Errors are JSON `{ error, message }` as for `/v1/chat`.

| Route | Meaning |
| --- | --- |
| `GET /v1/catalog/products` | list; query `category`, `brand` (exact names), `q` (name or brand contains), `updatedSince` (ISO time, for sync), `limit` (≤ 200, default 100), `offset` → `{ items, total, limit, offset }` |
| `GET /v1/catalog/products/:id` | one product with `ingredients`, `traits` and `prices` per shop |
| `GET /v1/catalog/categories`, `/brands`, `/stores`, `/ingredients` | reference lists |
| `POST /v1/devices` | the device registers itself → `{ userId, token }` (keep the token, it is shown once; 20 per hour per address) |
| `GET /v1/profile`, `PUT /v1/profile`, `DELETE /v1/profile` | `Authorization: Bearer <token>`. `PUT` is partial: `{ birthYear, skinType, skinTone, undertone, colorType, skinConcerns[], city }`, absent = unchanged, `null` = clear. `DELETE` removes the user with all their data |
| `GET /v1/reactions`, `PUT /v1/reactions/:clientId`, `DELETE /v1/reactions/:clientId` | reaction diary; `clientId` is the id in the app's own database, so repeating a `PUT` never duplicates: `{ productId?, title, severity 1–5, date "YYYY-MM-DD", notes? }` |
| `POST /v1/events` | `{ events: [{ type, props?, clientTime? }] }`, up to 50 per request; `type` is `snake_case` (send `app_open` when the app starts); `props` ≤ 2 000 bytes, no personal data please |

The server keeps only the **year** of birth. It does not compute an age: the
app (or the safety rules) do that from `birthYear`.

### Admin panel

`/admin` (Russian UI): overview counters; **Товары** (search, filter, edit name,
category, country, price, INCI list); **Входы** (`app_open` events);
**События** (all events, filter by type); **Устройства** (anonymous devices with
counts, no profile data); **Правки** (who changed what).

* The admin signs in with a name and password of its own (separate from the app,
  which has no passwords). Sessions last 12 hours, the cookie is `HttpOnly`,
  `SameSite=Strict` (and `Secure` with `ADMIN_COOKIE_SECURE=1`); every change
  also needs a custom header, so another website cannot send one.
* 10 wrong passwords from one address lock the sign-in for 15 minutes.
* The page loads nothing from other sites (CSP `default-src 'none'`) and writes
  server text only with `textContent`.
* A change that carries a foreign `Origin` header (a page of another site) is
  refused, and the server sends no CORS headers, so another site can neither
  act nor read.
* **By default the panel works only on the machine the server runs on**: the
  connection must come from a loopback address and the `Host` header must be
  `localhost`, `127.0.0.1` or `[::1]` (this also stops DNS rebinding). From
  another device it answers `403 admin_local_only`. The reason: the server speaks
  plain HTTP, so a password typed from another device would cross the network
  unencrypted. The app API (`/v1/...`) is not affected and stays reachable from
  a phone on the same Wi-Fi.
* **Not for the open internet as it is.** To reach the panel remotely put the
  server behind a reverse proxy that terminates HTTPS, and set
  `ADMIN_ALLOW_REMOTE=1`, `ADMIN_COOKIE_SECURE=1` and
  `ADMIN_ALLOWED_HOSTS=admin.example.com` (the `Host` header is still checked;
  `X-Forwarded-For` is never trusted). Also keep the proxy from exposing
  `/admin` to everyone if you can (an IP allow-list or its own login). Nothing in
  this repository publishes the server anywhere.

### When the database is not available

`DATABASE_URL` empty: `/health` and `/v1/chat` work, the database routes answer
`503 db_not_configured`. `DATABASE_URL` set but the database down, unreachable,
overloaded or too slow (`PG_CONNECT_TIMEOUT_MS` 5000, `PG_STATEMENT_TIMEOUT_MS`
10000): those routes answer `503 db_unavailable` with `Retry-After: 5`, `/health`
and `/v1/chat` keep working, and a connection that dies while idle is dropped
quietly (the next query opens a new one). At start-up an unreachable database
stops the server with `startup failed: ...` (no connection string in the
message). Anything else unexpected is a plain `500 internal` with no details.

## Tests

```bash
cd server && npm test
```

The 21 tests of the AI proxy use a fake AI API and need nothing else. The
database and admin tests need a PostgreSQL database they may write to:

```bash
TEST_DATABASE_URL=postgres://user@localhost:5432/cosmetix_test npm test
```

Each test file creates its own schema (`t_<random>`) in that database and drops
it at the end, so nothing else there is touched. **Without `TEST_DATABASE_URL`
those tests are skipped** (the run says so: "skipped"), so a green run without
it does not cover the database part.
