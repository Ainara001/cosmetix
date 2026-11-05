import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/features/virtual_makeup/virtual_makeup.dart';
import 'package:cosmetix/repositories/try_on_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';

/// "Try on" on a product page. Shown only when the catalog knows the colour of
/// THIS product (shade); when the product is a makeup product without a known
/// colour, a short note says why there is no button. Other products show
/// nothing. Reads the local database, no network.
class TryOnButton extends StatefulWidget {
  const TryOnButton({super.key, required this.productId});

  final int productId;

  @override
  State<TryOnButton> createState() => _TryOnButtonState();
}

class _TryOnButtonState extends State<TryOnButton> {
  Future<TryOnItem?>? _item;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _item ??= TryOnRepository(
      context.read<DatabaseHelper>(),
    ).item(widget.productId);
  }

  @override
  void didUpdateWidget(TryOnButton old) {
    super.didUpdateWidget(old);
    if (old.productId != widget.productId) {
      _item = TryOnRepository(
        context.read<DatabaseHelper>(),
      ).item(widget.productId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TryOnItem?>(
      future: _item,
      builder: (context, snap) {
        final item = snap.data;
        if (item == null) return const SizedBox.shrink();
        if (!item.canTryOn) {
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              tr(
                'Примерка недоступна: в каталоге нет данных о цвете этого оттенка.',
              ),
              key: const Key('try-on-unavailable'),
              style: AppTextStyles.small.copyWith(color: context.pal.subtext),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: OutlinedButton.icon(
            key: const Key('try-on-button'),
            onPressed: () => Navigator.pushNamed(
              context,
              AppRoutes.virtualMakeup,
              arguments: item.productId,
            ),
            icon: const Icon(Icons.face_retouching_natural),
            label: Text(tr('Примерить')),
          ),
        );
      },
    );
  }
}
