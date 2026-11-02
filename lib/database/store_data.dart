import 'dart:math' as math;

/// One real shop (name, chain, position, address, opening hours).
class StoreSeed {
  const StoreSeed(
    this.name,
    this.chain,
    this.lat,
    this.lng,
    this.address,
    this.hours,
    this.source,
  );

  final String name;
  final String chain;
  final double lat;
  final double lng;
  final String address;

  /// Free text like "Ежедневно 10:00–22:00"; empty when unknown.
  final String hours;

  /// Where the position/address comes from (shown on the map screen).
  final String source;
}

/// Real cosmetics shops of Astana. Positions and hours come from OpenStreetMap
/// (© OpenStreetMap contributors, ODbL); the "Подружка" addresses come from the
/// chain's public job ads and were put on the map with the OSM geocoder, so
/// they are marked as unverified. Prices and stock are DEMO values (see
/// [StoreData.offerPrice]): the shops publish no open price/stock feed.
class StoreData {
  StoreData._();

  static const osm = 'OpenStreetMap';
  static const ads = 'Адрес из открытых объявлений сети (не проверен)';

  /// The city centre (Baiterek): where distances are counted from until the
  /// user allows the location.
  static const centerLat = 51.1282;
  static const centerLng = 71.4304;

  /// The first three rows replace the old demo shops (ids 1..3 are kept, so
  /// carts and orders stay valid).
  static const stores = [
    StoreSeed(
      'Диона',
      'Диона',
      51.16801,
      71.4079,
      'пр. Сарыарка, 15',
      'Ежедневно 10:00–22:00',
      osm,
    ),
    StoreSeed(
      'Золотое Яблоко',
      'Золотое Яблоко',
      51.08961,
      71.40607,
      'пр. Кабанбай батыра, 62',
      'Ежедневно 10:00–22:00',
      osm,
    ),
    StoreSeed(
      'MonAmie',
      'MonAmie',
      51.16586,
      71.435,
      'ул. Кенесары, 42',
      'Ежедневно 10:00–21:00',
      osm,
    ),
    StoreSeed(
      'Диона',
      'Диона',
      51.18907,
      71.41327,
      'ул. Ильяса Есенберлина, 24',
      '',
      osm,
    ),
    StoreSeed(
      'Диона',
      'Диона',
      51.15374,
      71.44946,
      'ул. Жумабека Ташенова, 23',
      '',
      osm,
    ),
    StoreSeed(
      'Диона',
      'Диона',
      51.16224,
      71.42778,
      'пр. Республики, 15',
      'Ежедневно 09:00–22:00',
      osm,
    ),
    StoreSeed('Диона', 'Диона', 51.15544, 71.47306, 'ул. Жирентаева', '', osm),
    StoreSeed(
      'Диона',
      'Диона',
      51.16496,
      71.45509,
      'ул. Кенесары, 64',
      'Ежедневно 10:00–22:00',
      osm,
    ),
    StoreSeed(
      'MonAmie',
      'MonAmie',
      51.1596,
      71.42949,
      'пр. Республики, 8',
      'Ежедневно 10:00–21:00',
      osm,
    ),
    StoreSeed(
      'The Face Shop',
      'The Face Shop',
      51.12819,
      71.4124,
      'пр. Кабанбай батыра, 21',
      'Ежедневно 10:00–22:00',
      osm,
    ),
    StoreSeed(
      'Подружка',
      'Подружка',
      51.1812,
      71.379,
      'пр. Нургисы Тлендиева, 12а (ТЦ Коктал)',
      '',
      ads,
    ),
    StoreSeed(
      'Подружка',
      'Подружка',
      51.1306,
      71.3924,
      'ул. Сыганак, 17Б',
      '',
      ads,
    ),
    StoreSeed(
      'Подружка',
      'Подружка',
      51.0957,
      71.40616,
      'пр. Кабанбай батыра, 58Б',
      '',
      ads,
    ),
  ];

  /// Distance in metres between two points (haversine).
  static int meters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.pow(math.sin(dLng / 2), 2);
    return (2 * r * math.asin(math.sqrt(a))).round();
  }

  /// Distance of every seeded shop from the city centre (the legacy
  /// `stores.distance_m` column).
  static int fromCenter(StoreSeed s) =>
      meters(centerLat, centerLng, s.lat, s.lng);

  // ---------------- demo offers ----------------

  /// Stable 0..99 value from a product and a shop (no randomness, so every
  /// install and the migration give the same demo data).
  static int _h(int productId, int storeIndex) =>
      (productId * 37 + storeIndex * 53 + productId * storeIndex * 7) % 100;

  /// DEMO price of a product in a shop. The first three shops keep the
  /// original pattern (nearest priciest), the others differ by chain.
  static int offerPrice(int basePrice, int productId, int storeIndex) {
    if (storeIndex < 3) return basePrice + const [1200, 0, 600][storeIndex];
    final chain = stores[storeIndex].chain;
    final delta = switch (chain) {
      'Диона' => -300,
      'Подружка' => 200,
      'The Face Shop' => 900,
      _ => 300,
    };
    final wobble = (_h(productId, storeIndex) % 5) * 100;
    return basePrice + delta + wobble;
  }

  /// DEMO units in stock (0 = none). A product that is out of stock
  /// everywhere stays out of stock in every shop.
  static int offerQty(
    bool productInStock,
    int productId,
    int storeIndex, {
    bool perfume = false,
  }) {
    if (!productInStock) return 0;
    final h = _h(productId, storeIndex);
    // the original demo rule of the first three shops
    if (storeIndex < 3) return perfume && storeIndex == 1 ? 0 : 2 + h % 8;
    if (h < 22) return 0;
    return 1 + h % 9;
  }
}
