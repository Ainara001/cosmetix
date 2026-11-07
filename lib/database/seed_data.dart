import 'package:sqflite/sqflite.dart';

import 'package:cosmetix/database/catalog_data.dart';
import 'package:cosmetix/database/catalog_structure_data.dart';
import 'package:cosmetix/database/store_data.dart';

import 'package:cosmetix/core/utils/password_hasher.dart';

/// Demo content that makes the app look alive right after the first launch.
/// The product catalog itself lives in `assets/catalog/*.json`
/// (see [CatalogData]); this class puts it into SQLite.
class SeedData {
  SeedData._();

  static const demoEmail = 'ainara.rust@gmail.com';
  static const demoPassword = 'Cosmetix123';

  static const greeting =
      'Здравствуйте! Я ИИ-помощник Cosmetix. Какой вопрос по косметике или '
      'уходу за собой я могу помочь решить сегодня?';

  static Future<void> insertAll(DatabaseExecutor db) async {
    final catalog = await CatalogData.load();
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();

    for (final s in StoreData.stores) {
      batch.insert('stores', _storeRow(s));
    }

    for (final i in catalog.ingredients) {
      batch.insert('ingredients', {
        'name': i.name,
        'description': i.description,
        'risk': i.risk,
        'is_allergen': i.isAllergen ? 1 : 0,
        'group_key': i.groupKey,
      });
    }

    for (var i = 0; i < catalog.products.length; i++) {
      final p = catalog.products[i];
      final id = i + 1;
      batch.insert(
        'products',
        _productRow(id, p, now - i * 86400000, withCountry: true),
      );
      // The same product in every shop (DEMO prices and stock, see StoreData).
      for (var s = 0; s < StoreData.stores.length; s++) {
        batch.insert('product_prices', _offerRow(id, p, s));
      }
      for (final ing in p.ingredients) {
        batch.insert('product_ingredients', {
          'product_id': id,
          'ingredient_id': ing,
        });
      }
      _insertTraits(batch, id, p);
    }

    batch.insert('users', {
      'id': 1,
      'first_name': 'Айнара',
      'last_name': 'Рустемкызы',
      'email': demoEmail,
      'password_hash': PasswordHasher.hash(demoPassword),
      'phone': '+7 707 334 52 11',
      'city': 'Астана',
      'skin_type': 'Нормальная',
      'skin_tone': 'Светлый',
      'undertone': 'Тёплый',
      'color_type': 'Весна',
      'skin_concerns': 'Сухость и шелушение|Пигментация',
      'bonus_points': 0,
      'visits': 0,
      'created_at': now,
      'updated_at': now,
    });
    await batch.commit(noResult: true);

    await applyTryOn(db, catalog);
    await applyCatalogStructure(db, catalog);
    await insertUserDefaults(db, 1, demo: true);
    await _insertReviews(db, now);
  }

  static void _insertTraits(Batch batch, int productId, ProductSeed p) {
    final t = p.traits;
    if (t == null) return;
    void rows(String table, String column, List<String> values) {
      for (final v in values) {
        batch.insert(table, {
          'product_id': productId,
          column: v,
          'source': 'seed',
        });
      }
    }

    rows('product_skin_types', 'skin_type', t.skinTypes);
    rows('product_color_types', 'color_type', t.colorTypes);
    rows('product_undertones', 'undertone', t.undertones);
    rows('product_concerns', 'concern', t.concerns);
    rows('product_tags', 'tag', t.tags);
  }

  /// [withCountry]: the `country` columns exist from DB v14 on; the older
  /// migration steps (v10, v11) run before that and must not write them.
  static Map<String, Object?> _productRow(
    int id,
    ProductSeed p,
    int createdAt, {
    bool withCountry = false,
  }) => {
    'id': id,
    'brand': p.brand,
    'name': p.name,
    'category': p.category,
    'zone': p.zone,
    'price': p.price,
    'old_price': p.oldPrice,
    'in_stock': p.inStock ? 1 : 0,
    'art': p.artValue,
    'color': p.color,
    'description': p.description,
    'inci': p.inci,
    'source_url': p.sourceUrl,
    if (withCountry) ...{
      'country': p.country,
      'country_source': p.countrySource,
    },
    'shade': p.shade,
    'natural_percent': p.naturalPercent,
    'featured': p.featured ? 1 : 0,
    'trending': p.trending ? 1 : 0,
    // newer products have a later date (used by "По новизне")
    'created_at': createdAt,
  };

  /// Migration steps (DB v10, v11): products added after the first real
  /// catalog (acids, retinol, vitamin C, BHA, palettes by number, serums) for a
  /// database that already has the older ones; a fresh install gets them from [insertAll]. Shops and
  /// ingredients must exist (else: nothing to attach to, nothing is done).
  static Future<void> applyNewProducts(DatabaseExecutor db) async {
    final existing = {
      for (final r in await db.query(
        'products',
        columns: ['id', 'brand', 'name'],
      ))
        '${r['brand']}|${r['name']}': r['id']! as int,
    };
    if (existing.isEmpty) return; // a fresh install: insertAll seeds them
    final usedIds = {
      for (final r in await db.query('products', columns: ['id']))
        r['id']! as int,
    };
    final storeCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM stores'),
    );
    final known = {
      for (final r in await db.query('ingredients', columns: ['id']))
        r['id']! as int,
    };
    final catalog = await CatalogData.load();
    final products = catalog.products;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (var i = catalog.firstNewProduct; i < products.length; i++) {
      final p = products[i];
      if (existing.containsKey(p.key)) continue;
      final id = i + 1;
      // the id belongs to another product of this database: never mix them
      if (usedIds.contains(id)) continue;
      batch.insert(
        'products',
        _productRow(id, p, now - (products.length - i) * 3600000),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      for (var s = 0; s < (storeCount ?? 0); s++) {
        batch.insert(
          'product_prices',
          _offerRow(id, p, s),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      for (final ing in p.ingredients) {
        if (known.contains(ing)) {
          batch.insert('product_ingredients', {
            'product_id': id,
            'ingredient_id': ing,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
      _insertTraits(batch, id, p);
    }
    await batch.commit(noResult: true);
  }

  static Map<String, Object?> _storeRow(StoreSeed s) => {
    'name': s.name,
    'distance_m': StoreData.fromCenter(s),
    'address': s.address,
    'rating': 0.0,
    'lat': s.lat,
    'lng': s.lng,
    'chain': s.chain,
    'hours': s.hours,
    'source': s.source,
  };

  static Map<String, Object?> _offerRow(
    int productId,
    ProductSeed p,
    int storeIndex,
  ) {
    final qty = StoreData.offerQty(
      p.inStock,
      productId,
      storeIndex,
      perfume: p.art == 'perfume',
    );
    return {
      'product_id': productId,
      'store_id': storeIndex + 1,
      'price': StoreData.offerPrice(p.price, productId, storeIndex),
      'in_stock': qty > 0 ? 1 : 0,
      'qty': qty,
      'source': 'demo',
    };
  }

  /// Migration step (DB v9): the three old demo shops (ids 1..3, kept so carts
  /// and orders stay valid) become real ones and the other real shops are
  /// added, each with demo price and stock for every product. Prices of the
  /// old rows are kept.
  static Future<void> applyRealStores(DatabaseExecutor db) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM stores'),
    );
    if ((count ?? 0) == 0) return; // a fresh install: insertAll seeds them
    final existing = {
      for (final r in await db.query('stores', columns: ['id']))
        r['id']! as int,
    };
    final batch = db.batch();
    for (var i = 0; i < StoreData.stores.length; i++) {
      final row = _storeRow(StoreData.stores[i]);
      if (existing.contains(i + 1)) {
        batch.update('stores', row, where: 'id = ?', whereArgs: [i + 1]);
      } else {
        batch.insert('stores', {'id': i + 1, ...row});
      }
    }
    await batch.commit(noResult: true);
    final products = await db.query(
      'products',
      columns: ['id', 'price', 'in_stock', 'art'],
    );
    final prices = await db.query('product_prices');
    final have = {
      for (final r in prices) '${r['product_id']}|${r['store_id']}',
    };
    final b2 = db.batch();
    for (final r in products) {
      final id = r['id']! as int;
      final base = r['price']! as int;
      final stocked = (r['in_stock'] as int? ?? 1) == 1;
      final perfume = (r['art'] as String? ?? '').startsWith('perfume');
      for (var s = 0; s < StoreData.stores.length; s++) {
        final qty = StoreData.offerQty(stocked, id, s, perfume: perfume);
        if (have.contains('$id|${s + 1}')) {
          // keep the price and stock the old row had, only add the quantity
          final old = prices.firstWhere(
            (x) => x['product_id'] == id && x['store_id'] == s + 1,
          );
          final wasIn = (old['in_stock'] as int? ?? 1) == 1;
          b2.update(
            'product_prices',
            {'qty': wasIn ? (qty > 0 ? qty : 2) : 0, 'source': 'demo'},
            where: 'id = ?',
            whereArgs: [old['id']],
          );
        } else {
          b2.insert('product_prices', {
            'product_id': id,
            'store_id': s + 1,
            'price': StoreData.offerPrice(base, id, s),
            'in_stock': qty > 0 ? 1 : 0,
            'qty': qty,
            'source': 'demo',
          });
        }
      }
    }
    await b2.commit(noResult: true);
  }

  /// Migration step (DB v8, v12): stores the shade colour of each makeup
  /// product of the catalog (`shade` in products.json): sampled from its photo,
  /// one shade of the line, so the match is approximate.
  static Future<void> applyShades(DatabaseExecutor db) async {
    final catalog = await CatalogData.load();
    final batch = db.batch();
    for (final p in catalog.products) {
      if (p.shade == null) continue;
      batch.update(
        'products',
        {'shade': p.shade},
        where: 'brand = ? AND name = ?',
        whereArgs: [p.brand, p.name],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Migration step (DB v15) and fresh install: the try-on data of the catalog
  /// products that have it (`try_on` in products.json). Only what the catalog
  /// states is written; a colour never appears without its source and status
  /// (the parser refuses that). Rows are found by `brand|name`, so another
  /// product of the same database is never touched; existing rows are replaced
  /// by the catalog's data for the same product.
  static Future<void> applyTryOn(
    DatabaseExecutor db, [
    CatalogData? from,
  ]) async {
    final catalog = from ?? await CatalogData.load();
    final ids = {
      for (final r in await db.query(
        'products',
        columns: ['id', 'brand', 'name'],
      ))
        '${r['brand']}|${r['name']}': r['id']! as int,
    };
    final batch = db.batch();
    for (final p in catalog.products) {
      final t = p.tryOn;
      final id = ids[p.key];
      if (t == null || id == null) continue;
      batch.insert('product_shades', {
        'product_id': id,
        'kind': t.kind,
        'line_key': t.line,
        'shade_code': t.shadeCode,
        'shade_name': t.shadeName,
        'colour': t.colour,
        'colour_source': t.colourSource,
        'colour_status': t.colourStatus,
        'finish': t.finish,
        'finish_source': t.finishSource,
        'note': t.note,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Migration step (DB v16): the product lines, what is known about each
  /// variant of them and the (still colourless) cells of the palettes whose
  /// number of cells a source confirms (`assets/catalog/lines.json`).
  ///
  /// Safe to run again: lines and variant facts are written again (nothing
  /// refers to them with a cascade), cells are only ADDED when missing, so a
  /// colour that was measured and stored later is never overwritten. Products,
  /// ids, prices, cart, favourites and `products.shade` are not touched.
  static Future<void> applyCatalogStructure(
    DatabaseExecutor db, [
    CatalogData? from,
    CatalogStructure? structure,
  ]) async {
    final catalog = from ?? await CatalogData.load();
    final data = structure ?? await CatalogStructure.load();
    data.validateAgainst(catalog);
    final ids = {
      for (final r in await db.query(
        'products',
        columns: ['id', 'brand', 'name'],
      ))
        '${r['brand']}|${r['name']}': r['id']! as int,
    };
    final slugOf = {for (final l in data.lines) l.key: l.slug};
    final batch = db.batch();
    for (final l in data.lines) {
      batch.insert('product_lines', {
        'line_key': l.key,
        'slug': l.slug,
        'brand': l.brand,
        'name': l.name,
        'kind': l.kind,
        'source_url': l.sourceUrl,
        'checked_at': l.checkedAt,
        'confidence': l.confidence,
        'note': l.note,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    final byKey = catalog.byKey;
    for (final v in data.variants) {
      final id = ids[v.productKey];
      if (id == null) {
        // a fresh install fills the table after the products exist
        continue;
      }
      batch.insert('product_variant_facts', {
        'product_id': id,
        'pan_count': v.panCount,
        'source_url': v.sourceUrl,
        'checked_at': v.checkedAt,
        'confidence': v.confidence,
        'note': v.note,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final n = v.panCount;
      if (n == null) continue;
      final t = byKey[v.productKey]!.tryOn;
      final slug = slugOf[t?.line];
      final code = t?.shadeCode;
      if (slug == null || code == null) {
        throw FormatException(
          'lines.json: ${v.productKey} has cells but no line or variant code',
        );
      }
      for (var pos = 1; pos <= n; pos++) {
        batch.insert('product_shade_pans', {
          'pan_key': panKeyOf(slug, code, pos),
          'product_id': id,
          'position': pos,
          'colour_status': PanColourStatus.missing,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    await batch.commit(noResult: true);
  }

  /// Migration step (DB v14): the country of manufacture of the catalog
  /// products that have one with a source (`country`, `country_source` in
  /// products.json). Products without a verified country are left empty: the
  /// value is never guessed. Rows the catalog has nothing for are not touched.
  static Future<void> applyCountries(
    DatabaseExecutor db, [
    CatalogData? from,
  ]) async {
    final catalog = from ?? await CatalogData.load();
    final batch = db.batch();
    for (final p in catalog.products) {
      if (p.country == null) continue;
      batch.update(
        'products',
        {'country': p.country, 'country_source': p.countrySource},
        where: 'brand = ? AND name = ?',
        whereArgs: [p.brand, p.name],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Migration step (DB v7): the first demo catalog had invented products. The
  /// products keep their ids (favourites, cart, orders, reviews stay valid) and
  /// become real ones with a photo, the published INCI list and its source.
  /// Prices, stock and flags are left as they were.
  static Future<void> applyRealCatalog(DatabaseExecutor db) async {
    // products are found by their old name, not by id: anything the user or an
    // older build added under another name is left alone
    final idByName = {
      for (final r in await db.query(
        'products',
        columns: ['id', 'brand', 'name'],
      ))
        '${r['brand']}|${r['name']}': r['id']! as int,
    };
    final known = {
      for (final r in await db.query('ingredients', columns: ['id']))
        r['id']! as int,
    };
    final catalog = await CatalogData.load();
    final batch = db.batch();
    for (final p in catalog.products) {
      final legacy = p.legacyName;
      if (legacy == null) continue; // the Cosmetix gift set stays as it was
      final id = idByName[legacy];
      if (id == null) continue;
      batch.update(
        'products',
        {
          'brand': p.brand,
          'name': p.name,
          'category': p.category,
          'zone': p.zone,
          'art': p.artValue,
          'color': p.color,
          'description': p.description,
          'inci': p.inci,
          'source_url': p.sourceUrl,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      batch.delete(
        'product_ingredients',
        where: 'product_id = ?',
        whereArgs: [id],
      );
      for (final ing in p.ingredients) {
        if (!known.contains(ing)) continue;
        batch.insert('product_ingredients', {
          'product_id': id,
          'ingredient_id': ing,
        });
      }
      // curated traits belong to the old product; AI answers were cached for it
      for (final t in const [
        'product_skin_types',
        'product_color_types',
        'product_undertones',
        'product_concerns',
        'product_tags',
      ]) {
        batch.delete(t, where: 'product_id = ?', whereArgs: [id]);
      }
      batch.delete(
        'product_ai_classification',
        where: 'product_id = ?',
        whereArgs: [id],
      );
      _insertTraits(batch, id, p);
    }
    await batch.commit(noResult: true);
  }

  /// Migration step: gives products that already exist in a user's database
  /// the curated traits (matched by brand + name).
  static Future<void> backfillProductTraits(DatabaseExecutor db) async {
    final products = await db.query(
      'products',
      columns: ['id', 'brand', 'name'],
    );
    final seeds = (await CatalogData.load()).byKey;
    final batch = db.batch();
    for (final p in products) {
      final seed = seeds['${p['brand']}|${p['name']}'];
      if (seed != null) _insertTraits(batch, p['id']! as int, seed);
    }
    await batch.commit(noResult: true);
  }

  /// Blacklist, welcome chat message (and demo favourites/reactions).
  static Future<void> insertUserDefaults(
    DatabaseExecutor db,
    int userId, {
    bool demo = false,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final b in _blacklist) {
      batch.insert('blacklist', {
        'user_id': userId,
        'name': b.$1,
        'description': b.$2,
        'group_key': b.$3,
        'enabled': demo ? (b.$4 ? 1 : 0) : 0,
        'is_custom': 0,
      });
    }
    batch.insert('chat_messages', {
      'user_id': userId,
      'is_user': 0,
      'text': greeting,
      'created_at': now - 60000 * 5,
    });
    if (demo) {
      for (final productId in [1, 2]) {
        batch.insert('favorites', {
          'user_id': userId,
          'product_id': productId,
          'created_at': now,
        });
      }
      final reactions = [
        (3, 'Покраснение и зуд', 3, DateTime(2025, 10, 12)),
        (4, 'Сильные высыпания', 5, DateTime(2025, 9, 5)),
        (15, 'Легкое шелушение', 1, DateTime(2025, 8, 22)),
      ];
      for (final r in reactions) {
        batch.insert('reactions', {
          'user_id': userId,
          'product_id': r.$1,
          'title': r.$2,
          'severity': r.$3,
          'reaction_date': r.$4.millisecondsSinceEpoch,
          'notes': '',
          'created_at': now,
          'updated_at': now,
        });
      }
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _insertReviews(DatabaseExecutor db, int now) async {
    const text1 =
        'Нифига себе рил качественно - держится долго, не '
        'чувствуется на коже и не подчеркивает поры.';
    const text2 =
        'Нифига себе рил качественно - оттенок понравился, но на '
        'второй день слегка блестит.';
    const text3 =
        'Нифига себе рил качественно - отлично подходит для '
        'ежедневного макияжа и не вызывает дискомфорта.';
    final rows = [
      (1, 'Амина', 5, text1, const Duration(hours: 2)),
      (1, 'Мария', 4, text2, const Duration(days: 1)),
      (1, 'Алима', 5, text3, const Duration(days: 3)),
      (
        1,
        'Анастасия',
        5,
        'Очень нежные оттенки, пигмент хороший.',
        const Duration(days: 6),
      ),
      (
        1,
        'София',
        5,
        'Беру уже вторую, всем советую.',
        const Duration(days: 9),
      ),
      (
        1,
        'Елена',
        4,
        'Красивая упаковка, цвета как на фото.',
        const Duration(days: 12),
      ),
      (
        2,
        'Динара',
        5,
        'Мягкие тени, легко растушевываются.',
        const Duration(days: 2),
      ),
      (
        3,
        'Айгерим',
        4,
        'Приятный оттенок, но немного липкий.',
        const Duration(days: 4),
      ),
      (
        5,
        'Жанар',
        5,
        'Кожа стала заметно ровнее за две недели.',
        const Duration(days: 5),
      ),
      (
        11,
        'Мадина',
        5,
        'Лучший SPF, что я пробовала, не оставляет белых следов.',
        const Duration(days: 1),
      ),
      (
        6,
        'Камила',
        4,
        'Стойкий аромат, но дороговат.',
        const Duration(days: 8),
      ),
    ];
    final batch = db.batch();
    for (final r in rows) {
      batch.insert('reviews', {
        'product_id': r.$1,
        'author': r.$2,
        'rating': r.$3,
        'body': r.$4,
        'created_at': now - r.$5.inMilliseconds,
      });
    }
    await batch.commit(noResult: true);
  }

  // (name, description, group key, enabled for the demo user)
  static const _blacklist = [
    ('Парабены', 'Сложные эфиры, консерванты', 'paraben', true),
    ('Сульфаты (SLS / SLES)', 'Пенообразователи, сушат кожу', 'sulfate', true),
    ('Силиконы', 'Создают пленку, забивают поры', 'silicone', false),
    ('Минеральное масло', 'Продукт нефтепереработки', 'mineral_oil', false),
    ('Формальдегид', 'Канцерогенный консервант', 'formaldehyde', true),
    ('Фталаты', 'Токсичные фиксаторы запаха', 'phthalates', false),
    ('Триклозан', 'Антибактериальное вещество', 'triclosan', false),
  ];
}
