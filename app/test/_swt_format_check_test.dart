import 'dart:io';
import 'dart:typed_data';

import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports the supplied legacy SPB Wallet SWT template', () {
    final bytes = Uint8List.fromList(
      File('../docs/Компьютеры- Сеть.swt').readAsBytesSync(),
    );
    final template = decodeSwtTemplate(bytes);

    expect(template.name, 'Компьютеры: Сеть');
    expect(template.fields, hasLength(14));
    expect(template.fields.first.label, 'Сеть');
    expect(template.fields.last.label, 'Пароль админ.');
    expect(template.fields.last.type, 'password');
  });

  test('permanently deleting a template removes its dependent cards', () {
    final directory =
        Directory.systemTemp.createTempSync('wallet_aps_template_delete_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final database = SpbWalletDatabase.create(
      '${directory.path}${Platform.pathSeparator}template-delete.swl',
      '',
    );
    addTearDown(database.close);
    final templateId = SpbWalletDatabase.makeId();
    final fieldId = SpbWalletDatabase.makeId();
    database.saveTemplate(
      SpbWalletTemplateDraft(
        id: templateId,
        name: 'Удаляемый шаблон',
        fields: [
          SpbWalletTemplateFieldRecord(
            id: fieldId,
            name: 'Поле',
            templateId: templateId,
            fieldTypeId: 1,
          ),
        ],
      ),
    );
    database.saveCard(
      SpbWalletCardDraft(
        id: SpbWalletDatabase.makeId(),
        title: 'Связанная карточка',
        description: '',
        categoryPath: '',
        templateId: templateId,
        fieldValues: {fieldId: 'Значение'},
      ),
    );

    database.deleteTemplate(templateId);

    final snapshot = database.loadSnapshot();
    expect(
        snapshot.templates.where((entry) => entry.id == templateId), isEmpty);
    expect(snapshot.cards.where((entry) => entry.templateId == templateId),
        isEmpty);
  });

  testWidgets('orphaned cards remain visible through a safe template',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    state.applySpbSnapshot(
      const SpbWalletSnapshot(
        templates: [],
        categories: [],
        cards: [
          SpbWalletCardRecord(
            id: 'orphan-card',
            title: 'Карточка без шаблона',
            description: 'Заметка сохранена',
            categoryPath: '',
            templateId: 'missing-template',
            fieldValues: {'missing-field': 'Важное значение'},
            attachments: [],
            hitCount: 0,
            iconId: '',
            cardColor: 16777215,
          ),
        ],
      ),
    );
    state.setState(() {});
    await tester.pumpAndSettle();

    expect(state.templates.single.name, 'Неизвестный шаблон');
    expect(state.items.single.values['missing-field'], 'Важное значение');
    expect(find.text('Карточка без шаблона'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('template icon menu opens create, edit, export and delete',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Шаблоны'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить'), findsOneWidget);
    expect(find.byKey(const Key('spbTemplateWorkspace')), findsOneWidget);
    expect(
      find.byKey(const Key('spbCentralTemplate-tpl_password')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('spbCentralTemplate-tpl_password')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('createTemplateFromIconContextAction')),
      findsOneWidget,
    );
    expect(find.text('Создать шаблон'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('createTemplateFromIconContextAction')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Image || widget is Icon,
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('viewTemplateContextAction')), findsOneWidget);
    expect(find.byKey(const Key('editTemplateContextAction')), findsOneWidget);
    expect(
      find.byKey(const Key('exportTemplateContextAction')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('importTemplateFromIconContextAction')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('deleteTemplateContextAction')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('createTemplateFromIconContextAction')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('templateEditorSurface')), findsOneWidget);
  });

  testWidgets('navigator sections keep accordion order and template menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    final navigatorContent = find.byKey(const Key('spbNavigatorScrollbar'));
    expect(
      tester.getBottomLeft(find.byKey(const Key('spbMyCardsModeButton'))).dy,
      lessThanOrEqualTo(tester.getTopLeft(navigatorContent).dy),
    );
    expect(
      tester.getBottomLeft(navigatorContent).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const Key('spbTemplatesModeButton'))).dy,
      ),
    );

    await tester.tap(
      find.byKey(const Key('spbTemplatesModeButton')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Создать шаблон'), findsOneWidget);
    expect(find.text('Импортировать шаблон'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('createTemplateContextAction')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Image || widget is Icon,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('importTemplateContextAction')),
        matching: find.byIcon(Icons.file_open_outlined),
      ),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(1100, 800));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('spbTemplatesModeButton')));
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.byKey(const Key('spbMyCardsModeButton'))).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const Key('spbTemplatesModeButton'))).dy,
      ),
    );
    expect(
      tester.getBottomLeft(find.byKey(const Key('spbTemplatesModeButton'))).dy,
      lessThanOrEqualTo(tester.getTopLeft(navigatorContent).dy),
    );
    expect(
      tester.getBottomLeft(navigatorContent).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const Key('spbIconsModeButton'))).dy,
      ),
    );
  });

  testWidgets('template opens in preview by double click', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Шаблоны'));
    await tester.pumpAndSettle();
    final templateIcon =
        find.byKey(const Key('spbCentralTemplate-tpl_password'));
    await tester.tap(templateIcon);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(templateIcon);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('templatePreviewSurface')), findsOneWidget);
    expect(find.byKey(const Key('templatePreviewTitle')), findsOneWidget);
    expect(find.byKey(const Key('templatePreviewCloseButton')), findsOneWidget);
    expect(
        find.byKey(const Key('templatePreviewField-username')), findsOneWidget);
  });

  testWidgets('template empty workspace opens import menu', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Шаблоны'));
    await tester.pumpAndSettle();
    final workspace = find.byKey(const Key('spbTemplateWorkspace'));
    final emptyPoint = tester.getBottomRight(workspace) - const Offset(20, 20);
    await tester.tapAt(emptyPoint, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('createTemplateContextAction')), findsOneWidget);
    expect(find.text('Создать шаблон'), findsOneWidget);
    expect(
        find.byKey(const Key('importTemplateContextAction')), findsOneWidget);

    await tester.tap(find.byKey(const Key('createTemplateContextAction')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('templateEditorSurface')), findsOneWidget);
    expect(find.byKey(const Key('templateNameField')), findsOneWidget);
    expect(find.byKey(const Key('templateBoundIcon')), findsOneWidget);
    expect(find.text('Новый шаблон'), findsOneWidget);
    final newTemplateName = tester.widget<TextField>(
      find.byKey(const Key('templateNameField')),
    );
    expect(newTemplateName.decoration!.fillColor, Colors.white);
    final newTemplateColorPicker = tester.widget<ColorPicker>(
      find.descendant(
        of: find.byKey(const Key('templateEditorSurface')),
        matching: find.byType(ColorPicker),
      ),
    );
    expect(newTemplateColorPicker.value, 'template_white');
    expect(
      tester.getTopLeft(find.byKey(const Key('templateNameField'))).dy,
      tester.getTopLeft(find.byKey(const Key('templateBoundIcon'))).dy,
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('templateNameField'))).dx,
      greaterThan(
        tester.getTopRight(find.byKey(const Key('templateBoundIcon'))).dx,
      ),
    );
    expect(find.byKey(const Key('templateUndoButton')), findsOneWidget);
    expect(find.byKey(const Key('templateSaveButton')), findsNothing);
    expect(find.byKey(const Key('templateCloseButton')), findsOneWidget);
  });

  testWidgets('template right workspace has create context action',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Шаблоны'));
    await tester.pumpAndSettle();
    final rightWorkspace = find.byKey(const Key('spbTemplateRightWorkspace'));
    expect(rightWorkspace, findsOneWidget);
    final point = tester.getBottomRight(rightWorkspace) - const Offset(12, 12);
    await tester.tapAt(point, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('createTemplateRightContextAction')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('importTemplateRightContextAction')),
      findsOneWidget,
    );
    expect(find.text('Создать шаблон'), findsOneWidget);
  });

  testWidgets('card menus are identical in tree and central workspace',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    final template = builtInTemplates().first;
    final item = SecretItem(
      id: 'context-card',
      templateId: template.id,
      title: 'Контекстная карточка',
      category: '',
      colorId: template.colorId,
      values: {template.fields.first.id: 'Значение'},
      modifiedAt: DateTime(2026),
    );
    state.setState(() {
      state.items = [item];
      state.selectedCategoryPath = '';
    });
    await tester.pumpAndSettle();

    Future<void> expectCardMenu(Finder target) async {
      await tester.tap(target, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      for (final key in const [
        'viewCardContextAction',
        'createCardContextAction',
        'editCardContextAction',
        'copyCardContextAction',
        'exportObjectContextAction',
        'importCardContextAction',
        'deleteCardContextAction',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget);
      }
      expect(find.text('Импортировать'), findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
    }

    await expectCardMenu(find.byKey(const Key('spbTreeCard-context-card')));
    await expectCardMenu(
      find.byKey(const Key('spbCentralCard-context-card')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('card export creates password protected and passwordless SWL',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1010));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    final item = SecretItem(
      id: 'test-card',
      templateId: 'tpl_password',
      title: 'Экспортируемая карточка',
      category: 'Тест',
      colorId: 'blue',
      values: const {
        'username': 'tester',
        'password': 'secret-value',
        'notes': 'Примечание',
      },
      modifiedAt: DateTime(2026),
    );
    final directory = Directory.systemTemp.createTempSync('wallet_aps_export_');
    addTearDown(() => directory.deleteSync(recursive: true));

    final protectedPath = '${directory.path}${Platform.pathSeparator}card.swl';
    await state.createSpbItemsExportFile(
      [item],
      password: 'export-password',
      targetPath: protectedPath,
    );
    expect(
      () => SpbWalletDatabase.open(protectedPath, ''),
      throwsA(isA<SpbWalletOpenException>()),
    );
    final protected = SpbWalletDatabase.open(protectedPath, 'export-password');
    final protectedSnapshot = protected.loadSnapshot();
    protected.close();
    expect(protectedSnapshot.cards.single.title, item.title);
    expect(
      protectedSnapshot.cards.single.fieldValues.values,
      containsAll(['tester', 'secret-value', 'Примечание']),
    );

    final openPath = '${directory.path}${Platform.pathSeparator}open.swl';
    await state.createSpbItemsExportFile(
      [item],
      password: '',
      targetPath: openPath,
    );
    final passwordless = SpbWalletDatabase.open(openPath, '');
    expect(passwordless.loadSnapshot().cards.single.title, item.title);
    passwordless.close();
  });

  testWidgets('object menus do not open the empty workspace menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1010));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    state.items = [
      SecretItem(
        id: 'menu-card',
        templateId: 'tpl_password',
        title: 'Карточка меню',
        category: 'Папка меню',
        colorId: 'blue',
        values: const {'username': 'tester'},
        modifiedAt: DateTime(2026),
      ),
    ];
    state.selectedCategoryPath = 'Папка меню';
    state.setState(() {});
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('spbCentralCard-menu-card')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exportObjectContextAction')), findsOneWidget);
    expect(find.byKey(const Key('copyCardContextAction')), findsOneWidget);
    expect(find.text('Создать карточку'), findsNothing);
    expect(find.text('Создать папку'), findsNothing);

    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    final workspace = find.byKey(const Key('spbCentralWorkspace'));
    final emptyPoint = tester.getBottomRight(workspace) - const Offset(20, 20);
    await tester.tapAt(emptyPoint, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Создать карточку'), findsOneWidget);
    expect(find.text('Создать папку'), findsOneWidget);
    expect(find.text('Импорт'), findsOneWidget);
  });
}
