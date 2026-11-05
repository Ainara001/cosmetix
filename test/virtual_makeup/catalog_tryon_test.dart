import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/database/catalog_data.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/features/virtual_makeup/engine/color_math.dart';
import 'package:cosmetix/features/virtual_makeup/ui/virtual_makeup_controller.dart';
import 'package:cosmetix/features/virtual_makeup/virtual_makeup.dart';
import 'package:cosmetix/repositories/try_on_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';

import '../widget_test.dart' show pumpUntil;
import 'screen_test.dart'
    show FakeLandmarks, FakePhotos, host, pngOf, reveal, settle;
import 'synthetic_face.dart';

/// Counts every attempt to use the network (and refuses it).
class _NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw const SocketException('the try-on must work offline');
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final face = SyntheticFace.build();
  late Uint8List png;
  late CatalogData catalog;
  final noNet = _NoNetwork();

  setUpAll(() async {
    HttpOverrides.global = noNet;
    catalog = await CatalogData.load();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.runAsync(() async => png = await pngOf(face.image));
  });
  tearDownAll(() => HttpOverrides.global = null);

  int idOf(String name) =>
      catalog.products.indexWhere((p) => p.name == name) + 1;

  int berryId() => idOf('Ink Mood Glowy Tint 30 Happy Berry');
  int roseId() => idOf('Ink Mood Glowy Tint 03 Rose In Mind');

  Future<T> real<T>(WidgetTester t, Future<T> Function() body) async =>
      (await t.runAsync(body)) as T;

  Future<DatabaseHelper> openDb(WidgetTester t) async {
    final h = DatabaseHelper(path: inMemoryDatabasePath);
    await real(t, () => h.database);
    addTearDown(() => t.runAsync(h.close));
    return h;
  }

  group('the controller with catalog products', () {
    testWidgets('the requested product and its colour are what is shown', (
      t,
    ) async {
      final h = await openDb(t);
      final c = VirtualMakeupController(
        landmarks: FakeLandmarks([face.points]),
        catalog: TryOnRepository(h),
        debounce: Duration.zero,
      );
      addTearDown(c.dispose);
      expect(await real(t, () => c.startWith(berryId())), isTrue);
      final berry = c.items[MakeupZone.lips]!;
      expect(berry.productId, berryId());
      expect(c.colourMode, ColourMode.catalog);
      expect(c.look.lips.color, berry.colour);
      expect(c.look.lips.enabled, isTrue);
      expect(
        c.look.eyeshadow.enabled,
        isFalse,
        reason: 'only the chosen product',
      );
      expect(c.look.blush.enabled, isFalse);
      // the other shade of the line is offered, with its own colour
      expect(c.lineShades.map((i) => i.shadeCode), ['03', '30']);
      final rose = c.lineShades.firstWhere((i) => i.shadeCode == '03');
      expect(rose.colour, isNot(berry.colour));
    });

    testWidgets('switching shades switches the colour, never mixes them', (
      t,
    ) async {
      final h = await openDb(t);
      final repo = TryOnRepository(h);
      final c = VirtualMakeupController(
        landmarks: FakeLandmarks([face.points]),
        catalog: repo,
        debounce: Duration.zero,
      );
      addTearDown(c.dispose);
      await real(t, () => c.startWith(berryId()));
      final berryColour = c.look.lips.color;
      await real(
        t,
        () => c.applyItem(c.lineShades.firstWhere((i) => i.shadeCode == '03')),
      );
      expect(c.items[MakeupZone.lips]!.productId, roseId());
      expect(c.look.lips.color, isNot(berryColour));
      expect(
        c.look.lips.color,
        (await real(t, () => repo.item(roseId())))!.colour,
      );
      await real(
        t,
        () => c.applyItem(c.lineShades.firstWhere((i) => i.shadeCode == '30')),
      );
      expect(
        c.look.lips.color,
        berryColour,
        reason: 'back to the first colour',
      );
      expect(c.items.length, 1);
    });

    testWidgets('intensity stays when the shade changes', (t) async {
      final h = await openDb(t);
      final c = VirtualMakeupController(
        landmarks: FakeLandmarks([face.points]),
        catalog: TryOnRepository(h),
        debounce: Duration.zero,
      );
      addTearDown(c.dispose);
      await real(t, () => c.startWith(berryId()));
      c.setZone(MakeupZone.lips, c.look.lips.copyWith(intensity: 0.9));
      await real(t, () => c.applyItem(c.lineShades.first));
      expect(c.look.lips.intensity, 0.9);
    });

    testWidgets('products of several kinds can be worn together', (t) async {
      final h = await openDb(t);
      final c = VirtualMakeupController(
        landmarks: FakeLandmarks([face.points]),
        catalog: TryOnRepository(h),
        debounce: Duration.zero,
      );
      addTearDown(c.dispose);
      await real(t, () => c.startWith(berryId()));
      await real(t, () => c.loadBrowse(MakeupZone.blush));
      expect(c.browseList.length, 2);
      await real(t, () => c.applyItem(c.browseList.first));
      expect(c.items.keys, {MakeupZone.lips, MakeupZone.blush});
      expect(c.look.blush.enabled, isTrue);
      expect(c.look.blush.color, c.browseList.first.colour);
      expect(
        c.look.lips.color,
        c.items[MakeupZone.lips]!.colour,
        reason: 'lips kept',
      );
      c.clearItem(MakeupZone.blush);
      expect(c.look.blush.enabled, isFalse);
      expect(c.items.keys, {MakeupZone.lips});
    });

    testWidgets(
      'a product with no colour data is refused and changes nothing',
      (t) async {
        final h = await openDb(t);
        final c = VirtualMakeupController(
          landmarks: FakeLandmarks([face.points]),
          catalog: TryOnRepository(h),
          debounce: Duration.zero,
        );
        addTearDown(c.dispose);
        final before = c.look;
        final palette = idOf('Better Than Palette 05 Shade & Shadow Garden');
        expect(await real(t, () => c.startWith(palette)), isFalse);
        expect(
          await real(
            t,
            () => c.startWith(idOf('Super Slim Waterproof Mascara')),
          ),
          isFalse,
        );
        expect(await real(t, () => c.startWith(12345)), isFalse);
        expect(c.colourMode, ColourMode.manual);
        expect(c.items, isEmpty);
        expect(identical(c.look, before), isTrue);
      },
    );

    testWidgets('own colours are a separate mode and come back unchanged', (
      t,
    ) async {
      final h = await openDb(t);
      final c = VirtualMakeupController(
        landmarks: FakeLandmarks([face.points]),
        catalog: TryOnRepository(h),
        debounce: Duration.zero,
      );
      addTearDown(c.dispose);
      const mine = Color(0xFF123456);
      c.setZone(MakeupZone.lips, c.look.lips.copyWith(color: mine));
      await real(t, () => c.startWith(berryId()));
      expect(c.look.lips.color, isNot(mine));
      c.useManualColours();
      expect(c.colourMode, ColourMode.manual);
      expect(c.look.lips.color, mine, reason: 'the hand-picked colour is kept');
      expect(c.look.eyeshadow.enabled, isTrue, reason: 'as it was before');
      c.useCatalogColours();
      expect(c.look.lips.color, c.items[MakeupZone.lips]!.colour);
      expect(c.look.eyeshadow.enabled, isFalse);
    });

    testWidgets('the shown result follows the chosen shade (not another one)', (
      t,
    ) async {
      final h = await openDb(t);
      final repo = TryOnRepository(h);
      final berry = (await real(t, () => repo.item(berryId())))!;
      final rose = (await real(t, () => repo.item(roseId())))!;
      final prepared = PreparedFace.from(face.image, face.points);
      const backend = PigmentBackend();

      Lab lipMean(Color colour) {
        final out = backend.renderSync(
          MakeupRequest(
            face: prepared,
            look: MakeupLook(
              lips: ZoneLook(color: colour, intensity: 1),
              eyeshadow: const ZoneLook(
                color: Color(0xFF000000),
                enabled: false,
              ),
              blush: const ZoneLook(color: Color(0xFF000000), enabled: false),
            ),
          ),
        );
        var w = 0.0, l = 0.0, a = 0.0, b = 0.0;
        final m = prepared.masks.lips;
        for (var y = 0; y < m.height; y++) {
          for (var x = 0; x < m.width; x++) {
            final k = m.data[y * m.width + x];
            if (k < 0.9) continue;
            final o = ((m.y0 + y) * out.width + m.x0 + x) * 4;
            final c = ColorMath.rgbToLab(
              out.pixels[o],
              out.pixels[o + 1],
              out.pixels[o + 2],
            );
            w++;
            l += c.l;
            a += c.a;
            b += c.b;
          }
        }
        return Lab(l / w, a / w, b / w);
      }

      double dist(Lab p, Lab q) =>
          ((p.l - q.l) * (p.l - q.l) +
          (p.a - q.a) * (p.a - q.a) +
          (p.b - q.b) * (p.b - q.b));

      final withBerry = lipMean(berry.colour!);
      final withRose = lipMean(rose.colour!);
      final tBerry = ColorMath.colorToLab(berry.colour!);
      final tRose = ColorMath.colorToLab(rose.colour!);
      expect(dist(withBerry, tBerry), lessThan(dist(withBerry, tRose)));
      expect(dist(withRose, tRose), lessThan(dist(withRose, tBerry)));
      expect(
        dist(withBerry, withRose),
        greaterThan(1),
        reason: 'visibly different',
      );
    });

    testWidgets('a product chosen before the photo stays on it', (t) async {
      final h = await openDb(t);
      final c = VirtualMakeupController(
        landmarks: FakeLandmarks([face.points]),
        catalog: TryOnRepository(h),
        debounce: Duration.zero,
      );
      addTearDown(c.dispose);
      await real(t, () => c.startWith(berryId()));
      final colour = c.look.lips.color;
      await real(t, () => c.loadPhoto(png));
      expect(c.status, MakeupStatus.ready);
      expect(c.look.lips.color, colour);
      expect(c.look.lips.enabled, isTrue);
      expect(c.look.blush.enabled, isFalse);
      // a second photo keeps it too
      await real(t, () => c.loadPhoto(png));
      expect(c.look.lips.color, colour);
      expect(c.items[MakeupZone.lips]!.productId, berryId());
    });
  });

  group('the screen with catalog products', () {
    Future<(FakeLandmarks, FakePhotos, List<int>)> open(
      WidgetTester t, {
      int? productId,
    }) async {
      t.view.physicalSize = const Size(420, 1100) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final h = await openDb(t);
      final lm = FakeLandmarks([face.points]);
      final photos = FakePhotos(png);
      final opened = <int>[];
      await t.pumpWidget(
        host(
          VirtualMakeupScreen(
            landmarks: lm,
            photos: photos,
            catalog: TryOnRepository(h),
            productId: productId,
            onOpenProduct: opened.add,
          ),
        ),
      );
      await settle(t, find.byKey(const Key('vm-selected-lips')), max: 20);
      return (lm, photos, opened);
    }

    testWidgets(
      'brand, product, shade and the approximate colour are shown before a photo',
      (t) async {
        await open(t, productId: berryId());
        expect(find.byKey(const Key('vm-picker')), findsOneWidget);
        expect(find.text('Peripera'), findsOneWidget);
        expect(find.byKey(const Key('vm-item-name-lips')), findsOneWidget);
        expect(
          tester0(t, const Key('vm-item-name-lips')),
          'Ink Mood Glowy Tint',
        );
        expect(
          tester0(t, const Key('vm-item-shade-lips')),
          'Оттенок: 30 Happy Berry',
        );
        expect(find.byKey(const Key('vm-item-trust-lips')), findsOneWidget);
        expect(find.byKey(const Key('vm-colour-caveat')), findsOneWidget);
        expect(
          find.textContaining('не по данным производителя'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'after the photo: compare, switch shades, return to the product',
      (t) async {
        final (_, _, opened) = await open(t, productId: berryId());
        await t.tap(find.byKey(const Key('vm-gallery')));
        await settle(t, find.byKey(const Key('vm-photo')));
        expect(find.byKey(const Key('vm-compare')), findsOneWidget);
        await t.tap(find.text('Оригинал'));
        await t.pump();
        await t.tap(find.text('Результат'));
        await t.pump();

        await reveal(t, find.byKey(Key('vm-shade-${roseId()}')));
        await t.tap(find.byKey(Key('vm-shade-${roseId()}')));
        await settle(t, find.textContaining('03 Rose In Mind'));
        expect(
          tester0(t, const Key('vm-item-shade-lips')),
          'Оттенок: 03 Rose In Mind',
        );
        expect(
          tester0(t, const Key('vm-item-name-lips')),
          'Ink Mood Glowy Tint',
        );

        await reveal(t, find.byKey(Key('vm-open-product-${roseId()}')));
        await t.tap(find.byKey(Key('vm-open-product-${roseId()}')));
        expect(opened, [roseId()], reason: 'the page of the shade now shown');
      },
    );

    testWidgets('products of another kind, and a kind with no colours', (
      t,
    ) async {
      await open(t, productId: berryId());
      await t.tap(find.byKey(const Key('vm-gallery')));
      await settle(t, find.byKey(const Key('vm-photo')));
      await reveal(t, find.byKey(const Key('vm-kind-blush')));
      await t.tap(find.byKey(const Key('vm-kind-blush')));
      await settle(
        t,
        find.byKey(Key('vm-product-${idOf('Better Than Cheek')}')),
      );
      await reveal(
        t,
        find.byKey(Key('vm-product-${idOf('Better Than Cheek')}')),
      );
      await t.tap(find.byKey(Key('vm-product-${idOf('Better Than Cheek')}')));
      await settle(t, find.byKey(const Key('vm-selected-blush')));
      expect(find.byKey(const Key('vm-selected-lips')), findsOneWidget);
      expect(find.byKey(const Key('vm-selected-blush')), findsOneWidget);

      await reveal(t, find.byKey(const Key('vm-kind-eyeshadow')));
      await t.tap(find.byKey(const Key('vm-kind-eyeshadow')));
      await settle(t, find.byKey(const Key('vm-no-products')));
      expect(find.byKey(const Key('vm-no-products')), findsOneWidget);
    });

    testWidgets('own colours stay available as a separate mode', (t) async {
      await open(t, productId: berryId());
      await t.tap(find.byKey(const Key('vm-gallery')));
      await settle(t, find.byKey(const Key('vm-photo')));
      await reveal(t, find.byKey(const Key('vm-colour-mode')));
      await t.tap(find.text('Свой цвет').first);
      await t.pump();
      await reveal(t, find.byKey(const Key('vm-zone-lips')));
      expect(find.byKey(const Key('vm-zone-lips')), findsOneWidget);
      expect(find.byKey(const Key('vm-selected-lips')), findsNothing);
      await reveal(t, find.byKey(const Key('vm-colour-mode')));
      await t.tap(find.text('Каталог').first);
      await t.pump();
      await settle(t, find.byKey(const Key('vm-selected-lips')));
      expect(find.byKey(const Key('vm-selected-lips')), findsOneWidget);
    });

    testWidgets(
      'without a product the screen starts with own colours, as before',
      (t) async {
        await open(t);
        expect(find.byKey(const Key('vm-picker')), findsOneWidget);
        expect(find.byKey(const Key('vm-selected-lips')), findsNothing);
        await t.tap(find.byKey(const Key('vm-gallery')));
        await settle(t, find.byKey(const Key('vm-photo')));
        await reveal(t, find.byKey(const Key('vm-zone-lips')));
        expect(find.byKey(const Key('vm-zone-lips')), findsOneWidget);
      },
    );

    testWidgets(
      'a product with no colour data is not shown and says nothing wrong',
      (t) async {
        await open(
          t,
          productId: idOf('Better Than Palette 05 Shade & Shadow Garden'),
        );
        expect(find.byKey(const Key('vm-selected-eyeshadow')), findsNothing);
        expect(find.byKey(const Key('vm-picker')), findsOneWidget);
        expect(find.byKey(const Key('vm-colour-mode')), findsOneWidget);
      },
    );
  });

  group('the shop around the try-on keeps working (offline)', () {
    Future<DatabaseHelper> boot(WidgetTester t) async {
      t.view.physicalSize = const Size(1080, 4200);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(() => t.runAsync(h.close));
      await t.runAsync(() => UserRepository(h).setCurrentUser(1));
      await t.pumpWidget(CosmetixApp(helper: h));
      await pumpUntil(t, find.text('Кабинет'));
      for (var i = 0; i < 8; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
      return h;
    }

    Future<void> openProduct(WidgetTester t, int id) async {
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      nav.pushNamed(AppRoutes.product, arguments: id);
      for (var i = 0; i < 10; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await t.pump(const Duration(milliseconds: 120));
      }
    }

    testWidgets('the Try on button appears only where the colour is known', (
      t,
    ) async {
      await boot(t);
      await openProduct(t, berryId());
      expect(find.byKey(const Key('try-on-button')), findsOneWidget);
      expect(find.byKey(const Key('try-on-unavailable')), findsNothing);
      expect(find.text('Примерить'), findsOneWidget);

      await openProduct(
        t,
        idOf('Better Than Palette 05 Shade & Shadow Garden'),
      );
      expect(find.byKey(const Key('try-on-button')), findsNothing);
      expect(find.byKey(const Key('try-on-unavailable')), findsOneWidget);

      await openProduct(t, idOf('Super Slim Waterproof Mascara'));
      expect(find.byKey(const Key('try-on-button')), findsNothing);
      expect(find.byKey(const Key('try-on-unavailable')), findsNothing);
    });

    testWidgets('favourite and cart survive a trip through the try-on', (
      t,
    ) async {
      final h = await boot(t);
      await openProduct(t, berryId());

      // cart first, then the favourite: a message of the first one would cover
      // the cart bar at the bottom
      await t.tap(find.text('В корзину'));
      for (var i = 0; i < 4; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.tap(find.byIcon(Icons.favorite_border).first);
      for (var i = 0; i < 4; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
      Future<List<Map<String, Object?>>> rows(String sql) => t
          .runAsync(() async => (await h.database).rawQuery(sql, [berryId()]))
          .then((v) => v!);
      expect(
        await rows(
          'SELECT * FROM favorites WHERE user_id = 1 AND product_id = ?',
        ),
        hasLength(1),
      );
      expect(
        await rows(
          'SELECT * FROM cart_items WHERE user_id = 1 AND product_id = ?',
        ),
        hasLength(1),
      );

      // to the try-on and back to the product page
      await t.tap(find.byKey(const Key('try-on-button')));
      for (var i = 0; i < 12; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(find.byKey(const Key('vm-selected-lips')), findsOneWidget);
      await t.tap(find.byKey(Key('vm-open-product-${berryId()}')));
      for (var i = 0; i < 10; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await t.pump(const Duration(milliseconds: 120));
      }
      // the product page again, with its cart control and the filled heart
      expect(find.text('О товаре'), findsWidgets);
      expect(find.byIcon(Icons.favorite), findsWidgets);
      expect(find.byKey(const Key('try-on-button')), findsOneWidget);
      expect(
        await rows(
          'SELECT * FROM favorites WHERE user_id = 1 AND product_id = ?',
        ),
        hasLength(1),
      );
      expect(
        (await rows(
          'SELECT quantity FROM cart_items WHERE user_id = 1 AND product_id = ?',
        )).single['quantity'],
        1,
      );
    });
  });

  test('nothing in all of this used the network', () {
    expect(noNet.attempts, 0);
  });
}

/// The text of the Text widget with [key].
String? tester0(WidgetTester t, Key key) =>
    (t.widget(find.byKey(key)) as Text).data;
