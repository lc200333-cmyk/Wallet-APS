import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';
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
}
