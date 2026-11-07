import 'package:flutter/foundation.dart';

import 'package:cosmetix/repositories/offer_sync_repository.dart';
import 'package:cosmetix/services/offer_sync_service.dart';

/// State of the price sync for the screens: "updated on a date", "updating",
/// "could not update, the old prices are shown with their date".
class OfferSyncProvider extends ChangeNotifier {
  OfferSyncProvider(this._service, this._repo, {required this.configured});

  final OfferSyncService _service;
  final OfferSyncRepository _repo;

  /// Whether a server address is set at all.
  final bool Function() configured;

  /// Called after a snapshot was stored so the lists reload their prices.
  VoidCallback? onApplied;

  bool syncing = false;
  DateTime? lastSyncedAt;
  String? error;
  OfferSyncResult? last;

  Future<void> load() async {
    lastSyncedAt = await _repo.lastSyncedAt();
    notifyListeners();
  }

  Future<void> sync() async {
    if (syncing) return;
    syncing = true;
    error = null;
    notifyListeners();
    try {
      final r = await _service.sync();
      last = r;
      if (r.ok) {
        lastSyncedAt = await _repo.lastSyncedAt();
        onApplied?.call();
      } else if (!r.notConfigured) {
        error = r.error;
      }
    } catch (e) {
      error = e.toString();
      debugPrint('offer sync failed: $e');
    }
    syncing = false;
    notifyListeners();
  }
}
