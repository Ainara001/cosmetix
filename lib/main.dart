import 'package:flutter/material.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/core/utils/app_paths.dart';
import 'package:cosmetix/database/database_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPaths.init();
  runApp(CosmetixApp(helper: DatabaseHelper()));
}
