import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/widgets/context_menu_label.dart';

Future<dynamic> pumpMenuShell(
    WidgetTester tester, TargetPlatform platform) async {
  debugDefaultTargetPlatformOverride = platform;
  await tester.binding.setSurfaceSize(platform == TargetPlatform.windows
      ? const Size(1280, 900)
      : const Size(360, 800));
  addTearDown(() {
    debugDefaultTargetPlatformOverride = null;
    tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
  );
  await tester.pumpAndSettle();
  return tester.state(find.byType(VaultShell));
}

void expectMenuIcons(WidgetTester tester) {
  final entries = find.byWidgetPredicate((widget) => widget is PopupMenuItem);
  expect(entries, findsWidgets);
  for (final element in entries.evaluate()) {
    final entry =
        find.byElementPredicate((candidate) => identical(candidate, element));
    expect(find.descendant(of: entry, matching: find.byType(ContextMenuLabel)),
        findsOneWidget,
        reason: 'Menu entries must use uniform pictograms');
    expect(
        find.descendant(of: entry, matching: find.byType(Image)), findsNothing);
    expect(find.descendant(of: entry, matching: find.byType(ImageIcon)),
        findsNothing);
    final icons = find.descendant(
        of: find.byWidget(element.widget), matching: find.byType(Icon));
    expect(icons, findsWidgets, reason: 'Every menu entry must have an icon');
    for (final icon in tester.widgetList<Icon>(icons)) {
      expect(icon.size ?? 24, 24);
    }
  }
  expect(tester.takeException(), isNull);
}

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final pane in ['left', 'center']) {
      testWidgets('card menu icons in $pane pane on ${platform.name}',
          (tester) async {
        final dynamic state = await pumpMenuShell(tester, platform);
        final template = builtInTemplates().first;
        final card = SecretItem(
            id: 'menu-card',
            templateId: template.id,
            title: 'Тестовая карточка',
            category: '',
            colorId: template.colorId,
            values: const {},
            modifiedAt: DateTime.utc(2026));
        state.setState(() {
          state.templates = [template];
          state.templatesById = {template.id: template};
          state.items = [card];
          state.itemsById = {card.id: card};
          state.selectedCategoryPath = '';
          state.mobilePane = pane == 'center' ? 1 : 0;
        });
        await tester.pumpAndSettle();
        final target = find.byKey(ValueKey(pane == 'left'
            ? 'spbTreeCard-${card.id}'
            : 'spbCentralCard-${card.id}'));
        await tester.ensureVisible(target);
        if (platform == TargetPlatform.windows) {
          await tester.tap(target, buttons: kSecondaryMouseButton);
        } else {
          await tester.longPress(target);
        }
        await tester.pumpAndSettle();
        for (final action in [
          'viewCardContextAction',
          'createCardContextAction',
          'editCardContextAction',
          'copyCardContextAction',
          'moveCardContextAction',
          'exportObjectContextAction',
          'importCardContextAction',
          'deleteCardContextAction'
        ]) {
          final entry = find.byKey(Key(action));
          expect(entry, findsOneWidget);
          expect(find.descendant(of: entry, matching: find.byType(Icon)),
              findsOneWidget);
        }
        expectMenuIcons(tester);
        // Dismiss the menu without executing mutations or opening native dialogs.
        Navigator.of(tester.element(target)).pop();
        await tester.pumpAndSettle();
        expect(state.items.single.id, card.id);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      });
    }

    testWidgets('remaining menus have icons on ${platform.name}',
        (tester) async {
      final dynamic state = await pumpMenuShell(tester, platform);
      final template = builtInTemplates().first;
      Future<void> checkMenu(Future<void> Function() open) async {
        final pending = open();
        await tester.pumpAndSettle();
        expectMenuIcons(tester);
        Navigator.of(tester.element(find.byType(VaultShell))).pop();
        await tester.pumpAndSettle();
        await pending;
      }

      await checkMenu(() => state.showSpbTemplateMenu(
          template, const Offset(80, 100)) as Future<void>);
      await checkMenu(() => state.showSpbTemplateImportMenu(
          const Offset(80, 100),
          folder: 'Другие') as Future<void>);
      await checkMenu(() => state.showSpbFolderMenu(
          CategoryTreeNode('Работа'), const Offset(80, 100)) as Future<void>);
      await checkMenu(() => state.showIconFolderMenu(
          IconCatalogKind.values.first, const Offset(80, 100)) as Future<void>);
      await checkMenu(() =>
          state.showSpbCreationMenu(const Offset(80, 100)) as Future<void>);
      await checkMenu(() async {
        await state.showSpbFolderCreationMenu(const Offset(80, 100));
      });
      await checkMenu(() => state
          .showSpbTemplateRightMenu(const Offset(80, 100)) as Future<void>);
      await checkMenu(() => state.showManagedIconMenu(
          'key', const Offset(80, 100)) as Future<void>);
      final attachmentMenu = showAttachmentContextMenu(
          tester.element(find.byType(VaultShell)), const Offset(80, 100),
          allowCopy: true, allowShare: true);
      await tester.pumpAndSettle();
      expectMenuIcons(tester);
      Navigator.of(tester.element(find.byType(VaultShell))).pop();
      await tester.pumpAndSettle();
      expect(await attachmentMenu, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('recent section has new title on ${platform.name}',
        (tester) async {
      final dynamic state = await pumpMenuShell(tester, platform);
      state.setState(() => state.mobilePane = 2);
      await tester.pumpAndSettle();
      expect(find.text('Последние'), findsOneWidget);
      expect(find.text('Часто используемые'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('spbCollapseПоследние')));
      await tester.pumpAndSettle();
      expect(find.text('Последние'), findsOneWidget);
      expect(find.byKey(const ValueKey('spbExpandПоследние')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('selection menus use pictograms on ${platform.name}',
        (tester) async {
      await pumpMenuShell(tester, platform);
      const template = CardTemplate(
          id: 'pictogram-template',
          name: 'Тест',
          iconId: 'key',
          colorId: 'template_white',
          fields: [
            FieldDefinition(id: 'test-field', label: 'Поле', type: 'text'),
          ]);
      await tester.pumpWidget(const MaterialApp(
          home: ItemEditorDialog(
        templates: [template],
        categories: ['Работа'],
        categoryIcons: {'Работа': 'key'},
      )));
      await tester.pumpAndSettle();
      Future<void> checkSelection(Key key) async {
        final target = find.byKey(key);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        final entries = find.byWidgetPredicate((w) => w is DropdownMenuItem);
        expect(entries, findsWidgets);
        for (final entry in entries.evaluate()) {
          final row = find
              .byElementPredicate((candidate) => identical(candidate, entry));
          expect(
              find.descendant(of: row, matching: find.byType(ContextMenuLabel)),
              findsOneWidget);
          expect(find.descendant(of: row, matching: find.byType(Image)),
              findsNothing);
          expect(find.descendant(of: row, matching: find.byType(ImageIcon)),
              findsNothing);
          for (final icon in tester.widgetList<Icon>(
              find.descendant(of: row, matching: find.byType(Icon)))) {
            expect(icon.size, 24);
          }
        }
        Navigator.of(tester.element(target)).pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await checkSelection(const Key('cardTemplateField'));
      await checkSelection(const Key('cardCategoryField'));
      await tester.pumpWidget(
          const MaterialApp(home: TemplateEditorDialog(initial: template)));
      await tester.pumpAndSettle();
      await checkSelection(const ValueKey('templateFieldType-test-field'));
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
