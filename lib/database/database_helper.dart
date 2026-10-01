import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'seed_data.dart';

/// Owns the SQLite connection: creates the schema, seeds demo data and
/// handles database versioning.
class DatabaseHelper {
  /// [path] is only set in tests (use `inMemoryDatabasePath`).
  DatabaseHelper({this.path});

  static const dbName = 'cosmetix.db';

  /// Increase this number and extend [_onUpgrade] when the schema changes.
  static const dbVersion = 1;

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

  Future<void> _onCreate(Database db, int version) async {
    for (final sql in _schema) {
      await db.execute(sql);
    }
    await SeedData.insertAll(db);
  }

  /// Demo strategy: the catalog is seed data, so when the version changes we
  /// rebuild all tables and seed them again.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (final table in _tables.reversed) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
    await _onCreate(db, newVersion);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Deletes all data and builds the demo database again.
  Future<void> resetDemoData() async {
    final db = await database;
    for (final table in _tables.reversed) {
      await db.execute('DELETE FROM $table');
      await db.execute("DELETE FROM sqlite_sequence WHERE name = '$table'");
    }
    await SeedData.insertAll(db);
  }

  static const _tables = [
    'users',
    'settings',
    'stores',
    'products',
    'product_prices',
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
  ];

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
