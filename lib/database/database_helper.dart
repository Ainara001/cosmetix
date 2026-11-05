import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'package:cosmetix/core/utils/app_paths.dart';

import 'seed_data.dart';

/// Owns the SQLite connection: creates the schema, seeds demo data and
/// handles database versioning.
class DatabaseHelper {
  /// [path] is only set in tests (use `inMemoryDatabasePath`).
  DatabaseHelper({this.path});

  static const dbName = 'cosmetix.db';

  /// Increase this number and extend [_onUpgrade] when the schema changes.
  static const dbVersion = 15;

  final String? path;
  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final dbPath = path ?? join(await getDatabasesPath(), dbName);
    return openDatabase(
      dbPath,
      version: dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Fresh install: the original (v3) tables, then the same migrations an
  /// existing database goes through, then the demo data.
  Future<void> _onCreate(Database db, int version) async {
    for (final sql in schemaV3) {
      await db.execute(sql);
    }
    await _migrate(db, 3, version);
    await SeedData.insertAll(db);
  }

  /// Safe upgrade: runs the migrations one by one, user data is never dropped.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) =>
      _migrate(db, oldVersion, newVersion);

  Future<void> _migrate(Database db, int from, int to) async {
    for (var v = from + 1; v <= to; v++) {
      await _migrations[v]!(db);
    }
  }

  /// Version -> migration. Version 3 is the first step for databases created
  /// by older builds (v1/v2 only differed by demo data and one column).
  static final Map<int, Future<void> Function(Database)> _migrations = {
    3: (db) async {
      await _addColumn(db, 'reviews', 'photo_path', 'TEXT');
    },
    4: (db) async {
      await _addColumn(db, 'users', 'avatar_path', 'TEXT');
      await _addColumn(
        db,
        'users',
        'beauty_source',
        "TEXT NOT NULL DEFAULT 'questionnaire'",
      );
      await _addColumn(db, 'users', 'beauty_confidence', 'REAL');
      await _addColumn(db, 'users', 'beauty_analyzed_at', 'INTEGER');
      await _addColumn(db, 'users', 'beauty_completed_at', 'INTEGER');
      for (final sql in _schemaV4) {
        await db.execute(sql);
      }
      await SeedData.backfillProductTraits(db);
    },
    5: (db) async {
      await _addColumn(
        db,
        'orders',
        'bonus_spent',
        'INTEGER NOT NULL DEFAULT 0',
      );
    },
    6: (db) async {
      for (final sql in _schemaV6) {
        await db.execute(sql);
      }
      await _addColumn(db, 'reactions', 'photo_path', 'TEXT');
      await _addColumn(db, 'users', 'preferences', "TEXT NOT NULL DEFAULT ''");
      await _addColumn(
        db,
        'users',
        'reco_use_history',
        'INTEGER NOT NULL DEFAULT 0',
      );
    },
    7: (db) async {
      await _addColumn(db, 'products', 'inci', "TEXT NOT NULL DEFAULT ''");
      await _addColumn(
        db,
        'products',
        'source_url',
        "TEXT NOT NULL DEFAULT ''",
      );
      await SeedData.applyRealCatalog(db);
    },
    8: (db) async {
      await _addColumn(db, 'products', 'shade', 'INTEGER');
      await SeedData.applyShades(db);
    },
    9: (db) async {
      await _addColumn(db, 'stores', 'lat', 'REAL');
      await _addColumn(db, 'stores', 'lng', 'REAL');
      await _addColumn(db, 'stores', 'chain', "TEXT NOT NULL DEFAULT ''");
      await _addColumn(db, 'stores', 'hours', "TEXT NOT NULL DEFAULT ''");
      await _addColumn(db, 'stores', 'source', "TEXT NOT NULL DEFAULT 'demo'");
      await _addColumn(db, 'product_prices', 'qty', 'INTEGER');
      await _addColumn(
        db,
        'product_prices',
        'source',
        "TEXT NOT NULL DEFAULT 'demo'",
      );
      await _addColumn(db, 'product_prices', 'updated_at', 'INTEGER');
      await SeedData.applyRealStores(db);
    },
    10: (db) async {
      await SeedData.applyNewProducts(db);
    },
    // palettes by number, more tints, serums, toners (same idempotent step)
    11: (db) async {
      await SeedData.applyNewProducts(db);
    },
    // the colour circles of the shade picker: shade colours of the new
    // palettes are the hand-picked ones (writes the same map again)
    12: (db) async {
      await SeedData.applyShades(db);
    },
    // year of birth (optional): strong actives are limited for children
    13: (db) async {
      await _addColumn(db, 'users', 'birth_year', 'INTEGER');
    },
    // JSON catalog: country of manufacture (with the page that proves it) and
    // the queue of store categories that need a manual look
    14: (db) async {
      await _addColumn(db, 'products', 'country', 'TEXT');
      await _addColumn(db, 'products', 'country_source', 'TEXT');
      for (final sql in _schemaV14) {
        await db.execute(sql);
      }
      await SeedData.applyCountries(db);
    },
    // virtual try-on: how a shade of a catalog product looks on a face (colour
    // with its source and trust level). A new table only; products, cart,
    // favourites and the old `products.shade` are not touched.
    15: (db) async {
      for (final sql in _schemaV15) {
        await db.execute(sql);
      }
      await SeedData.applyTryOn(db);
    },
  };

  static Future<void> _addColumn(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    if (info.any((r) => r['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Deletes all data (and the saved photos) and builds the demo database
  /// again. All-or-nothing: if anything fails the old data stays.
  Future<void> resetDemoData() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in _tables.reversed) {
        await txn.execute('DELETE FROM $table');
        await txn.execute("DELETE FROM sqlite_sequence WHERE name = '$table'");
      }
      await SeedData.insertAll(txn);
    });
    await AppPaths.deletePhotos();
  }

  static const _tables = [
    'category_review_queue',
    'product_ai_classification',
    'product_tags',
    'product_concerns',
    'product_undertones',
    'product_color_types',
    'product_skin_types',
    'users',
    'settings',
    'stores',
    'products',
    'product_prices',
    'product_shades',
    'favorites',
    'cart_items',
    'orders',
    'order_items',
    'reviews',
    'search_history',
    'ingredients',
    'product_ingredients',
    'blacklist',
    'reactions',
    'chat_messages',
    'my_products',
    'care_steps',
    'care_logs',
    'reaction_history',
  ];

  /// Schema version 15: the shade data of the virtual try-on. One row per
  /// PRODUCT (every shade is a product of its own, with its own id, price, cart
  /// line and favourite). `colour` is NULL when the colour is not known; a
  /// colour always comes with its source and status (see `TryOnSeed`).
  static const _schemaV15 = [
    '''
CREATE TABLE IF NOT EXISTS product_shades (
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
)''',
  ];

  /// Schema version 14: store categories the normalizer could not place with
  /// certainty wait here for a human (the admin panel reads this queue).
  static const _schemaV14 = [
    '''
CREATE TABLE IF NOT EXISTS category_review_queue (
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
)''',
  ];

  /// Schema version 6: the user's cosmetic bag, the morning / evening care
  /// plan with its history and the change history of reaction diary entries.
  static const _schemaV6 = [
    '''
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
)''',
    '''
CREATE TABLE care_steps (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  period TEXT NOT NULL,
  position INTEGER NOT NULL,
  my_product_id INTEGER NOT NULL REFERENCES my_products(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  UNIQUE (user_id, period, my_product_id)
)''',
    '''
CREATE TABLE care_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day TEXT NOT NULL,
  period TEXT NOT NULL,
  my_product_id INTEGER REFERENCES my_products(id) ON DELETE SET NULL,
  product_name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (user_id, day, period, my_product_id)
)''',
    '''
CREATE TABLE reaction_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  reaction_id INTEGER NOT NULL REFERENCES reactions(id) ON DELETE CASCADE,
  changed_at INTEGER NOT NULL,
  summary TEXT NOT NULL
)''',
  ];

  /// Tables added in schema version 4: what each product is suitable for.
  /// `source` is 'seed' (curated) or 'ai' (validated AI classification).
  static const _schemaV4 = [
    '''
CREATE TABLE product_skin_types (
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  skin_type TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'seed',
  PRIMARY KEY (product_id, skin_type, source)
)''',
    '''
CREATE TABLE product_color_types (
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  color_type TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'seed',
  PRIMARY KEY (product_id, color_type, source)
)''',
    '''
CREATE TABLE product_undertones (
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  undertone TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'seed',
  PRIMARY KEY (product_id, undertone, source)
)''',
    '''
CREATE TABLE product_concerns (
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  concern TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'seed',
  PRIMARY KEY (product_id, concern, source)
)''',
    '''
CREATE TABLE product_tags (
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  tag TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'seed',
  PRIMARY KEY (product_id, tag, source)
)''',
    '''
CREATE TABLE product_ai_classification (
  product_id INTEGER PRIMARY KEY REFERENCES products(id) ON DELETE CASCADE,
  model TEXT NOT NULL,
  confidence REAL NOT NULL,
  explanation TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
)''',
  ];

  /// The original tables (schema version 3).
  @visibleForTesting
  static List<String> get schemaV3 => _schema;

  static const _schema = [
    '''
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
)''',
    '''
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''',
    '''
CREATE TABLE stores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  distance_m INTEGER NOT NULL,
  address TEXT NOT NULL,
  rating REAL NOT NULL
)''',
    '''
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
)''',
    '''
CREATE TABLE product_prices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  price INTEGER NOT NULL,
  in_stock INTEGER NOT NULL DEFAULT 1,
  UNIQUE (product_id, store_id)
)''',
    '''
CREATE TABLE favorites (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, product_id)
)''',
    '''
CREATE TABLE cart_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  store_id INTEGER REFERENCES stores(id) ON DELETE SET NULL,
  quantity INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  UNIQUE (user_id, product_id)
)''',
    '''
CREATE TABLE orders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  total INTEGER NOT NULL,
  bonus INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'Оформлен',
  created_at INTEGER NOT NULL
)''',
    '''
CREATE TABLE order_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id INTEGER NOT NULL REFERENCES products(id),
  store_id INTEGER,
  quantity INTEGER NOT NULL,
  price INTEGER NOT NULL
)''',
    '''
CREATE TABLE reviews (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  author TEXT NOT NULL,
  rating INTEGER NOT NULL,
  body TEXT NOT NULL,
  photo_path TEXT,
  created_at INTEGER NOT NULL
)''',
    '''
CREATE TABLE search_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  query TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  UNIQUE (user_id, query)
)''',
    '''
CREATE TABLE ingredients (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  risk INTEGER NOT NULL DEFAULT 0,
  is_allergen INTEGER NOT NULL DEFAULT 0,
  group_key TEXT
)''',
    '''
CREATE TABLE product_ingredients (
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  ingredient_id INTEGER NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
  PRIMARY KEY (product_id, ingredient_id)
)''',
    '''
CREATE TABLE blacklist (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  group_key TEXT,
  enabled INTEGER NOT NULL DEFAULT 0,
  is_custom INTEGER NOT NULL DEFAULT 0
)''',
    '''
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
)''',
    '''
CREATE TABLE chat_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  is_user INTEGER NOT NULL,
  text TEXT NOT NULL,
  created_at INTEGER NOT NULL
)''',
  ];
}
