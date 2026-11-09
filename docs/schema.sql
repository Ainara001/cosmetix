-- Cosmetix SQLite schema (version 19), generated from a fresh install

CREATE TABLE blacklist (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  group_key TEXT,
  enabled INTEGER NOT NULL DEFAULT 0,
  is_custom INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE care_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day TEXT NOT NULL,
  period TEXT NOT NULL,
  my_product_id INTEGER REFERENCES my_products(id) ON DELETE SET NULL,
  product_name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (user_id, day, period, my_product_id)
);

CREATE TABLE care_steps (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  period TEXT NOT NULL,
  position INTEGER NOT NULL,
  my_product_id INTEGER NOT NULL REFERENCES my_products(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  UNIQUE (user_id, period, my_product_id)
);

CREATE TABLE cart_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  store_id INTEGER REFERENCES stores(id) ON DELETE SET NULL,
  quantity INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  UNIQUE (user_id, product_id)
);

CREATE TABLE category_review_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  store TEXT NOT NULL DEFAULT '',
  raw_category TEXT NOT NULL,
  normalized_key TEXT NOT NULL,
  product_name TEXT NOT NULL DEFAULT '',
  reason TEXT NOT NULL,
  candidates TEXT NOT NULL DEFAULT '',
  ai_hint TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  resolved_type TEXT,
  created_at INTEGER NOT NULL,
  resolved_at INTEGER,
  UNIQUE (store, normalized_key)
);

CREATE TABLE chat_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  is_user INTEGER NOT NULL,
  text TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE favorites (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, product_id)
);

CREATE TABLE ingredients (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  risk INTEGER NOT NULL DEFAULT 0,
  is_allergen INTEGER NOT NULL DEFAULT 0,
  group_key TEXT
);

CREATE TABLE my_products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  brand TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT '',
  purchased_at INTEGER,
  opened_at INTEGER,
  pao_months INTEGER,
  expires_at INTEGER,
  notes TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE order_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id INTEGER NOT NULL REFERENCES products(id),
  store_id INTEGER,
  quantity INTEGER NOT NULL,
  price INTEGER NOT NULL
);

CREATE TABLE orders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  total INTEGER NOT NULL,
  bonus INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'Оформлен',
  created_at INTEGER NOT NULL
, bonus_spent INTEGER NOT NULL DEFAULT 0);

CREATE TABLE product_ai_classification (
  product_id INTEGER PRIMARY KEY REFERENCES products(id) ON DELETE CASCADE,
  model TEXT NOT NULL,
  confidence REAL NOT NULL,
  explanation TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
);

CREATE TABLE product_color_types (
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  color_type TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'seed',
  PRIMARY KEY (product_id, color_type, source)
);

CREATE TABLE product_concerns (
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  concern TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'seed',
  PRIMARY KEY (product_id, concern, source)
);

CREATE TABLE product_ingredients (
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  ingredient_id INTEGER NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
  PRIMARY KEY (product_id, ingredient_id)
);

CREATE TABLE product_lines (
  line_key TEXT PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  brand TEXT NOT NULL,
  name TEXT NOT NULL,
  kind TEXT NOT NULL,
  source_url TEXT NOT NULL,
  checked_at TEXT,
  confidence TEXT NOT NULL CHECK (confidence IN
    ('official_page', 'official_page_unchecked', 'third_party', 'unconfirmed')),
  note TEXT
);

CREATE TABLE product_prices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  price INTEGER NOT NULL,
  in_stock INTEGER NOT NULL DEFAULT 1, qty INTEGER, source TEXT NOT NULL DEFAULT 'demo', updated_at INTEGER,
  UNIQUE (product_id, store_id)
);

CREATE TABLE product_shade_pans (
  pan_key TEXT PRIMARY KEY,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  position INTEGER NOT NULL CHECK (position >= 1),
  name TEXT,
  name_source TEXT,
  finish TEXT CHECK (finish IS NULL OR finish IN
    ('matte', 'satin', 'gloss', 'shimmer')),
  finish_source TEXT,
  colour INTEGER CHECK (colour IS NULL OR
    (colour >= 4278190080 AND colour <= 4294967295)),
  colour_source TEXT,
  colour_status TEXT NOT NULL DEFAULT 'missing' CHECK (colour_status IN
    ('manufacturer', 'swatch_sampled', 'legacy_estimate', 'measured_swatch',
     'missing')),
  measurement_ref TEXT,
  UNIQUE (product_id, position),
  CHECK ((colour IS NULL) = (colour_status = 'missing')),
  CHECK (colour IS NULL OR colour_source IS NOT NULL),
  CHECK (colour_status <> 'measured_swatch' OR measurement_ref IS NOT NULL)
);

CREATE TABLE product_shades (
  product_id INTEGER PRIMARY KEY REFERENCES products(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  line_key TEXT,
  shade_code TEXT,
  shade_name TEXT,
  colour INTEGER,
  colour_source TEXT,
  colour_status TEXT NOT NULL DEFAULT 'missing',
  finish TEXT,
  finish_source TEXT,
  note TEXT
);

CREATE TABLE product_skin_types (
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  skin_type TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'seed',
  PRIMARY KEY (product_id, skin_type, source)
);

CREATE TABLE product_tags (
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  tag TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'seed',
  PRIMARY KEY (product_id, tag, source)
);

CREATE TABLE product_undertones (
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  undertone TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'seed',
  PRIMARY KEY (product_id, undertone, source)
);

CREATE TABLE product_variant_facts (
  product_id INTEGER PRIMARY KEY REFERENCES products(id) ON DELETE CASCADE,
  pan_count INTEGER CHECK (pan_count IS NULL OR (pan_count BETWEEN 1 AND 64)),
  source_url TEXT NOT NULL,
  checked_at TEXT,
  confidence TEXT NOT NULL CHECK (confidence IN
    ('official_page', 'official_page_unchecked', 'third_party', 'unconfirmed')),
  note TEXT
);

CREATE TABLE products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  brand TEXT NOT NULL,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  zone TEXT NOT NULL DEFAULT '',
  price INTEGER NOT NULL,
  old_price INTEGER,
  in_stock INTEGER NOT NULL DEFAULT 1,
  art TEXT NOT NULL DEFAULT 'bottle',
  color INTEGER NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  natural_percent INTEGER NOT NULL DEFAULT 80,
  featured INTEGER NOT NULL DEFAULT 0,
  trending INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
, inci TEXT NOT NULL DEFAULT '', source_url TEXT NOT NULL DEFAULT '', shade INTEGER, country TEXT, country_source TEXT);

CREATE TABLE reaction_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  reaction_id INTEGER NOT NULL REFERENCES reactions(id) ON DELETE CASCADE,
  changed_at INTEGER NOT NULL,
  summary TEXT NOT NULL
);

CREATE TABLE reactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  severity INTEGER NOT NULL,
  reaction_date INTEGER NOT NULL,
  notes TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
, photo_path TEXT);

CREATE TABLE reviews (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  author TEXT NOT NULL,
  rating INTEGER NOT NULL,
  body TEXT NOT NULL,
  photo_path TEXT,
  created_at INTEGER NOT NULL
);

CREATE TABLE search_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  query TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (user_id, query)
);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE skin_zone_marks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  zone TEXT NOT NULL CHECK (zone IN
    ('forehead', 'cheek_right', 'cheek_left', 'nose', 'chin')),
  feature TEXT NOT NULL CHECK (feature IN
    ('acne', 'comedones', 'redness', 'post_acne', 'pigmentation', 'scars',
     'pores', 'texture')),
  marked_at INTEGER NOT NULL,
  UNIQUE (user_id, zone, feature)
);

CREATE TABLE store_offers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  city TEXT NOT NULL DEFAULT 'Астана',
  price INTEGER CHECK (price IS NULL OR price > 0),
  old_price INTEGER CHECK (old_price IS NULL OR old_price > 0),
  availability TEXT NOT NULL DEFAULT 'unknown' CHECK (availability IN
    ('in_stock', 'out_of_stock', 'unknown')),
  url TEXT,
  url_kind TEXT NOT NULL DEFAULT 'none' CHECK (url_kind IN
    ('product', 'search', 'none')),
  volume_text TEXT,
  variant_text TEXT,
  source TEXT NOT NULL CHECK (length(trim(source)) > 0),
  method TEXT NOT NULL CHECK (method IN
    ('manual_visit', 'manual_site', 'partner_feed', 'official_api',
     'import_file')),
  verification TEXT NOT NULL DEFAULT 'unverified' CHECK (verification IN
    ('verified', 'unverified', 'disputed')),
  checked_at INTEGER NOT NULL,
  checked_by TEXT,
  note TEXT, origin TEXT NOT NULL DEFAULT 'local', synced_at INTEGER,
  UNIQUE (product_id, store_id),
  CHECK (url_kind = 'none' OR url IS NOT NULL),
  CHECK (url IS NULL OR url LIKE 'https://%' OR url LIKE 'http://%'),
  CHECK (old_price IS NULL OR price IS NULL OR old_price > price),
  CHECK (verification <> 'verified' OR price IS NOT NULL OR
         availability <> 'unknown' OR url_kind = 'product')
);

CREATE TABLE stores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  distance_m INTEGER NOT NULL,
  address TEXT NOT NULL,
  rating REAL NOT NULL
, lat REAL, lng REAL, chain TEXT NOT NULL DEFAULT '', hours TEXT NOT NULL DEFAULT '', source TEXT NOT NULL DEFAULT 'demo');

CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  city TEXT NOT NULL DEFAULT '',
  skin_type TEXT NOT NULL DEFAULT 'Нормальная',
  skin_tone TEXT NOT NULL DEFAULT 'Светлый',
  undertone TEXT NOT NULL DEFAULT 'Нейтральный',
  color_type TEXT NOT NULL DEFAULT '',
  skin_concerns TEXT NOT NULL DEFAULT '',
  bonus_points INTEGER NOT NULL DEFAULT 0,
  visits INTEGER NOT NULL DEFAULT 0,
  avatar_color INTEGER NOT NULL DEFAULT 4291535020,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
, avatar_path TEXT, beauty_source TEXT NOT NULL DEFAULT 'questionnaire', beauty_confidence REAL, beauty_analyzed_at INTEGER, beauty_completed_at INTEGER, preferences TEXT NOT NULL DEFAULT '', reco_use_history INTEGER NOT NULL DEFAULT 0, birth_year INTEGER);

CREATE INDEX idx_offers_product ON store_offers(product_id);

CREATE INDEX idx_pans_product ON product_shade_pans(product_id);
