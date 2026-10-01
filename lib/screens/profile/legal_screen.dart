import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';

import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

/// Added screen: privacy policy / terms of use text.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.args});

  final LegalArgs args;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: tr(args.title),
      showNav: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Text(
          tr(args.text),
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
      ),
    );
  }
}
