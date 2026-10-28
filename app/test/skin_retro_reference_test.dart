import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:wallet_aps/main.dart';

// Retro must stay pixel-identical when Light and Dark skins are added. These
// references were rendered from the unchanged interface before the skin work
// started. Regenerate them only for an intentional Retro change:
//   flutter test test/skin_retro_reference_test.dart --dart-define=UPDATE_SKIN_GOLDENS=true
const _update = bool.fromEnvironment('UPDATE_SKIN_GOLDENS');
// The references are Windows renderings; other hosts rasterise gradients
// slightly differently, so the pixel comparison runs on Windows only.
final _skipReason = Platform.isWindows
    ? null
    : 'Retro references are rendered on Windows (pixel-exact comparison)';
const _shotKey = Key('skinReferenceShot');
const _directory = 'test/goldens/skin_retro';

Future<void> _settleImages(WidgetTester tester) async {
  for (var pass = 0; pass < 3; pass++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();
  }
}

Future<image.Image> _capture(WidgetTester tester, {Rect? crop}) async {
  await _settleImages(tester);
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  late image.Image result;
  await tester.runAsync(() async {
    final rendered = await boundary.toImage(pixelRatio: 1);
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    rendered.dispose();
    result = image.Image.fromBytes(
      width: rendered.width,
      height: rendered.height,
      bytes: bytes!.buffer,
      order: image.ChannelOrder.rgba,
      numChannels: 4,
    );
  });
  if (crop == null) return result;
  return image.copyCrop(
    result,
    x: crop.left.round(),
    y: crop.top.round(),
    width: crop.width.round(),
    height: crop.height.round(),
  );
}

Future<void> _expectReference(
  WidgetTester tester,
  String name, {
  Rect? crop,
}) async {
  final actual = await _capture(tester, crop: crop);
  final file = File('$_directory/$name.png');
  if (_update) {
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(image.encodePng(actual));
    return;
  }
  expect(file.existsSync(), isTrue, reason: 'missing Retro reference $name');
  final expected = image.decodePng(file.readAsBytesSync())!;
  expect((actual.width, actual.height), (expected.width, expected.height),
      reason: '$name size');
  var different = 0;
  var maxDelta = 0;
  var left = expected.width, top = expected.height, right = -1, bottom = -1;
  for (var y = 0; y < expected.height; y++) {
    for (var x = 0; x < expected.width; x++) {
      final a = actual.getPixel(x, y);
      final e = expected.getPixel(x, y);
      final delta = [
        (a.r - e.r).abs(),
        (a.g - e.g).abs(),
        (a.b - e.b).abs(),
        (a.a - e.a).abs(),
      ].reduce((p, q) => p > q ? p : q).toInt();
      if (delta > 0) {
        different++;
        if (delta > maxDelta) maxDelta = delta;
        if (x < left) left = x;
        if (y < top) top = y;
        if (x > right) right = x;
        if (y > bottom) bottom = y;
      }
    }
  }
  if (different > 0) {
    debugPrint('$name: $different px, max delta $maxDelta, '
        'box ($left,$top)-($right,$bottom)');
  }
  if (different > 0) {
    File('$_directory/failures/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(image.encodePng(actual));
  }
  expect(different, 0, reason: '$name differs in $different pixels');
}

Future<dynamic> _pumpApp(
  WidgetTester tester, {
  required Size size,
  required TargetPlatform platform,
  bool unlocked = true,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    const RepaintBoundary(key: _shotKey, child: WalletApsApp()),
  );
  await tester.pumpAndSettle();
  final dynamic state = tester.state(find.byType(VaultShell));
  if (!unlocked) return state;
  final CardTemplate template = state.templates.first as CardTemplate;
  final cards = <SecretItem>[
    for (var index = 0; index < 12; index++)
      SecretItem(
        id: 'reference-$index',
        templateId: template.id,
        title: index == 0
            ? 'A long card caption that wraps onto two lines'
            : 'Card ${index.toString().padLeft(2, '0')}',
        category: index < 8 ? '' : 'Finance',
        colorId: template.colorId,
        values: index == 1
            ? {for (final field in template.fields) field.id: 'value-$index'}
            : const {},
        modifiedAt: DateTime(2026),
      ),
    SecretItem(
      id: 'reference-nested',
      templateId: template.id,
      title: 'Nested card',
      category: 'Finance / Banks',
      colorId: template.colorId,
      values: const {},
      modifiedAt: DateTime(2026),
    ),
  ];
  state.setState(() {
    state.unlocked = true;
    state.items = cards;
    state.itemsById = {for (final card in cards) card.id: card};
    state.categoryPaths = <String>{'Finance', 'Finance / Banks', 'Personal'};
    state.recentlyOpenedItemIds.addAll(cards.take(3).map((item) => item.id));
  });
  await tester.pumpAndSettle();
  return state;
}

void _skinTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }, skip: _skipReason != null);
}

void main() {
  _skinTest('Retro password window', (tester) async {
    // The reference was rendered at 800x900 with the original 590 px window,
    // centred at y = 155. The window is now 52 px taller for the skin row; a
    // 952 px surface keeps it at the same absolute position, so gradient
    // dithering (which depends on device coordinates) stays comparable.
    await _pumpApp(
      tester,
      size: const Size(800, 952),
      platform: TargetPlatform.windows,
      unlocked: false,
    );
    final window = tester.getRect(find.byKey(const Key('passwordWindow')));
    // Only the original area is compared; the skin row is added below it.
    await _expectReference(
      tester,
      'password_window',
      crop: Rect.fromLTWH(window.left, window.top, window.width, 590),
    );
  });

  _skinTest('Retro wide cards workspace', (tester) async {
    await _pumpApp(
      tester,
      size: const Size(1280, 769.5),
      platform: TargetPlatform.windows,
    );
    await _expectReference(tester, 'wide_cards');
  });

  _skinTest('Retro wide folder and templates', (tester) async {
    final dynamic state = await _pumpApp(
      tester,
      size: const Size(1280, 800),
      platform: TargetPlatform.windows,
    );
    state.openSpbFolder('Finance');
    await tester.pumpAndSettle();
    await _expectReference(tester, 'wide_folder');
    state.showSpbTemplatesMode();
    await tester.pumpAndSettle();
    await _expectReference(tester, 'wide_templates');
  });

  _skinTest('Retro narrow Android panes', (tester) async {
    final dynamic state = await _pumpApp(
      tester,
      size: const Size(412, 915),
      platform: TargetPlatform.android,
    );
    await _expectReference(tester, 'narrow_pane0');
    state.setState(() => state.mobilePane = 1);
    await tester.pumpAndSettle();
    await _expectReference(tester, 'narrow_pane1');
    state.setState(() => state.mobilePane = 2);
    await tester.pumpAndSettle();
    await _expectReference(tester, 'narrow_pane2');
  });

  _skinTest('Retro card preview and editor', (tester) async {
    final dynamic state = await _pumpApp(
      tester,
      size: const Size(1280, 800),
      platform: TargetPlatform.windows,
    );
    final SecretItem item = state.items[1] as SecretItem;
    state.openCardPreviewDialog(item);
    await tester.pumpAndSettle();
    await _expectReference(tester, 'card_preview');
    Navigator.of(tester.element(find.byKey(const Key('cardPreviewTitle'))))
        .pop();
    await tester.pumpAndSettle();
    state.openItemDialog(item: item);
    await tester.pumpAndSettle();
    await _expectReference(tester, 'card_editor');
  });

  _skinTest('Retro narrow card preview', (tester) async {
    final dynamic state = await _pumpApp(
      tester,
      size: const Size(412, 915),
      platform: TargetPlatform.android,
    );
    state.openCardPreviewDialog(state.items[1] as SecretItem);
    await tester.pumpAndSettle();
    await _expectReference(tester, 'narrow_card_preview');
  });

  _skinTest('Retro change password dialog', (tester) async {
    final dynamic state = await _pumpApp(
      tester,
      size: const Size(1280, 800),
      platform: TargetPlatform.windows,
    );
    state.openChangePasswordDialog();
    await tester.pumpAndSettle();
    await _expectReference(tester, 'change_password');
  });
}
