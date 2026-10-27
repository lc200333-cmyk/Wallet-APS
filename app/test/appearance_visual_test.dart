import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/appearance/appearance.dart';
import 'package:wallet_aps/appearance/appearance_controller.dart';

const captureMode = String.fromEnvironment('APPEARANCE_CAPTURE');

Future<void> captureAppearance(WidgetTester tester, String name) async {
  if (captureMode.isEmpty) return;
  final root = find.byKey(const Key('appearance-capture-root'));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      root.evaluate().isNotEmpty ? root : find.byType(RepaintBoundary).first);
  final timestamps = find.byKey(const Key('cardEditorModifiedAt'));
  final timestampRects = timestamps
      .evaluate()
      .map((element) => tester
          .getRect(find.byElementPredicate((candidate) => candidate == element))
          .shift(-boundary.localToGlobal(Offset.zero)))
      .toList();
  await tester.runAsync(() async {
    final raster = await boundary.toImage();
    final png = await raster.toByteData(format: ui.ImageByteFormat.png);
    raster.dispose();
    final directory = Directory('../.codex/appearance-$captureMode');
    await directory.create(recursive: true);
    final bytes = png!.buffer.asUint8List();
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
    if (captureMode != 'baseline') {
      final original = File('../.codex/appearance-baseline/$name.png');
      if (!original.existsSync()) return;
      final before = img.decodePng(original.readAsBytesSync())!;
      final after = img.decodePng(bytes)!;
      expect(after.width, before.width);
      expect(after.height, before.height);
      // Only the actual timestamp Text bounds are masked, not its header or
      // any other UI. The baseline was captured before implementation.
      var mismatched = 0;
      for (var y = 0; y < before.height; y++) {
        for (var x = 0; x < before.width; x++) {
          if (timestampRects.any(
              (rect) => rect.contains(Offset(x.toDouble(), y.toDouble())))) {
            continue;
          }
          if (before.getPixel(x, y) != after.getPixel(x, y)) {
            final a = before.getPixel(x, y);
            final b = after.getPixel(x, y);
            if (a.r != b.r || a.g != b.g || a.b != b.b || a.a != b.a) {
              mismatched++;
            }
          }
        }
      }
      expect(mismatched, 0,
          reason: 'Retro must retain the original pixels: $name');
    }
  });
}

Future<void> loadAppearanceFonts() async {
  if (captureMode.isEmpty || !Platform.isWindows) return;
  final system = Platform.environment['WINDIR'];
  if (system == null) return;
  final bytes = File('$system/Fonts/segoeui.ttf').readAsBytesSync();
  for (final family in ['Roboto', 'Segoe UI']) {
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  }
  var runtime = File(Platform.resolvedExecutable).parent;
  while (runtime.parent.path != runtime.path) {
    final font = File(
        '${runtime.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (font.existsSync()) {
      await (FontLoader('MaterialIcons')
            ..addFont(
                Future.value(ByteData.sublistView(font.readAsBytesSync()))))
          .load();
      break;
    }
    runtime = runtime.parent;
  }
}

void main() {
  setUpAll(loadAppearanceFonts);
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('appearance visual baseline ${platform.name}', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.binding.setSurfaceSize(platform == TargetPlatform.android
          ? const Size(360, 800)
          : const Size(1280, 900));
      try {
        await tester.pumpWidget(const WalletApsApp());
        await tester.pumpAndSettle();
        final theme =
            tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
        final template = builtInTemplates().first;
        final item = SecretItem(
            id: 'visual-only',
            templateId: template.id,
            title: 'Тестовая запись',
            category: '',
            colorId: template.colorId,
            values: const {},
            modifiedAt: DateTime.utc(2026));
        final views = <String, Widget>{
          'login': const VaultShell(),
          'workspace': const VaultShell(initiallyUnlocked: true),
          'card': ItemEditorDialog(templates: [template], categories: const []),
          'template': const TemplateEditorDialog(),
          'folder': const CategoryEditorDialog(
              editing: false, initialName: '', initialIconId: 'folder'),
          'card-preview': CardPreviewDialog(item: item, template: template),
          'template-preview': TemplatePreviewDialog(template: template),
        };
        for (final entry in views.entries) {
          for (final mode in captureMode == 'all'
              ? AppAppearance.values
              : [AppAppearance.retro]) {
            final controller = AppearanceController(initial: mode);
            final viewTheme =
                mode == AppAppearance.retro ? theme : appearanceThemeData(mode);
            await tester.pumpWidget(AppearanceScope(
                controller: controller,
                child: MaterialApp(theme: viewTheme, home: entry.value)));
            await tester.pumpAndSettle();
            await captureAppearance(tester,
                '${mode == AppAppearance.retro ? '' : '${mode.name}-'}${platform.name}-${entry.key}');
            if (entry.key == 'login') {
              final dynamic state = tester.state(find.byType(VaultShell));
              for (final keyboard in VirtualKeyboardMode.values) {
                state.setState(() {
                  state.virtualKeyboardMode = keyboard;
                });
                await tester.pumpAndSettle();
                await captureAppearance(tester,
                    '${mode.name}-${platform.name}-keyboard-${keyboard.name}');
              }
              state.setState(() {
                state.message = 'Тестовая ошибка пароля';
                state.loginHintVisible = true;
              });
              await tester.pumpAndSettle();
              await captureAppearance(
                  tester, '${mode.name}-${platform.name}-login-error');
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            controller.dispose();
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
        await tester.binding.setSurfaceSize(null);
      }
    });
  }
}
