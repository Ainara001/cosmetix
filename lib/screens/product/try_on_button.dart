import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/features/virtual_makeup/virtual_makeup.dart';
import 'package:cosmetix/repositories/try_on_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/shade_widgets.dart';

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
          // the button is there but off, with one short reason: the app does not
          // try on a colour nobody knows
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomButton(
                  key: const Key('try-on-button-off'),
                  label: tr('Примерить'),
                  icon: Icons.face_retouching_natural,
                  outlined: true,
                  onPressed: null,
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    'Примерка недоступна: цвет этого оттенка ещё не известен.',
                  ),
                  key: const Key('try-on-unavailable'),
                  style: AppTextStyles.small.copyWith(
                    color: context.pal.subtext,
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomButton(
                key: const Key('try-on-button'),
                label: tr('Примерить'),
                icon: Icons.face_retouching_natural,
                outlined: true,
                onPressed: () => Navigator.pushNamed(
                  context,
                  AppRoutes.virtualMakeup,
                  arguments: item.productId,
                ),
              ),
              if (item.isApproximate) ...[
                const SizedBox(height: 8),
                const ApproxNote(key: Key('try-on-approx'), compact: true),
              ],
            ],
          ),
        );
      },
    );
  }
}
