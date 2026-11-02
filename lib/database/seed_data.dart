import 'package:sqflite/sqflite.dart';

import 'package:cosmetix/database/seed_traits.dart';
import 'package:cosmetix/database/store_data.dart';

import 'package:cosmetix/core/utils/password_hasher.dart';

/// Demo content that makes the app look alive right after the first launch.
class SeedData {
  SeedData._();

  static const demoEmail = 'ainara.rust@gmail.com';
  static const demoPassword = 'Cosmetix123';

  static const greeting =
      'Здравствуйте! Я ИИ-помощник Cosmetix. Какой вопрос по косметике или '
      'уходу за собой я могу помочь решить сегодня?';

  static Future<void> insertAll(DatabaseExecutor db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();

    for (final s in StoreData.stores) {
      batch.insert('stores', _storeRow(s));
    }

    for (final i in _ingredients) {
      batch.insert('ingredients', {
        'name': i.$1,
        'description': i.$2,
        'risk': i.$3,
        'is_allergen': i.$4 ? 1 : 0,
        'group_key': i.$5,
      });
    }

    for (var i = 0; i < _products.length; i++) {
      final p = _products[i];
      final id = i + 1;
      batch.insert('products', _productRow(id, p, now - i * 86400000));
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
      _insertTraits(batch, id, p.brand, p.name);
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

    await insertUserDefaults(db, 1, demo: true);
    await _insertReviews(db, now);
  }

  static void _insertTraits(
    Batch batch,
    int productId,
    String brand,
    String name,
  ) {
    final t = seedTraits['$brand|$name'];
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

  /// Representative colour of each makeup product (ARGB), sampled from its
  /// photo. It is one shade of the line, so the match is approximate; it lets
  /// the app compare the product with the colours of the user's colour type.
  static const shades = {
    'Rom&nd|Better Than Palette 05 Shade & Shadow Garden': 0xFFCCA186,
    'Peripera|Heart Jam Glow Lip': 0xFFD24E5E,
    'Rom&nd|Better Than Eyes': 0xFFC78A88,
    'Peripera|Ink The Velvet 31 Wine Nude': 0xFF753E44,
    'Peripera|Ink Mood Glowy Tint 30 Happy Berry': 0xFFF48C93,
    'Rom&nd|Glasting Color Gloss': 0xFFAF8488,
    'Missha|Magic Cushion Moist Up': 0xFFE3C1A6,
    'Rom&nd|Better Than Cheek': 0xFFDDB1B6,
    'Rom&nd|Better Than Palette 00 Light & Glitter Garden': 0xFFCD9D9A,
    'Rom&nd|Better Than Palette 01 Pampas Garden': 0xFFC78D7C,
    'Rom&nd|Better Than Palette 02 Mahogany Garden': 0xFFB6896F,
    'Rom&nd|Better Than Palette 03 Rosebud Garden': 0xFFBA867D,
    'Rom&nd|Better Than Palette 07 Berry Fuchsia Garden': 0xFFB4708C,
    'Peripera|Ink Mood Glowy Tint 03 Rose In Mind': 0xFFD06F69,
    'Rom&nd|Juicy Lasting Tint 01 Pomelo Skin': 0xFFDBA18C,
    '3CE|Mood Recipe Face Blush': 0xFFD79F88,
  };

  static Map<String, Object?> _productRow(int id, _P p, int createdAt) => {
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
    'source_url': p.source,
    'shade': shades['${p.brand}|${p.name}'],
    'natural_percent': p.natural,
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
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (var i = _firstNewProduct; i < _products.length; i++) {
      final p = _products[i];
      if (existing.containsKey('${p.brand}|${p.name}')) continue;
      final id = i + 1;
      // the id belongs to another product of this database: never mix them
      if (usedIds.contains(id)) continue;
      batch.insert(
        'products',
        _productRow(id, p, now - (_products.length - i) * 3600000),
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
      _insertTraits(batch, id, p.brand, p.name);
    }
    await batch.commit(noResult: true);
  }

  /// Index in [_products] of the first product added after DB v9.
  static const _firstNewProduct = 18;

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

  static Map<String, Object?> _offerRow(int productId, _P p, int storeIndex) {
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

  /// Migration step (DB v8): stores the shade colours above.
  static Future<void> applyShades(DatabaseExecutor db) async {
    final batch = db.batch();
    shades.forEach((key, argb) {
      final i = key.indexOf('|');
      batch.update(
        'products',
        {'shade': argb},
        where: 'brand = ? AND name = ?',
        whereArgs: [key.substring(0, i), key.substring(i + 1)],
      );
    });
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
    final batch = db.batch();
    for (var i = 0; i < _products.length; i++) {
      final p = _products[i];
      final legacy = _legacyNames[i];
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
          'source_url': p.source,
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
      _insertTraits(batch, id, p.brand, p.name);
    }
    await batch.commit(noResult: true);
  }

  /// `brand|name` of the products of the first demo catalog, by position in
  /// [_products] (null: the product did not change).
  static const _legacyNames = <int, String>{
    0: 'Flower Knows|Палетка Flower Knows Strawberry',
    1: 'Peripera|Палетка Peripera Ink Cozy',
    2: 'Flower Knows|Strawberry Lip Tint',
    3: 'Rom&nd|Better Than Eyes',
    4: 'Rom&nd|Сыворотка для лица',
    5: 'Peripera|Парфюм Peripera Mood',
    6: 'Flower Knows|Тинт для губ Flower Knows',
    7: 'Peripera|Тинт Peripera Ink',
    8: 'Rom&nd|Блеск Rom&nd Glasting',
    9: 'Missha|Кушон Missha Magic',
    10: 'Beauty of Joseon|Крем SPF 50 Relief Sun',
    11: 'The Ordinary|Сыворотка Niacinamide 10%',
    12: 'Rom&nd|Румяна Better Than Cheek',
    13: 'Dr.Jart+|Увлажняющий крем для тела',
    14: 'Cosmetics Mockup|Cosmetics Mockup Cream',
    15: 'Mise-en-scène|Шампунь Perfect Serum',
    17: 'Anua|Тонер Heartleaf 77%',
  };

  /// Migration step: gives products that already exist in a user's database
  /// the curated traits (matched by brand + name).
  static Future<void> backfillProductTraits(DatabaseExecutor db) async {
    final products = await db.query(
      'products',
      columns: ['id', 'brand', 'name'],
    );
    final batch = db.batch();
    for (final p in products) {
      _insertTraits(
        batch,
        p['id']! as int,
        p['brand']! as String,
        p['name']! as String,
      );
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

  // (name, description, risk 0-2, allergen, group key); ids are 1-based
  static const _ingredients = [
    (
      'Вода / Aqua',
      'Основной растворитель, абсолютно безопасен.',
      0,
      false,
      null,
    ),
    (
      'Глицерин / Glycerin',
      'Увлажняющий компонент, удерживает влагу.',
      0,
      false,
      null,
    ),
    (
      'Токоферол / Tocopherol',
      'Витамин Е. Антиоксидант, защищает кожу.',
      0,
      false,
      null,
    ),
    (
      'Салициловая кислота / Salicylic Acid',
      'BHA-кислота. Очищает поры. Возможна сухость.',
      1,
      true,
      null,
    ),
    (
      'Парабены / Parabens',
      'Консервант. Потенциальный аллерген.',
      2,
      true,
      'paraben',
    ),
    (
      'Лаурилсульфат натрия / SLS',
      'Пенообразователь, сушит кожу.',
      2,
      false,
      'sulfate',
    ),
    (
      'Диметикон / Dimethicone',
      'Силикон, создаёт плёнку на коже.',
      1,
      false,
      'silicone',
    ),
    (
      'Минеральное масло / Mineral Oil',
      'Продукт нефтепереработки.',
      1,
      false,
      'mineral_oil',
    ),
    (
      'Формальдегид / Formaldehyde',
      'Канцерогенный консервант.',
      2,
      false,
      'formaldehyde',
    ),
    (
      'Фталаты / Phthalates',
      'Токсичные фиксаторы запаха.',
      2,
      false,
      'phthalates',
    ),
    (
      'Триклозан / Triclosan',
      'Антибактериальное вещество.',
      2,
      false,
      'triclosan',
    ),
    (
      'Ниацинамид / Niacinamide',
      'Выравнивает тон и сужает поры.',
      0,
      false,
      null,
    ),
    (
      'Гиалуроновая кислота / Hyaluronic Acid',
      'Глубоко увлажняет кожу.',
      0,
      false,
      null,
    ),
    (
      'Парфюмерная композиция / Parfum',
      'Ароматизатор. Может вызвать раздражение.',
      1,
      true,
      null,
    ),
    ('Тальк / Talc', 'Матирующий наполнитель.', 0, false, null),
    ('Слюда / Mica', 'Придаёт сияние и пигмент.', 0, false, null),
    ('Оксид цинка / Zinc Oxide', 'Минеральный УФ-фильтр.', 0, false, null),
    (
      'Пчелиный воск / Beeswax',
      'Натуральный воск, смягчает губы.',
      0,
      false,
      null,
    ),
    (
      'Спирт денат. / Alcohol Denat.',
      'Сушит кожу, повышает проницаемость.',
      1,
      false,
      null,
    ),
  ];

  static const _products = [
    _P(
      '3CE',
      'Super Slim Waterproof Mascara',
      'Макияж',
      'Глаза',
      2500,
      5000,
      true,
      'tube',
      0xFFF4B6C2,
      'Тонкая водостойкая тушь для аккуратного прокрашивания каждой ресницы.',
      94,
      [],
      photo: 'assets/products/1.jpg',
      inci:
          'Isododecane, Trimethylsiloxysilicate, Microcrystalline Wax, Polyethylene, Disteardimonium Hectorite, Dextrin Palmitate/Ethylhexanoate, Iron Oxide Black (Ci 77499), Silica, Hydrogenated Polyisobutene, Silica Silylate, Vp/Eicosene Copolymer, Polypropylsilsesquioxane, Ethylene/Propylene Copolymer, Propylene Carbonate, Glyceryl Caprylate, Sorbitan Isostearate, Polymethylsilsesquioxane, Triethoxycaprylylsilane',
      source:
          'https://incidecoder.com/products/3ce-super-slim-waterproof-mascara',
      featured: true,
      trending: true,
    ),
    _P(
      'Rom&nd',
      'Better Than Palette 05 Shade & Shadow Garden',
      'Макияж',
      'Глаза',
      4800,
      null,
      true,
      'palette',
      0xFFF6C9D3,
      'Палетка из десяти матовых и сияющих оттенков для повседневного макияжа глаз.',
      86,
      [1, 7, 15, 16],
      photo: 'assets/products/2.jpg',
      inci:
          'Talc, Mica (Ci 77019), Nylon-12, Boron Nitride, Neopentyl Glycol Diethylhexanoate, Phenyl Trimethicone, Dimethicone, Methylpropanediol, Titanium Dioxide (Ci 77891), Magnesium Myristate, Diisostearyl Malate, Dipentaerythrityl Hexahydroxystearate/Hexastearate/Hexarosinate, Isostearyl Neopentanoate, Octyldodecyl Stearoyl Stearate, Iron Oxides (Ci 77492), Iron Oxides (Ci 77491), Propanediol, Polybutene, Magnesium Stearate, Iron Oxides (Ci 77499), Hydrogenated Lecithin, Lauroyl Lysine, Triethoxycaprylylsilane, Yellow 5 Lake (Ci 19140), Methicone, Ultramarines (Ci 77007), Red 30 (Ci 73360), Water',
      source:
          'https://incidecoder.com/products/rom-nd-better-than-palette-05-shade-shadow-garden',
      trending: true,
    ),
    _P(
      'Peripera',
      'Heart Jam Glow Lip',
      'Макияж',
      'Губы',
      3500,
      null,
      true,
      'tube',
      0xFFE06A7C,
      'Сияющая помада-бальзам для губ с лёгким цветом и блеском.',
      90,
      [8, 14, 18],
      photo: 'assets/products/3.jpg',
      inci:
          'Diisostearyl Malate, Bis-Behenyl/Isostearyl/Phytosteryl Dimer Dilinoleyl Dimer Dilinoleate, Polyglyceryl-2 Triisostearate, Paraffin, Tridecyl Trimellitate, Bis-Diglyceryl Polyacyladipate-2, Pentaerythrityl Tetraisostearate, Microcrystalline Wax, Sorbitan Isostearate, 1,2-Hexanediol, Synthetic Beeswax, Disteardimonium Hectorite, Titanium Dioxide, Phloxine B, Ethylene/Propylene Copolymer, Propylene Carbonate, Sunset Yellow Fcf, Tartrazine, Lithol Rubine Bca, Brilliant Blue Fcf, Fragrance, Persea Gratissima (Avocado) Oil, Butyrospermum Parkii (Shea) Butter, Prunus Armeniaca (Apricot) Kernel Oil',
      source: 'https://incidecoder.com/products/peripera-heart-jam-glow-lip',
    ),
    _P(
      'Rom&nd',
      'Better Than Eyes',
      'Макияж',
      'Глаза',
      5200,
      null,
      true,
      'palette',
      0xFFB08A7A,
      'Компактная палетка из четырёх оттенков теней: матовые и мерцающие.',
      82,
      [1, 7, 16],
      photo: 'assets/products/4.jpg',
      inci:
          'Caprylic/Capric Triglyceride, Silica, Iron Oxides (Ci 77492), Iron Oxides (Ci 77491), Iron Oxides (Ci 77499), Magnesium Myristate, Nylon-12, Methylpropanediol, Dimethiconol Stearate, Dimethicone, Propanediol, Lauroyl Lysine, Triethoxycaprylylsilane, Methicone, Water, Titanium Dioxide (Ci 77891), Yellow 5 Lake (Ci 19140), Mica (Ci 77019), Octyldodecyl Stearoyl Stearate, Phenyl Trimethicone, Octyldodecanol, Diisostearyl Malate, Dipentaerythrityl Hexahydroxystearate/Hexastearate/Hexarosinate, Hydrogenated Lecithin, Calcium Titanium Borosilicate, Synthetic Fluorphlogopite, Methyl Methacrylate Crosspolymer, Vinyl Dimethicone/Methicone Silsesquioxane Crosspolymer, Calcium Aluminum Borosilicate, Neopentyl Glycol Diethylhexanoate, Hexyl Laurate, Dimethicone/Vinyl Dimethicone Crosspolymer, Diglyceryl Sebacate/Isopalmitate, Polypropylene, Sorbitan Sesquiisostearate, Aluminum Distearate, PTFE, Synthetic Wax, Tin Oxide (Ci 77861), Phenoxyethanol, Macadamia Ternifolia (Macadamia) Seed Oil, Carmine (Ci 75470)',
      source: 'https://incidecoder.com/products/romand-better-than-eyes',
    ),
    _P(
      'COSRX',
      'Advanced Snail 96 Mucin Power Essence',
      'Уход за лицом',
      'Лицо',
      6900,
      null,
      true,
      'bottle',
      0xFFBFD8D2,
      'Лёгкая эссенция с 96% муцина улитки для увлажнения и восстановления кожи.',
      96,
      [13],
      photo: 'assets/products/5.jpg',
      inci:
          'Snail Secretion Filtrate, Betaine, Butylene Glycol, 1,2-Hexanediol, Sodium Polyacrylate, Phenoxyethanol, Sodium Hyaluronate, Allantoin, Ethyl Hexanediol, Carbomer, Panthenol, Arginine',
      source:
          'https://incidecoder.com/products/cosrx-advanced-snail-96-mucin-power-essence-3',
      featured: true,
    ),
    _P(
      'Maison Margiela',
      'Replica Lazy Sunday Morning',
      'Парфюмерия',
      '',
      9800,
      null,
      true,
      'perfume',
      0xFFD9B8D6,
      'Мягкий пудровый аромат: груша, ирис, роза и белый мускус.',
      70,
      [1, 14, 19],
      photo: 'assets/products/6.jpg',
      inci:
          'Alcohol, Fragrance, Water, Benzyl Salicylate, Benzyl Alcohol, Butyl Methoxydibenzoylmethane, Ethylhexyl Methoxycinnamate, Linalool, Citronellol, Geraniol, Cinnamyl Alcohol, Hydroxycitronellal, Farnesol, Limonene, CI 60730, CI 19140',
      source:
          'https://www.costco.com/maison-margiela-replica-lazy-sunday-morning-eau-de-toilette-34-fl-oz.product.100984918.html',
      featured: true,
    ),
    _P(
      'Peripera',
      'Ink The Velvet 31 Wine Nude',
      'Макияж',
      'Губы',
      3200,
      null,
      true,
      'tube',
      0xFFD9707F,
      'Бархатный тинт для губ с матовым финишем и стойким цветом.',
      91,
      [1, 7, 14],
      photo: 'assets/products/7.jpg',
      inci:
          'Dimethicone, Dimethicone/Vinyl Dimethicone Crosspolymer, Water, Polyglyceryl-2 Triisostearate, Cetyl PEG/PPG-10/1 Dimethicone, Isododecane, Butylene Glycol, Ci 77891, Vinyl Dimethicone/Methicone Silsesquioxane Crosspolymer, Dimethicone Crosspolymer, Ci 77492, Ci 77499, Diisostearyl Malate, Ci 77491, 1,2-Hexanediol, VP/Hexadecene Copolymer, PEG-60 Hydrogenated Castor Oil, Ci 15850, Disteardimonium Hectorite, Phenoxyethanol, Fragrance, Propylene Carbonate, Aluminum Hydroxide, Ci 19140, Ci 17200, Ci 42090',
      source:
          'https://incidecoder.com/products/peripera-ink-the-velvet-31-wine-nude',
      featured: true,
    ),
    _P(
      'Peripera',
      'Ink Mood Glowy Tint 30 Happy Berry',
      'Макияж',
      'Губы',
      1500,
      4000,
      true,
      'tube',
      0xFFE58895,
      'Глянцевый тинт для губ с эффектом сочных увлажнённых губ.',
      84,
      [1, 7, 14],
      photo: 'assets/products/8.jpg',
      inci:
          'Water, Diphenyl Dimethicone, Diisostearyl Malate, Bis-Diglyceryl Polyacyladipate-2, Hydrogenated Polyisobutene, Bis-Behenyl/Isostearyl/Phytosteryl Dimer Dilinoleyl Dimer Dilinoleate, Diglycerin, Dipropylene Glycol, Cetyl PEG/PPG-10/1 Dimethicone, Hydrogenated Polydecene, Polysorbate 60, Sorbitan Isostearate, Diisostearoyl Polyglyceryl-3 Dimer Dilinoleate, Pentylene Glycol, Hydroxyethyl Acrylate/Sodium Acryloyldimethyl Taurate Copolymer, Phenoxyethanol, Fragrance, Yellow 6 (Ci 15985), Ethylhexylglycerin, Red 33 (Ci 17200), Yellow 5 (Ci 19140), Red 28 (Ci 45410), Aluminum Hydroxide, Ammonium Polyacrylate, Butylene Glycol, Blue 1 (Ci 42090), Pentaerythrityl Tetra-Di-T-Butyl Hydroxyhydrocinnamate, Hamamelis Virginiana (Witch Hazel) Leaf Extract, Lilium Tigrinum Extract',
      source:
          'https://incidecoder.com/products/peripera-ink-mood-glowy-tint-30-happy-berry',
    ),
    _P(
      'Rom&nd',
      'Glasting Color Gloss',
      'Макияж',
      'Губы',
      3200,
      5500,
      true,
      'tube',
      0xFFEFA4B0,
      'Блеск для губ с цветом и зеркальным эффектом.',
      85,
      [14],
      photo: 'assets/products/9.jpg',
      inci:
          'Hydrogenated Polyisobutene, Bis-Behenyl/Isostearyl/Phytosteryl Dimer Dilinoleyl Dimer Dilinoleate, Diisostearyl Malate, Simmondsia Chinensis (Jojoba) Seed Oil, Silica Dimethyl Silylate, Synthetic Wax, Sorbitan Isostearate, 1,2-Hexanediol, Titanium Dioxide (Ci 77891), Phenoxyethanol, Yellow 5 Lake (Ci 19140), Red 7 Lake (Ci 15850), Fragrance, Blue 1 Lake (Ci 42090)',
      source: 'https://incidecoder.com/products/rom-nd-glasting-color-gloss-2',
    ),
    _P(
      'Missha',
      'Magic Cushion Moist Up',
      'Макияж',
      'Лицо',
      4800,
      6000,
      true,
      'compact',
      0xFFF1C9B5,
      'Увлажняющий кушон с SPF и лёгким покрытием.',
      80,
      [1, 2, 7, 12, 14],
      photo: 'assets/products/10.jpg',
      inci:
          'Water(Aqua), Disteardimonium Hectorite, Pentylene Glycol, Magnesium Sulfate, Cetearyl Dimethicone/Vinyl Dimethicone Crosspolymer, PEG-10 Dimethicone, Acrylates/Polytrimethylsiloxymethacrylate Copolymer, Camellia Sinensis Leaf Water, Salvia Officinalis (Sage) Leaf Water, Ethylhexyl Palmitate, Cyclopentasiloxane, Butylene Glycol Dicaprylate/Dicaprate, Ethylhexyl Salicylate, Fragrance(Parfum), Vinyl Dimethicone/Methicone Silsesquioxane Crosspolymer, Synthetic Fluorphlogopite, Octanediol, Ethylhexylglycerin, Ethylhexyl Methoxycinnamate, Methyl Trimethicone, Alumina, Triethoxycaprylylsilane, Diphenylsiloxy Phenyl Trimethicone, Trisiloxane, Isopropyl Myristate, Ethyl Hexanediol, Lecithin, Acrylates/Stearyl Acrylate/Dimethicone Methacrylate Copolymer, Aluminum Hydroxide, Isododecane, Polypropylsilsesquioxane, Isostearic Acid, Glycerin, Polyhydroxystearic Acid, Polyglyceryl-3 Polyricinoleate, Phenoxyethanol, Niacinamide, Dimethicone, Adenosine, Ci 77492, Ci 77491, Ci 77891, Stearic Acid, Ci 77499, Lauryl PEG-10 Tris(Trimethylsiloxy)silylethyl Dimethicone, Butylene Glycol, 1,2-Hexanediol, Disodium EDTA, Nelumbo Nucifera Root Water',
      source: 'https://incidecoder.com/products/missha-magic-cushion-moist-up',
    ),
    _P(
      'Beauty of Joseon',
      'Relief Sun: Rice + Probiotics SPF50+',
      'Уход за лицом',
      'Лицо',
      7200,
      null,
      true,
      'cream',
      0xFFF3E3A9,
      'Лёгкий солнцезащитный крем SPF50+ с рисовым экстрактом и пробиотиками.',
      88,
      [1, 2, 3, 7, 12],
      photo: 'assets/products/11.jpg',
      inci:
          'Water, Oryza Sativa (Rice) Extract (30%), Dibutyl Adipate, Propanediol, Diethylamino Hydroxybenzoyl Hexyl Benzoate, Polymethylsilsesquioxane, Ethylhexyl Triazone, Niacinamide, Methylene Bis-Benzotriazolyl Tetramethylbutylphenol, Coco-Caprylate/Caprate, Caprylyl Methicone, Diethylhexyl Butamido Triazone, Glycerin, Butylene Glycol, Oryza Sativa (Rice) Germ Extract, Camellia Sinensis Leaf Extract, Lactobacillus/Pumpkin Ferment Extract, Bacillus/Soybean Ferment Extract, Saccharum Officinarum (Sugarcane) Extract, Macrocystis Pyrifera (Kelp) Extract, Cocos Nucifera (Coconut) Fruit Extract, Panax Ginseng Root Extract, Monascus/Rice Ferment, Pentylene Glycol, Behenyl Alcohol, Poly C10-30 Alkyl Acrylate, Polyglyceryl-3 Methylglucose Distearate, Decyl Glucoside, Tromethamine, Carbomer, Acrylates/C10-30 Alkyl Acrylate Crosspolymer, 1,2-Hexanediol, Sodium Stearoyl Glutamate, Polyacrylate Crosspolymer-6, Ethylhexylglycerin, Adenosine, Xanthan Gum, Tocopherol, Lactobacillus/Rice Ferment, Aspergillus Ferment, Saccharomyces/Rice Ferment Filtrate',
      source:
          'https://incidecoder.com/products/beauty-of-joseon-rice-probiotics-sunscreen',
    ),
    _P(
      'The Ordinary',
      'Niacinamide 10% + Zinc 1%',
      'Уход за лицом',
      'Лицо',
      5600,
      null,
      true,
      'bottle',
      0xFFC9D6EA,
      'Сыворотка с 10% ниацинамида и 1% цинка для кожи с несовершенствами и расширенными порами.',
      92,
      [1, 12],
      photo: 'assets/products/12.jpg',
      inci:
          'Aqua (Water), Niacinamide, Zinc Pca, Tamarindus Indica Seed Gum, Pentylene Glycol, Carrageenan, Acacia Senegal Gum, Xanthan Gum, PPG-26-Buteth-26, PEG-40 Hydrogenated Castor Oil, Ethoxydiglycol, Phenoxyethanol, Chlorphenesin',
      source:
          'https://incidecoder.com/products/the-ordinary-niacinamide-10-zinc-1-8',
    ),
    _P(
      'Rom&nd',
      'Better Than Cheek',
      'Макияж',
      'Лицо',
      4900,
      5900,
      true,
      'compact',
      0xFFF0A59C,
      'Пудровые румяна с естественным оттенком для нежного румянца.',
      83,
      [1, 7, 15, 16],
      photo: 'assets/products/13.jpg',
      inci:
          'Talc, Mica (Ci 77019), Silica, Boron Nitride, Hexyl Laurate, Dimethicone, Caprylic/Capric Triglyceride, Manganese Violet (Ci 77742), Diphenylsiloxy Phenyl Trimethicone, Magnesium Myristate, Methylpropanediol, Calcium Carbonate, Dipentaerythrityl Hexahydroxystearate/Hexastearate/Hexarosinate, Propanediol, Ultramarines (Ci 77007), Triethoxycaprylylsilane, Iron Oxide Yellow (Ci 77492), Iron Oxide Red (Ci 77491), Methicone, Red 30 (Ci 73360), Iron Oxide Black (Ci 77499), Kaolin, Yellow 5 Lake (Ci 19140), Water',
      source: 'https://incidecoder.com/products/romand-better-than-cheek',
    ),
    _P(
      'CeraVe',
      'Moisturizing Cream',
      'Тело и ванна',
      'Тело',
      8400,
      null,
      true,
      'cream',
      0xFFBFDCCB,
      'Увлажняющий крем с тремя церамидами и гиалуроновой кислотой для сухой кожи.',
      75,
      [1, 2, 5, 7, 8, 13],
      photo: 'assets/products/14.jpg',
      inci:
          'Aqua, Glycerin, Cetearyl Alcohol, Caprylic/Capric Triglyceride, Cetyl Alcohol, Ceteareth-20, Ceramide NP, Ceramide AP, Ceramide EOP, Phytosphingosine, Cholesterol, Hyaluronic Acid, Sodium Lauroyl Lactylate, Dimethicone, Petrolatum, Behentrimonium Methosulfate, Potassium Phosphate, Dipotassium Phosphate, Phenoxyethanol, Methylparaben, Propylparaben, Disodium EDTA, Carbomer, Xanthan Gum',
      source: 'https://incidecoder.com/products/cerave-moisturizing-cream-6',
    ),
    _P(
      'Nivea',
      'Soft Moisturizing Creme',
      'Тело и ванна',
      'Тело',
      3900,
      null,
      true,
      'cream',
      0xFFE8D5C4,
      'Лёгкий увлажняющий крем для лица, тела и рук.',
      72,
      [1, 2, 3, 5, 7, 8, 14, 19],
      photo: 'assets/products/15.jpg',
      inci:
          'Water, Myristyl Alcohol, Mineral Oil (Paraffinum Liquidum), Glycerin, Butylene Glycol, Alcohol Denatured, Stearic Acid, Petrolatum, Myristyl Myristate, Glyceryl Stearate, Hydrogenated Coco-Glycerides, Dimethicone, Simmondsia Chinensis (Jojoba) Seed Oil (Jojoba), Tocopheryl Acetate (Vitamin E), Polyglyceryl-2 Caprate, Phenoxyethanol, Lanolin Alcohol, Fragrance, Carbomer, Sodium Hydroxide, Cetyl Phosphate, Methylparaben, Ethylparaben, Propylparaben, Butylparaben, Isobutylparaben',
      source: 'https://incidecoder.com/products/nivea-soft',
    ),
    _P(
      'Mise-en-scène',
      'Perfect Serum Shampoo',
      'Волосы',
      '',
      5100,
      null,
      true,
      'bottle',
      0xFFF2D8A7,
      'Шампунь с маслами арганы и жожоба для гладких и блестящих волос.',
      68,
      [1, 2, 3, 6, 7, 14, 19],
      photo: 'assets/products/16.jpg',
      inci:
          'Water/Aqua/Eau, Sodium Laureth Sulfate, Glycerin, Cocamidopropyl Betaine, Laureth-6 Carboxylic Acid, Fragrance/Parfum, Sodium Chloride, PEG-60 Hydrogenated Castor Oil, Polyquaternium-10, Dimethiconol, Sodium Lauroyl Sarcosinate, Tea-Dodecylbenzenesulfonate, Sodium Benzoate, Citric Acid, Tetrasodium EDTA, Ethylhexylglycerin, Limonene, Disodium EDTA, Linalool, Argania Spinosa Kernel Oil, Simmondsia Chinensis (Jojoba) Seed Oil, Cocos Nucifera (Coconut) Oil, Tocopherol, Olea Europaea (Olive) Fruit Oil, Prunus Armeniaca (Apricot) Kernel Oil, Sclerocarya Birrea Seed Oil, Camellia Japonica Seed Oil, Coco-Caprylate/Caprate, Caprylyl Glycol, Alcohol Denat, PEG-150 Pentaerythrityl Tetrastearate, PPG-2 Hydroxyethyl Cocamide, Glycolipids',
      source:
          'https://incidecoder.com/products/mise-en-scene-perfect-serum-shampoo',
    ),
    _P(
      'Cosmetix',
      'Подарочный набор «Нежность»',
      'Подарки',
      '',
      14900,
      18900,
      true,
      'box',
      0xFFE9B7C4,
      'Набор уходовой косметики в подарочной упаковке.',
      85,
      [1, 2, 14, 16],
    ),
    _P(
      'Anua',
      'Heartleaf 77% Soothing Toner',
      'Уход за лицом',
      'Лицо',
      6300,
      null,
      false,
      'bottle',
      0xFFB9D9B0,
      'Успокаивающий тонер с 77% экстракта хауттюйнии для чувствительной кожи.',
      95,
      [1, 2],
      photo: 'assets/products/18.jpg',
      inci:
          'Houttuynia Cordata Extract (77%), Water, 1,2-Hexanediol, Glycerin, Betaine, Panthenol, Saccharum Officinarum (Sugar Cane) Extract, Portulaca Oleracea Extract, Butylene Glycol, Vitex Agnus Castus Extract, Chamomilla Recutita (Matricaria) Flower Extract, Arctium Lappa Root Extract, Phellinus Linteus Extract, Vitis Vinifera (Grape) Fruit Extract, Pyrus Malus (Apple) Fruit Extract, Centella Asiatica Extract, Isopentyldiol, Methylpropanediol, Acrylates/C10-30 Alkyl Acrylate Crosspolymer, Tromethamine, Disodium EDTA',
      source:
          'https://incidecoder.com/products/anua-heartleaf-77-soothing-toner-4',
    ),
    _P(
      'The Ordinary',
      'Glycolic Acid 7% Toning Solution',
      'Уход за лицом',
      'Лицо',
      5200,
      null,
      true,
      'bottle',
      0xFFE9E2C8,
      'Тонер с 7% гликолевой кислоты для мягкого отшелушивания и сияния кожи.',
      70,
      [1, 2],
      photo: 'assets/products/19.jpg',
      inci:
          'Aqua (Water), Glycolic Acid, Rosa Damascena Flower Water, Centaurea Cyanus Flower Water, Aloe Barbadensis Leaf Water, Propanediol, Glycerin, Triethanolamine, Aminomethyl Propanol, Panax Ginseng Root Extract, Tasmannia Lanceolata Fruit/Leaf Extract, Aspartic Acid, Alanine, Glycine, Serine, Valine, Isoleucine, Proline, Threonine, Histidine, Phenylalanine, Glutamic Acid, Arginine, Pca, Sodium PCA, Sodium Lactate, Fructose, Glucose, Sucrose, Urea, Hexyl Nicotinate, Dextrin, Citric Acid, Polysorbate 20, Gellan Gum, Trisodium Ethylenediamine Disuccinate, Sodium Chloride, Hexylene Glycol, Potassium Sorbate, Sodium Benzoate, 1,2-Hexanediol, Caprylyl Glycol',
      source:
          'https://incidecoder.com/products/the-ordinary-glycolic-acid-7-toning-solution-6',
    ),
    _P(
      'The Ordinary',
      'Retinol 0.5% in Squalane',
      'Уход за лицом',
      'Лицо',
      5900,
      null,
      true,
      'bottle',
      0xFFE8C9A0,
      'Безводная сыворотка с 0,5% чистого ретинола в сквалане для вечернего ухода.',
      65,
      [],
      photo: 'assets/products/20.jpg',
      inci:
          'Squalane, Caprylic/Capric Triglyceride, Simmondsia Chinensis (Jojoba) Seed Oil, Retinol 0.5%, Solanum Lycopersicum (Tomato) Fruit Extract, Rosmarinus Officinalis (Rosemary) Leaf Extract, Hydroxymethoxyphenyl Decanone, BHT',
      source:
          'https://incidecoder.com/products/the-ordinary-retinol-0-5-in-squalane',
    ),
    _P(
      'COSRX',
      'BHA Blackhead Power Liquid',
      'Уход за лицом',
      'Лицо',
      7400,
      null,
      true,
      'bottle',
      0xFFDDE3E6,
      'Лёгкий лосьон с бетаин салицилатом (BHA) для очищения пор и ухода за чёрными точками.',
      85,
      [12, 13],
      photo: 'assets/products/21.jpg',
      inci:
          'Salix Alba (Willow) Bark Water, Butylene Glycol, Betaine, Niacinamide, Betaine Salicylate, 1,2-Hexanediol, Sodium Hydroxide, Sodium Hyaluronate, Panthenol, Xanthan Gum, Ethyl Hexanediol',
      source:
          'https://incidecoder.com/products/cosrx-bha-blackhead-power-liquid-4',
    ),
    _P(
      'Klairs',
      'Freshly Juiced Vitamin Drop',
      'Уход за лицом',
      'Лицо',
      8600,
      null,
      true,
      'bottle',
      0xFFEAD9B0,
      'Сыворотка с витамином C (аскорбиновая кислота) и центеллой для сияния кожи.',
      80,
      [1, 2, 13],
      photo: 'assets/products/22.jpg',
      inci:
          'Aqua (Water), Propylene Glycol, Ascorbic Acid, Hydroxyethylcellulose, Citrus Junos Fruit Extract, Centella Asiatica Extract, Polysorbate 60, Illicium Verum (Anise) Fruit Extract, Chaenomeles Sinensis Fruit Extract, Paeonia Suffruticosa Root Extract, Brassica Oleracea Italica (Broccoli) Extract, Nelumbium Speciosum Flower Extract, Citrus Paradisi (Grapefruit) Fruit Extract, Scutellaria Baicalensis Root Extract, Butylene Glycol, Glycerin, Citrus Aurantium Dulcis (Orange) Oil, 1,2-Hexanediol, Sodium Acrylate/Sodium Acryloyldimethyl Taurate Copolymer, Isohexadecane, Disodium EDTA, Lavandula Angustifolia (Lavender) Oil, Camellia Sinensis Callus Culture Extract, Polysorbate 80, Disodium Phosphate, Sorbitan Oleate, Chrysanthellum Indicum Extract, Asarum Sieboldii Root Extract, Quercus Mongolica Leaf Extract, Persicaria Hydropiper Extract, Larix Europaea Wood Extract, Magnolia Obovata Bark Extract, Rheum Palmatum Root Extract, Corydalis Turtschaninovii Root Extract, Coptis Chinensis Root Extract, Sodium Phosphate, Lysine Hcl, Sodium Ascorbyl Phosphate, Acetyl Methionine, Theanine, Proline, Lecithin, Acetyl Glutamine, Bacillus/Folic Acid/Soybean Ferment Extract, Sodium Hyaluronate, SH-Oligopeptide-1, SH-Oligopeptide-2, SH-Polypeptide-1, SH-Polypeptide-11, SH-Polypeptide-9, Caprylyl Glycol, Limonene',
      source:
          'https://incidecoder.com/products/dear-klairs-freshly-juiced-vitamin-drop-5',
    ),
    _P(
      'Rom&nd',
      'Better Than Palette 00 Light & Glitter Garden',
      'Макияж',
      'Глаза',
      5200,
      null,
      true,
      'palette',
      0xFFD9C8DC,
      'Десять чистых глиттеров без матовых оттенков: прозрачный опал, шампань, розовое золото и ледяная сирень.',
      40,
      [1, 10, 16],
      photo: 'assets/products/23.jpg',
      inci:
          'Polybutylene Terephthalate, Bis-Diglyceryl Polyacyladipate-2, Acrylates Copolymer, Ethylene/Va Copolymer, Polyethylene Terephthalate, Octyldodecyl Stearoyl Stearate, Calcium Aluminum Borosilicate, Magnesium Stearate, Phenylpropyldimethylsiloxysilicate, Methylpropanediol, Hydrogenated Polydecene, Trimethylsiloxysilicate, Propanediol, Silica, Titanium Dioxide (Ci 77891), Mica (Ci 77019), Iron Oxides (Ci 77491), Ethylene/Propylene Copolymer, Carmine (Ci 75470), Tin Oxide (Ci 77861), Triethoxycaprylylsilane, Yellow 5 (Ci 19140), Water',
      source:
          'https://incidecoder.com/products/rom-nd-better-than-palette-light-and-glitter-garden',
    ),
    _P(
      'Rom&nd',
      'Better Than Palette 01 Pampas Garden',
      'Макияж',
      'Глаза',
      5200,
      null,
      true,
      'palette',
      0xFFE2A58C,
      'Персиковые, коралловые и золотисто-шампанские оттенки на тёплой слоновой кости: яркие тона поздней весны.',
      40,
      [1, 7, 10, 15, 16],
      photo: 'assets/products/24.jpg',
      inci:
          'Talc, Mica (Ci 77019), Polybutylene Terephthalate, Bis-Diglyceryl Polyacyladipate-2, Acrylates Copolymer, Ethylene/Va Copolymer, Calcium Aluminum Borosilicate, Polyglyceryl-2 Triisostearate, Calcium Titanium Borosilicate, Titanium Dioxide (Ci 77891), Calcium Sodium Borosilicate, Silica, Methylpropanediol, Magnesium Stearate, Water, Tin Oxide (Ci 77861), Sunset Yellow Fcf (Ci 15985), Red Iron Oxide (Ci 77491), Polyethylene Terephthalate, Propanediol, Carmine (Ci 75470), Dimethicone, Synthetic Fluorphlogopite, Phenyl Trimethicone, Methyl Methacrylate Crosspolymer, Diisostearyl Malate, Dipentaerythrityl Hexahydroxystearate/Hexastearate/Hexarosinate, Nylon-12, Magnesium Myristate, Synthetic Wax, Triethoxycaprylylsilane, Phenoxyethanol, Tartrazine (Ci 19140), Helindone Pink Cn (Ci 73360), Yellow Iron Oxide (Ci 77492), Octyldodecanol, Octyldodecyl Stearoyl Stearate, Boron Nitride, Caprylic/Capric Triglyceride, Dimethiconol Stearate, Methicone, Hydrogenated Lecithin, Black Iron Oxide (Ci 77499), Ultramarines (Ci 77007), Triethylhexanoin, Hydrogenated Castor Oil Isostearate, Polybutene, Lauroyl Lysine, Manganese Violet (Ci 77742), Macadamia Integrifolia Seed Oil',
      source:
          'https://incidecoder.com/products/romand-better-than-palette-pampas-garden',
      trending: true,
    ),
    _P(
      'Rom&nd',
      'Better Than Palette 02 Mahogany Garden',
      'Макияж',
      'Глаза',
      5200,
      null,
      true,
      'palette',
      0xFFB07A55,
      'Карамель, корица и жидкое золото, переходящие в шоколад: сияние золотого часа.',
      40,
      [1, 7, 10, 15, 16],
      photo: 'assets/products/25.jpg',
      inci:
          'Talc, Mica (Ci 77019), Polybutylene Terephthalate, Bis-Diglyceryl Polyacyladipate-2, Acrylates Copolymer, Ethylene/Va Copolymer, Calcium Aluminum Borosilicate, Polyglyceryl-2 Triisostearate, Calcium Titanium Borosilicate, Titanium Dioxide (Ci 77891), Calcium Sodium Borosilicate, Silica, Methylpropanediol, Magnesium Stearate, Water, Tin Oxide (Ci 77861), Sunset Yellow Fcf (Ci 15985), Red Iron Oxide (Ci 77491), Polyethylene Terephthalate, Propanediol, Carmine (Ci 75470), Dimethicone, Synthetic Fluorphlogopite, Phenyl Trimethicone, Methyl Methacrylate Crosspolymer, Diisostearyl Malate, Dipentaerythrityl Hexahydroxystearate/Hexastearate/Hexarosinate, Nylon-12, Magnesium Myristate, Synthetic Wax, Triethoxycaprylylsilane, Phenoxyethanol, Tartrazine (Ci 19140), Helindone Pink Cn (Ci 73360), Yellow Iron Oxide (Ci 77492), Octyldodecanol, Octyldodecyl Stearoyl Stearate, Boron Nitride, Caprylic/Capric Triglyceride, Dimethiconol Stearate, Methicone, Hydrogenated Lecithin, Black Iron Oxide (Ci 77499), Ultramarines (Ci 77007), Triethylhexanoin, Hydrogenated Castor Oil Isostearate, Polybutene, Lauroyl Lysine, Manganese Violet (Ci 77742), Macadamia Integrifolia Seed Oil',
      source:
          'https://incidecoder.com/products/romand-better-than-palette-pampas-garden',
    ),
    _P(
      'Rom&nd',
      'Better Than Palette 03 Rosebud Garden',
      'Макияж',
      'Глаза',
      5200,
      null,
      true,
      'palette',
      0xFFC18A8E,
      'Пыльная роза, мальва и мягкий розово-бежевый: прохладное спокойствие и романтичный финиш.',
      40,
      [1, 7, 10, 15, 16],
      photo: 'assets/products/26.jpg',
      inci:
          'Talc, Mica (Ci 77019), Polybutylene Terephthalate, Bis-Diglyceryl Polyacyladipate-2, Acrylates Copolymer, Ethylene/Va Copolymer, Calcium Aluminum Borosilicate, Polyglyceryl-2 Triisostearate, Calcium Titanium Borosilicate, Titanium Dioxide (Ci 77891), Calcium Sodium Borosilicate, Silica, Methylpropanediol, Magnesium Stearate, Water, Tin Oxide (Ci 77861), Sunset Yellow Fcf (Ci 15985), Red Iron Oxide (Ci 77491), Polyethylene Terephthalate, Propanediol, Carmine (Ci 75470), Dimethicone, Synthetic Fluorphlogopite, Phenyl Trimethicone, Methyl Methacrylate Crosspolymer, Diisostearyl Malate, Dipentaerythrityl Hexahydroxystearate/Hexastearate/Hexarosinate, Nylon-12, Magnesium Myristate, Synthetic Wax, Triethoxycaprylylsilane, Phenoxyethanol, Tartrazine (Ci 19140), Helindone Pink Cn (Ci 73360), Yellow Iron Oxide (Ci 77492), Octyldodecanol, Octyldodecyl Stearoyl Stearate, Boron Nitride, Caprylic/Capric Triglyceride, Dimethiconol Stearate, Methicone, Hydrogenated Lecithin, Black Iron Oxide (Ci 77499), Ultramarines (Ci 77007), Triethylhexanoin, Hydrogenated Castor Oil Isostearate, Polybutene, Lauroyl Lysine, Manganese Violet (Ci 77742), Macadamia Integrifolia Seed Oil',
      source:
          'https://incidecoder.com/products/romand-better-than-palette-pampas-garden',
    ),
    _P(
      'Rom&nd',
      'Better Than Palette 07 Berry Fuchsia Garden',
      'Макияж',
      'Глаза',
      5200,
      null,
      true,
      'palette',
      0xFFA3517B,
      'Фуксия, слива и ледяная лаванда на холодных розовых: самая смелая палетка для вечера.',
      40,
      [1, 7, 10, 15, 16],
      photo: 'assets/products/27.jpg',
      inci:
          'Talc, Mica (Ci 77019), Polybutylene Terephthalate, Bis-Diglyceryl Polyacyladipate-2, Acrylates Copolymer, Ethylene/Va Copolymer, Calcium Aluminum Borosilicate, Polyglyceryl-2 Triisostearate, Calcium Titanium Borosilicate, Titanium Dioxide (Ci 77891), Calcium Sodium Borosilicate, Silica, Methylpropanediol, Magnesium Stearate, Water, Tin Oxide (Ci 77861), Sunset Yellow Fcf (Ci 15985), Red Iron Oxide (Ci 77491), Polyethylene Terephthalate, Propanediol, Carmine (Ci 75470), Dimethicone, Synthetic Fluorphlogopite, Phenyl Trimethicone, Methyl Methacrylate Crosspolymer, Diisostearyl Malate, Dipentaerythrityl Hexahydroxystearate/Hexastearate/Hexarosinate, Nylon-12, Magnesium Myristate, Synthetic Wax, Triethoxycaprylylsilane, Phenoxyethanol, Tartrazine (Ci 19140), Helindone Pink Cn (Ci 73360), Yellow Iron Oxide (Ci 77492), Octyldodecanol, Octyldodecyl Stearoyl Stearate, Boron Nitride, Caprylic/Capric Triglyceride, Dimethiconol Stearate, Methicone, Hydrogenated Lecithin, Black Iron Oxide (Ci 77499), Ultramarines (Ci 77007), Triethylhexanoin, Hydrogenated Castor Oil Isostearate, Polybutene, Lauroyl Lysine, Manganese Violet (Ci 77742), Macadamia Integrifolia Seed Oil',
      source:
          'https://incidecoder.com/products/romand-better-than-palette-pampas-garden',
    ),
    _P(
      'Peripera',
      'Ink Mood Glowy Tint 03 Rose In Mind',
      'Макияж',
      'Губы',
      1500,
      null,
      true,
      'tube',
      0xFFF1A0A8,
      'Глянцевый тинт для губ нежно-розового оттенка с эффектом сочных увлажнённых губ.',
      45,
      [1, 2, 7, 14],
      photo: 'assets/products/28.jpg',
      inci:
          'Water, Diphenyl Dimethicone, Diisostearyl Malate, Bis-Diglyceryl Polyacyladipate-2, Hydrogenated Polyisobutene, Bis-Behenyl/Isostearyl/Phytosteryl Dimer Dilinoleyl Dimer Dilinoleate, Diglycerin, Cetyl PEG/PPG-10/1 Dimethicone, Dipropylene Glycol, Hydrogenated Poly (C6-14 Olefin), Polysorbate 60, Sorbitan Isostearate, Diisostearoyl Polyglyceryl-3 Dimer Dilinoleate, Pentylene Glycol, Hydroxyethyl Acrylate/Sodium Acryloyldimethyl Taurate Copolymer, Caprylic/Capric Triglyceride, Squalane, Ceteareth-20, Ethylene/Propylene Copolymer, Phenoxyethanol, Glycerin, Titanium Dioxide (Ci 77891), Polyglycerin-3, Yellow 6 (Ci 15985), Fragrance, Ethylhexylglycerin, Red 28 (Ci 45410), Red 33 (Ci 17200), Blue 1 (Ci 42090), Hamamelis Virginiana (Witch Hazel) Leaf Extract, Lilium Tigrinum Extract, Butylene Glycol',
      source:
          'https://incidecoder.com/products/peripera-ink-mood-glowy-tint-03-rose-in-mind',
    ),
    _P(
      'Rom&nd',
      'Juicy Lasting Tint 01 Pomelo Skin',
      'Макияж',
      'Губы',
      3600,
      null,
      true,
      'tube',
      0xFFE8A98F,
      'Стойкий глянцевый тинт персиково-нюдового оттенка: блеск, как глазурь на фруктах.',
      45,
      [1, 7, 13, 14, 19],
      photo: 'assets/products/29.jpg',
      inci:
          'Water, Octyldodecanol, Alcohol Denat, Polysorbate 60, Trimethylsiloxyphenyl Dimethicone, Ethylcellulose, Behenyl Alcohol, Pentylene Glycol, Phytosteryl Isostearyl Dimer Dilinoleate, Acrylates Copolymer, Sorbitan Stearate, Silica, Sodium Acrylate/Sodium Acryloyldimethyl Taurate Copolymer, Isohexadecane, Diisostearyl Malate, Phenoxyethanol, Titanium Dioxide (Ci 77891), Polyglyceryl-2 Triisostearate, Glyceryl Stearate, PEG-100 Stearate, Iron Oxides (Ci 77491), Polysorbate 80, Iron Oxides (Ci 77492), Iron Oxides (Ci 77499), Sorbitan Oleate, Fragrance, Trisodium Ethylenediamine Disuccinate, Flavor, Ethylhexylglycerin, Red 7 Lake (Ci 15850), Polyglyceryl-2 Diisostearate, Yellow 6 (Ci 15985), Red 33 (Ci 17200), Benzyl Alcohol, Linalool, Blue 1 (Ci 42090), Raspberry Seed Oil/Tocopheryl Succinate Aminopropanediol Esters, Prunus Domestica Seed Extract, Mangifera Indica (Mango) Seed Butter, Butylene Glycol, 1,2-Hexanediol, Dimethylsilanol Hyaluronate, Hydrolyzed Hyaluronic Acid, Hydrolyzed Sodium Hyaluronate, Sodium Hyaluronate, Hyaluronic Acid, Potassium Hyaluronate, Sodium Hyaluronate Crosspolymer, Hydroxypropyltrimonium Hyaluronate, Sodium Hyaluronate Dimethylsilanol, Sodium Acetylated Hyaluronate',
      source:
          'https://incidecoder.com/products/rom-nd-juicy-lasting-tint-new-01-pomelo-skin',
    ),
    _P(
      '3CE',
      'Mood Recipe Face Blush',
      'Макияж',
      'Лицо',
      4200,
      null,
      true,
      'compact',
      0xFFEDB19A,
      'Нежные румяна в компактной коробочке тёплого персикового оттенка для естественного румянца.',
      40,
      [7, 15, 16],
      photo: 'assets/products/30.jpg',
      inci:
          'Talc, Mica (Ci 77019), Titanium Dioxide (Ci 77891), Octyldodecyl Stearoyl Stearate, Phenyl Trimethicone, Silica, Nylon-12, Iron Oxides (Ci 77491), Magnesium Myristate, Magnesium Stearate, Dimethicone, Macadamia Ternifolia Seed Oil, Propanediol, Hdi/Trimethylol Hexyllactone Crosspolymer, Lauroyl Lysine, Methicone, Hydrogenated Lecithin, Triethoxycaprylylsilane, Iron Oxides (Ci 77499), Iron Oxides (Ci 77492), Yellow 5 Lake (Ci 19140), Ultramarines (Ci 77007), Red 30 (Ci 73360), Carmine (Ci 75470)',
      source: 'https://incidecoder.com/products/3ce-mood-recipe-face-blush',
    ),
    _P(
      'Torriden',
      'Dive-In Serum',
      'Уход за лицом',
      'Лицо',
      7900,
      null,
      true,
      'bottle',
      0xFFD9E6EE,
      'Лёгкая сыворотка с низкомолекулярной гиалуроновой кислотой для глубокого увлажнения.',
      85,
      [1, 2, 13],
      photo: 'assets/products/31.jpg',
      inci:
          'Water, Butylene Glycol, Glycerin, Dipropylene Glycol, 1,2-Hexanediol, Panthenol, Sodium Hyaluronate, Hydrolyzed Hyaluronic Acid, Sodium Acetylated Hyaluronate, Sodium Hyaluronate Crosspolymer, Hydrolyzed Sodium Hyaluronate, Allantoin, Trehalose, Betaine, Propanediol, Portulaca Oleracea Extract, Hamamelis Virginiana Extract, Madecassoside, Madecassic Acid, Ceramide NP, Beta-Glucan, Malachite Extract, Cholesterol, Pentylene Glycol, Glyceryl Acrylate/Acrylic Acid Copolymer, Pvm/Ma Copolymer, Polyglyceryl-10 Laurate, Xanthan Gum, Tromethamine, Carbomer, Ethylhexylglycerin, Scutellaria Baicalensis Root Extract, Paeonia Suffruticosa Root Extract',
      source: 'https://incidecoder.com/products/torriden-dive-in-serum',
      trending: true,
    ),
    _P(
      'Skin1004',
      'Madagascar Centella Ampoule',
      'Уход за лицом',
      'Лицо',
      7600,
      null,
      true,
      'bottle',
      0xFFE9D6A0,
      'Успокаивающая ампула с экстрактом центеллы азиатской для чувствительной и раздражённой кожи.',
      95,
      [1, 2],
      photo: 'assets/products/32.jpg',
      inci:
          'Water, Glycerin, Butylene Glycol, Centella Asiatica Extract, 1,2-Hexanediol, Cellulose Gum, Ethylhexylglycerin',
      source:
          'https://incidecoder.com/products/skin1004-madagascar-centella-ampoule',
    ),
    _P(
      'Beauty of Joseon',
      'Glow Serum: Propolis + Niacinamide',
      'Уход за лицом',
      'Лицо',
      7800,
      null,
      true,
      'bottle',
      0xFFE9C98A,
      'Сыворотка с прополисом и ниацинамидом для сияния кожи и баланса себума.',
      90,
      [1, 2, 3, 12, 13],
      photo: 'assets/products/33.jpg',
      inci:
          'Propolis Extract, Dipropylene Glycol, Glycerin, Butylene Glycol, Water, Niacinamide, 1,2-Hexanediol, Melia Azadirachta Flower Extract, Melia Azadirachta Leaf Extract, Sodium Hyaluronate, Curcuma Longa (Turmeric) Root Extract, Ocimum Sanctum Leaf Extract, Theobroma Cacao (Cocoa) Seed Extract, Melaleuca Alternifolia (Tea Tree) Extract, Centella Asiatica Extract, Corallina Officinalis Extract, Lotus Corniculatus Seed Extract, Calophyllum Inophyllum Seed Oil, Betaine Salicylate, Sodium Polyacryloyldimethyl Taurate, Tromethamine, Polyglyceryl-10 Laurate, Caprylyl Glycol, Ethylhexylglycerin, Dextrin, Pentylene Glycol, Octanediol, Tocopherol, Xanthan Gum, Carbomer',
      source:
          'https://incidecoder.com/products/beauty-of-joseon-glow-serum-propolis-niacinamide',
      featured: true,
    ),
    _P(
      'Isntree',
      'Hyaluronic Acid Toner',
      'Уход за лицом',
      'Лицо',
      6400,
      null,
      true,
      'bottle',
      0xFFE3E8EE,
      'Лёгкий тонер с гиалуроновой кислотой для мгновенного увлажнения.',
      90,
      [1, 2, 13],
      photo: 'assets/products/34.jpg',
      inci:
          'Water, Propanediol, 1,2-Hexanediol, Sodium Hyaluronate, Trehalose, Sodium PCA, Glycerin, Hyaluronic Acid, Aloe Barbadensis Leaf Extract, Althaea Rosea Root Extract, Betula Alba Juice, Portulaca Oleracea Extract, Hydrolyzed Sodium Hyaluronate, Beta-Glucan, Panthenol, Pentylene Glycol, Caprylyl Glycol, Butylene Glycol',
      source: 'https://incidecoder.com/products/isntree-hyaluronic-acid-toner',
    ),
    _P(
      'Round Lab',
      '1025 Dokdo Toner',
      'Уход за лицом',
      'Лицо',
      5900,
      null,
      true,
      'bottle',
      0xFFD7E4EC,
      'Мягкий тонер с глубинной морской водой для ежедневного ухода без раздражения.',
      92,
      [2],
      photo: 'assets/products/35.jpg',
      inci:
          'Purified Water, Butylene Glycol, Glycerin, Pentylene Glycol, Propanediol, Chondrus Crispus Extract, Saccharum Officinarum (Sugarcane) Extract, Sea Water, 1,2-Hexanediol, Protease, Betaine, Panthenol, Ethylhexylglycerin, Allantoin, Xanthan Gum, Disodium EDTA',
      source: 'https://incidecoder.com/products/round-lab-1025-dokdo-toner-2',
    ),
    _P(
      'Laneige',
      'Lip Sleeping Mask',
      'Уход за лицом',
      'Губы',
      7200,
      null,
      true,
      'cream',
      0xFFEFA3B5,
      'Ночная маска для губ: увлажняет, смягчает и восстанавливает кожу губ за ночь.',
      60,
      [1, 2, 7, 13, 14, 16, 19],
      photo: 'assets/products/36.jpg',
      inci:
          'Diisostearyl Malate, Hydrogenated Polyisobutene, Phytosteryl/Isostearyl/Cetyl/Stearyl/Behenyl Dimer Dilinoleate, Hydrogenated Poly(C6-14 Olefin), Polybutene, Microcrystalline Wax\\Cera Microcristallina\\Cire Microcristalline, Butyrospermum Parkii (Shea) Butter, Synthetic Wax, Euphorbia Cerifera (Candelilla) Wax/Candelilla Cera/Cire De Candelilla, Sucrose Tetrastearate Triacetate, Butylene/Ethylene/Styrene Copolymer, Ethylene/Propylene/Styrene Copolymer, Mica (Ci 77019), Astrocaryum Murumuru Seed Butter, Titanium Dioxide (Ci 77891), Dimethicone, Fragrance/Parfum, Polyglyceryl-2 Diisostearate, Dehydroacetic Acid, Methicone, Copernicia Cerifera (Carnauba) Wax / Cera Carnauba / Cire De Carnauba, Polyglyceryl-2 Triisostearate, Yellow 6 Lake (Ci 15985), Red 6 (Ci 15850), Polyhydroxystearic Acid, Water / Aqua Eau, Potassium Alginate, Propanediol, Glycerin, Alcohol, Lycium Chinense Fruit Extract, Vaccinium Macrocarpon (Cranberry) Fruit Extract, Fragaria Chiloensis (Strawberry) Fruit Extract, Rubus Idaeus (Raspberry) Fruit Extract, Sapindus Mukorossi Fruit Extract, Vaccinium Angustifolium (Blueberry) Fruit Extract, Rubus Chamaemorus Seed Extract, Coffea Arabica (Coffee) Seed Extract, Chenopodium Quinoa Seed Extract, Magnesium Sulfate, Calcium Chloride, Sodium Hyaluronate, Beta-Glucan, Manganese Sulfate, Zinc Sulfate, Ascorbyl Glucoside',
      source: 'https://incidecoder.com/products/laneige-lip-sleeping-mask',
    ),
    _P(
      'COSRX',
      'Low pH Good Morning Gel Cleanser',
      'Уход за лицом',
      'Лицо',
      5200,
      null,
      true,
      'tube',
      0xFFDDEBF0,
      'Мягкий гель для умывания с pH около 5,5 для ежедневного очищения кожи.',
      85,
      [1],
      photo: 'assets/products/37.jpg',
      inci:
          'Water, Cocamidopropyl Betaine, Sodium Lauroyl Methyl Isethionate, Sodium Chloride, Polysorbate 20, Styrax Japonicus Branch/Fruit/Leaf Extract, Butylene Glycol, Saccharomyces Ferment, Cryptomeria Japonica Leaf Extract, Nelumbo Nucifera Leaf Extract, Pinus Palustris Leaf Extract, Ulmus Davidiana Root Extract, Oenothera Biennis (Evening Primrose) Flower Extract, Pueraria Lobata Root Extract, Melaleuca Alternifolia (Tea Tree) Leaf Oil, Allantoin, Caprylyl Glycol, Ethylhexylglycerin, Betaine Salicylate, Citric Acid, Ethyl Hexanediol, 1,2-Hexanediol, Trisodium Ethylenediamine Disuccinate, Sodium Benzoate, Disodium EDTA',
      source:
          'https://incidecoder.com/products/cosrx-low-ph-good-morning-gel-cleanser',
    ),
    _P(
      'Dr.Jart+',
      'Ceramidin Cream',
      'Уход за лицом',
      'Лицо',
      11500,
      null,
      true,
      'cream',
      0xFFF2E36C,
      'Питательный крем с керамидами восстанавливает барьер и смягчает сухую кожу.',
      65,
      [1, 2, 7, 13],
      photo: 'assets/products/38.jpg',
      inci:
          'Water, Glycerin, Dipropylene Glycol, Cetearyl Alcohol, Caprylic/Capric Triglyceride, Hydrogenated Poly(C6-14 Olefin), Hydrogenated Polydecene, Methyl Trimethicone, 1, 2-Hexanediol, Bifida Ferment Lysate, Phenyl Trimethicone, Vegetable Oil, Butyrospermum Parkii (Shea) Butter, Glyceryl Stearate SE, Ceramide NP, Stearic Acid, Algae Extract, Eclipta Prostrata Leaf Extract, Cetearyl Glucoside, Hydrogenated Lecithin, Microcrystalline Cellulose, Butylene Glycol, C12-16 Alcohols, Ammonium Acryloyldimethyltaurate/VP Copolymer, Malt Extract, Beta Vulgaris (Beet) Root Extract, Melia Azadirachta Flower Extract, Melia Azadirachta Leaf Extract, Theobroma Cacoa (Cocoa) Seed Extract, Curcuma Longa (Turmeric) Root Extract, Ocimum Sanctum Leaf Extract, Amaranthus Caudatus Seed Extract, Ulmus Davidiana Root Extract, Avena Sativa (Oat) Kernel Extract, Cynara Scolymus (Artichoke) Leaf Extract, Pteris Multifida Extract, Artemisia Vulgaris Extract, Corallina Officinalis Extract, Pyracantha Fortuneana Fruit Extract, Glyceryl Polymethacrylate, Cholesterol, Citrus Aurantium Bergamia (Bergamot) Fruit Oil, Hydrolyzed Corn Starch, Sodium Hyaluronate, Pelargonium Graveolens Flower Oil, Fructooligosaccharides, Beta-Glucan, Dextrin, Disodium EDTA, Panthenol, Polyquaternium-51, Raffinose, Hydrolyzed Hyaluronic Acid, Folic Acid, Salvia Officinalis (Sage) Oil, Pogostemon Cablin Oil, Tromethamine, Ceramide AP, Ceramide AS, Ceramide NS, Palmitoyl Pentapeptide-4, Ceramide EOP',
      source: 'https://incidecoder.com/products/dr-jart-ceramidin-cream-3',
    ),
  ];
}

class _P {
  const _P(
    this.brand,
    this.name,
    this.category,
    this.zone,
    this.price,
    this.oldPrice,
    this.inStock,
    this.art,
    this.color,
    this.description,
    this.natural,
    this.ingredients, {
    this.photo,
    this.inci = '',
    this.source = '',
    this.featured = false,
    this.trending = false,
  });

  final String brand;
  final String name;
  final String category;
  final String zone;
  final int price;
  final int? oldPrice;
  final bool inStock;
  final String art;
  final int color;
  final String description;
  final int natural;
  final List<int> ingredients;

  /// Photo from `assets/products/` (see CREDITS.txt there).
  final String? photo;

  /// Full ingredient list (INCI) as published, and the page it was taken from.
  final String inci;
  final String source;

  /// What the `art` column stores: the drawing kind, plus `|photo` when the
  /// product has a photo (see `ProductArt`).
  String get artValue => photo == null ? art : '$art|$photo';
  final bool featured;
  final bool trending;
}
