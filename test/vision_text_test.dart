import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/models/ai_models.dart';
import 'package:cosmetix/services/ai/ai_client.dart';
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/ai/vision_analyzer.dart';

import 'ai_test.dart' show FakeAiProxy;

/// The photo analysis returns three codes and nothing else. In the audit
/// (PR #24) 30 of 79 answers carried free text with unmeasured statements about
/// the skin ("expressed skin texture", "no visible redness", "healthy glow").
/// Such text is neither requested, nor kept, nor shown.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('the request', () {
    const p = VisionAnalyzer.prompt;

    test('asks for exactly the three codes and the self-report, no text', () {
      expect(p, contains('"skinTone"'));
      expect(p, contains('"undertone"'));
      expect(p, contains('"colorType"'));
      expect(p, contains('"confidence"'));
      expect(p, isNot(contains('"observations"')));
      expect(p, isNot(contains('"explanation"')));
      expect(p, contains('Write nothing else'));
    });

    test('forbids comments about the skin', () {
      for (final word in [
        'condition',
        'texture',
        'redness',
        'spots',
        'pigmentation',
        'disease',
      ]) {
        expect(p, contains(word), reason: word);
      }
      expect(p, contains('Do not guess'));
    });

    test(
      'the request that is sent carries that prompt and no language request',
      () async {
        final fake = await FakeAiProxy.start();
        addTearDown(fake.stop);
        fake.chatAnswer =
            '{"skinTone":"light","undertone":"cool","colorType":"summer","confidence":0.8}';
        final client = AiClient(() => AiConfig(baseUrl: fake.url));
        await VisionAnalyzer(
          client,
        ).analyze(Uint8List.fromList(List.filled(10, 1)));
        final sent = jsonEncode(fake.requests.single);
        expect(sent, contains('Write nothing else'));
        expect(sent, isNot(contains('Requested language')));
        expect(sent, isNot(contains('observations')));
      },
    );
  });

  group('the answer', () {
    const withText =
        '{"skinTone":"deep","undertone":"warm","colorType":"autumn",'
        '"observations":["выраженная текстура кожи","отсутствие видимых покраснений",'
        '"естественный здоровый блеск"],"confidence":0.85,'
        '"explanation":"Кожа склонна к покраснениям"}';

    test('the codes are kept', () {
      final a = VisionAnalysis.parse(withText);
      expect(a.skinTone, SkinTone.deep);
      expect(a.undertone, Undertone.warm);
      expect(a.colorType, ColorType.autumn);
      expect(a.confidence, 0.85);
    });

    test('the free text a model adds anyway is dropped, not carried', () {
      final a = VisionAnalysis.parse(withText) as dynamic;
      expect(() => a.observations, throwsNoSuchMethodError);
      expect(() => a.explanation, throwsNoSuchMethodError);
      expect(a.toString().contains('текстура'), isFalse);
    });

    test('an answer that is only text is an error, not a profile', () {
      expect(
        () => VisionAnalysis.parse(
          '{"observations":["ровная текстура кожи"],"confidence":0.9}',
        ),
        throwsA(isA<AiBadResponse>()),
      );
    });
  });
}
