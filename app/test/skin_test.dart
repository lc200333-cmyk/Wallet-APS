import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/ui/skin/app_skin.dart';

Directory _useTemporarySettings() {
  final directory = Directory.systemTemp.createTempSync('wallet-aps-skin-');
  AppSkinStore.directoryProvider = () async => directory;
  addTearDown(() {
    AppSkinStore.directoryProvider = null;
    appSkin.value = AppSkin.retro;
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return directory;
}

File _settingsFile(Directory directory) =>
    File('${directory.path}${Platform.pathSeparator}${AppSkinStore.fileName}');

/// The skin is saved with real file I/O outside the fake test clock.
Future<Object?> _waitForStoredSkin(
  WidgetTester tester,
  Directory directory,
  String expected,
) async {
  Object? stored;
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    // Also advances the fake clock for the store's brief rename retries.
    await tester.pump(const Duration(milliseconds: 30));
    final file = _settingsFile(directory);
    if (file.existsSync()) {
      try {
        stored = (jsonDecode(file.readAsStringSync()) as Map)['skin'];
      } on FormatException {
        stored = null;
      } on FileSystemException {
        // The application is replacing the file at this moment.
        stored = null;
      }
      if (stored == expected) break;
    }
  }
  return stored;
}

void main() {
  group('skin storage', () {
    test('missing file yields the default Dark skin', () async {
      _useTemporarySettings();
      expect(await AppSkinStore.load(), AppSkin.dark);
    });

    test('stored Retro skin is read back', () async {
      final directory = _useTemporarySettings();
      _settingsFile(directory)
          .writeAsStringSync('{"skin":"retro","version":2}');
      expect(await AppSkinStore.load(), AppSkin.retro);
    });

    test('a choice stored by an older version opens Dark once', () async {
      final directory = _useTemporarySettings();
      _settingsFile(directory).writeAsStringSync('{"skin":"retro"}');
      expect(await AppSkinStore.load(), AppSkin.dark);
      await AppSkinStore.save(AppSkin.retro);
      expect(await AppSkinStore.load(), AppSkin.retro);
    });

    test('garbage and unknown values yield Dark', () async {
      final directory = _useTemporarySettings();
      final file = _settingsFile(directory);
      for (final content in [
        'not json',
        '[]',
        '{"skin":"neon","version":2}',
        '{"skin":3,"version":2}',
        '{"skin":"light","version":1}',
        '',
      ]) {
        file.writeAsStringSync(content);
        expect(await AppSkinStore.load(), AppSkin.dark, reason: content);
      }
    });

    test('saving replaces the file atomically and leaves no temporary file',
        () async {
      final directory = _useTemporarySettings();
      await AppSkinStore.save(AppSkin.light);
      expect(
        jsonDecode(_settingsFile(directory).readAsStringSync()),
        {'skin': 'light', 'version': 2},
      );
      await AppSkinStore.save(AppSkin.dark);
      expect(
        jsonDecode(_settingsFile(directory).readAsStringSync()),
        {'skin': 'dark', 'version': 2},
      );
      expect(
        directory.listSync().map((entry) => entry.uri.pathSegments.last),
        [AppSkinStore.fileName],
      );
    });
  });

  group('password window skin selector', () {
    testWidgets('window is 562 x 642, and 562 x 702 with a message',
        (tester) async {
      _useTemporarySettings();
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final skin in AppSkin.values) {
        appSkin.value = skin;
        await tester.pumpWidget(const WalletApsApp());
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const Key('passwordWindow'))),
          const Size(562, 642),
          reason: skin.name,
        );
        final dynamic state = tester.state(find.byType(VaultShell));
        state.setState(() => state.message = 'Ошибка');
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const Key('passwordWindow'))),
          const Size(562, 702),
          reason: skin.name,
        );
        expect(find.byKey(const Key('skinSelector')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets(
        'switching keeps the typed password, focus and keyboard mode, '
        'and persists the choice', (tester) async {
      final directory = _useTemporarySettings();
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const WalletApsApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('keypadModeLowercase')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('passwordInput')), 'abc');
      await tester.pumpAndSettle();

      for (final (key, skin) in [
        (const Key('skinLightButton'), AppSkin.light),
        (const Key('skinDarkButton'), AppSkin.dark),
        (const Key('skinRetroButton'), AppSkin.retro),
      ]) {
        await tester.tap(find.byKey(key));
        await tester.pumpAndSettle();
        expect(appSkin.value, skin);
        final context = tester.element(find.byKey(const Key('passwordInput')));
        expect(WalletSkinTokens.of(context).skin, skin);
        final field = tester.widget<TextField>(
          find.byKey(const Key('passwordInput')),
        );
        expect(field.controller!.text, 'abc');
        expect(field.focusNode!.hasFocus, isTrue);
        final dynamic state = tester.state(find.byType(VaultShell));
        expect(state.virtualKeyboardMode.toString(), contains('lowercase'));
        expect(
          await _waitForStoredSkin(tester, directory, skin.name),
          skin.name,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('selected skin button is announced as selected',
        (tester) async {
      _useTemporarySettings();
      appSkin.value = AppSkin.light;
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const WalletApsApp());
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Тема: Светлая')),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          label: 'Тема: Светлая',
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Тема: Ретро')),
        matchesSemantics(
          isButton: true,
          hasSelectedState: true,
          label: 'Тема: Ретро',
        ),
      );
      handle.dispose();
    });
  });

  group('skin tokens', () {
    test('text roles reach WCAG AA contrast on their backgrounds', () {
      for (final t in [WalletSkinTokens.light, WalletSkinTokens.dark]) {
        final pairs = <String, (Color, Color)>{
          'onSurface/bg': (t.onSurface, t.bg),
          'onSurface/surface': (t.onSurface, t.surface),
          'onSurfaceVariant/surface': (t.onSurfaceVariant, t.surface),
          'onSurfaceVariant/bg': (t.onSurfaceVariant, t.bg),
          'onPrimary/primary': (t.onPrimary, t.primary),
          'onPrimaryContainer/primaryContainer': (
            t.onPrimaryContainer,
            t.primaryContainer
          ),
          'onSelection/selection': (t.onSelection, t.selection),
          'error/surface': (t.error, t.surface),
          'onError/error': (t.onError, t.error),
          'onWarningContainer/warningContainer': (
            t.onWarningContainer,
            t.warningContainer
          ),
          'onTooltip/tooltip': (t.onTooltip, t.tooltip),
          'onSnackBar/snackBar': (t.onSnackBar, t.snackBar),
        };
        for (final entry in pairs.entries) {
          expect(
            contrastRatio(entry.value.$1, entry.value.$2),
            greaterThanOrEqualTo(4.5),
            reason: '${t.skin.name} ${entry.key}',
          );
        }
      }
    });

    test('palette glyphs reach 3:1 against their tiles', () {
      for (final t in [WalletSkinTokens.light, WalletSkinTokens.dark]) {
        for (final entry in {...t.palette, 'folder': t.folderTile}.entries) {
          expect(
            contrastRatio(entry.value.icon, entry.value.tile),
            greaterThanOrEqualTo(3),
            reason: '${t.skin.name} ${entry.key}',
          );
        }
      }
    });

    test('custom colours fall back to readable glyphs', () {
      for (final t in [WalletSkinTokens.light, WalletSkinTokens.dark]) {
        for (final color in [
          const Color(0xffffff00),
          const Color(0xff000000),
          const Color(0xff808080),
          const Color(0xffffffff),
        ]) {
          final pair = t.customTile(color);
          expect(contrastRatio(pair.icon, pair.tile), greaterThanOrEqualTo(3),
              reason: '${t.skin.name} $color');
        }
      }
    });

    testWidgets('a widget tree without the extension resolves to Retro',
        (tester) async {
      late WalletSkinTokens tokens;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) {
            tokens = WalletSkinTokens.of(context);
            return const SizedBox.shrink();
          }),
        ),
      );
      expect(tokens.isRetro, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
