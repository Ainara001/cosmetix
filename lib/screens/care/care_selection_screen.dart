import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/repositories/skin_marks_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/services/care_selection_service.dart';
import 'package:cosmetix/services/ingredient_catalog.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

/// Rule-based (no AI) care selection: a short questionnaire (skin type,
/// concerns, pregnancy, budget) runs [CareSelectionService] over the catalog
/// and lists the products with a verified price, or "price not confirmed".
class CareSelectionScreen extends StatefulWidget {
  const CareSelectionScreen({
    super.key,
    this.products,
    this.initialSkinType,
    this.initialConcerns = const {},
    this.initialAge,
  });

  /// Products to pick from; null reads `CatalogProvider.products` (the real app).
  final List<Product>? products;
  final SkinType? initialSkinType;
  final Set<SkinConcern> initialConcerns;
  final int? initialAge;

  @override
  State<CareSelectionScreen> createState() => _CareSelectionScreenState();
}

class _CareSelectionScreenState extends State<CareSelectionScreen> {
  SkinType? _skinType;
  final Set<SkinConcern> _concerns = {};
  bool _pregnant = false;
  final _budget = TextEditingController();
  CareSelectionResult? _result;

  @override
  void initState() {
    super.initState();
    _skinType = widget.initialSkinType;
    _concerns.addAll(widget.initialConcerns);
    if (widget.initialConcerns.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMarked());
    }
  }

  /// Pre-selects the concerns the user marked on the face zones screen.
  Future<void> _loadMarked() async {
    final SkinMarksRepository repo;
    final AuthProvider auth;
    try {
      repo = context.read<SkinMarksRepository>();
      auth = context.read<AuthProvider>();
    } on ProviderNotFoundException {
      return; // ponytail: screen used without the app's providers (tests)
    }
    if (auth.user == null) return;
    final marked = (await repo.current(auth.userId)).concerns;
    if (!mounted || marked.isEmpty || _result != null) return;
    setState(() => _concerns.addAll(marked));
  }

  @override
  void dispose() {
    _budget.dispose();
    super.dispose();
  }

  CareNeed _need() => CareNeed(
    skinType: _skinType,
    concerns: _concerns,
    age: widget.initialAge,
    pregnant: _pregnant,
    budget: int.tryParse(_budget.text.trim()) ?? 0,
  );

  void _run() {
    final products =
        widget.products ?? context.read<CatalogProvider>().products;
    setState(() => _result = CareSelectionService.select(_need(), products));
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: tr('Подбор ухода'),
      showNav: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            tr(
              'Подберите уход под свою кожу без ИИ: ответьте на несколько вопросов.',
            ),
            style: AppTextStyles.body.copyWith(color: context.pal.subtext),
          ),
          const SizedBox(height: 14),
          Text(tr('Тип кожи'), style: AppTextStyles.subtitle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in SkinType.values)
                AppChip(
                  label: tr(s.label),
                  selected: _skinType == s,
                  onTap: () => setState(() => _skinType = s),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(tr('Проблемы кожи'), style: AppTextStyles.subtitle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in SkinConcern.values)
                AppChip(
                  label: tr(c.label),
                  selected: _concerns.contains(c),
                  onTap: () => setState(() {
                    if (!_concerns.remove(c)) _concerns.add(c);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(tr('Беременность или планирование')),
            value: _pregnant,
            onChanged: (v) => setState(() => _pregnant = v),
          ),
          TextField(
            controller: _budget,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: tr('Бюджет (₸)')),
          ),
          const SizedBox(height: 14),
          CustomButton(label: tr('Подобрать'), onPressed: _run),
          const SizedBox(height: 20),
          if (_result != null) ..._results(context),
        ],
      ),
    );
  }

  List<Widget> _results(BuildContext context) {
    final r = _result!;
    if (r.matches.isEmpty) {
      return [
        EmptyState(
          icon: Icons.spa_outlined,
          title: tr('Подходящих товаров не найдено'),
        ),
        ..._left(context, r),
      ];
    }
    return [
      Text(
        tr('Найдено товаров: {n}').replaceAll('{n}', '${r.matches.length}'),
        style: AppTextStyles.subtitle,
      ),
      const SizedBox(height: 6),
      Text(
        tr(
          'Показываем только товары с проверенной ценой в пределах бюджета. Правила не заменяют консультацию врача.',
        ),
        style: AppTextStyles.caption.copyWith(color: context.pal.subtext),
      ),
      const SizedBox(height: 12),
      for (final m in r.matches) _card(context, m),
      ..._left(context, r),
    ];
  }

  /// Why the other products were left out, grouped: the selection explains
  /// itself, a missing price or a safety rule is not hidden.
  List<Widget> _left(BuildContext context, CareSelectionResult r) {
    if (r.exclusions.isEmpty) return const [];
    final counts = <String, int>{};
    for (final e in r.exclusions) {
      counts[e.reason] = (counts[e.reason] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      const SizedBox(height: 12),
      Text(tr('Не вошли в подбор'), style: AppTextStyles.bodyBold),
      const SizedBox(height: 4),
      for (final e in sorted)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${tr(e.key)} — ${e.value}',
            style: AppTextStyles.caption.copyWith(color: context.pal.subtext),
          ),
        ),
    ];
  }

  Widget _card(BuildContext context, CareMatch m) {
    final p = m.product;
    final priceText = p.hasPrice
        ? Formatters.price(p.price)
        : tr('Цена не подтверждена');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${p.brand} ${tr(p.name)}'.trim(),
            style: AppTextStyles.bodyBold,
          ),
          const SizedBox(height: 2),
          Text(
            priceText,
            style: AppTextStyles.body.copyWith(color: context.pal.accent),
          ),
          if (m.functions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              m.functions.map((f) => tr(f.label)).join(' · '),
              style: AppTextStyles.caption.copyWith(color: context.pal.subtext),
            ),
          ],
          if (m.matchedActives.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              m.matchedActives
                  .map((a) => tr(IngredientCatalog.byCode(a)?.label ?? a))
                  .join(', '),
              style: AppTextStyles.caption,
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pushNamed(
                context,
                AppRoutes.product,
                arguments: p.id,
              ),
              child: Text(tr('К товару')),
            ),
          ),
        ],
      ),
    );
  }
}
