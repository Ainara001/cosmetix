import 'dart:async';
import 'dart:io';

import 'package:cosmetix/database/catalog_data.dart';
import 'package:cosmetix/database/database_helper.dart';

import 'support/verified_offers.dart';

/// Runs before every test file. The catalog JSON is read straight from the
/// project folder: that needs no Flutter binding (a binding would block the
/// real HTTP the AI tests use) and no async I/O inside widget tests.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  CatalogData.assetReader = (path) async => File(path).readAsStringSync();
  // the old tests expect shop prices: give them verified fixture offers
  // (the new honesty tests switch this off)
  DatabaseHelper.afterSeed = verifyDemoOffers;
  await testMain();
}
