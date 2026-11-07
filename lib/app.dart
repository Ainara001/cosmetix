import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/constants/app_constants.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_theme.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/offer_sync_provider.dart';
import 'package:cosmetix/repositories/offer_sync_repository.dart';
import 'package:cosmetix/services/offer_sync_service.dart';
import 'package:cosmetix/services/server/server_http.dart';
import 'package:cosmetix/providers/care_provider.dart';
import 'package:cosmetix/providers/chat_provider.dart';
import 'package:cosmetix/providers/nav_provider.dart';
import 'package:cosmetix/providers/safety_provider.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/repositories/care_repository.dart';
import 'package:cosmetix/repositories/cart_repository.dart';
import 'package:cosmetix/repositories/chat_repository.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/review_repository.dart';
import 'package:cosmetix/repositories/safety_repository.dart';
import 'package:cosmetix/repositories/settings_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/providers/ai_provider.dart';
import 'package:cosmetix/providers/location_provider.dart';
import 'package:cosmetix/services/age_safety.dart';
import 'package:cosmetix/services/ai/product_classifier.dart';
import 'package:cosmetix/services/ai/recommendation_refiner.dart';
import 'package:cosmetix/services/ai/vision_analyzer.dart';
import 'package:cosmetix/services/photo_check/photo_check.dart';
import 'package:cosmetix/services/assistant_service.dart';
import 'package:cosmetix/services/ingredient_scan/ingredient_ocr.dart';
import 'package:cosmetix/services/avatar_service.dart';
import 'package:cosmetix/services/recommendation_service.dart';

/// Creates repositories and providers (Screen -> Provider -> Repository ->
/// SQLite) and starts the app after the saved session is restored.
class CosmetixApp extends StatefulWidget {
  const CosmetixApp({
    super.key,
    required this.helper,
    this.ocr = const PlatformIngredientOcr(),
    this.photoSource = const ImagePickerPhotoSource(),
    this.locationFetcher,
  });

  final DatabaseHelper helper;

  /// Text recognition and photo picking of the ingredient scanner (replaced by
  /// fakes in tests).
  final IngredientOcr ocr;
  final ScanPhotoSource photoSource;

  /// Reads the device position (a fake in tests).
  final LocationFetcher? locationFetcher;

  @override
  State<CosmetixApp> createState() => _CosmetixAppState();
}

class _CosmetixAppState extends State<CosmetixApp> {
  late final ProductRepository _products;
  late final SafetyRepository _safety;
  late final ReviewRepository _reviews;
  late final AuthProvider _auth;
  late final SettingsProvider _settings;
  late final SafetyProvider _safetyProvider;
  late final CatalogProvider _catalogProvider;
  late final AiProvider _ai;
  late final OfferSyncProvider _offerSync;
  late final LocationProvider _location;
  late final CareProvider _care;
  late final RecommendationService _reco;
  late final Future<void> _init;

  @override
  void initState() {
    super.initState();
    final h = widget.helper;
    _products = ProductRepository(h);
    _safety = SafetyRepository(h);
    _reviews = ReviewRepository(h);
    _auth = AuthProvider(UserRepository(h));
    _settings = SettingsProvider(SettingsRepository(h));
    final users = UserRepository(h);
    _safetyProvider = SafetyProvider(_safety);
    _reco = RecommendationService(_products, _safety, users, CareRepository(h));
    _ai = AiProvider(SettingsRepository(h));
    // the Gemini API terms: no remote AI for under-18s or for an unknown age
    _ai.ageSource = () => _auth.user?.age;
    _auth.addListener(_ai.ageChanged);
    _location = LocationProvider(fetcher: widget.locationFetcher);
    _catalogProvider = CatalogProvider(_products, _reco);
    // re-personalize when the Beauty Profile or the blacklist changes
    _care = CareProvider(CareRepository(h));
    _catalogProvider.watchProfile(
      signature: () =>
          '${_auth.user?.beautyProfile.signature}|'
          '${_safetyProvider.blacklist.where((b) => b.enabled).map((b) => b.id).join(',')}|'
          '${_historySignature()}',
      sources: [_auth, _safetyProvider, _care],
    );
    // prices of the shops: a plain GET of the server's public snapshot, only when
    // a server address is set; no user data is sent
    final syncRepo = OfferSyncRepository(h);
    _offerSync = OfferSyncProvider(
      OfferSyncService(
        ServerHttp(() => _ai.config),
        syncRepo,
        configured: () => _ai.config.isConfigured,
      ),
      syncRepo,
      configured: () => _ai.config.isConfigured,
    );
    _offerSync.onApplied = () {
      final u = _auth.user;
      if (u != null) _catalogProvider.load(u.id);
    };
    _init = Future.wait([
      _auth.restoreSession(),
      _settings.load(),
      _ai.load(),
      _offerSync.load(),
    ]).then((_) {
      if (_ai.config.isConfigured) _offerSync.sync();
    });
  }

  /// Shops, distances and offers for the AI (distances only when the position
  /// is real; the position itself is never sent).
  Future<StoreContext> _storeContext(List<int> productIds) async {
    final stores = await _products.getStores();
    final located = _location.isReal;
    final nearest = [
      for (final s in stores)
        s.withDistance(_location.distanceTo(s.lat, s.lng)),
    ]..sort((a, b) => a.distanceM.compareTo(b.distanceM));
    final offers = <int, List<StorePrice>>{};
    for (final id in productIds) {
      offers[id] = [
        for (final o in await _products.getStorePrices(id))
          if (o.hasPosition)
            o.withDistance(_location.distanceTo(o.lat!, o.lng!)),
      ]..sort((a, b) => a.distanceM.compareTo(b.distanceM));
    }
    return StoreContext(
      located: located,
      nearest: nearest.take(5).toList(),
      offers: offers,
    );
  }

  /// Changes when the user's reactions or cosmetic bag change AND they allowed
  /// the recommendations to use them.
  String _historySignature() {
    if (!(_auth.user?.recoUseHistory ?? false)) return 'no-history';
    final reactions = _safetyProvider.reactions
        .map((r) => '${r.productId}:${r.severity}')
        .join(',');
    final owned = _care.bag.map((p) => p.productId).join(',');
    return '$reactions|$owned';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            home: const Scaffold(
              body: Center(
                child: Text(
                  AppConstants.appName,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ),
          );
        }
        return MultiProvider(
          providers: [
            Provider<DatabaseHelper>.value(value: widget.helper),
            Provider<ReviewRepository>.value(value: _reviews),
            ChangeNotifierProvider<AuthProvider>.value(value: _auth),
            ChangeNotifierProvider<SettingsProvider>.value(value: _settings),
            ChangeNotifierProvider<AiProvider>.value(value: _ai),
            ChangeNotifierProvider<OfferSyncProvider>.value(value: _offerSync),
            ChangeNotifierProvider<LocationProvider>.value(value: _location),
            Provider<AvatarService>(create: (_) => AvatarService()),
            Provider<IngredientOcr>.value(value: widget.ocr),
            Provider<ScanPhotoSource>.value(value: widget.photoSource),
            // the local photo check: on the phone, before any server call
            Provider<PhotoCheck>(
              create: (_) => PhotoCheck(MediaPipePhotoFaceFinder()),
              dispose: (_, check) => check.dispose(),
            ),
            Provider<VisionAnalyzer>(create: (_) => VisionAnalyzer(_ai.client)),
            Provider<ProductClassifier>(
              create: (_) => ProductClassifier(_ai.client, _products, _safety),
            ),
            Provider<RecommendationRefiner>(
              create: (_) => RecommendationRefiner(
                _ai.client,
                profileAllowed: () => _ai.shareProfile,
              ),
            ),
            ChangeNotifierProvider(create: (_) => NavProvider()),
            ChangeNotifierProvider<CatalogProvider>.value(
              value: _catalogProvider,
            ),
            ChangeNotifierProvider(
              create: (_) =>
                  CartProvider(CartRepository(widget.helper))
                    ..guard = (p) => AgeSafety.blockReason(_auth.user?.age, p),
            ),
            ChangeNotifierProvider<CareProvider>.value(value: _care),
            ChangeNotifierProvider<SafetyProvider>.value(
              value: _safetyProvider,
            ),
            ChangeNotifierProvider(
              create: (_) => ChatProvider(
                ChatRepository(widget.helper),
                AssistantService(_reco, _ai.client, stores: _storeContext),
                shareProfile: () => _ai.shareProfile,
                chatAllowed: () => _ai.shareChat,
              ),
            ),
          ],
          child: Consumer<SettingsProvider>(
            builder: (context, settings, _) => MaterialApp(
              title: AppConstants.appName,
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: settings.themeMode,
              locale: Locale(settings.language.code),
              supportedLocales: const [
                Locale('ru'),
                Locale('en'),
                Locale('kk'),
              ],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              initialRoute: _auth.isLoggedIn ? AppRoutes.main : AppRoutes.login,
              // Flutter would also build '/' under '/main' (an "unavailable
              // screen" you could pop back to); start with the single route.
              onGenerateInitialRoutes: (name) => [
                AppRoutes.onGenerate(RouteSettings(name: name)),
              ],
              onGenerateRoute: AppRoutes.onGenerate,
            ),
          ),
        );
      },
    );
  }
}
