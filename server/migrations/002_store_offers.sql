-- Step 2: real offers of shops, entered by a person (or later by a feed that the
-- shop's published conditions allow). The demo rows of `prices` stay as they are
-- and are never shown as prices.
--
-- One row = what is known about ONE product in ONE shop of a city as of
-- checked_at. Nothing has a default that looks like data: price is NULL when it
-- was not confirmed, availability is 'unknown' unless it was really checked.

CREATE TABLE store_offers (
  id           BIGSERIAL PRIMARY KEY,
  product_id   INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  store_id     INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  city         TEXT NOT NULL DEFAULT 'Астана',
  price        INTEGER CHECK (price IS NULL OR price > 0),
  old_price    INTEGER CHECK (old_price IS NULL OR old_price > 0),
  availability TEXT NOT NULL DEFAULT 'unknown'
               CHECK (availability IN ('in_stock', 'out_of_stock', 'unknown')),
  -- the address of the product page on the shop's site; url_kind says what it opens
  url          TEXT,
  url_kind     TEXT NOT NULL DEFAULT 'none' CHECK (url_kind IN ('product', 'search', 'none')),
  volume_text  TEXT,
  variant_text TEXT,
  -- where the information comes from, how it was obtained, how far it can be trusted
  source       TEXT NOT NULL CHECK (length(btrim(source)) > 0),
  method       TEXT NOT NULL CHECK (method IN
               ('manual_visit', 'manual_site', 'partner_feed', 'official_api', 'import_file')),
  verification TEXT NOT NULL DEFAULT 'unverified'
               CHECK (verification IN ('verified', 'unverified', 'disputed')),
  checked_at   TIMESTAMPTZ NOT NULL,
  checked_by   TEXT,
  note         TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (product_id, store_id),
  CHECK (url_kind = 'none' OR url IS NOT NULL),
  CHECK (url IS NULL OR url ~ '^https?://[^[:space:]]+$'),
  CHECK (old_price IS NULL OR (price IS NOT NULL AND old_price > price)),
  CHECK (verification <> 'verified' OR price IS NOT NULL OR availability <> 'unknown'
         OR url_kind = 'product')
);
CREATE INDEX store_offers_product_idx ON store_offers (product_id);
CREATE INDEX store_offers_checked_idx ON store_offers (checked_at);
