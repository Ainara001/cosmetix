// ignore_for_file: curly_braces_in_flow_control_structures, unnecessary_brace_in_string_interps

import 'dart:convert';
import 'dart:io';

import 'package:cosmetix/services/catalog/product_classifier.dart';

/// Evaluates [ProductClassifier] against a hand-labelled sample and prints
/// precision / recall / F1 for the form and the main purpose, the rinse-off
/// accuracy and the share of products sent to manual review (`needsReview`).
///
/// The sample is an independent JSON file with verifiable origin; it is NOT
/// generated here. Format:
///
///   {
///     "items": [
///       { "name": "...", "category": "...", "inci": "...",
///         "trueForm": "cleanser", "truePurpose": "cleansing",
///         "trueRinseOff": true }
///     ]
///   }
///
/// `trueForm` / `truePurpose` / `trueRinseOff` are optional per item; an item
/// without a label is skipped for that metric. Enum values are the Dart enum
/// names (e.g. `cleanser`, `cream`; `cleansing`, `acneCare`).
///
/// Usage: dart run tool/eval_classifier.dart path/to/sample.json
Future<void> main(List<String> args) async {
  final src = args.isEmpty
      ? await stdin.transform(utf8.decoder).join()
      : await File(args.first).readAsString();
  final root = jsonDecode(src);
  final items = (root is Map && root['items'] is List)
      ? root['items'] as List
      : const [];

  const classifier = ProductClassifier();
  var n = 0;
  var formTp = 0, formFp = 0, formFn = 0;
  var purTp = 0, purFp = 0, purFn = 0;
  var rinseOk = 0, rinseWrong = 0, rinseUndetermined = 0;
  var needsReview = 0;
  final mismatches = <String>[];
  // per form: tp / fp / fn (fn includes "undetermined")
  final cTp = <String, int>{}, cFp = <String, int>{}, cFn = <String, int>{};
  void inc(Map<String, int> m, String k) => m[k] = (m[k] ?? 0) + 1;

  for (final it in items) {
    if (it is! Map) continue;
    n++;
    final pc = classifier.classify(
      name: '${it['name'] ?? ''}',
      category: '${it['category'] ?? ''}',
      inci: '${it['inci'] ?? ''}',
      zone: '${it['zone'] ?? ''}',
    );
    if (pc.needsReview) needsReview++;

    final trueForm = it['trueForm']?.toString();
    if (trueForm != null) {
      final pred = pc.form?.name;
      if (pred == null) {
        formFn++;
        inc(cFn, trueForm);
      } else if (pred == trueForm) {
        formTp++;
        inc(cTp, trueForm);
      } else {
        formFp++;
        inc(cFp, pred);
        inc(cFn, trueForm);
        mismatches.add('form: "${it['name']}" got $pred, want $trueForm');
      }
    }

    final truePurpose = it['truePurpose']?.toString();
    if (truePurpose != null) {
      final pred = pc.mainPurpose?.name;
      if (pred == null)
        purFn++;
      else if (pred == truePurpose)
        purTp++;
      else {
        purFp++;
        mismatches.add('purpose: "${it['name']}" got $pred, want $truePurpose');
      }
    }

    if (it['trueRinseOff'] is bool) {
      final want = it['trueRinseOff'] as bool;
      final pred = pc.rinseOff;
      if (pred == null)
        rinseUndetermined++;
      else if (pred == want)
        rinseOk++;
      else
        rinseWrong++;
    }
  }

  double prec(int tp, int fp) => (tp + fp) == 0 ? 0 : tp / (tp + fp);
  double rec(int tp, int fn) => (tp + fn) == 0 ? 0 : tp / (tp + fn);
  double f1(int tp, int fp, int fn) {
    final p = prec(tp, fp), r = rec(tp, fn);
    return (p + r) == 0 ? 0 : 2 * p * r / (p + r);
  }

  String pct(int a, int b) =>
      b == 0 ? 'n/a' : '${(100 * a / b).toStringAsFixed(1)}%';

  stdout.writeln('items: $n');
  stdout.writeln(
    'form      precision ${pct(formTp, formTp + formFp)}  recall ${pct(formTp, formTp + formFn)}  F1 ${f1(formTp, formFp, formFn).toStringAsFixed(3)}  (TP ${formTp}, FP ${formFp}, FN ${formFn})',
  );
  stdout.writeln(
    'purpose   precision ${pct(purTp, purTp + purFp)}  recall ${pct(purTp, purTp + purFn)}  F1 ${f1(purTp, purFp, purFn).toStringAsFixed(3)}  (TP ${purTp}, FP ${purFp}, FN ${purFn})',
  );
  stdout.writeln(
    'rinseOff  correct ${pct(rinseOk, rinseOk + rinseWrong + rinseUndetermined)}  wrong ${pct(rinseWrong, rinseOk + rinseWrong + rinseUndetermined)}  undetermined ${pct(rinseUndetermined, rinseOk + rinseWrong + rinseUndetermined)}',
  );
  stdout.writeln(
    'needsReview (undetermined -> manual queue): ${pct(needsReview, n)}',
  );
  final classes = {...cTp.keys, ...cFp.keys, ...cFn.keys}.toList()..sort();
  if (classes.isNotEmpty) {
    stdout.writeln('per form (n = labelled items of that form):');
    for (final c in classes) {
      final tp = cTp[c] ?? 0, fp = cFp[c] ?? 0, fn = cFn[c] ?? 0;
      stdout.writeln(
        '  ${c.padRight(12)} n ${(tp + fn).toString().padLeft(3)}  precision ${pct(tp, tp + fp).padLeft(6)}  recall ${pct(tp, tp + fn).padLeft(6)}',
      );
    }
  }
  if (mismatches.isNotEmpty) {
    stdout.writeln('mismatches:');
    for (final m in mismatches) {
      stdout.writeln('  - $m');
    }
  }
}
