// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/server/app_events.dart';
import 'package:cosmetix/services/server/server_consent.dart';
import 'package:cosmetix/services/server/server_exceptions.dart';
import 'package:cosmetix/services/server/server_http.dart';
import 'package:cosmetix/services/server/server_models.dart';
import 'package:cosmetix/services/server/sync_payloads.dart';

/// The result of [CosmetixServer.sendEvents]: batches before an error were
/// delivered, so [accepted] is real even when [error] is set.
class EventSendResult {
  const EventSendResult(this.accepted, [this.error]);
  final int accepted;
  final ServerException? error;
  bool get ok => error == null;
}

/// The app's door to the Cosmetix server (see `server/`): catalog, anonymous
/// device, events, profile and reactions.
///
/// Rules this class keeps:
///  * The local SQLite database stays the source of truth and the app works
///    offline. Nothing here reads or writes it, except the consent and the
///    device token (through a [ServerStateStore]).
///  * Nothing is called by itself. There is no timer, no start-up hook, no
///    queue: the app (a later step, after the data rules are approved) decides
///    when to call a method.
///  * Anything about the user needs the user's consent for exactly that kind of
///    data ([ShareScope]) under the current rules; without it the method throws
///    [ConsentRequired] and sends nothing. Reading the catalog sends no user
///    data and needs no consent.
///  * The identity is a random token from the server, no hardware id.
class CosmetixServer {
  CosmetixServer({
    required AiConfig Function() config,
    required ServerStateStore store,
    ServerHttp? http,
    DateTime Function()? now,
  }) : _store = store,
       _http = http ?? ServerHttp(config),
       _now = now ?? DateTime.now;

  final ServerStateStore _store;
  final ServerHttp _http;
  final DateTime Function() _now;

  /// The server takes at most this many events per request.
  static const eventBatchSize = 50;

  Future<DeviceCredentials?>? _registering;

  // ---------------------------------------------------------------- consent

  Future<ServerConsent> consent() => _store.loadConsent();

  /// Saves what the user allowed (replaces the earlier choice). Switching a
  /// scope off stops that kind of sending at once; the data already on the
  /// server stays until [deleteServerData].
  Future<void> setConsent(Set<ShareScope> scopes) =>
      _store.saveConsent(ServerConsent(scopes: scopes, givenAt: _now()));

  /// The user takes everything back: the consent is erased first (so nothing
  /// more is sent whatever happens next), then the data on the server is
  /// deleted when [deleteServerData] is true and the server can be reached.
  /// Returns false when that deletion did not happen: the device credentials are
  /// kept then, so [deleteServerData] can be repeated later.
  Future<bool> withdrawConsent({bool deleteServerData = true}) async {
    await _store.saveConsent(ServerConsent.none);
    if (!deleteServerData) return true;
    try {
      await this.deleteServerData();
      return true;
    } on ServerException {
      return false;
    }
  }

  /// Deletes the anonymous user on the server with everything stored for them
  /// (profile, reactions, events) and forgets the credentials. Needs no
  /// consent: deleting is always allowed. Does nothing when never registered.
  Future<void> deleteServerData() async {
    final cred = await _store.loadCredentials();
    if (cred == null) return;
    try {
      await _http.send(
        'DELETE',
        '/v1/profile',
        bearer: cred.token,
        idempotent: true,
      );
    } on ServerUnauthorized {
      // the server does not know this token any more: nothing left to delete
    }
    await _store.saveCredentials(null);
  }

  Future<void> _need(ShareScope scope) async {
    if (!(await _store.loadConsent()).allows(scope)) {
      throw ConsentRequired(scope);
    }
  }

  // ----------------------------------------------------------------- device

  /// Gives the installation its anonymous identity. Needs
  /// [ShareScope.deviceRegistration]. Nothing is sent with the request. Calling
  /// it again returns the stored identity instead of registering twice.
  Future<DeviceCredentials> registerDevice() async {
    await _need(ShareScope.deviceRegistration);
    final inFlight = _registering;
    if (inFlight != null) return (await inFlight)!;
    final future = _register();
    _registering = future;
    try {
      return (await future)!;
    } finally {
      _registering = null;
    }
  }

  Future<DeviceCredentials?> _register() async {
    final existing = await _store.loadCredentials();
    if (existing != null) return existing;
    final data = await _http.send('POST', '/v1/devices');
    final cred = data is Map ? DeviceCredentials.fromJson(data) : null;
    if (cred == null) {
      throw const ServerBadResponse('The registration answer is incomplete');
    }
    await _store.saveCredentials(cred);
    return cred;
  }

  /// Registered, with a token, right now.
  Future<bool> get isRegistered async =>
      (await _store.loadCredentials()) != null;

  Future<DeviceCredentials> _credentials() async {
    final c = await _store.loadCredentials();
    if (c == null) throw const DeviceNotRegistered();
    return c;
  }

  /// A request on behalf of the registered user. A 401 means the server does
  /// not know the token (for example it was reset): the stored credentials are
  /// dropped so the next registration starts clean.
  Future<Object?> _asUser(
    ShareScope scope,
    String method,
    String path, {
    Object? json,
    bool idempotent = false,
  }) async {
    await _need(scope);
    final cred = await _credentials();
    try {
      return await _http.send(
        method,
        path,
        json: json,
        bearer: cred.token,
        idempotent: idempotent,
      );
    } on ServerUnauthorized {
      await _store.saveCredentials(null);
      rethrow;
    }
  }

  // ---------------------------------------------------------------- catalog

  /// One page of the catalog. Sends no user data and needs no consent.
  Future<ServerCatalogPage> fetchCatalogPage({
    int limit = 100,
    int offset = 0,
    String? category,
    String? brand,
    String? query,
    DateTime? updatedSince,
  }) async {
    final data = await _http.send(
      'GET',
      '/v1/catalog/products',
      idempotent: true,
      query: {
        'limit': '$limit',
        'offset': '$offset',
        'category': ?category,
        'brand': ?brand,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (updatedSince != null)
          'updatedSince': updatedSince.toUtc().toIso8601String(),
      },
    );
    return ServerCatalogPage.fromJson(data);
  }

  /// The whole catalog (or what changed since [updatedSince]), page by page.
  /// [maxPages] is a safety stop against a server that never ends. If one page
  /// fails the error is thrown and nothing partial is returned: the caller
  /// keeps its local catalog.
  Future<List<ServerProduct>> fetchCatalog({
    DateTime? updatedSince,
    int pageSize = 100,
    int maxPages = 50,
  }) async {
    final all = <ServerProduct>[];
    for (var page = 0; page < maxPages; page++) {
      final p = await fetchCatalogPage(
        limit: pageSize,
        offset: all.length,
        updatedSince: updatedSince,
      );
      all.addAll(p.items);
      if (p.items.isEmpty || all.length >= p.total) return all;
    }
    throw const ServerBadResponse('The catalog has more pages than expected');
  }

  Future<ServerProductDetails> fetchProduct(int id) async {
    final data = await _http.send(
      'GET',
      '/v1/catalog/products/$id',
      idempotent: true,
    );
    return ServerProductDetails.fromJson(data);
  }

  // ----------------------------------------------------------------- events

  /// Sends events. Needs [ShareScope.usageEvents] and a registered device.
  /// Never retried by itself after an unclear failure (a repeat could count
  /// events twice). Batches before a failure were delivered: see
  /// [EventSendResult.accepted]. Nothing is queued for later.
  Future<EventSendResult> sendEvents(List<AppEvent> events) async {
    await _need(ShareScope.usageEvents);
    await _credentials();
    var accepted = 0;
    for (var i = 0; i < events.length; i += eventBatchSize) {
      final batch = events.skip(i).take(eventBatchSize).toList();
      try {
        final data = await _asUser(
          ShareScope.usageEvents,
          'POST',
          '/v1/events',
          json: {
            'events': [for (final e in batch) e.toJson()],
          },
        );
        accepted += data is Map && data['accepted'] is int
            ? data['accepted'] as int
            : batch.length;
      } on ServerException catch (e) {
        return EventSendResult(accepted, e);
      }
    }
    return EventSendResult(accepted);
  }

  // ---------------------------------------------------------------- profile

  /// Sends the profile (see [ProfileSyncPayload] for what it holds). Needs
  /// [ShareScope.profile]. Repeating it is harmless.
  Future<void> pushProfile(ProfileSyncPayload payload) async {
    await _asUser(
      ShareScope.profile,
      'PUT',
      '/v1/profile',
      json: payload.toJson(),
      idempotent: true,
    );
  }

  // -------------------------------------------------------------- reactions

  /// Sends one diary entry. Needs [ShareScope.reactions]. Repeating it updates
  /// the same entry.
  Future<void> pushReaction(ReactionSyncPayload payload) async {
    await _asUser(
      ShareScope.reactions,
      'PUT',
      '/v1/reactions/${Uri.encodeComponent(payload.clientId)}',
      json: payload.toJson(),
      idempotent: true,
    );
  }

  /// Removes one diary entry from the server (the local id of the entry).
  Future<void> deleteReaction(int localId) async {
    await _asUser(
      ShareScope.reactions,
      'DELETE',
      '/v1/reactions/$localId',
      idempotent: true,
    );
  }
}
