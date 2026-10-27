import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/appearance/appearance.dart';
import 'package:wallet_aps/appearance/appearance_controller.dart';
import 'package:wallet_aps/appearance/appearance_selector.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';

Widget themed(AppearanceController controller, Widget home) => RepaintBoundary(
    key: const Key('appearance-capture-root'),
    child: AppearanceScope(
      controller: controller,
      child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: appearanceThemeData(controller.mode),
              themeAnimationDuration: Duration.zero,
              home: home)),
    ));

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
}

class UnwritablePreferences extends AppearancePreferences {
  UnwritablePreferences() : super(() async => Directory.systemTemp);
  @override
  Future<void> write(AppAppearance value) async =>
      throw const FileSystemException('test');
}

void main() {
  test('Retro preserves every legacy semantic value, stored colour and alpha',
      () {
    final t =
        appearanceThemeData(AppAppearance.retro).extension<AppearanceTheme>()!;
    for (final c in [
      Colors.transparent,
      const Color(0x12456789),
      Colors.white,
      Colors.red
    ]) {
      for (final r in AppearanceRole.values) {
        expect(t.resolve(r, c), c);
      }
      expect(t.objectSurface(c), c);
    }
  });
  for (final mode in [AppAppearance.light, AppAppearance.dark]) {
    test('${mode.name}: readable text and unchanged stored colour IDs', () {
      final t = appearanceThemeData(mode).extension<AppearanceTheme>()!;
      for (final surface in [
        AppearanceRole.canvas,
        AppearanceRole.surface,
        AppearanceRole.header,
        AppearanceRole.selected
      ]) {
        for (final text in [
          AppearanceRole.text,
          AppearanceRole.secondaryText
        ]) {
          expect(
              contrast(t.resolve(text, Colors.black),
                  t.resolve(surface, Colors.white)),
              greaterThanOrEqualTo(4.5),
              reason: '$surface / $text');
        }
      }
      final scheme = t.scheme;
      expect(contrast(scheme.primary, scheme.onPrimary),
          greaterThanOrEqualTo(4.5));
      expect(contrast(scheme.error, scheme.surface), greaterThanOrEqualTo(4.5));
      for (final colour in storedTemplateColorPalette) {
        final id = paletteColorToSpb(colour.id);
        final displayed = t.objectSurface(colour.bg);
        expect(
            contrast(displayed, scheme.onSurface), greaterThanOrEqualTo(4.5));
        expect(paletteColorToSpb(colour.id), id);
        expect(colorById(colour.id).bg, colour.bg);
      }
      const arbitrary = Color(0xff8236ac);
      expect(contrast(t.objectSurface(arbitrary), scheme.onSurface),
          greaterThanOrEqualTo(4.5));
      expect(t.resolve(AppearanceRole.selected, Colors.transparent),
          Colors.transparent);
      expect(t.resolve(AppearanceRole.selected, const Color(0x33367ca8)).a,
          closeTo(0x33 / 255, .001));
    });
  }
  test(
      'preferences: missing, malformed, unknown version and value fall back to Retro',
      () async {
    final temp = Directory.systemTemp.createTempSync('appearance-preference-');
    try {
      final store = AppearancePreferences(() async => temp);
      expect(await store.read(), AppAppearance.retro);
      for (final text in [
        'broken',
        '[]',
        '{"version":2,"appearance":"dark"}',
        '{"version":1,"appearance":"system"}'
      ]) {
        (await store.file).writeAsStringSync(text);
        expect(await store.read(), AppAppearance.retro);
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
  test(
      'preferences: serialized repeated writes survive restart and do not touch vault files',
      () async {
    final temp = Directory.systemTemp.createTempSync('appearance-restart-');
    try {
      final vault = File('${temp.path}/unrelated.swl')
        ..writeAsBytesSync([1, 2, 3, 255]);
      final store = AppearancePreferences(() async => temp);
      final controller = AppearanceController(preferences: store);
      for (var i = 0; i < 8; i++) {
        controller.choose(i.isEven ? AppAppearance.dark : AppAppearance.light);
      }
      await controller.saved;
      expect(controller.error, isNull);
      final restart = AppearanceController(preferences: store);
      await restart.load();
      expect(restart.mode, AppAppearance.light);
      controller.choose(AppAppearance.retro);
      await controller.saved;
      expect(await store.read(), AppAppearance.retro);
      expect(vault.readAsBytesSync(), [1, 2, 3, 255]);
      expect(File('${(await store.file).path}.tmp').existsSync(), isFalse);
      controller.dispose();
      restart.dispose();
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
  test('a write error does not block theme switching or throw into the app',
      () async {
    final c = AppearanceController(preferences: UnwritablePreferences());
    c.choose(AppAppearance.dark);
    await c.saved;
    expect(c.mode, AppAppearance.dark);
    expect(c.error, isNotNull);
    c.choose(AppAppearance.light);
    await c.saved;
    expect(c.mode, AppAppearance.light);
    c.dispose();
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    final size = platform == TargetPlatform.windows
        ? const Size(1280, 900)
        : const Size(360, 800);
    testWidgets(
        '${platform.name}: selector preserves password, caret, focus, keyboard and shell',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final c = AppearanceController();
      final semantics = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(size);
      try {
        await tester.pumpWidget(WalletApsApp(appearance: c));
        await tester.pumpAndSettle();
        final dynamic state = tester.state(find.byType(VaultShell));
        final shell = state;
        final field = find.byKey(const Key('passwordInput'));
        await tester.tap(field);
        await tester.enterText(field, 'Synthetic only!');
        const selection = TextSelection(baseOffset: 2, extentOffset: 7);
        state.passwordController.selection = selection;
        state.setState(() {
          state.showPassword = true;
          state.virtualKeyboardMode = VirtualKeyboardMode.symbols;
        });
        await tester.pumpAndSettle();
        final oldPath = state.selectedVaultTitle;
        for (final mode in [
          AppAppearance.dark,
          AppAppearance.light,
          AppAppearance.retro
        ]) {
          await tester
              .ensureVisible(find.byKey(ValueKey('appearance-${mode.name}')));
          await tester.tap(find.byKey(ValueKey('appearance-${mode.name}')));
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(VaultShell)), same(shell));
          expect(state.passwordController.text, 'Synthetic only!');
          expect(state.passwordController.selection, selection);
          expect(state.passwordFocusNode.hasFocus, isTrue);
          expect(state.virtualKeyboardMode, VirtualKeyboardMode.symbols);
          expect(state.showPassword, isTrue);
          expect(state.unlocked, isFalse);
          expect(state.selectedVaultTitle, oldPath);
          expect(state.message, isNull);
          final data = tester
              .getSemantics(
                  find.byKey(ValueKey('appearanceChoice-${mode.name}')))
              .getSemanticsData();
          expect(data.flagsCollection.isSelected, ui.Tristate.isTrue);
          expect(tester.takeException(), isNull);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(state.unlocked, isFalse);
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        debugDefaultTargetPlatformOverride = null;
        await tester.binding.setSurfaceSize(null);
      }
    });
    for (final isTemplate in [false, true]) {
      testWidgets(
          '${platform.name}: ${isTemplate ? 'template' : 'card'} editor retains route, draft, undo and validation across themes',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final c = AppearanceController();
        await tester.binding.setSurfaceSize(size);
        Object? result;
        try {
          await tester.pumpWidget(themed(
              c,
              Builder(
                  builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () async {
                            result = await showDialog<Object>(
                                context: context,
                                builder: (context) => isTemplate
                                    ? const TemplateEditorDialog()
                                    : ItemEditorDialog(
                                        templates: [builtInTemplates().first],
                                        categories: const []));
                          },
                          child: const Text('open'))))));
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          final editor =
              find.byType(isTemplate ? TemplateEditorDialog : ItemEditorDialog);
          final dynamic draft = tester.state(editor);
          final save = find
              .byKey(Key(isTemplate ? 'templateSaveButton' : 'cardSaveButton'));
          final title = find
              .byKey(Key(isTemplate ? 'templateNameField' : 'cardTitleField'));
          expect(save, findsNothing);
          await tester.enterText(title, 'Тестовый черновик');
          await tester.pumpAndSettle();
          expect(save, findsOneWidget);
          final oldColour = draft.colorId;
          final oldIcon = draft.iconId;
          final oldUndo = (draft.undoHistory as List).length;
          for (final mode in AppAppearance.values) {
            c.choose(mode);
            await tester.pumpAndSettle();
            expect(tester.state(editor), same(draft));
            expect((isTemplate ? draft.name : draft.title).text,
                'Тестовый черновик');
            expect(draft.colorId, oldColour);
            expect(draft.iconId, oldIcon);
            expect((draft.undoHistory as List).length, oldUndo);
            expect(save, findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(result, isNotNull);
          expect(
              isTemplate
                  ? (result as CardTemplate).name
                  : (result as SecretItem).title,
              'Тестовый черновик');
          expect(editor, findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          debugDefaultTargetPlatformOverride = null;
          await tester.binding.setSurfaceSize(null);
        }
      });
    }
  }
  for (final mode in AppAppearance.values) {
    testWidgets(
        '${mode.name}: Enter substring search and blue exact search retain original semantics',
        (tester) async {
      final c = AppearanceController(initial: mode);
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      try {
        await tester
            .pumpWidget(themed(c, const VaultShell(initiallyUnlocked: true)));
        await tester.pumpAndSettle();
        final dynamic state = tester.state(find.byType(VaultShell));
        final template = builtInTemplates().first;
        state.setState(() {
          state.items = [
            SecretItem(
                id: 'search-test',
                templateId: template.id,
                title: 'Почта рабочая',
                category: '',
                colorId: 'template_white',
                values: const {},
                modifiedAt: DateTime.utc(2026))
          ];
        });
        await tester.enterText(
            find.byKey(const Key('spbSearchInput')), 'Почта');
        await tester.pumpAndSettle();
        expect(state.spbExactSearch, isFalse);
        expect(state.spbMatchingCards('Почта'), hasLength(1));
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(state.spbExactSearch, isFalse);
        expect(state.spbMatchingCards('Почта'), hasLength(1));
        await tester.tap(find.byKey(const Key('spbSubmitSearchButton')));
        await tester.pumpAndSettle();
        expect(state.spbExactSearch, isTrue);
        expect(state.spbMatchingCards('Почта'), isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        await tester.binding.setSurfaceSize(null);
      }
    });
  }
  testWidgets(
      'theme changes never mutate a synthetic open SWL, dirty flag, IDs or session history',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('appearance-swl-');
    final path = '${temp.path}/test.swl';
    final wallet = SpbWalletDatabase.create(path, 'synthetic-password');
    wallet.savePasswordHint('synthetic hint');
    wallet.createCategory('Only test', '');
    final c = AppearanceController();
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    try {
      await tester
          .pumpWidget(themed(c, const VaultShell(initiallyUnlocked: true)));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(VaultShell));
      state.setState(() {
        state.spbWallet = wallet;
        state.applySpbSnapshot(wallet.loadSnapshot());
      });
      await tester.pumpAndSettle();
      final before = File(path).readAsBytesSync();
      final dirty = state.vaultDirty, pending = state.spbWritePending;
      final history = List<Object>.from(state.sessionUndoHistory);
      final categories = Set<String>.from(state.categoryPaths);
      final ids = Map<String, String>.from(state.categoryIdsByPath);
      final trash = List<Object>.from(state.sessionTrash);
      for (final mode in [
        ...AppAppearance.values,
        ...AppAppearance.values.reversed
      ]) {
        c.choose(mode);
        await tester.pumpAndSettle();
        expect(state.spbWallet, same(wallet));
        expect(state.vaultDirty, dirty);
        expect(state.spbWritePending, pending);
        expect(state.sessionUndoHistory, history);
        expect(state.categoryPaths, categories);
        expect(state.categoryIdsByPath, ids);
        expect(state.sessionTrash, trash);
        expect(File(path).readAsBytesSync(), before);
      }
      state.spbWallet = null;
      wallet.close(flush: false);
      final reopened = SpbWalletDatabase.open(path, 'synthetic-password');
      expect(reopened.loadPasswordHint(), 'synthetic hint');
      reopened.close(flush: false);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await tester.binding.setSurfaceSize(null);
      temp.deleteSync(recursive: true);
    }
  });
  testWidgets(
      'selector fixed colours and accessible controls at enlarged narrow text',
      (tester) async {
    final c = AppearanceController();
    await tester.binding.setSurfaceSize(const Size(320, 900));
    try {
      await tester.pumpWidget(themed(
          c,
          const MediaQuery(
              data: MediaQueryData(
                  size: Size(320, 900), textScaler: TextScaler.linear(1.6)),
              child: Scaffold(body: AppearanceSelector()))));
      await tester.pumpAndSettle();
      for (final mode in AppAppearance.values) {
        final finder = find.byKey(ValueKey('appearance-${mode.name}'));
        expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
        final button = tester.widget<TextButton>(finder);
        expect(button.style!.backgroundColor!.resolve({}),
            AppearanceSelector.backgrounds[mode.index]);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await tester.binding.setSurfaceSize(null);
    }
  });
}
