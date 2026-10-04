import 'package:sqflite/sqflite.dart';

import 'package:cosmetix/database/seed_traits.dart';

import 'package:cosmetix/core/utils/password_hasher.dart';

/// Demo content that makes the app look alive right after the first launch.
class SeedData {
  SeedData._();

  static const demoEmail = 'ainara.rust@gmail.com';
  static const demoPassword = 'Cosmetix123';

  static const greeting =
      'Здравствуйте! Я ИИ-помощник Cosmetix. Какой вопрос по косметике или '
      'уходу за собой я могу помочь решить сегодня?';

  static Future<void> insertAll(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();

    for (final s in _stores) {
      batch.insert('stores', {
        'name': s.$1,
        'distance_m': s.$2,
        'address': s.$3,
        'rating': s.$4,
      });
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
      batch.insert('products', {
        'id': id,
        'brand': p.brand,
        'name': p.name,
        'category': p.category,
        'zone': p.zone,
        'price': p.price,
        'old_price': p.oldPrice,
        'in_stock': p.inStock ? 1 : 0,
        'art': p.art,
        'color': p.color,
        'description': p.description,
        'natural_percent': p.natural,
        'featured': p.featured ? 1 : 0,
        'trending': p.trending ? 1 : 0,
        // newer products have a later date (used by "По новизне")
        'created_at': now - i * 86400000,
      });
      // The same product in 3 stores. Nearest store is the priciest, the middle
      // one is cheapest, so "cheap first" and "closest" give different order.
      final extras = [1200, 0, 600];
      for (var s = 0; s < 3; s++) {
        batch.insert('product_prices', {
          'product_id': id,
          'store_id': s + 1,
          'price': p.price + extras[s],
          'in_stock': p.inStock && !(p.art == 'perfume' && s == 1) ? 1 : 0,
        });
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

  static Future<void> _insertReviews(Database db, int now) async {
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

  // (name, distance m, address, rating)
  static const _stores = [
    ('Korean Beauty', 200, 'ул. Абая 45', 4.9),
    ('Cosmetix Store', 500, 'пр. Достык 12', 4.7),
    ('Золотое Яблоко', 1200, 'ТРЦ Dostyk Plaza', 4.8),
  ];

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
      'Flower Knows',
      'Палетка Flower Knows Strawberry',
      'Макияж',
      'Глаза',
      2500,
      5000,
      true,
      'palette',
      0xFFF4B6C2,
      'Палетка из 9 нежных оттенков с мерцающими и матовыми текстурами.',
      94,
      [1, 2, 3, 4, 5],
      featured: true,
      trending: true,
    ),
    _P(
      'Peripera',
      'Палетка Peripera Ink Cozy',
      'Макияж',
      'Глаза',
      4800,
      null,
      true,
      'palette',
      0xFFF6C9D3,
      'Уютная палетка в тёплых розово-коричневых тонах.',
      86,
      [15, 16, 7, 3, 5],
      trending: true,
    ),
    _P(
      'Flower Knows',
      'Strawberry Lip Tint',
      'Макияж',
      'Губы',
      3500,
      null,
      true,
      'tube',
      0xFFE06A7C,
      'Стойкий тинт для губ с эффектом сочных губ.',
      90,
      [18, 3, 14],
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
      'Универсальная палетка нюдовых оттенков на каждый день.',
      82,
      [15, 16, 7, 8],
    ),
    _P(
      'Rom&nd',
      'Сыворотка для лица',
      'Уход за лицом',
      'Лицо',
      6900,
      null,
      true,
      'bottle',
      0xFFBFD8D2,
      'Лёгкая сыворотка с ниацинамидом и гиалуроновой кислотой.',
      96,
      [1, 2, 12, 13],
      featured: true,
    ),
    _P(
      'Peripera',
      'Парфюм Peripera Mood',
      'Парфюмерия',
      '',
      9800,
      null,
      true,
      'perfume',
      0xFFD9B8D6,
      'Нежный цветочно-мускусный аромат на весь день.',
      70,
      [19, 14, 10, 1],
      featured: true,
    ),
    _P(
      'Flower Knows',
      'Тинт для губ Flower Knows',
      'Макияж',
      'Губы',
      3200,
      null,
      true,
      'tube',
      0xFFD9707F,
      'Тинт с бархатным финишем и насыщенным цветом.',
      91,
      [18, 3, 14],
      featured: true,
    ),
    _P(
      'Peripera',
      'Тинт Peripera Ink',
      'Макияж',
      'Губы',
      1500,
      4000,
      true,
      'tube',
      0xFFE58895,
      'Культовый тинт для губ, держится до 8 часов.',
      84,
      [18, 14, 7, 3],
    ),
    _P(
      'Rom&nd',
      'Блеск Rom&nd Glasting',
      'Макияж',
      'Губы',
      3200,
      5500,
      true,
      'tube',
      0xFFEFA4B0,
      'Глянцевый блеск с эффектом стекла.',
      85,
      [18, 14, 7],
    ),
    _P(
      'Missha',
      'Кушон Missha Magic',
      'Макияж',
      'Лицо',
      4800,
      6000,
      true,
      'compact',
      0xFFF1C9B5,
      'Лёгкий кушон с сияющим финишем и SPF.',
      80,
      [1, 2, 7, 17, 3],
    ),
    _P(
      'Beauty of Joseon',
      'Крем SPF 50 Relief Sun',
      'Уход за лицом',
      'Лицо',
      7200,
      null,
      true,
      'cream',
      0xFFF3E3A9,
      'Солнцезащитный крем на основе рисовых экстрактов.',
      88,
      [1, 17, 2, 3, 13],
    ),
    _P(
      'The Ordinary',
      'Сыворотка Niacinamide 10%',
      'Уход за лицом',
      'Лицо',
      5600,
      null,
      true,
      'bottle',
      0xFFC9D6EA,
      'Сыворотка против расширенных пор и несовершенств.',
      92,
      [1, 12, 13, 2],
    ),
    _P(
      'Rom&nd',
      'Румяна Better Than Cheek',
      'Макияж',
      'Лицо',
      4900,
      5900,
      true,
      'compact',
      0xFFF0A59C,
      'Пудровые румяна с естественным сиянием.',
      83,
      [15, 16, 7, 3],
    ),
    _P(
      'Dr.Jart+',
      'Увлажняющий крем для тела',
      'Тело и ванна',
      'Тело',
      8400,
      null,
      true,
      'cream',
      0xFFBFDCCB,
      'Питательный крем для тела с керамидами.',
      75,
      [1, 2, 8, 14, 5],
    ),
    _P(
      'Cosmetics Mockup',
      'Cosmetics Mockup Cream',
      'Тело и ванна',
      'Тело',
      3900,
      null,
      true,
      'cream',
      0xFFE8D5C4,
      'Базовый увлажняющий крем на каждый день.',
      72,
      [1, 2, 8, 6, 14],
    ),
    _P(
      'Mise-en-scène',
      'Шампунь Perfect Serum',
      'Волосы',
      '',
      5100,
      null,
      true,
      'bottle',
      0xFFF2D8A7,
      'Восстанавливающий шампунь для повреждённых волос.',
      68,
      [1, 6, 7, 14, 2],
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
      'Тонер Heartleaf 77%',
      'Уход за лицом',
      'Лицо',
      6300,
      null,
      false,
      'bottle',
      0xFFB9D9B0,
      'Успокаивающий тонер с экстрактом хауттюйнии.',
      95,
      [1, 13, 2, 12],
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
  final bool featured;
  final bool trending;
}
