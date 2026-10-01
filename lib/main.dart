import 'package:flutter/material.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/database/database_helper.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CosmetixApp(helper: DatabaseHelper()));
}
