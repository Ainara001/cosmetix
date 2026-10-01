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
    'Губы': ['помад', 'тинт', 'губ', 'блеск'],
    'Глаза': ['палет', 'тен', 'глаз', 'подвод', 'тушь'],
    'Лицо': ['кушон', 'тональ', 'румян', 'лицо', 'лица', 'сыворот', 'тонер'],
    'Уход за лицом': ['крем', 'spf', 'уход', 'сыворот', 'тонер'],
    'Парфюмерия': ['парфюм', 'аромат', 'духи'],
    'Тело и ванна': ['тело', 'тела', 'ванн'],
    'Волосы': ['волос', 'шампун'],
    'Подарки': ['подар', 'набор'],
  };

  Future<String> reply(String text, int userId) async {
    final q = text.toLowerCase().trim();
    final all = await _products.getAll(userId);
    final mentioned = _mentioned(q, all);

    bool has(List<String> words) => words.any(q.contains);

    if (has(['привет', 'здравств', 'добрый'])) {
      return 'Здравствуйте! Спросите меня о ценах, составе, скидках или '
          'попросите подобрать косметику.';
    }

    if (has(['состав', 'безопас', 'аллерг', 'ингредиент']) &&
        mentioned.isNotEmpty) {
      final p = mentioned.first;
      final blacklist = await _safety.blacklist(userId);
      final analysis = IngredientAnalyzer.analyze(
        await _safety.ingredientsOf(p.id),
        blacklist,
      );
      final buffer = StringBuffer(
        '«${p.name}»: оценка состава ${analysis.score.toStringAsFixed(1)}/10 '
        '(${analysis.grade}). ${analysis.summary}',
      );
      if (analysis.blacklistHits.isNotEmpty) {
        buffer.write(
          ' Внимание: в составе есть компоненты из вашего '
          'чёрного списка — ${analysis.blacklistHits.join(', ')}.',
        );
      }
      return buffer.toString();
    }

    if (has(['скидк', 'акци', 'распродаж', 'дешев'])) {
      final sale = all.where((p) => p.hasDiscount && p.inStock).toList()
        ..sort((a, b) => b.discountPercent.compareTo(a.discountPercent));
      if (sale.isEmpty) {
        return 'Сейчас скидок нет, но я сообщу, когда появятся.';
      }
      if (mentioned.length < 2) {
        return 'Сейчас со скидкой: ${sale.take(3).map(_line).join('; ')}.';
      }
    }

    if (has(['цен', 'стоит', 'сколько', 'сравн', 'дешевле', 'выгодн']) &&
        mentioned.isNotEmpty) {
      if (mentioned.length >= 2) {
        final a = mentioned[0], b = mentioned[1];
        final cheaper = a.price <= b.price ? a : b;
        return '${a.name} стоит ${Formatters.price(a.price)}, а ${b.name} — '
            '${Formatters.price(b.price)}. Если бюджет важнее, то '
            '«${cheaper.name}» выигрывает по цене.';
      }
      final p = mentioned.first;
      final prices = await _products.getStorePrices(p.id);
      final best = prices.isEmpty ? null : prices.first;
      return best == null
          ? '«${p.name}» стоит ${Formatters.price(p.price)}.'
          : '«${p.name}» от ${Formatters.price(best.price)} в магазине '
                '${best.storeName} (${best.distanceLabel.replaceAll(' от вас', '')}).';
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
        ]) ||
        category != null) {
      final pool = all.where((p) => p.inStock).where((p) {
        if (category == null) return true;
        return p.zone == category || p.category == category;
      }).toList()..sort((a, b) => a.price.compareTo(b.price));
      if (pool.isEmpty) return 'К сожалению, подходящих товаров не нашлось.';
      return 'Рекомендую: ${pool.take(3).map(_line).join('; ')}.';
    }

    if (mentioned.isNotEmpty) {
      final p = mentioned.first;
      return '«${p.name}» (${p.brand}) — ${Formatters.price(p.price)}. '
          '${p.description} Спросите про состав или сравнение цен.';
    }

    return 'Я могу сравнить цены, проверить состав, показать скидки или '
        'подобрать косметику. Например: «Посоветуй тинт для губ» или '
        '«Какой состав у палетки Flower Knows?»';
  }

  String _line(Product p) =>
      '${p.name} — ${Formatters.price(p.price)}${p.hasDiscount ? ' (−${p.discountPercent}%)' : ''}';

  List<Product> _mentioned(String q, List<Product> all) {
    final scored = <(Product, int)>[];
    for (final p in all) {
      final words = '${p.brand} ${p.name}'
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
