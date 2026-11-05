import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/providers/ai_provider.dart';
import 'package:cosmetix/repositories/settings_repository.dart';
import 'package:cosmetix/services/ai/ai_config.dart';

import 'ai_test.dart' show FakeAiProxy;

/// AiProvider side of the photo switch: photos are sent only when the server
/// says, explicitly, that it accepts them. Unknown means no. (Real HTTP to a fake
/// proxy, so no widget tests in this file: see photo_step_test.dart.)
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  currentLang = AppLang.ru;

  late FakeAiProxy fake;
  AiProvider provider() => AiProvider(
    SettingsRepository(DatabaseHelper(path: inMemoryDatabasePath)),
    initial: AiConfig(baseUrl: fake.url),
  );

  setUp(() async => fake = await FakeAiProxy.start());
  tearDown(() => fake.stop());

  group('AiProvider photo switch', () {
    test(
      'unknown until the health check: not allowed, but not "off" either',
      () {
        final ai = provider();
        expect(ai.photoAnalysisAllowed, isFalse);
        expect(ai.photoAnalysisOff, isFalse);
      },
    );

    test('an explicit yes allows photos', () async {
      fake.photoAnalysis = true;
      final ai = provider();
      await ai.testConnection();
      expect(ai.photoAnalysisAllowed, isTrue);
      expect(ai.photoAnalysisOff, isFalse);
    });

    test(
      'an explicit no, a missing field and the test mode all mean off',
      () async {
        for (final setup in <void Function()>[
          () => fake.photoAnalysis = false,
          () => fake.photoAnalysis = null, // an older proxy that does not say
          () {
            fake
              ..mode = 'mock'
              ..photoAnalysis = false;
          },
        ]) {
          setup();
          final ai = provider();
          await ai.testConnection();
          expect(ai.photoAnalysisAllowed, isFalse);
          expect(ai.photoAnalysisOff, isTrue);
        }
      },
    );

    test('offline: not allowed and the answer is forgotten', () async {
      fake.photoAnalysis = true;
      final ai = provider();
      await ai.testConnection();
      expect(ai.photoAnalysisAllowed, isTrue);
      await ai.update(baseUrl: 'http://127.0.0.1:1');
      expect(ai.photoAnalysisAllowed, isFalse);
      await ai.testConnection();
      expect(ai.photoAnalysisAllowed, isFalse);
    });

    test('a refusal at send time switches the photo step off', () async {
      fake.photoAnalysis = true;
      final ai = provider();
      await ai.testConnection();
      ai.markPhotoDisabled();
      expect(ai.photoAnalysisAllowed, isFalse);
      expect(ai.photoAnalysisOff, isTrue);
    });
  });
}
