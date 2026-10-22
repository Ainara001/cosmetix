import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';

import 'package:cosmetix/models/cart_models.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/screens/auth/forgot_password_screen.dart';
import 'package:cosmetix/screens/auth/login_screen.dart';
import 'package:cosmetix/screens/auth/register_screen.dart';
import 'package:cosmetix/screens/auth/reset_password_screen.dart';
import 'package:cosmetix/screens/beauty/beauty_profile_screen.dart';
import 'package:cosmetix/screens/beauty/beauty_photo_screen.dart';
import 'package:cosmetix/screens/beauty/color_result_screen.dart';
import 'package:cosmetix/screens/beauty/skin_test_screen.dart';
import 'package:cosmetix/screens/beauty/color_test_screen.dart';
import 'package:cosmetix/screens/beauty/undertone_test_screen.dart';
import 'package:cosmetix/screens/care/bag_form_screen.dart';
import 'package:cosmetix/screens/care/bag_screen.dart';
import 'package:cosmetix/screens/care/care_history_screen.dart';
import 'package:cosmetix/screens/care/care_screen.dart';
import 'package:cosmetix/screens/cart/order_success_screen.dart';
import 'package:cosmetix/screens/cart/orders_screen.dart';
import 'package:cosmetix/screens/catalog/catalog_screen.dart';
import 'package:cosmetix/screens/catalog/filters_screen.dart';
import 'package:cosmetix/screens/home/main_shell.dart';
import 'package:cosmetix/screens/home/search_screen.dart';
import 'package:cosmetix/screens/product/analysis_screen.dart';
import 'package:cosmetix/screens/product/price_compare_screen.dart';
import 'package:cosmetix/screens/product/product_screen.dart';
import 'package:cosmetix/screens/product/reviews_screen.dart';
import 'package:cosmetix/screens/profile/edit_profile_screen.dart';
import 'package:cosmetix/screens/profile/favorites_screen.dart';
import 'package:cosmetix/screens/profile/legal_screen.dart';
import 'package:cosmetix/screens/profile/settings_screen.dart';
import 'package:cosmetix/screens/safety/blacklist_screen.dart';
import 'package:cosmetix/screens/safety/reaction_form_screen.dart';
import 'package:cosmetix/screens/safety/reactions_screen.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

/// All route names in one place + the route table.
class AppRoutes {
  AppRoutes._();

  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const main = '/main';
  static const catalog = '/catalog';
  static const search = '/search';
  static const filters = '/filters';
  static const product = '/product';
  static const priceCompare = '/price-compare';
  static const reviews = '/reviews';
  static const analysis = '/analysis';
  static const favorites = '/favorites';
  static const orders = '/orders';
  static const orderSuccess = '/order-success';
  static const beautyProfile = '/beauty-profile';
  static const colorTest = '/color-test';
  static const undertoneTest = '/undertone-test';
  static const skinTest = '/skin-test';
  static const beautyPhoto = '/beauty-photo';
  static const colorResult = '/color-result';
  static const editProfile = '/edit-profile';
  static const settings = '/settings';
  static const blacklist = '/blacklist';
  static const reactions = '/reactions';
  static const reactionForm = '/reaction-form';
  static const legal = '/legal';
  static const bag = '/bag';
  static const bagForm = '/bag-form';
  static const care = '/care';
  static const careHistory = '/care-history';

  static Route<dynamic> onGenerate(RouteSettings s) {
    final a = s.arguments;
    final Widget page;
    switch (s.name) {
      case login:
        page = const LoginScreen();
      case register:
        page = const RegisterScreen();
      case forgotPassword:
        page = const ForgotPasswordScreen();
      case resetPassword:
        page = a is String ? ResetPasswordScreen(email: a) : _bad();
      case main:
        page = const MainShell();
      case catalog:
        page = CatalogScreen(args: a is CatalogArgs ? a : const CatalogArgs());
      case search:
        page = const SearchScreen();
      case filters:
        page = a is FiltersArgs ? FiltersScreen(args: a) : _bad();
      case product:
        page = a is int ? ProductScreen(productId: a) : _bad();
      case priceCompare:
        page = a is int ? PriceCompareScreen(productId: a) : _bad();
      case reviews:
        page = a is int ? ReviewsScreen(productId: a) : _bad();
      case analysis:
        page = a is int ? AnalysisScreen(productId: a) : _bad();
      case favorites:
        page = const FavoritesScreen();
      case orders:
        page = const OrdersScreen();
      case orderSuccess:
        page = a is Order ? OrderSuccessScreen(order: a) : _bad();
      case beautyProfile:
        page = const BeautyProfileScreen();
      case colorTest:
        page = const ColorTestScreen();
      case undertoneTest:
        page = a is UndertoneArgs ? UndertoneTestScreen(args: a) : _bad();
      case skinTest:
        page = a is SkinTestArgs ? SkinTestScreen(args: a) : _bad();
      case beautyPhoto:
        page = a is BeautyPhotoArgs ? BeautyPhotoScreen(args: a) : _bad();
      case colorResult:
        page = a is BeautyResultArgs ? ColorResultScreen(result: a) : _bad();
      case editProfile:
        page = const EditProfileScreen();
      case AppRoutes.settings:
        page = const SettingsScreen();
      case blacklist:
        page = const BlacklistScreen();
      case reactions:
        page = const ReactionsScreen();
      case reactionForm:
        page = ReactionFormScreen(reactionId: a is int ? a : null);
      case bag:
        page = const BagScreen();
      case bagForm:
        page = BagFormScreen(
          args: a is BagFormArgs ? a : BagFormArgs(id: a is int ? a : null),
        );
      case care:
        page = const CareScreen();
      case careHistory:
        page = const CareHistoryScreen();
      case legal:
        page = LegalScreen(args: a is LegalArgs ? a : LegalArgs.terms);
      default:
        page = _bad();
    }
    return MaterialPageRoute<dynamic>(settings: s, builder: (_) => page);
  }

  static Widget _bad() => PageScaffold(
    title: tr('Ошибка'),
    showNav: false,
    child: EmptyState(
      icon: Icons.error_outline,
      title: tr('Экран недоступен'),
      subtitle: tr('Не удалось открыть этот экран. Вернитесь назад.'),
    ),
  );
}
