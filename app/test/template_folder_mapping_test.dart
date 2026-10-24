import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wallet_aps/features/templates/template_folders.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';

void main() {
  test('default template folders are alphabetical and include empty folders',
      () {
    expect(defaultTemplateFolders, hasLength(11));
    final sorted = [...defaultTemplateFolders]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    expect(defaultTemplateFolders, sorted);
    expect(defaultTemplateFolders,
        containsAll(['Интернет', 'Банковские счета', 'Заметки']));
  });

  test('legacy name prefix determines folder before existing metadata', () {
    expect(templateFolderFor('компьютеры: Сеть', ''), 'Компьютеры');
    expect(templateFolderFor('Кредитная карта: Visa', ''), 'Кредитная карта');
    expect(templateFolderFor('Шаблон без префикса', ''), 'Другие');
    expect(templateFolderFor('Своя группа: Сервер', ''), 'Своя группа');
    expect(templateFolderFor('Компьютеры: Сеть', 'Интернет'), 'Компьютеры');
    expect(templateFolderFor('Сервер', 'Работа / Серверы'), 'Работа');
    expect(templateFolderFor(' : Имя', 'Личные'), 'Личные');
    expect(
        templateCategoryPathFor('Компьютеры: Сеть', 'Интернет'), 'Компьютеры');
    expect(templateCategoryPathFor('Сеть', 'Работа / Серверы'),
        'Работа / Серверы');
    expect(templateCategoryPathFor('Компьютеры:', 'Интернет'), 'Интернет');
    expect(templateLabelInFolder('компьютеры: Сеть', 'Компьютеры'), 'Сеть');
    expect(templateLabelInFolder('Компьютеры: Сеть', 'Интернет'),
        'Компьютеры: Сеть');
    expect(templateLabelInFolder('Компьютеры:', 'Компьютеры'), 'Компьютеры:');
  });

  test('template folder survives database reopen without rewriting IDs', () {
    final directory = Directory.systemTemp.createTempSync('template-folders-');
    final path = '${directory.path}${Platform.pathSeparator}synthetic.swl';
    addTearDown(() => directory.deleteSync(recursive: true));
    const id = 'A123456789ABCDEF';
    final database = SpbWalletDatabase.create(path, '');
    try {
      database.saveTemplate(
        const SpbWalletTemplateDraft(
          id: id,
          name: 'Сайт',
          categoryPath: 'Интернет',
          fields: [],
        ),
      );
      database.flushToDisk();
    } finally {
      database.close();
    }
    final reopened = SpbWalletDatabase.open(path, '');
    try {
      final template = reopened.loadSnapshot().templates.single;
      expect(template.id, id);
      expect(template.name, 'Сайт');
      expect(template.categoryPath, 'Интернет');
      expect(
          templateFolderFor(template.name, template.categoryPath), 'Интернет');
    } finally {
      reopened.close();
    }
  });

  test('saving separated name preserves links, values and unknown metadata',
      () {
    final directory = Directory.systemTemp.createTempSync('template-rename-');
    final path = '${directory.path}${Platform.pathSeparator}synthetic.swl';
    addTearDown(() => directory.deleteSync(recursive: true));
    const templateId = 'A123456789ABCDEF';
    const fieldId = 'B123456789ABCDEF';
    const cardId = 'C123456789ABCDEF';
    final original = SpbWalletDatabase.create(path, '');
    try {
      original.saveTemplate(const SpbWalletTemplateDraft(
        id: templateId,
        name: 'Компьютеры: Сеть',
        categoryPath: 'Интернет',
        fields: [
          SpbWalletTemplateFieldRecord(
            id: fieldId,
            name: 'Сервер',
            templateId: templateId,
            fieldTypeId: 1,
          )
        ],
      ));
      original.saveCard(SpbWalletCardDraft(
        id: cardId,
        description: '',
        title: 'Тестовая карточка',
        categoryPath: '',
        templateId: templateId,
        fieldValues: const {fieldId: 'Сохранённое значение'},
        modifiedAt: DateTime.utc(2026),
      ));
      original.flushToDisk();
    } finally {
      original.close();
    }
    final legacy = sqlite3.open(path);
    try {
      legacy.execute(
          'ALTER TABLE spbwlt_Template ADD COLUMN CompatibilityNote TEXT');
      legacy.execute(
          'ALTER TABLE spbwlt_TemplateField ADD COLUMN CompatibilityNote TEXT');
      legacy.execute(
          "UPDATE spbwlt_Template SET CompatibilityNote = 'keep-template'");
      legacy.execute(
          "UPDATE spbwlt_TemplateField SET CompatibilityNote = 'keep-field'");
    } finally {
      legacy.dispose();
    }
    final editing = SpbWalletDatabase.open(path, '');
    try {
      final template = editing.loadSnapshot().templates.single;
      expect(template.name, 'Компьютеры: Сеть');
      final folder = templateFolderFor(template.name, template.categoryPath);
      editing.saveTemplate(SpbWalletTemplateDraft(
        id: template.id,
        name: templateLabelInFolder(template.name, folder),
        categoryPath:
            templateCategoryPathFor(template.name, template.categoryPath),
        fields: template.fields,
      ));
      editing.flushToDisk();
    } finally {
      editing.close();
    }
    final reopened = SpbWalletDatabase.open(path, '');
    try {
      final snapshot = reopened.loadSnapshot();
      final template = snapshot.templates.single;
      expect(template.id, templateId);
      expect(template.name, 'Сеть');
      expect(template.categoryPath, 'Компьютеры');
      expect(template.fields.single.id, fieldId);
      expect(snapshot.cards.single.id, cardId);
      expect(snapshot.cards.single.templateId, templateId);
      expect(
          snapshot.cards.single.fieldValues[fieldId], 'Сохранённое значение');
    } finally {
      reopened.close();
    }
    final preserved = sqlite3.open(path);
    try {
      expect(
          preserved
              .select('SELECT CompatibilityNote FROM spbwlt_Template')
              .single['CompatibilityNote'],
          'keep-template');
      expect(
          preserved
              .select('SELECT CompatibilityNote FROM spbwlt_TemplateField')
              .single['CompatibilityNote'],
          'keep-field');
    } finally {
      preserved.dispose();
    }
  });
}
