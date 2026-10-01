import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/safety_repository.dart';
import 'package:cosmetix/services/ingredient_analyzer.dart';

/// A small offline "AI" assistant: it understands a few kinds of questions
/// (price comparison, composition, discounts, recommendations) and answers
/// from the products stored in SQLite.
class AssistantService {
  AssistantService(this._products, this._safety);

  final ProductRepository _products;
  final SafetyRepository _safety;

  static const _categoryWords = {
    'Губы': ['помад', 'тинт', 'губ', 'блеск', 'lip', 'tint', 'gloss', 'ерін'],
    'Глаза': [
      'палет',
      'тен',
      'глаз',
      'подвод',
      'тушь',
      'eye',
      'palette',
      'shadow',
      'көз',
      'палитр',
    ],
    'Лицо': [
      'кушон',
      'тональ',
      'румян',
      'лицо',
      'лица',
      'сыворот',
      'тонер',
      'face',
      'serum',
      'toner',
      'бет',
      'сарысу',
    ],
    'Уход за лицом': [
      'крем',
      'spf',
      'уход',
      'сыворот',
      'тонер',
      'cream',
      'skincare',
      'skin care',
      'күтім',
    ],
    'Парфюмерия': ['парфюм', 'аромат', 'духи', 'perfume', 'fragrance', 'иіс'],
    'Тело и ванна': ['тело', 'тела', 'ванн', 'body', 'bath', 'дене'],
    'Волосы': ['волос', 'шампун', 'hair', 'shampoo', 'шаш'],
    'Подарки': ['подар', 'набор', 'gift', 'set', 'сыйлық'],
  };

  Future<String> reply(String text, int userId) async {
    final q = text.toLowerCase().trim();
    final all = await _products.getAll(userId);
    final mentioned = _mentioned(q, all);

    bool has(List<String> words) => words.any(q.contains);

    if (has(['привет', 'здравств', 'добрый', 'hello', 'hi ', 'hey', 'сәлем'])) {
      return tr(
        'Здравствуйте! Спросите меня о ценах, составе, скидках или попросите подобрать косметику.',
      );
    }

    if (has([
          'состав',
          'безопас',
          'аллерг',
          'ингредиент',
          'composition',
          'ingredient',
          'safe',
          'allerg',
          'құрам',
          'қауіпсіз',
          'аллерг',
        ]) &&
        mentioned.isNotEmpty) {
      final p = mentioned.first;
      final blacklist = await _safety.blacklist(userId);
      final analysis = IngredientAnalyzer.analyze(
        await _safety.ingredientsOf(p.id),
        blacklist,
      );
      final buffer = StringBuffer(
        trf('«{v0}»: оценка состава {v1}/10 ({v2}). {v3}', {
          'v0': tr(p.name),
          'v1': analysis.score.toStringAsFixed(1),
          'v2': analysis.grade,
          'v3': analysis.summary,
        }),
      );
      if (analysis.blacklistHits.isNotEmpty) {
        buffer.write(
          trf(
            ' Внимание: в составе есть компоненты из вашего чёрного списка — {v0}.',
            {'v0': analysis.blacklistHits.map(tr).join(', ')},
          ),
        );
      }
      return buffer.toString();
    }

    if (has([
      'скидк',
      'акци',
      'распродаж',
      'дешев',
      'discount',
      'sale',
      'offer',
      'cheap',
      'жеңілдік',
      'арзан',
    ])) {
      final sale = all.where((p) => p.hasDiscount && p.inStock).toList()
        ..sort((a, b) => b.discountPercent.compareTo(a.discountPercent));
      if (sale.isEmpty) {
        return tr('Сейчас скидок нет, но я сообщу, когда появятся.');
      }
      if (mentioned.length < 2) {
        return trf('Сейчас со скидкой: {v0}.', {
          'v0': sale.take(3).map(_line).join('; '),
        });
      }
    }

    if (has([
          'цен',
          'стоит',
          'сколько',
          'сравн',
          'дешевле',
          'выгодн',
          'price',
          'cost',
          'how much',
          'compare',
          'cheaper',
          'баға',
          'қанша',
          'салыстыр',
        ]) &&
        mentioned.isNotEmpty) {
      if (mentioned.length >= 2) {
        final a = mentioned[0], b = mentioned[1];
        final cheaper = a.price <= b.price ? a : b;
        return trf(
          '{v0} стоит {v1}, а {v2} — {v3}. Если бюджет важнее, то «{v4}» выигрывает по цене.',
          {
            'v0': tr(a.name),
            'v1': Formatters.price(a.price),
            'v2': tr(b.name),
            'v3': Formatters.price(b.price),
            'v4': tr(cheaper.name),
          },
        );
      }
      final p = mentioned.first;
      final prices = await _products.getStorePrices(p.id);
      final best = prices.isEmpty ? null : prices.first;
      return best == null
          ? trf('«{v0}» стоит {v1}.', {
              'v0': tr(p.name),
              'v1': Formatters.price(p.price),
            })
          : trf('«{v0}» от {v1} в магазине {v2} ({v3}).', {
              'v0': tr(p.name),
              'v1': Formatters.price(best.price),
              'v2': tr(best.storeName),
              'v3': best.distanceLabel.replaceAll(' от вас', ''),
            });
    }

    final category = _categoryFor(q);
    if (has([
          'посоветуй',
          'подбер',
          'порекомен',
          'хочу',
          'ищу',
          'нужен',
          'нужна',
          'лучш',
          'recommend',
          'suggest',
          'looking for',
          'need',
          'best',
          'want',
          'ұсын',
          'іздеп',
          'керек',
        ]) ||
        category != null) {
      final pool = all.where((p) => p.inStock).where((p) {
        if (category == null) return true;
        return p.zone == category || p.category == category;
      }).toList()..sort((a, b) => a.price.compareTo(b.price));
      if (pool.isEmpty) {
        return tr('К сожалению, подходящих товаров не нашлось.');
      }
      return trf('Рекомендую: {v0}.', {
        'v0': pool.take(3).map(_line).join('; '),
      });
    }

    if (mentioned.isNotEmpty) {
      final p = mentioned.first;
      return trf(
        '«{v0}» ({v1}) — {v2}. {v3} Спросите про состав или сравнение цен.',
        {
          'v0': tr(p.name),
          'v1': p.brand,
          'v2': Formatters.price(p.price),
          'v3': p.description,
        },
      );
    }

    return tr(
      'Я могу сравнить цены, проверить состав, показать скидки или подобрать косметику. Например: «Посоветуй тинт для губ» или «Какой состав у палетки Flower Knows?»',
    );
  }

  String _line(Product p) =>
      '${p.name} — ${Formatters.price(p.price)}${p.hasDiscount ? ' (−${p.discountPercent}%)' : ''}';

  List<Product> _mentioned(String q, List<Product> all) {
    final scored = <(Product, int)>[];
    for (final p in all) {
      final words = '${p.brand} ${p.name} ${tr(p.name)}'
          .toLowerCase()
          .split(RegExp(r'[^a-zа-яё0-9&+]+'))
          .where((w) => w.length >= 4)
          .toSet();
      final nospace = q.replaceAll(' ', '');
      var score = words.where(q.contains).length;
      if (nospace.contains(p.brand.toLowerCase().replaceAll(' ', ''))) score++;
      if (score > 0) scored.add((p, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    // one product per brand, so "FlowerKnows или Peripera" compares two brands
    final seen = <String>{};
    final result = <Product>[];
    for (final s in scored) {
      if (seen.add(s.$1.brand)) result.add(s.$1);
    }
    return result;
  }

  String? _categoryFor(String q) {
    for (final e in _categoryWords.entries) {
      if (e.value.any(q.contains)) return e.key;
    }
    return null;
  }
}
