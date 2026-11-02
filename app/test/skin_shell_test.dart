import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/app_version.dart';
import 'package:wallet_aps/ui/skin/app_skin.dart';
import 'package:wallet_aps/widgets/context_menu_label.dart';

// Shell construction and completeness checks for the three skins (task
// section 14.1, items 4-6 and 8). Synthetic in-memory data only.

enum _Layout {
  narrow(Size(412, 915), TargetPlatform.android),
  wide(Size(1280, 800), TargetPlatform.windows),
  tablet(Size(1280, 800), TargetPlatform.android);

  const _Layout(this.size, this.platform);

  final Size size;
  final TargetPlatform platform;

  bool get isNarrow => this == _Layout.narrow;
}

Future<dynamic> _pumpShell(
  WidgetTester tester,
  AppSkin skin,
  _Layout layout,
) async {
  debugDefaultTargetPlatformOverride = layout.platform;
  appSkin.value = skin;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = layout.size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(const WalletApsApp());
  await tester.pumpAndSettle();
  final dynamic state = tester.state(find.byType(VaultShell));
  final CardTemplate template = (state.templates as List).first as CardTemplate;
  SecretItem card(String id, String title, String category) => SecretItem(
        id: id,
        templateId: template.id,
        title: title,
        category: category,
        colorId: template.colorId,
        values: const {},
        modifiedAt: DateTime(2026, 10, 25),
      );
  final cards = [
    card('s-root', 'Root card', ''),
    card('s-fin', 'Finance card', 'Finance'),
    card('s-bank', 'Bank card', 'Finance / Banks'),
  ];
  state.setState(() {
    state.unlocked = true;
    state.items = cards;
    state.itemsById = {for (final item in cards) item.id: item};
    state.categoryPaths = <String>{'Finance', 'Finance / Banks', 'Personal'};
    state.recentlyOpenedItemIds.addAll(['s-root', 's-fin']);
  });
  await tester.pumpAndSettle();
  return state;
}

/// Runs a body and resets debug state inside the test (the framework checks
/// foundation variables before tearDown runs).
void _skinTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      appSkin.value = AppSkin.retro;
    }
  });
}

/// Pumps without settling; the icon library spinner never settles and
/// pumpAndSettle would advance the fake clock past the inactivity lock.
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

List<String> _taskLabels(dynamic state) => [
      for (final task in state.spbTasksForCurrentMode() as List)
        (task as (Widget, String, VoidCallback)).$2,
    ];

void main() {
  for (final skin in AppSkin.values) {
    for (final layout in _Layout.values) {
      _skinTest('${skin.name} ${layout.name}: central icon creation menus',
          (tester) async {
        var clipboardReads = 0;
        const channel = MethodChannel('wallet_aps/window');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
            (call) async {
          if (call.method == 'readClipboardImage') clipboardReads++;
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));
        final dynamic state = await _pumpShell(tester, skin, layout);
        state.showSpbIconsMode();
        state.setState(() => state.mobilePane = 1);
        await _pumpFrames(tester);
        final area = tester
            .getRect(find.byKey(const Key('spbIconWorkspaceCreationTarget')));
        await tester.tapAt(area.topCenter + const Offset(0, 2));
        await _pumpFrames(tester);
        void expectActions() {
          expect(find.byType(BottomSheet), findsNothing);
          final entries = tester
              .widgetList<PopupMenuItem<String>>(
                  find.byType(PopupMenuItem<String>))
              .take(3);
          expect(entries.map((entry) => entry.value),
              ['folder', 'upload', 'paste']);
          expect(
              entries.map((entry) => (entry.child as ContextMenuLabel).label), [
            'Создать папку',
            'Загрузить иконку из файла',
            'Вставить иконку из буфера обмена'
          ]);
        }

        expectActions();
        await tester.tap(find.byKey(const Key('pasteIconWorkspaceAction')));
        await _pumpFrames(tester);
        expect(clipboardReads, 1);
        unawaited(state.showManagedIconMenu('spb://synthetic', area.center)
            as Future<void>);
        await _pumpFrames(tester);
        expectActions();
        expect(find.byKey(const Key('deleteManagedIconContextAction')),
            findsOneWidget);
        expect(find.textContaining('Переместить в'), findsWidgets);
        await tester.tap(find.byKey(const Key('pasteIconWorkspaceAction')));
        await _pumpFrames(tester);
        expect(clipboardReads, 2);
        expect(state.selectedManagedIconId, 'spb://synthetic');
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final skin in AppSkin.values) {
    for (final layout in _Layout.values) {
      _skinTest(
          '${skin.name} ${layout.name}: icons left popup and paste action',
          (tester) async {
        var clipboardReads = 0;
        const channel = MethodChannel('wallet_aps/window');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
            (call) async {
          if (call.method == 'readClipboardImage') clipboardReads++;
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null));
        final dynamic state = await _pumpShell(tester, skin, layout);
        state.showSpbIconsMode();
        if (layout.isNarrow) {
          state.setState(() {
            state.mobilePane = 0;
            if (skin != AppSkin.retro) state.modernVaultTabOpen = false;
          });
        }
        await _pumpFrames(tester);
        final panel = tester.getRect(find.byKey(const Key('spbLeftWorkspace')));
        final point = panel.topCenter + const Offset(0, 2);
        await tester.tapAt(point);
        await _pumpFrames(tester);
        expect(find.byType(BottomSheet), findsNothing);
        final entries = tester
            .widgetList<PopupMenuItem<String>>(
                find.byType(PopupMenuItem<String>))
            .toList();
        expect(
            entries.map((entry) => entry.value), ['folder', 'upload', 'paste']);
        expect(
            entries.map((entry) => (entry.child as ContextMenuLabel).label), [
          'Создать папку',
          'Загрузить иконку из файла',
          'Вставить иконку из буфера обмена'
        ]);
        await tester.tap(find.byKey(const Key('pasteIconWorkspaceAction')));
        await _pumpFrames(tester);
        expect(clipboardReads, 1);
        expect(find.text('В буфере обмена нет изображения.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final skin in AppSkin.values) {
    for (final layout in _Layout.values) {
      _skinTest(
          '${skin.name} ${layout.name}: template left popup includes category',
          (tester) async {
        final dynamic state = await _pumpShell(tester, skin, layout);
        state.showSpbTemplatesMode();
        if (layout.isNarrow) {
          state.setState(() {
            state.mobilePane = 0;
            if (skin != AppSkin.retro) state.modernVaultTabOpen = false;
          });
        }
        await _pumpFrames(tester);
        final panel = tester.getRect(find.byKey(const Key('spbLeftWorkspace')));
        final point = panel.topCenter + const Offset(0, 2);
        await tester.tapAt(point);
        await _pumpFrames(tester);
        expect(find.byType(BottomSheet), findsNothing);
        final entries = tester
            .widgetList<PopupMenuItem<String>>(
                find.byType(PopupMenuItem<String>))
            .toList();
        expect(entries.map((entry) => entry.value),
            ['category', 'create', 'import']);
        expect(entries.map((entry) => (entry.child as ContextMenuLabel).label),
            ['Создать категорию', 'Создать шаблон', 'Импортировать шаблон']);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final skin in AppSkin.values) {
    for (final layout in _Layout.values) {
      _skinTest('${skin.name} ${layout.name}: cards left panel uses popup copy',
          (tester) async {
        final dynamic state = await _pumpShell(tester, skin, layout);
        if (layout.isNarrow) {
          state.setState(() {
            state.mobilePane = 0;
            if (skin != AppSkin.retro) state.modernVaultTabOpen = false;
          });
        }
        await _pumpFrames(tester);
        final panel = tester.getRect(find.byKey(const Key('spbLeftWorkspace')));
        // Wide modern panels have empty padding above their first group.
        final point = panel.topCenter + const Offset(0, 2);
        for (final buttons in [kPrimaryMouseButton, kSecondaryMouseButton]) {
          await tester.tapAt(point, buttons: buttons);
          await _pumpFrames(tester);
          expect(find.byType(BottomSheet), findsNothing);
          final entries = tester
              .widgetList<PopupMenuItem<String>>(
                  find.byType(PopupMenuItem<String>))
              .toList();
          expect(entries.map((entry) => entry.value),
              ['folder', 'card', 'import']);
          expect(
              entries.map((entry) => (entry.child as ContextMenuLabel).label),
              ['Создать папку', 'Создать карточку', 'Импорт']);
          expect(
              entries.map((entry) => (entry.child as ContextMenuLabel).icon), [
            Icons.create_new_folder_outlined,
            Icons.note_add_outlined,
            Icons.file_open_outlined
          ]);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _pumpFrames(tester);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final skin in AppSkin.values) {
    for (final layout in _Layout.values) {
      _skinTest(
          '${skin.name} ${layout.name}: empty right panel no longer opens menus',
          (tester) async {
        final dynamic state = await _pumpShell(tester, skin, layout);
        Future<void> checkMenu(List<String> keys) async {
          state.setState(() {
            state.spbTasksExpanded = false;
            state.spbFoundExpanded = false;
            state.spbFrequentExpanded = false;
          });
          if (layout.isNarrow) {
            state.setState(() {
              state.mobilePane = 2;
              if (skin != AppSkin.retro) state.modernVaultTabOpen = true;
            });
          }
          await _pumpFrames(tester);
          final target = find.byKey(const Key('spbRightWorkspace'));
          expect(target, findsOneWidget);
          final rect = tester.getRect(target);
          // The narrow management tab has full-width history rows; its side
          // margin is empty. Wide panes have empty space below their groups.
          await tester.tapAt(layout.isNarrow
              ? rect.bottomRight - const Offset(8, 8)
              : rect.bottomCenter - const Offset(0, 8));
          await _pumpFrames(tester);
          for (final key in keys) {
            expect(find.byKey(Key(key)), findsNothing);
          }

          await _pumpFrames(tester);
        }

        await checkMenu([
          'createFolderRootContextAction',
          'createCardRootContextAction',
          'importRootContextAction',
        ]);
        state.showSpbTemplatesMode();
        await checkMenu([
          'createTemplateRightContextAction',
          'importTemplateRightContextAction',
        ]);
        state.showSpbIconsMode();
        await checkMenu([
          'createIconFolderWorkspaceAction',
          'uploadIconWorkspaceAction',
        ]);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final layout in _Layout.values) {
    _skinTest('${layout.name}: password theme buttons tolerate rapid switching',
        (tester) async {
      final dynamic state = await _pumpShell(tester, AppSkin.retro, layout);
      state.setState(() => state.unlocked = false);
      await _pumpFrames(tester);
      await tester.enterText(
          find.byKey(const Key('passwordInput')), 'synthetic');
      for (var round = 0; round < 6; round++) {
        for (final skin in ['Light', 'Dark', 'Retro']) {
          await tester.tap(find.byKey(Key('skin${skin}Button')));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull);
          expect(tester.state(find.byType(VaultShell)), same(state));
          expect(state.passwordController.text, 'synthetic');
        }
      }
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
    _skinTest(
        '${layout.name}: repeated theme changes preserve the active wallet',
        (tester) async {
      final dynamic state = await _pumpShell(tester, AppSkin.retro, layout);
      for (var round = 0; round < 3; round++) {
        for (final mode in [
          state.showSpbCardsMode,
          state.showSpbTemplatesMode,
          state.showSpbIconsMode
        ]) {
          mode();
          await _pumpFrames(tester);
          for (final skin in [
            AppSkin.light,
            AppSkin.dark,
            AppSkin.retro,
            AppSkin.dark,
            AppSkin.light,
            AppSkin.retro
          ]) {
            appSkin.value = skin;
            for (final millis in [0, 16, 80, 150]) {
              await tester.pump(Duration(milliseconds: millis));
              expect(tester.takeException(), isNull,
                  reason: '${layout.name} ${skin.name} at $millis ms');
            }
            expect(tester.state(find.byType(VaultShell)), same(state));
            expect(state.unlocked, isTrue);
            expect((state.items as List).length, 3);
          }
        }
      }
    });
  }
  for (final skin in AppSkin.values) {
    for (final layout in _Layout.values) {
      _skinTest(
          '${skin.name} ${layout.name}: password header versions are readable',
          (tester) async {
        final dynamic shell = await _pumpShell(tester, skin, layout);
        shell.setState(() => shell.unlocked = false);
        await _pumpFrames(tester);
        final label = find.byKey(const Key('passwordVersion'));
        expect(label, findsOneWidget);
        final tokens = WalletSkinTokens.of(tester.element(label));
        final expectedColor =
            skin == AppSkin.retro ? const Color(0xffeeeeee) : tokens.onSurface;
        Text current() =>
            tester.widget<Text>(find.text('v. $currentAppVersion'));
        expect(current().style!.color, expectedColor);
        final foreground = expectedColor.computeLuminance();
        final background = tokens.titleBar.computeLuminance();
        expect(
            (foreground > background
                ? (foreground + 0.05) / (background + 0.05)
                : (background + 0.05) / (foreground + 0.05)),
            greaterThan(3));
        final dynamic versionState = tester.state(label);
        versionState.setState(
            () => versionState.latestGithubVersion = currentAppVersion);
        await _pumpFrames(tester);
        expect(tester.widget<Text>(find.text(currentAppVersion)).style!.color,
            expectedColor);
        versionState
            .setState(() => versionState.latestGithubVersion = '99.0.0');
        await _pumpFrames(tester);
        expect(tester.widget<Text>(find.text('99.0.0')).style!.color,
            const Color(0xffff3b30));
        await tester.tap(find.byKey(const Key('availableGithubVersion')));
        await _pumpFrames(tester);
        expect(find.text('Доступно обновление'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final layout in [_Layout.narrow, _Layout.tablet, _Layout.wide]) {
    for (final platform in layout.isNarrow
        ? [TargetPlatform.android, TargetPlatform.windows]
        : [layout.platform]) {
      _skinTest('retro ${layout.name} ${platform.name}: empty workspace menus',
          (tester) async {
        final dynamic state = await _pumpShell(tester, AppSkin.retro, layout);
        debugDefaultTargetPlatformOverride = platform;
        state.setState(() => state.mobilePane = 1);
        await _pumpFrames(tester);
        final enabled = layout.isNarrow || platform == TargetPlatform.android;
        Future<void> tapBlank(String key, List<String> actions) async {
          final rect = tester.getRect(find.byKey(Key(key)));
          await tester.tapAt(rect.bottomLeft + const Offset(18, -18));
          await _pumpFrames(tester);
          for (final action in actions) {
            expect(find.byKey(Key(action)),
                enabled ? findsOneWidget : findsNothing);
          }
          if (enabled) {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await _pumpFrames(tester);
          }
        }

        await tapBlank('spbCentralWorkspace', [
          'createFolderRootContextAction',
          'createCardRootContextAction',
          'importRootContextAction',
        ]);
        await tester
            .tap(find.byKey(const ValueKey('spbCentralFolder-Finance')));
        await _pumpFrames(tester);
        expect(state.selectedCategoryPath, 'Finance');
        expect(find.byKey(const Key('createFolderRootContextAction')),
            findsNothing);
        state.openSpbFolder('');
        state.showSpbTemplatesMode();
        state.setState(() => state.mobilePane = 1);
        await _pumpFrames(tester);
        await tapBlank('spbTemplateWorkspace', [
          'createTemplateContextAction',
          'importTemplateContextAction',
        ]);
        state.showSpbIconsMode();
        state.setState(() => state.mobilePane = 1);
        await _pumpFrames(tester);
        if (enabled) {
          await tapBlank('spbIconWorkspaceCreationTarget', [
            'createIconFolderWorkspaceAction',
            'uploadIconWorkspaceAction',
          ]);
          final rect = tester
              .getRect(find.byKey(const Key('spbIconWorkspaceCreationTarget')));
          final previousLibraryFuture = managedIconLibraryFuture;
          managedIconLibraryFuture = Future<void>.value();
          addTearDown(() {
            managedIconLibraryFuture = previousLibraryFuture;
          });
          await tester.tapAt(rect.bottomLeft + const Offset(18, -18));
          await _pumpFrames(tester);
          await tester
              .tap(find.byKey(const Key('createIconFolderWorkspaceAction')));
          await _pumpFrames(tester);
          expect(find.byKey(const Key('categoryNameField')), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _pumpFrames(tester);
        } else {
          expect(find.byKey(const Key('spbIconWorkspaceCreationTarget')),
              findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final skin in AppSkin.values) {
    for (final layout in _Layout.values) {
      _skinTest(
          '${skin.name} ${layout.name}: icon workspace has no bottom toolbar',
          (tester) async {
        final dynamic state = await _pumpShell(tester, skin, layout);
        state.showSpbIconsMode();
        if (skin == AppSkin.retro && layout.isNarrow) {
          state.setState(() => state.mobilePane = 1);
        }
        await _pumpFrames(tester);
        for (final key in [
          'createIconFolderButton',
          'uploadManagedIconButton',
          'pasteManagedIconButton',
        ]) {
          expect(find.byKey(Key(key)), findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final skin in [AppSkin.light, AppSkin.dark]) {
    for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
      _skinTest(
        '${skin.name} narrow ${platform.name}: compact overlay actions',
        (tester) async {
          final dynamic state = await _pumpShell(tester, skin, _Layout.narrow);
          debugDefaultTargetPlatformOverride = platform;
          await _pumpFrames(tester);
          Future<void> checkButton(String key, String label) async {
            final finder = find.byKey(Key(key));
            final fab = tester.widget<FloatingActionButton>(finder);
            expect(fab.isExtended, isFalse);
            expect(fab.tooltip, label);
            expect(tester.getSize(finder), const Size(56, 56));
            expect(
              find.descendant(of: finder, matching: find.byType(Text)),
              findsNothing,
            );
            final navTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
            final scaffold = tester.widget<Scaffold>(
              find.ancestor(of: finder, matching: find.byType(Scaffold)).first,
            );
            final body = find.byWidget(scaffold.body!);
            expect(tester.getBottomRight(body).dy, navTop);
            expect(
              tester.getRect(body).overlaps(tester.getRect(finder)),
              isTrue,
            );
          }

          await checkButton('modernCreateFab', 'Создать');
          await tester.tap(find.byKey(const Key('modernCreateFab')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('createCardRootContextAction')),
            findsOneWidget,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          state.showSpbTemplatesMode();
          await _pumpFrames(tester);
          await checkButton('modernCreateTemplateFab', 'Создать шаблон');
          final workspace = find.byKey(const Key('spbTemplateWorkspace'));
          final navTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
          expect(tester.getBottomRight(workspace).dy, closeTo(navTop - 8, 2));
          state.showSpbIconsMode();
          await _pumpFrames(tester);
          await checkButton('modernUploadIconFab', 'Загрузить иконку');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final skin in AppSkin.values) {
    for (final layout in _Layout.values) {
      _skinTest('${skin.name} ${layout.name}: every mode builds cleanly',
          (tester) async {
        final dynamic state = await _pumpShell(tester, skin, layout);
        expect(tester.takeException(), isNull);
        state.openSpbFolder('Finance / Banks');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        state.showSpbTemplatesMode();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        state.showSpbIconsMode();
        await _pumpFrames(tester);
        expect(tester.takeException(), isNull);
        state.showSpbCardsMode();
        await _pumpFrames(tester);
        if (skin != AppSkin.retro && layout.isNarrow) {
          state.setState(() => state.modernVaultTabOpen = true);
          await _pumpFrames(tester);
          expect(find.byKey(const Key('modernVaultTab')), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });

      _skinTest('${skin.name} ${layout.name}: common controls are present',
          (tester) async {
        final dynamic state = await _pumpShell(tester, skin, layout);
        final modernNarrow = skin != AppSkin.retro && layout.isNarrow;
        for (final key in [
          'spbSearchInput',
          'spbSubmitSearchButton',
          'spbForceCloseButton',
        ]) {
          expect(find.byKey(Key(key)), findsOneWidget, reason: key);
        }
        expect(
            find.byKey(state.spbSessionUndoButtonKey as Key), findsOneWidget);
        if (layout.isNarrow) {
          expect(find.byKey(const Key('spbMobileWalletTitle')), findsOneWidget);
        } else {
          for (final key in [
            'spbVaultTitle',
            'spbMyCardsModeButton',
            'spbTemplatesModeButton',
            'spbIconsModeButton',
            'spbNavigatorSplitter',
            'spbActionsPanelSplitter',
            'spbFoundCount',
            'spbManagementHeader',
          ]) {
            expect(find.byKey(Key(key)), findsOneWidget, reason: key);
          }
        }
        if (modernNarrow) {
          for (final key in [
            'modernTabCards',
            'modernTabTemplates',
            'modernTabIcons',
            'modernTabVault',
            'modernCreateFab',
            'frequentCardsScroll',
          ]) {
            expect(find.byKey(Key(key)), findsOneWidget, reason: key);
          }
        }
        if (layout.isNarrow && skin == AppSkin.retro) {
          for (final key in ['mobilePaneBack', 'mobilePaneForward']) {
            expect(find.byKey(Key(key)), findsOneWidget, reason: key);
          }
        }
      });

      _skinTest(
          '${skin.name} ${layout.name}: every task of every mode is '
          'reachable', (tester) async {
        final dynamic state = await _pumpShell(tester, skin, layout);
        final modernNarrow = skin != AppSkin.retro && layout.isNarrow;

        Future<void> expectTasks(String mode, {Key? sheetButton}) async {
          final labels = _taskLabels(state);
          expect(labels, isNotEmpty, reason: mode);
          if (sheetButton != null) {
            await tester.tap(find.byKey(sheetButton));
            await _pumpFrames(tester);
          }
          for (final label in labels) {
            if (modernNarrow || !layout.isNarrow) {
              expect(find.text(label), findsWidgets, reason: '$mode: $label');
            }
          }
          if (sheetButton != null) {
            Navigator.of(tester.element(find.byType(VaultShell)),
                    rootNavigator: true)
                .maybePop();
            await _pumpFrames(tester);
          }
        }

        if (modernNarrow) {
          state.setState(() => state.modernVaultTabOpen = true);
          await _pumpFrames(tester);
          await expectTasks('cards');
          state.setState(() => state.modernVaultTabOpen = false);
          state.showSpbTemplatesMode();
          await _pumpFrames(tester);
          await expectTasks(
            'templates',
            sheetButton: const Key('modernTemplateTasksMenu'),
          );
          state.showSpbIconsMode();
          await _pumpFrames(tester);
          await expectTasks(
            'icons',
            sheetButton: const Key('modernIconTasksMenu'),
          );
        } else if (!layout.isNarrow) {
          await expectTasks('cards');
          state.showSpbTemplatesMode();
          await tester.pumpAndSettle();
          await expectTasks('templates');
          state.showSpbIconsMode();
          await _pumpFrames(tester);
          await expectTasks('icons');
        } else {
          // Retro narrow keeps its third pane; the task list itself is
          // unchanged and covered by the existing narrow tests.
          state.setState(() => state.mobilePane = 2);
          await tester.pumpAndSettle();
          for (final label in _taskLabels(state)) {
            expect(find.text(label), findsWidgets, reason: label);
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final skin in [AppSkin.light, AppSkin.dark]) {
    _skinTest(
        '${skin.name} narrow: tabs, folder screen and FABs call the '
        'existing methods', (tester) async {
      final dynamic state = await _pumpShell(tester, skin, _Layout.narrow);
      await tester.tap(find.byKey(const Key('modernTabTemplates')));
      await _pumpFrames(tester);
      expect(state.mobileTemplatesOpen, isTrue);
      expect(find.byKey(const Key('modernCreateTemplateFab')), findsOneWidget);
      await tester.tap(find.byKey(const Key('modernTabIcons')));
      await _pumpFrames(tester);
      expect(state.iconLibraryOpen, isTrue);
      expect(find.byKey(const Key('modernUploadIconFab')), findsOneWidget);
      await tester.tap(find.byKey(const Key('modernTabVault')));
      await _pumpFrames(tester);
      expect(state.modernVaultTabOpen, isTrue);
      expect(
          find.descendant(
              of: find.byKey(const Key('modernTabVault')),
              matching: find.text('Управление')),
          findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Нет изменений для отмены'),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('modernVaultTab')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Нет изменений для отмены'), findsOneWidget);
      await tester.tap(find.byKey(const Key('modernTabCards')));
      await _pumpFrames(tester);
      expect(state.modernVaultTabOpen, isFalse);
      expect(state.iconLibraryOpen, isFalse);
      expect(state.mobileTemplatesOpen, isFalse);

      await tester.tap(find.text('Finance'));
      await tester.pumpAndSettle();
      expect(state.selectedCategoryPath, 'Finance');
      expect(find.byKey(const Key('mobileFolderUp')), findsOneWidget);
      expect(find.text('Finance card'), findsOneWidget);
      await tester.tap(find.byKey(const Key('mobileFolderUp')));
      await tester.pumpAndSettle();
      expect(state.selectedCategoryPath, '');
      expect(tester.takeException(), isNull);
    });

    if (skin != AppSkin.retro) {
      _skinTest('${skin.name} narrow: search stays on top while results scroll',
          (tester) async {
        final dynamic state = await _pumpShell(tester, skin, _Layout.narrow);
        final CardTemplate template =
            (state.templates as List).first as CardTemplate;
        final cards = [
          for (var index = 0; index < 40; index++)
            SecretItem(
              id: 'many-$index',
              templateId: template.id,
              title: 'Bank $index',
              category: '',
              colorId: template.colorId,
              values: const {},
              modifiedAt: DateTime(2026, 10, 25),
            ),
        ];
        state.setState(() {
          state.items = cards;
          state.itemsById = {for (final item in cards) item.id: item};
        });
        await tester.pumpAndSettle();
        final field = find.byKey(const Key('spbSearchInput'));
        await tester.enterText(field, 'Bank');
        await tester.pumpAndSettle();
        final top = tester.getTopLeft(field);
        await tester.dragFrom(const Offset(206, 500), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(state.spbMobileActionsScrollController.offset, greaterThan(0));
        expect(tester.getTopLeft(field), top);
        expect(tester.takeException(), isNull);
      });
    }

    _skinTest('${skin.name} narrow: Android Back follows section 11.8',
        (tester) async {
      final dynamic state = await _pumpShell(tester, skin, _Layout.narrow);
      state.openSpbFolder('Finance / Banks');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('spbSearchInput')), 'Bank');
      await tester.pumpAndSettle();
      expect(state.spbSubmittedSearchQuery, 'Bank');

      Future<void> back() async {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }

      await back();
      expect(state.searchController.text, isEmpty);
      expect(state.selectedCategoryPath, 'Finance / Banks');
      await back();
      expect(state.selectedCategoryPath, 'Finance');
      await back();
      expect(state.selectedCategoryPath, '');
      state.showSpbTemplatesMode();
      await tester.pumpAndSettle();
      await back();
      expect(state.mobileTemplatesOpen, isFalse);
      expect(find.byType(VaultShell), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _skinTest(
        '${skin.name} narrow: card menu opens as a bottom sheet with '
        'the original items', (tester) async {
      await _pumpShell(tester, skin, _Layout.narrow);
      await tester
          .longPress(find.byKey(const ValueKey('spbCentralCard-s-root')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      for (final key in [
        'viewCardContextAction',
        'editCardContextAction',
        'deleteCardContextAction',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      final delete = tester.widget<PopupMenuItem<String>>(
        find.byKey(const Key('deleteCardContextAction')),
      );
      expect(delete.child, isA<ContextMenuLabel>());
      final style = delete.labelTextStyle?.resolve(<WidgetState>{});
      expect(style?.color, WalletSkinTokens.forSkin(skin).error);
      Navigator.of(tester.element(find.byType(VaultShell)), rootNavigator: true)
          .maybePop();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    _skinTest('${skin.name}: unsaved chip follows the existing flag',
        (tester) async {
      for (final layout in [_Layout.narrow, _Layout.wide]) {
        final dynamic state = await _pumpShell(tester, skin, layout);
        expect(find.byKey(const Key('unsavedChip')), findsNothing);
        state.setState(() => state.spbWritePending = true);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('unsavedChip')), findsOneWidget,
            reason: layout.name);
        state.setState(() => state.spbWritePending = false);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('unsavedChip')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  List<VerticalDivider> dividers(WidgetTester tester) =>
      tester.widgetList<VerticalDivider>(find.byType(VerticalDivider)).toList();

  _skinTest(
      'wide splitters: primary under the pointer in Light and Dark, '
      'unchanged in Retro', (tester) async {
    for (final skin in AppSkin.values) {
      await _pumpShell(tester, skin, _Layout.wide);
      final splitter = find.byKey(const Key('spbNavigatorSplitter'));
      expect(tester.getSize(splitter).width, 9, reason: skin.name);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(splitter));
      await tester.pumpAndSettle();
      final tokens = WalletSkinTokens.forSkin(skin);
      final first = dividers(tester).first;
      if (skin == AppSkin.retro) {
        expect(first.color, isNull);
        expect(first.thickness, 1);
      } else {
        expect(first.color, tokens.primary, reason: skin.name);
        expect(first.thickness, 2);
        expect(dividers(tester).last.color, tokens.splitter);
      }
      await mouse.moveTo(const Offset(640, 400));
      await tester.pumpAndSettle();
      if (skin != AppSkin.retro) {
        expect(dividers(tester).first.color, tokens.splitter);
      }
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  _skinTest(
      'Android tablet splitters get a handle and a 24 dp grab zone in '
      'Light and Dark only', (tester) async {
    for (final skin in AppSkin.values) {
      await _pumpShell(tester, skin, _Layout.tablet);
      for (final key in ['spbNavigatorSplitter', 'spbActionsPanelSplitter']) {
        final splitter = find.byKey(Key(key));
        final handle = find.descendant(
          of: splitter,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.constraints?.maxWidth == 7 &&
                widget.constraints?.maxHeight == 36,
          ),
        );
        if (skin == AppSkin.retro) {
          expect(tester.getSize(splitter).width, 9, reason: key);
          expect(handle, findsNothing);
        } else {
          expect(tester.getSize(splitter).width, 24,
              reason: '${skin.name} $key');
          expect(handle, findsOneWidget);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final skin in [AppSkin.light, AppSkin.dark]) {
    _skinTest('${skin.name} narrow: menu sheets start with the object header',
        (tester) async {
      await _pumpShell(tester, skin, _Layout.narrow);
      await tester
          .longPress(find.byKey(const ValueKey('spbCentralCard-s-root')));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('Root card')),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.byType(VaultShell)), rootNavigator: true)
          .maybePop();
      await tester.pumpAndSettle();
      await tester.longPress(
        find.byKey(const ValueKey('spbCentralFolder-Finance')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
            of: find.byType(BottomSheet), matching: find.text('Папка')),
        findsOneWidget,
      );
      expect(
          find.byKey(const Key('deleteFolderContextAction')), findsOneWidget);
      Navigator.of(tester.element(find.byType(VaultShell)), rootNavigator: true)
          .maybePop();
      await tester.pumpAndSettle();
    });
  }

  _skinTest('Retro never shows the unsaved chip or modern controls',
      (tester) async {
    for (final layout in _Layout.values) {
      final dynamic state = await _pumpShell(tester, AppSkin.retro, layout);
      state.setState(() => state.spbWritePending = true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unsavedChip')), findsNothing);
      expect(find.byKey(const Key('modernTabCards')), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final skin in AppSkin.values) {
    _skinTest('${skin.name} wide: "Сменить тему" opens the three skins',
        (tester) async {
      final dynamic state = await _pumpShell(tester, skin, _Layout.wide);
      for (final open in <void Function()>[
        state.showSpbTemplatesMode,
        state.showSpbIconsMode,
        state.showSpbCardsMode,
      ]) {
        open();
        await _pumpFrames(tester);
        final labels = _taskLabels(state);
        expect(labels, contains('Сменить тему'));
        expect(labels.indexOf('Сменить тему'), labels.indexOf('Выйти') - 1);
      }
      await tester.tap(find.text('Сменить тему'));
      await _pumpFrames(tester);
      expect(find.byKey(const Key('skinDialog')), findsOneWidget);
      for (final key in ['Retro', 'Light', 'Dark']) {
        expect(find.byKey(Key('skinDialog$key')), findsOneWidget);
      }
      final target = skin == AppSkin.dark ? AppSkin.light : AppSkin.dark;
      await tester.tap(find.byKey(
        Key(target == AppSkin.dark ? 'skinDialogDark' : 'skinDialogLight'),
      ));
      await _pumpFrames(tester);
      expect(appSkin.value, target);
      expect(find.byKey(const Key('skinDialog')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  _skinTest('wide Light and Dark centre has the create button of each mode',
      (tester) async {
    for (final skin in [AppSkin.light, AppSkin.dark]) {
      final dynamic state = await _pumpShell(tester, skin, _Layout.wide);
      expect(find.byKey(const Key('modernCreateFab')), findsOneWidget);
      expect(
          tester
              .widget<FloatingActionButton>(
                  find.byKey(const Key('modernCreateFab')))
              .isExtended,
          isTrue);
      await tester.tap(find.byKey(const Key('modernCreateFab')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('createCardRootContextAction')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      state.showSpbTemplatesMode();
      await _pumpFrames(tester);
      expect(find.byKey(const Key('modernCreateTemplateFab')), findsOneWidget);
      expect(
          tester
              .widget<FloatingActionButton>(
                  find.byKey(const Key('modernCreateTemplateFab')))
              .isExtended,
          isTrue);
      state.showSpbIconsMode();
      await _pumpFrames(tester);
      expect(find.byKey(const Key('modernUploadIconFab')), findsOneWidget);
      expect(
          tester
              .widget<FloatingActionButton>(
                  find.byKey(const Key('modernUploadIconFab')))
              .isExtended,
          isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    await _pumpShell(tester, AppSkin.retro, _Layout.wide);
    expect(find.byKey(const Key('modernCreateFab')), findsNothing);
  });

  _skinTest('Retro centre has a blue "+" button with the creation menu',
      (tester) async {
    final dynamic state = await _pumpShell(tester, AppSkin.retro, _Layout.wide);
    final button = find.byKey(const Key('retroCreateButton'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('createCardRootContextAction')), findsOneWidget);
    expect(
        find.byKey(const Key('createFolderRootContextAction')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    state.showSpbTemplatesMode();
    await _pumpFrames(tester);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('createTemplateContextAction')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());

    final dynamic narrow =
        await _pumpShell(tester, AppSkin.retro, _Layout.narrow);
    expect(button, findsNothing);
    narrow.setState(() => narrow.mobilePane = 1);
    await tester.pumpAndSettle();
    expect(button, findsOneWidget);
  });

  _skinTest('Light and Dark draw icons without a tile', (tester) async {
    for (final skin in [AppSkin.light, AppSkin.dark]) {
      await _pumpShell(tester, skin, _Layout.wide);
      final icon = find.byKey(const ValueKey('spbActionIcon-Выйти'));
      final tile = tester.widget<Container>(icon);
      expect(tile.decoration, isNull, reason: skin.name);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  test('icon folders use the new names', () {
    expect(IconCatalogKind.brands.label, 'Логотипы');
    expect(IconCatalogKind.thirdParty.label, 'Разные');
  });

  _skinTest('narrow skins use the system status bar style of their brightness',
      (tester) async {
    for (final (skin, brightness) in [
      (AppSkin.light, Brightness.dark),
      (AppSkin.dark, Brightness.light),
    ]) {
      await _pumpShell(tester, skin, _Layout.narrow);
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
      );
      expect(region.value.statusBarIconBrightness, brightness,
          reason: skin.name);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  _skinTest('Light and Dark frame the icons of the icon workspace like Retro',
      (tester) async {
    for (final skin in [AppSkin.light, AppSkin.dark]) {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(MaterialApp(
        theme: buildModernTheme(
            skin == AppSkin.dark ? Brightness.dark : Brightness.light),
        home: Builder(
          builder: (context) => Column(children: [
            for (final selected in [false, true])
              SizedBox.square(
                dimension: 48,
                child: managedCatalogIconFrame(context, 'missing',
                    key: ValueKey('frame-$selected'),
                    selected: selected,
                    skinFrames: true,
                    baseColor: retroIconFrameTheme.colorScheme.surface),
              ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      final scheme = retroIconFrameTheme.colorScheme;
      Color expected(Color color) =>
          skin == AppSkin.dark ? invertedColor(color) : color;
      for (final (selected, fill, border) in [
        (false, scheme.surface, managedIconFrameGrey),
        (true, scheme.primaryContainer, scheme.primary),
      ]) {
        final decoration = tester
            .widget<DecoratedBox>(find.byKey(ValueKey('frame-$selected')))
            .decoration as BoxDecoration;
        expect(decoration.color, expected(fill),
            reason: '${skin.name} $selected');
        final side = (decoration.border! as Border).top;
        expect(side.color, expected(border), reason: '${skin.name} $selected');
        // 25 % thinner and less rounded than the picker frames (1 px, 8).
        expect(side.width, 0.75);
        expect(decoration.borderRadius, BorderRadius.circular(6));
      }
    }
  });

  _skinTest(
      'Dark card preview fields have the main dark colour and grey outlines',
      (tester) async {
    final dynamic state = await _pumpShell(tester, AppSkin.dark, _Layout.wide);
    final SecretItem first = state.items.first as SecretItem;
    final template = state.templateFor(first.templateId) as CardTemplate;
    final card = SecretItem(
      id: first.id,
      templateId: first.templateId,
      title: first.title,
      category: first.category,
      colorId: first.colorId,
      values: {for (final field in template.fields) field.id: 'value'},
      modifiedAt: first.modifiedAt,
    );
    state.setState(() {
      state.items = [card];
      state.itemsById = {card.id: card};
    });
    await tester.pumpAndSettle();
    unawaited(state.openCardPreviewDialog(card) as Future<void>);
    await tester.pumpAndSettle();
    final surface = WalletSkinTokens.dark.bg;
    final fields = find.byWidgetPredicate((widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>)
            .value
            .startsWith('cardPreviewField-'));
    expect(find.byKey(const Key('cardPreviewTitle')), findsOneWidget);
    expect(fields, findsWidgets);
    final grey = WalletSkinTokens.light.outline;
    for (final decorator in tester.widgetList<InputDecorator>(
        find.descendant(of: fields, matching: find.byType(InputDecorator)))) {
      final decoration = decorator.decoration;
      expect(decoration.fillColor, surface);
      expect(decoration.enabledBorder!.borderSide.color, grey);
      expect(decoration.labelStyle!.color, grey);
    }
  });

  _skinTest('Light and Dark card mode selection frame is grey and thin',
      (tester) async {
    for (final skin in [AppSkin.light, AppSkin.dark]) {
      final dynamic state = await _pumpShell(tester, skin, _Layout.wide);
      state.setState(() => state.selectedItemId = 's-root');
      await tester.pumpAndSettle();
      final frame = tester
          .widgetList<Container>(find.descendant(
            of: find.byKey(const ValueKey('spbCentralCard-s-root')),
            matching: find.byType(Container),
          ))
          .map((container) => container.foregroundDecoration)
          .whereType<BoxDecoration>()
          .single;
      final side = (frame.border! as Border).top;
      expect(
          side.color,
          skin == AppSkin.dark
              ? invertedColor(managedIconFrameGrey)
              : managedIconFrameGrey,
          reason: skin.name);
      // Half the radius (12) and 25 % thinner (2 px) than before.
      expect(side.width, 1.5);
      expect(frame.borderRadius, BorderRadius.circular(6));
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  _skinTest('Light and Dark search field has a thin grey frame',
      (tester) async {
    for (final skin in [AppSkin.light, AppSkin.dark]) {
      for (final layout in [_Layout.wide, _Layout.narrow]) {
        await _pumpShell(tester, skin, layout);
        final decorator = tester.widget<InputDecorator>(find.descendant(
          of: find.byKey(const Key('spbSearchInput')),
          matching: find.byType(InputDecorator),
        ));
        final grey = skin == AppSkin.dark
            ? invertedColor(managedIconFrameGrey)
            : managedIconFrameGrey;
        final height =
            tester.getSize(find.byKey(const Key('spbSearchInput'))).height;
        for (final border in [
          decorator.decoration.enabledBorder!,
          decorator.decoration.focusedBorder!,
        ]) {
          expect(border.borderSide.color, grey, reason: skin.name);
          expect(border.borderSide.width, 1.5);
          expect((border as OutlineInputBorder).borderRadius,
              BorderRadius.circular(height / 2 * 0.3),
              reason: '${skin.name} ${layout.name}');
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  _skinTest('Light and Dark password field has a thin grey frame',
      (tester) async {
    for (final skin in [AppSkin.light, AppSkin.dark]) {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      appSkin.value = skin;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 700);
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(const WalletApsApp());
      await tester.pumpAndSettle();
      final decoration = tester
          .widget<InputDecorator>(find.descendant(
            of: find.byKey(const Key('passwordInput')),
            matching: find.byType(InputDecorator),
          ))
          .decoration;
      final grey = skin == AppSkin.dark
          ? invertedColor(managedIconFrameGrey)
          : managedIconFrameGrey;
      for (final (border, width) in [
        (decoration.enabledBorder!, 0.75),
        (decoration.focusedBorder!, 1.5),
      ]) {
        expect(border.borderSide.color, grey, reason: skin.name);
        expect(border.borderSide.width, width);
        expect((border as OutlineInputBorder).borderRadius,
            BorderRadius.circular(12 * 0.3));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
