import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/ui/skin/app_skin.dart';

// Manual screenshot tool for reviewing the three skins with real fonts.
// It is skipped unless explicitly enabled:
//   flutter test test/skin_preview_test.dart --dart-define=SKIN_PREVIEW=true
//     --dart-define=SKIN_FONT_DIR=<flutter>/bin/cache/artifacts/material_fonts
// Images are written to ../.codex/skin-preview (ignored by Git). Synthetic
// data only.
const _enabled = bool.fromEnvironment('SKIN_PREVIEW');
const _fontDir = String.fromEnvironment('SKIN_FONT_DIR');
const _shotKey = Key('skinPreviewShot');

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    var added = false;
    for (final path in files) {
      final file = File(path);
      if (!file.existsSync()) continue;
      loader
          .addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      added = true;
    }
    if (added) await loader.load();
  }

  const windows = r'C:\Windows\Fonts';
  await family('Segoe UI', [
    '$windows\\segoeui.ttf',
    '$windows\\segoeuib.ttf',
    '$windows\\seguisb.ttf',
  ]);
  await family('Roboto', [
    '$_fontDir/roboto-regular.ttf',
    '$_fontDir/roboto-medium.ttf',
    '$_fontDir/roboto-bold.ttf',
  ]);
  await family('MaterialIcons', ['$_fontDir/materialicons-regular.otf']);
}

Future<void> _shoot(
  WidgetTester tester,
  String name, {
  bool settle = true,
}) async {
  for (var pass = 0; pass < 3; pass++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    // A loading spinner never settles; pumpAndSettle would then advance the
    // fake clock past the inactivity lock.
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('../.codex/skin-preview/$name.png')
      ..parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<dynamic> _pump(
  WidgetTester tester,
  AppSkin skin, {
  required Size size,
  required TargetPlatform platform,
  bool unlocked = true,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  appSkin.value = skin;
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
  final List<CardTemplate> templates =
      (state.templates as List).cast<CardTemplate>();
  CardTemplate templateNamed(String part) => templates.firstWhere(
        (template) => template.name.contains(part),
        orElse: () => templates.first,
      );
  final web = templateNamed('Пароль');
  final card = templateNamed('карта');
  final note = templateNamed('замет');
  SecretItem item(String id, String title, String category, CardTemplate t,
          [Map<String, String> values = const {}]) =>
      SecretItem(
        id: id,
        templateId: t.id,
        title: title,
        category: category,
        colorId: t.colorId,
        values: values,
        modifiedAt: DateTime(2026, 10, 25, 14, 32),
      );
  final cards = <SecretItem>[
    item('p-1', 'Интернет-банк', 'Финансы', web, {
      for (final field in web.fields)
        field.id: field.type == 'password'
            ? 'k7#Vq!2mR9z@Lp4'
            : field.type == 'url'
                ? 'online.bank.example'
                : 'ivan.petrov',
    }),
    item('p-2', 'Карта Visa · основная', 'Финансы', card),
    item('p-3', 'Брокерский счёт', 'Финансы', web),
    item('p-4', 'Налоговый кабинет', 'Финансы', web),
    item('p-5', 'Wi-Fi Дом', 'Личное', web),
    item('p-6', 'Личная почта', 'Личное', web),
    item('p-7', 'Кодовое слово', '', note),
    item('p-8', 'Сервер проекта', 'Работа / Серверы', web),
    item('p-9', 'Банк-клиент', 'Финансы / Банки', web),
  ];
  state.setState(() {
    state.unlocked = true;
    state.items = cards;
    state.itemsById = {for (final card in cards) card.id: card};
    state.categoryPaths = <String>{
      'Личное',
      'Работа',
      'Работа / Серверы',
      'Финансы',
      'Финансы / Банки',
      'Документы',
    };
    state.recentlyOpenedItemIds.addAll(['p-1', 'p-5', 'p-6']);
  });
  await tester.pumpAndSettle();
  return state;
}

void _preview(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    // Real shadows make the review images match the running application.
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
      debugDefaultTargetPlatformOverride = null;
      appSkin.value = AppSkin.retro;
    }
  }, skip: !_enabled);
}

void main() {
  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });

  for (final skin in AppSkin.values) {
    final s = skin.name;
    _preview('$s password window', (tester) async {
      await _pump(
        tester,
        skin,
        size: const Size(600, 700),
        platform: TargetPlatform.windows,
        unlocked: false,
      );
      await _shoot(tester, '${s}_password');
    });

    _preview('$s wide workspace', (tester) async {
      final dynamic state = await _pump(
        tester,
        skin,
        size: const Size(1280, 769.5),
        platform: TargetPlatform.windows,
      );
      await _shoot(tester, '${s}_wide_root');
      state.openSpbFolder('Финансы');
      await tester.pumpAndSettle();
      await _shoot(tester, '${s}_wide_folder');
      state.showSpbTemplatesMode();
      await tester.pumpAndSettle();
      await _shoot(tester, '${s}_wide_templates');
      state.showSpbIconsMode();
      await tester.pump(const Duration(milliseconds: 100));
      await _shoot(tester, '${s}_wide_icons', settle: false);
    });

    _preview('$s wide dialogs', (tester) async {
      final dynamic state = await _pump(
        tester,
        skin,
        size: const Size(1280, 800),
        platform: TargetPlatform.windows,
      );
      final SecretItem first = state.items.first as SecretItem;
      state.openCardPreviewDialog(first);
      await tester.pumpAndSettle();
      await _shoot(tester, '${s}_wide_card_preview');
      Navigator.of(tester.element(find.byKey(const Key('cardPreviewTitle'))))
          .pop();
      await tester.pumpAndSettle();
      state.openItemDialog(item: first);
      await tester.pumpAndSettle();
      await _shoot(tester, '${s}_wide_card_editor');
      Navigator.of(tester.element(find.byKey(const Key('cardSaveButton'))))
          .pop();
      await tester.pumpAndSettle();
      state.openChangePasswordDialog();
      await tester.pumpAndSettle();
      await _shoot(tester, '${s}_wide_change_password');
    });

    _preview('$s narrow phone', (tester) async {
      final dynamic state = await _pump(
        tester,
        skin,
        size: const Size(412, 915),
        platform: TargetPlatform.android,
      );
      await _shoot(tester, '${s}_narrow_root');
      state.openSpbFolder('Финансы');
      await tester.pumpAndSettle();
      await _shoot(tester, '${s}_narrow_folder');
      state.showSpbTemplatesMode();
      await tester.pumpAndSettle();
      await _shoot(tester, '${s}_narrow_templates');
      state.showSpbIconsMode();
      await tester.pump(const Duration(milliseconds: 100));
      await _shoot(tester, '${s}_narrow_icons', settle: false);
      state.showSpbCardsMode();
      state.setState(() => state.modernVaultTabOpen = true);
      await tester.pump(const Duration(milliseconds: 100));
      await _shoot(tester, '${s}_narrow_vault', settle: false);
    });

    for (final (layout, size, platform) in [
      ('wide', const Size(1280, 800), TargetPlatform.windows),
      ('narrow', const Size(412, 915), TargetPlatform.android),
    ]) {
      _preview('$s $layout dialog gallery', (tester) async {
        final dynamic state = await _pump(
          tester,
          skin,
          size: size,
          platform: platform,
        );
        void popTop() => Navigator.of(
              tester.element(find.byType(VaultShell)),
              rootNavigator: true,
            ).maybePop();
        final dynamic root = state.buildCategoryTree(
          state.items,
          includeAllCategories: true,
        );
        final dynamic folder = state.categoryNodeAt(root, 'Финансы');
        final List<CardTemplate> templates =
            (state.templates as List).cast<CardTemplate>();
        final steps = <String, void Function()>{
          'folder_editor': () =>
              state.openCategoryEditorDialog(folder: null, parentPath: ''),
          'folder_delete': () => state.confirmDeleteCategory(folder),
          'template_preview': () => state.openTemplatePreview(templates[1]),
          'template_editor': () =>
              state.openTemplateDialog(template: templates[1]),
          'move_target': () => state.showMoveTargetDialog(initialPath: ''),
          'export_password': () => state.askSpbExportPassword(),
        };
        for (final entry in steps.entries) {
          entry.value();
          await tester.pumpAndSettle();
          await _shoot(tester, '${s}_${layout}_${entry.key}');
          popTop();
          await tester.pumpAndSettle();
        }
        state.showInactivityWarning();
        await tester.pump(const Duration(milliseconds: 300));
        await _shoot(tester, '${s}_${layout}_inactivity', settle: false);
      });
    }

    _preview('$s narrow card', (tester) async {
      final dynamic state = await _pump(
        tester,
        skin,
        size: const Size(412, 915),
        platform: TargetPlatform.android,
      );
      final SecretItem first = state.items.first as SecretItem;
      state.openCardPreviewDialog(first);
      await tester.pumpAndSettle();
      await _shoot(tester, '${s}_narrow_card_preview');
      Navigator.of(tester.element(find.byKey(const Key('cardPreviewTitle'))))
          .pop();
      await tester.pumpAndSettle();
      state.openItemDialog(item: first);
      await tester.pumpAndSettle();
      await _shoot(tester, '${s}_narrow_card_editor');
    });
  }
}
