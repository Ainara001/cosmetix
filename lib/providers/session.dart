import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/chat_provider.dart';
import 'package:cosmetix/providers/nav_provider.dart';
import 'package:cosmetix/providers/safety_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';

/// Loads / clears all per-user data when the user signs in or out.
class Session {
  Session._();

  static Future<void> loadUserData(BuildContext context) async {
    final uid = context.read<AuthProvider>().userId;
    await Future.wait([
      context.read<CatalogProvider>().load(uid),
      context.read<CartProvider>().load(uid),
      context.read<SafetyProvider>().load(uid),
      context.read<ChatProvider>().load(uid),
    ]);
  }

  static Future<void> signOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    context.read<CatalogProvider>().reset();
    context.read<CartProvider>().reset();
    context.read<SafetyProvider>().reset();
    context.read<ChatProvider>().reset();
    context.read<NavProvider>().setTab(NavProvider.home);
    await context.read<AuthProvider>().logout();
    navigator.pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  }
}
