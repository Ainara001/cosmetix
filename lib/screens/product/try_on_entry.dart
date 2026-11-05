import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/features/virtual_makeup/virtual_makeup.dart';
import 'package:cosmetix/repositories/try_on_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';

/// The virtual try-on screen connected to the local catalog: the app side of
/// the module (the module itself knows nothing about the database or routes).
/// [productId] shows a catalog product right away; without it the screen starts
/// with hand-picked colours, as before.
class TryOnEntry extends StatelessWidget {
  const TryOnEntry({super.key, this.productId});

  final int? productId;

  @override
  Widget build(BuildContext context) {
    return VirtualMakeupScreen(
      catalog: TryOnRepository(context.read<DatabaseHelper>()),
      productId: productId,
      // the product page has the cart and the favourites
      onOpenProduct: (id) =>
          Navigator.pushNamed(context, AppRoutes.product, arguments: id),
    );
  }
}
