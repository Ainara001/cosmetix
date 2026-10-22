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
import 'package:cosmetix/providers/chat_provider.dart';
import 'package:cosmetix/providers/nav_provider.dart';
import 'package:cosmetix/providers/safety_provider.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/repositories/cart_repository.dart';
import 'package:cosmetix/repositories/chat_repository.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/review_repository.dart';
import 'package:cosmetix/repositories/safety_repository.dart';
import 'package:cosmetix/repositories/settings_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/providers/ai_provider.dart';
import 'package:cosmetix/services/ai/product_classifier.dart';
import 'package:cosmetix/services/ai/recommendation_refiner.dart';
import 'package:cosmetix/services/ai/vision_analyzer.dart';
import 'package:cosmetix/services/assistant_service.dart';
import 'package:cosmetix/services/avatar_service.dart';
import 'package:cosmetix/services/recommendation_service.dart';

/// Creates repositories and providers (Screen -> Provider -> Repository ->
/// SQLite) and starts the app after the saved session is restored.
class CosmetixApp extends StatefulWidget {
  const CosmetixApp({super.key, required this.helper});

  final DatabaseHelper helper;

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
    _reco = RecommendationService(_products, _safety, users);
    _ai = AiProvider(SettingsRepository(h));
    _catalogProvider = CatalogProvider(_products, _reco);
    // re-personalize when the Beauty Profile or the blacklist changes
    _catalogProvider.watchProfile(
      signature: () =>
          '${_auth.user?.beautyProfile.signature}|'
          '${_safetyProvider.blacklist.where((b) => b.enabled).map((b) => b.id).join(',')}',
      sources: [_auth, _safetyProvider],
    );
    _init = Future.wait([_auth.restoreSession(), _settings.load(), _ai.load()]);
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
            Provider<AvatarService>(create: (_) => AvatarService()),
            Provider<VisionAnalyzer>(create: (_) => VisionAnalyzer(_ai.client)),
            Provider<ProductClassifier>(
              create: (_) => ProductClassifier(_ai.client, _products, _safety),
            ),
            Provider<RecommendationRefiner>(
              create: (_) => RecommendationRefiner(_ai.client),
            ),
            ChangeNotifierProvider(create: (_) => NavProvider()),
            ChangeNotifierProvider<CatalogProvider>.value(
              value: _catalogProvider,
            ),
            ChangeNotifierProvider(
              create: (_) => CartProvider(CartRepository(widget.helper)),
            ),
            ChangeNotifierProvider<SafetyProvider>.value(
              value: _safetyProvider,
            ),
            ChangeNotifierProvider(
              create: (_) => ChatProvider(
                ChatRepository(widget.helper),
                AssistantService(_reco, _ai.client),
                shareProfile: () => _ai.shareProfile,
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
