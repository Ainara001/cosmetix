import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/providers/nav_provider.dart';
import 'package:cosmetix/providers/session.dart';
import 'package:cosmetix/screens/cart/cart_screen.dart';
import 'package:cosmetix/screens/chat/chat_screen.dart';
import 'package:cosmetix/screens/home/home_screen.dart';
import 'package:cosmetix/screens/profile/profile_screen.dart';
import 'package:cosmetix/widgets/app_bottom_nav.dart';

/// Four tabs behind the bottom navigation: Home, Cart, AI chat, Profile.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Session.loadUserData(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavProvider>();
    return PopScope(
      // The back button on a non-home tab returns to Home first.
      canPop: nav.tab == NavProvider.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.read<NavProvider>().setTab(NavProvider.home);
      },
      child: Scaffold(
        body: IndexedStack(
          index: nav.tab,
          children: const [
            HomeScreen(),
            CartScreen(),
            ChatScreen(),
            ProfileScreen(),
          ],
        ),
        bottomNavigationBar: const AppBottomNav(),
      ),
    );
  }
}
