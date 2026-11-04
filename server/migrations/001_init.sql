-- Cosmetix server schema, step 1: catalog, app users and activity, admin accounts.
-- Money is stored in tenge as whole numbers (the app does the same).

CREATE TABLE brands (
  id    SERIAL PRIMARY KEY,
  name  TEXT NOT NULL UNIQUE
);

CREATE TABLE categories (
  id    SERIAL PRIMARY KEY,
  name  TEXT NOT NULL UNIQUE
);

CREATE TABLE products (
  id              SERIAL PRIMARY KEY,
  brand_id        INTEGER NOT NULL REFERENCES brands(id),
  category_id     INTEGER NOT NULL REFERENCES categories(id),
  name            TEXT NOT NULL,
  zone            TEXT NOT NULL DEFAULT '',
  price           INTEGER NOT NULL CHECK (price >= 0),
  -- where the price comes from: 'demo' = placeholder value of the app seed,
  -- 'admin' = entered in the admin panel
  price_source    TEXT NOT NULL DEFAULT 'demo' CHECK (price_source IN ('demo', 'admin')),
  old_price       INTEGER CHECK (old_price IS NULL OR old_price >= 0),
  in_stock        BOOLEAN NOT NULL DEFAULT TRUE,
  art             TEXT NOT NULL DEFAULT 'bottle',
  color           BIGINT NOT NULL,
  shade           BIGINT,
  description     TEXT NOT NULL DEFAULT '',
  natural_percent INTEGER NOT NULL DEFAULT 80 CHECK (natural_percent BETWEEN 0 AND 100),
  featured        BOOLEAN NOT NULL DEFAULT FALSE,
  trending        BOOLEAN NOT NULL DEFAULT FALSE,
  -- full ingredient list (INCI) as published, and the page it was taken from
  inci            TEXT NOT NULL DEFAULT '',
  source_url      TEXT NOT NULL DEFAULT '',
  -- country of the manufacturer; NULL = not known yet (never guessed)
  country         TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (brand_id, name)
);
CREATE INDEX products_category_idx ON products (category_id);
CREATE INDEX products_updated_idx ON products (updated_at);

-- Ingredients the app explains to the user (risk, allergens). Not the same as
-- products.inci, which is the complete published list.
CREATE TABLE ingredients (
  id          SERIAL PRIMARY KEY,
  name        TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  risk        INTEGER NOT NULL DEFAULT 0,
  is_allergen BOOLEAN NOT NULL DEFAULT FALSE,
  group_key   TEXT
);

CREATE TABLE product_ingredients (
  product_id    INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  ingredient_id INTEGER NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
  PRIMARY KEY (product_id, ingredient_id)
);

-- What a product is suitable for: skin_type, color_type, undertone, concern, tag.
-- source: 'seed' = curated in the app, 'ai' = validated AI classification.
CREATE TABLE product_traits (
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  kind       TEXT NOT NULL CHECK (kind IN ('skin_type', 'color_type', 'undertone', 'concern', 'tag')),
  value      TEXT NOT NULL,
  source     TEXT NOT NULL DEFAULT 'seed',
  PRIMARY KEY (product_id, kind, value, source)
);

CREATE TABLE stores (
  id      SERIAL PRIMARY KEY,
  name    TEXT NOT NULL,
  chain   TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL,
  lat     DOUBLE PRECISION,
  lng     DOUBLE PRECISION,
  hours   TEXT NOT NULL DEFAULT '',
  -- where the position and address come from
  source  TEXT NOT NULL DEFAULT ''
);

CREATE TABLE prices (
  id         SERIAL PRIMARY KEY,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  store_id   INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  price      INTEGER NOT NULL CHECK (price >= 0),
  in_stock   BOOLEAN NOT NULL DEFAULT TRUE,
  qty        INTEGER CHECK (qty IS NULL OR qty >= 0),
  -- 'demo' = placeholder from the app seed (shops publish no open price feed)
  source     TEXT NOT NULL DEFAULT 'demo',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (product_id, store_id)
);

-- App users are anonymous: a device registers itself and gets a random token.
-- No e-mail, no password, no name. Only the token's hash is stored.
CREATE TABLE app_users (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash     TEXT NOT NULL UNIQUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- age is derived from the year of birth, the exact date is never stored
  birth_year     SMALLINT CHECK (birth_year IS NULL OR birth_year BETWEEN 1900 AND 2100),
  skin_type      TEXT,
  skin_tone      TEXT,
  undertone      TEXT,
  color_type     TEXT,
  skin_concerns  TEXT[] NOT NULL DEFAULT '{}',
  city           TEXT,
  profile_updated_at TIMESTAMPTZ
);

CREATE TABLE reactions (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  -- id of the entry in the app's own database: makes the sync idempotent
  client_id     TEXT NOT NULL,
  product_id    INTEGER REFERENCES products(id) ON DELETE SET NULL,
  title         TEXT NOT NULL,
  severity      SMALLINT NOT NULL CHECK (severity BETWEEN 1 AND 5),
  reaction_date DATE NOT NULL,
  notes         TEXT NOT NULL DEFAULT '',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, client_id)
);

CREATE TABLE activity_events (
  id         BIGSERIAL PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  -- 'app_open' is a sign-in to the app; other types are free-form snake_case
  type       TEXT NOT NULL CHECK (type ~ '^[a-z][a-z0-9_]{0,39}$'),
  props      JSONB NOT NULL DEFAULT '{}',
  -- time on the device (informational); created_at is the server time
  client_time TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX activity_events_created_idx ON activity_events (created_at DESC);
CREATE INDEX activity_events_type_idx ON activity_events (type, created_at DESC);
CREATE INDEX activity_events_user_idx ON activity_events (user_id, created_at DESC);

CREATE TABLE admins (
  id            SERIAL PRIMARY KEY,
  username      TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE admin_sessions (
  token_hash TEXT PRIMARY KEY,
  admin_id   INTEGER NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL
);

-- Who changed which product in the admin panel, and what.
CREATE TABLE admin_audit (
  id         BIGSERIAL PRIMARY KEY,
  admin_id   INTEGER REFERENCES admins(id) ON DELETE SET NULL,
  username   TEXT NOT NULL,
  product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
  changes    JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
