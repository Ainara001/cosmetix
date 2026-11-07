import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/providers/offer_sync_provider.dart';
import 'package:cosmetix/widgets/offer_widgets.dart';

/// One line under the prices: when they were last copied from the server, that
/// an update is running, or that it failed (and the saved prices are shown with
/// the date they were checked). Does nothing when the provider is absent.
class OfferSyncStatus extends StatelessWidget {
  const OfferSyncStatus({super.key, this.onRefreshed});

  /// Called after a manual refresh finished, so the screen can reload.
  final VoidCallback? onRefreshed;

  @override
  Widget build(BuildContext context) {
    final OfferSyncProvider sync;
    try {
      sync = context.watch<OfferSyncProvider>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    final at = sync.lastSyncedAt;
    final configured = sync.configured();
    final String text;
    if (sync.syncing) {
      text = tr('Обновляем цены…');
    } else if (sync.error != null) {
      text = tr(
        'Не удалось обновить цены. Показаны сохранённые, с датой проверки.',
      );
    } else if (!configured && at == null) {
      text = tr('Сервер цен не подключён.');
    } else if (at == null) {
      text = tr('Цены с сервера ещё не загружались.');
    } else {
      text = trf('Цены обновлены: {d}', {'d': offerDate(at.millisecondsSinceEpoch)});
    }
    return Row(
      key: const Key('offer-sync-status'),
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: sync.error != null
                  ? AppColors.warning
                  : context.pal.subtext,
            ),
          ),
        ),
        if (configured)
          IconButton(
            key: const Key('offer-sync-refresh'),
            tooltip: tr('Обновить цены'),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh),
            onPressed: sync.syncing
                ? null
                : () async {
                    await sync.sync();
                    onRefreshed?.call();
                  },
          ),
      ],
    );
  }
}
