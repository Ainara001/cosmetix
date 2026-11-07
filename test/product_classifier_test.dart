import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/database/catalog_data.dart';
import 'package:cosmetix/services/catalog/product_classifier.dart';

/// Quality of the classifier against the hand-labelled reference set
/// (test/fixtures/classification_gold.json). The labels are the developer's, not
/// a specialist's, so the numbers are a measurement against that reference and
/// not a proof of correctness.
void main() {
  const classifier = ProductClassifier();
  late CatalogData catalog;
  late Map<String, Map<String, Object?>> gold;

  setUpAll(() async {
    catalog = await CatalogData.load();
    final j =
        jsonDecode(
              File('test/fixtures/classification_gold.json').readAsStringSync(),
            )
            as Map;
    gold = {
      for (final e in (j['products'] as Map).entries)
        e.key as String: (e.value as Map).cast(),
    };
  });

  ProductClass of(String name) {
    final p = catalog.products.firstWhere((p) => p.name == name);
    return classifier.classify(
      name: p.name,
      category: p.category,
      inci: p.inci,
      zone: p.zone,
    );
  }

  test('every real product has a hand label', () {
    final real = catalog.products
        .where((p) => !p.demo)
        .map((p) => p.name)
        .toSet();
    expect(gold.keys.toSet(), real);
  });

  group('the cases the owner named', () {
    test(
      'a cleanser is a rinse-off cleanser, never a leave-on cream or gel',
      () {
        final c = of('Low pH Good Morning Gel Cleanser');
        expect(c.form, ProductForm.cleanser);
        expect(c.rinseOff, isTrue);
        expect(c.mainPurpose, Purpose.cleansing);
      },
    );

    test('a moisturising cream is a leave-on cream, not a cleanser', () {
      for (final n in [
        'Moisturizing Cream',
        'Soft Moisturizing Creme',
        'Ceramidin Cream',
      ]) {
        final c = of(n);
        expect(c.form, ProductForm.cream, reason: n);
        expect(c.rinseOff, isFalse, reason: n);
        expect(c.purposes, isNot(contains(Purpose.cleansing)), reason: n);
      }
    });

    test('an acid product is an exfoliant, not "just moisturising"', () {
      final g = of('Glycolic Acid 7% Toning Solution');
      expect(g.form, ProductForm.toner);
      expect(g.purposes, contains(Purpose.exfoliation));
      final b = of('BHA Blackhead Power Liquid');
      expect(b.form, ProductForm.peeling);
      expect(b.mainPurpose, Purpose.exfoliation);
      expect(b.purposes, contains(Purpose.acneCare));
    });

    test(
      'a serum is a serum, an SPF product is a sunscreen, a shampoo is a shampoo',
      () {
        expect(of('Dive-In Serum').form, ProductForm.serum);
        expect(
          of('Relief Sun: Rice + Probiotics SPF50+').form,
          ProductForm.sunscreen,
        );
        expect(
          of('Relief Sun: Rice + Probiotics SPF50+').mainPurpose,
          Purpose.sunProtection,
        );
        final s = of('Perfect Serum Shampoo');
        expect(
          s.form,
          ProductForm.shampoo,
          reason: '"Serum" in a shampoo name',
        );
        expect(s.rinseOff, isTrue);
      },
    );

    test('titanium dioxide in a lip mask is not sun protection', () {
      final l = of('Lip Sleeping Mask');
      expect(l.form, ProductForm.lipCare);
      expect(l.purposes, isNot(contains(Purpose.sunProtection)));
      expect(l.actives.map((a) => a.code), isNot(contains('uv_filter')));
    });

    test(
      'a product the name and the INCI cannot place goes to review, with a reason',
      () {
        final r = of('Retinol 0.5% in Squalane');
        expect(r.needsReview, isTrue);
        expect(r.reviewReasons, isNotEmpty);
      },
    );
  });

  test('measured against the hand labels', () {
    final rows = <String>[];
    var real = 0, formAuto = 0, formRight = 0;
    var purposeGold = 0, purposeAuto = 0, purposeRight = 0;
    var reviewShould = 0, reviewDid = 0;
    var keyTotal = 0, keyFound = 0;
    var rinseWrong = 0;
    for (final e in gold.entries) {
      real++;
      final g = e.value;
      final c = of(e.key);
      final gForm = g['form'] as String;
      if (c.form != null) {
        formAuto++;
        if (c.form!.name == gForm) formRight++;
      }
      final gRinse = g['rinse_off'] as bool?;
      if (gRinse != null && c.rinseOff != null && c.rinseOff != gRinse) {
        rinseWrong++;
      }
      final gp = (g['purposes'] as List).cast<String>();
      if (gp.isNotEmpty) {
        purposeGold++;
        if (c.mainPurpose != null) {
          purposeAuto++;
          if (gp.contains(c.mainPurpose!.name)) purposeRight++;
        }
      }
      // skincare the taxonomy does not cover: the classifier should say "review"
      if (gp.isEmpty &&
          !['makeup', 'perfume', 'shampoo', 'giftSet'].contains(gForm)) {
        reviewShould++;
        if (c.needsReview) reviewDid++;
      }
      final keys = (g['key_actives'] as List).cast<String>();
      for (final k in keys) {
        keyTotal++;
        if (c.actives.any((a) => a.code == k)) keyFound++;
      }
      rows.add(
        '${e.key}: form ${c.form?.name ?? 'REVIEW'} (gold $gForm), main ${c.mainPurpose?.name ?? '-'} (gold ${gp.isEmpty ? '-' : gp.join('|')}), review ${c.needsReview}',
      );
    }
    // ignore: avoid_print
    print(rows.join('\n'));
    // ignore: avoid_print
    print(
      'PRODUCTS $real | FORM coverage $formAuto/$real precision $formRight/$formAuto recall $formRight/$real'
      ' | PURPOSE (skincare with a gold purpose: $purposeGold) auto $purposeAuto precision $purposeRight/$purposeAuto recall $purposeRight/$purposeGold'
      ' | REVIEW of uncovered skincare $reviewDid/$reviewShould | KEY ACTIVES found $keyFound/$keyTotal | RINSE-OFF contradictions $rinseWrong',
    );
    // what must never happen: a confident wrong form, or a rinse-off contradiction
    expect(
      formRight,
      formAuto,
      reason: 'every product the classifier labels must be labelled right',
    );
    expect(rinseWrong, 0);
  });
}
