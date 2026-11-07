import 'package:cosmetix/models/server_offer.dart';
import 'package:cosmetix/repositories/offer_sync_repository.dart';
import 'package:cosmetix/services/server/server_exceptions.dart';
import 'package:cosmetix/services/server/server_http.dart';

/// Result of one sync run.
class OfferSyncResult {
  const OfferSyncResult.done(this.applied, this.received)
    : error = null,
      notConfigured = false;
  const OfferSyncResult.failed(this.error)
    : applied = null,
      received = 0,
      notConfigured = false;
  const OfferSyncResult.notConfigured()
    : applied = null,
      received = 0,
      error = null,
      notConfigured = true;

  final SnapshotApplied? applied;
  final int received;
  final String? error;
  final bool notConfigured;

  bool get ok => applied != null;
}

/// Copies the server's snapshot of VERIFIED offers into the local database.
///
/// Reading the public catalog needs no consent and sends nothing about the
/// user: a plain GET with no profile, no ids and no photos. If the server is not
/// set, unreachable or answers with rubbish, the local data stays exactly as it
/// was (the old snapshot is shown with its date).
class OfferSyncService {
  OfferSyncService(this._http, this._repo, {required this.configured});

  final ServerHttp _http;
  final OfferSyncRepository _repo;
  final bool Function() configured;

  Future<OfferSyncResult> sync({DateTime? now}) async {
    if (!configured()) return const OfferSyncResult.notConfigured();
    final List<ServerOffer> offers;
    try {
      final body = await _http.send('GET', '/v1/catalog/offers', idempotent: true);
      offers = parse(body);
    } on ServerException catch (e) {
      return OfferSyncResult.failed(e.message);
    } on FormatException catch (e) {
      return OfferSyncResult.failed('Bad snapshot: ${e.message}');
    }
    final applied = await _repo.apply(offers, now: now);
    await _repo.remember(
      OfferSyncRepository.keySyncedAt,
      (now ?? DateTime.now()).millisecondsSinceEpoch.toString(),
    );
    await _repo.forget(OfferSyncRepository.keyError);
    return OfferSyncResult.done(applied, offers.length);
  }

  /// A snapshot is all-or-nothing: one malformed row means the server and the
  /// app do not agree on the format, so nothing is applied.
  static List<ServerOffer> parse(Object? body) {
    if (body is! Map || body['items'] is! List) {
      throw const FormatException('no "items" list');
    }
    return [
      for (final j in body['items'] as List)
        if (j is Map<String, Object?>)
          ServerOffer.fromJson(j)
        else
          throw const FormatException('an item is not an object'),
    ];
  }
}
