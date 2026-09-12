import 'dart:io';

import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('date formatter inserts separators immediately after day and month', () {
    final formatter = DateTextInputFormatter();
    var value = TextEditingValue.empty;

    TextEditingValue enter(String text) {
      value = formatter.formatEditUpdate(
        value,
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );
      return value;
    }

    expect(enter('1').text, '1');
    expect(enter('12').text, '12.');
    expect(enter('12.3').text, '12.3');
    expect(enter('12.34').text, '12.34.');
    expect(enter('12.34.2026').text, '12.34.2026');
    expect(enter('12.34.20267').text, '12.34.2026');

    value = const TextEditingValue(
      text: '12.',
      selection: TextSelection.collapsed(offset: 3),
    );
    expect(enter('12').text, '1');
  });

  test('Linux new-vault picker normalizes a selected file to its folder', () {
    final separator = Platform.pathSeparator;
    final filePath = ['tmp', 'wallets', 'existing.swl'].join(separator);
    expect(
      normalizeNewVaultDirectorySelection(filePath, FileSystemEntityType.file),
      ['tmp', 'wallets'].join(separator),
    );
    expect(
      normalizeNewVaultDirectorySelection(
        ['tmp', 'wallets'].join(separator),
        FileSystemEntityType.directory,
      ),
      ['tmp', 'wallets'].join(separator),
    );
    expect(
      normalizeNewVaultDirectorySelection(
        filePath,
        FileSystemEntityType.notFound,
      ),
      isNull,
    );
  });

  test('new wallet is cloned from MyWallet and encrypted with new password',
      () async {
    final baseFile = File('assets/base_wallet/MyWallet.swl');
    expect(baseFile.existsSync(), isTrue);
    final source = SpbWalletDatabase.open(baseFile.path, '0000');
    final sourceSnapshot = source.loadSnapshot();
    source.close(flush: false);
    final directory = await Directory.systemTemp.createTemp('mywallet_clone_');
    final targetPath = '${directory.path}${Platform.pathSeparator}created.swl';
    addTearDown(() => directory.deleteSync(recursive: true));

    expect(
      createSwlVaultFromBaseFile({
        'path': targetPath,
        'password': 'new-password',
        'passwordHint': 'Любимая книга',
        'baseBytes': baseFile.readAsBytesSync(),
      }),
      isTrue,
    );

    expect(
      () => SpbWalletDatabase.open(targetPath, '0000'),
      throwsA(isA<SpbWalletOpenException>()),
    );
    final created = SpbWalletDatabase.open(targetPath, 'new-password');
    final createdSnapshot = created.loadSnapshot();
    expect(createdSnapshot.templates.length, sourceSnapshot.templates.length);
    expect(createdSnapshot.cards.length, sourceSnapshot.cards.length);
    expect(createdSnapshot.categories.length, sourceSnapshot.categories.length);
    expect(
      createdSnapshot.categories
          .where((category) => category.name == 'О программе SPB Wallet'),
      isEmpty,
    );
    expect(
      createdSnapshot.categories
          .where((category) => category.name == 'О программе Wallet'),
      hasLength(1),
    );
    expect(
      createdSnapshot.templates.map((template) => template.name).toSet(),
      sourceSnapshot.templates.map((template) => template.name).toSet(),
    );
    created.close(flush: false);
    expect(
      SpbWalletDatabase.readPasswordHint(targetPath),
      'Любимая книга',
    );

    final changedPath =
        '${directory.path}${Platform.pathSeparator}password-changed.swl';
    const crossPlatformPassword = 'Пароль-Android-Windows-42!';
    expect(
      cloneSwlVaultWithPassword({
        'path': changedPath,
        'password': crossPlatformPassword,
        'sourcePassword': 'new-password',
        'passwordHint': 'Новая подсказка',
        'baseBytes': File(targetPath).readAsBytesSync(),
      }),
      isTrue,
    );
    expect(
      () => SpbWalletDatabase.open(changedPath, 'new-password'),
      throwsA(isA<SpbWalletOpenException>()),
    );
    final changed = SpbWalletDatabase.open(changedPath, crossPlatformPassword);
    expect(changed.loadSnapshot().cards.length, sourceSnapshot.cards.length);
    changed.close(flush: false);
    expect(
      SpbWalletDatabase.readPasswordHint(changedPath),
      'Новая подсказка',
    );
  });

  test('template category survives SQLite round-trip', () async {
    final directory =
        await Directory.systemTemp.createTemp('template_category_');
    final path = '${directory.path}${Platform.pathSeparator}category.swl';
    final wallet = SpbWalletDatabase.create(path, '2468');
    addTearDown(() {
      wallet.close();
      directory.deleteSync(recursive: true);
    });
    const templateId = '7171717171717171';
    wallet.createCategory('Работа / Серверы', '');
    wallet.saveTemplate(
      const SpbWalletTemplateDraft(
        id: templateId,
        name: 'Сервер',
        categoryPath: 'Работа / Серверы',
        fields: [],
      ),
    );

    expect(
      wallet.loadSnapshot().templates.single.categoryPath,
      'Работа / Серверы',
    );
  });

  testWidgets('template name is fixed below palette and required',
      (tester) async {
    CardTemplate? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<CardTemplate>(
                context: context,
                builder: (_) => const TemplateEditorDialog(),
              );
            },
            child: const Text('Открыть'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    final colorTop = tester
        .getTopLeft(
          find.byKey(
            ValueKey('templateColor-${templateColorPalette.first.id}'),
          ),
        )
        .dy;
    final nameTop =
        tester.getTopLeft(find.byKey(const Key('templateNameField'))).dy;
    expect(nameTop, greaterThan(colorTop));
    expect(find.byKey(const Key('templateCategoryField')), findsNothing);

    await tester.tap(find.byKey(const Key('templateSaveButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('templateNameField')), findsOneWidget);
    expect(find.text('Название обязательно'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('templateNameField')),
      'Сервер',
    );
    await tester.tap(find.byKey(const Key('templateSaveButton')));
    await tester.pumpAndSettle();

    expect(saved?.name, 'Сервер');
  });

  test('card description, layout and modified date survive SQLite round-trip',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('layout_roundtrip_');
    final path = '${directory.path}${Platform.pathSeparator}layout.swl';
    final wallet = SpbWalletDatabase.create(path, '2468');
    addTearDown(() {
      wallet.close();
      directory.deleteSync(recursive: true);
    });
    const templateId = '1111111111111111';
    const firstField = '2222222222222222';
    const secondField = '3333333333333333';
    const cardId = '4444444444444444';
    final modifiedAt = DateTime.utc(2026, 7, 31, 12, 30);
    wallet.saveTemplate(
      const SpbWalletTemplateDraft(
        id: templateId,
        name: 'Проверка данных',
        fields: [
          SpbWalletTemplateFieldRecord(
            id: firstField,
            name: 'Первое поле',
            templateId: templateId,
            fieldTypeId: 1,
          ),
          SpbWalletTemplateFieldRecord(
            id: secondField,
            name: 'Второе поле',
            templateId: templateId,
            fieldTypeId: 1,
          ),
        ],
      ),
    );
    wallet.saveCard(
      SpbWalletCardDraft(
        id: cardId,
        title: 'Карточка',
        description: 'Важная заметка',
        categoryPath: 'Папка',
        templateId: templateId,
        fieldValues: const {firstField: 'A', secondField: 'B'},
        fieldOrder: const [secondField],
        hiddenFieldIds: const {firstField},
        modifiedAt: modifiedAt,
      ),
    );

    final card = wallet.loadSnapshot().cards.single;
    expect(card.description, 'Важная заметка');
    expect(card.fieldValues, const {firstField: 'A', secondField: 'B'});
    expect(card.fieldOrder, const [secondField]);
    expect(card.hiddenFieldIds, const {firstField});
    expect(card.modifiedAt, modifiedAt);
  });

  testWidgets('card editor exposes and preserves the database description',
      (tester) async {
    const description = FieldDefinition(
      id: spbDescriptionFieldId,
      label: 'Заметки',
      type: 'multiline_note',
    );
    const template = CardTemplate(
      id: 'template',
      name: 'Шаблон',
      iconId: 'key',
      colorId: 'neutral',
      fields: [description],
    );
    final item = SecretItem(
      id: 'card',
      templateId: template.id,
      title: 'Карточка',
      category: '',
      colorId: 'neutral',
      values: const {spbDescriptionFieldId: 'Не потерять'},
      modifiedAt: DateTime(2026),
    );
    SecretItem? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<SecretItem>(
                context: context,
                builder: (_) => ItemEditorDialog(
                  templates: const [template],
                  categories: const [],
                  initial: item,
                ),
              );
            },
            child: const Text('Открыть'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('cardField-$spbDescriptionFieldId')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('cardSaveButton')));
    await tester.pumpAndSettle();
    expect(saved?.values[spbDescriptionFieldId], 'Не потерять');
  });

  test('orphan values participate in the common field projection', () {
    const template = CardTemplate(
      id: 'template',
      name: 'Шаблон',
      iconId: 'key',
      colorId: 'neutral',
      fields: [],
    );
    final item = SecretItem(
      id: 'card',
      templateId: template.id,
      title: 'Карточка',
      category: '',
      colorId: 'neutral',
      values: const {'DEADBEEF12345678': 'Сохранено'},
      modifiedAt: DateTime(2026),
    );
    final fields = fieldsForItem(template, item);
    expect(fields.single.id, 'DEADBEEF12345678');
    expect(fields.single.label, startsWith('Сохранённое поле'));
  });

  test('empty orphan values do not create saved field placeholders', () {
    const template = CardTemplate(
      id: 'template',
      name: 'Шаблон',
      iconId: 'key',
      colorId: 'neutral',
      fields: [],
    );
    final item = SecretItem(
      id: 'card',
      templateId: template.id,
      title: 'Карточка',
      category: '',
      colorId: 'neutral',
      values: const {
        'DEADBEEF12345678': '   ',
        'LEGACYURL1234567': 'http://www',
      },
      modifiedAt: DateTime(2026),
    );

    expect(fieldsForItem(template, item), isEmpty);
  });

  testWidgets('card editor omits fields left empty when saving',
      (tester) async {
    const template = CardTemplate(
      id: 'template',
      name: 'Шаблон',
      iconId: 'key',
      colorId: 'neutral',
      fields: [
        FieldDefinition(id: 'filled', label: 'Заполнено', type: 'text'),
        FieldDefinition(id: 'empty', label: 'Пусто', type: 'text'),
        FieldDefinition(id: 'url', label: 'Сайт', type: 'url'),
      ],
    );
    SecretItem? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<SecretItem>(
                context: context,
                builder: (_) => const ItemEditorDialog(
                  templates: [template],
                  categories: [],
                ),
              );
            },
            child: const Text('Открыть'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('cardField-url')))
          .controller
          ?.text,
      isEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('cardField-filled')),
      'Значение',
    );
    await tester.tap(find.byKey(const Key('cardSaveButton')));
    await tester.pumpAndSettle();

    expect(saved?.values, const {'filled': 'Значение'});
  });

  testWidgets('legacy empty orphan fields stay hidden while editing',
      (tester) async {
    const template = CardTemplate(
      id: 'template',
      name: 'Шаблон',
      iconId: 'key',
      colorId: 'neutral',
      fields: [
        FieldDefinition(id: 'known', label: 'Обычное поле', type: 'text'),
      ],
    );
    final item = SecretItem(
      id: 'card',
      templateId: template.id,
      title: 'Карточка',
      category: '',
      colorId: 'neutral',
      values: const {
        'EMPTY1234567890': '',
        'LEGACYURL1234567': 'http://www',
      },
      modifiedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ItemEditorDialog(
          templates: const [template],
          categories: const [],
          initial: item,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cardField-known')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('cardField-EMPTY1234567890')), findsNothing);
    expect(
        find.byKey(const ValueKey('cardField-LEGACYURL1234567')), findsNothing);
    expect(find.textContaining('Сохранённое поле'), findsNothing);
  });

  testWidgets('selected category follows its ID after rename', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1010));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    const id = 'AAAAAAAAAAAAAAAA';
    state.applySpbSnapshot(
      const SpbWalletSnapshot(
        templates: [],
        cards: [],
        categories: [
          SpbWalletCategoryRecord(
            id: id,
            name: 'Старое имя',
            parentId: '',
            iconId: '',
          ),
        ],
        embeddedIconPngs: {},
      ),
    );
    state.selectedCategoryId = id;
    state.selectedCategoryPath = 'Старое имя';
    state.applySpbSnapshot(
      const SpbWalletSnapshot(
        templates: [],
        cards: [],
        categories: [
          SpbWalletCategoryRecord(
            id: id,
            name: 'Новое имя',
            parentId: '',
            iconId: '',
          ),
        ],
        embeddedIconPngs: {},
      ),
    );
    expect(state.selectedCategoryId, id);
    expect(state.selectedCategoryPath, 'Новое имя');
  });
}
