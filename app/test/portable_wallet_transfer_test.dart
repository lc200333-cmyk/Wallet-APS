import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';

class _Picker extends FilePicker {
  _Picker(this.file);
  final File file;
  @override
  Future<FilePickerResult?> pickFiles(
          {String? dialogTitle,
          String? initialDirectory,
          FileType type = FileType.any,
          List<String>? allowedExtensions,
          Function(FilePickerStatus)? onFileLoading,
          bool allowCompression = false,
          int compressionQuality = 0,
          bool allowMultiple = false,
          bool withData = false,
          bool withReadStream = false,
          bool lockParentWindow = false,
          bool readSequential = false}) async =>
      FilePickerResult([
        PlatformFile(
            name: 'Source.swl', path: file.path, size: file.lengthSync()),
      ]);
}

Uint8List _png(int red, int green, int blue) {
  final pixels = image.Image(width: 64, height: 64, numChannels: 4);
  image.fill(pixels, color: image.ColorRgba8(red, green, blue, 255));
  return Uint8List.fromList(image.encodePng(pixels));
}

const _icon = 'A123456789ABCDEF';
const _template = 'B123456789ABCDEF';
const _field = 'C123456789ABCDEF';
const _card = 'D123456789ABCDEF';

void _populate(SpbWalletDatabase wallet, Uint8List bytes) {
  wallet.saveTemplate(SpbWalletTemplateDraft(
      id: _template,
      name: 'Source template',
      iconId: _icon,
      iconBytes: bytes,
      categoryPath: 'Templates',
      fields: const [
        SpbWalletTemplateFieldRecord(
            id: _field, templateId: _template, name: 'Login'),
      ]));
  wallet.createCategory('Source', _icon, colorId: 'template_green');
  wallet.createCategory('Templates', _icon, colorId: 'template_red');
  wallet.createCategory('Source / Empty', _icon, colorId: 'template_blue');
  wallet.saveCard(SpbWalletCardDraft(
      id: _card,
      title: 'Transferred card',
      templateId: _template,
      categoryPath: 'Source',
      iconId: _icon,
      description: 'Description',
      fieldValues: const {_field: 'user@example.test'},
      fieldOrder: const [_field],
      hiddenFieldIds: const {_field},
      modifiedAt: DateTime(2026, 1, 2)));
  wallet.saveAttachment(
      cardId: _card, fileName: 'data.bin', bytes: const [1, 2, 3, 4]);
}

void main() {
  FilePicker.platform = _Picker(File('unused.swl'));
  testWidgets(
      'export includes icons, empty folders, field layout and attachments',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('portable-export-');
    final source = SpbWalletDatabase.create(
        '${directory.path}/source.swl', 'source-password');
    _populate(source, _png(12, 180, 30));
    const folderIcon = 'E123456789ABCDEF';
    const templateIcon = 'F123456789ABCDEF';
    for (final path in ['Source', 'Source / Empty', 'Templates']) {
      source.createCategory(path, folderIcon, iconBytes: _png(30, 40, 210));
    }
    source.saveTemplate(SpbWalletTemplateDraft(
        id: _template,
        name: 'Source template',
        iconId: templateIcon,
        iconBytes: _png(200, 70, 90),
        categoryPath: 'Templates',
        fields: const [
          SpbWalletTemplateFieldRecord(
              id: _field, templateId: _template, name: 'Login'),
        ]));
    final originalBytes = source.readEmbeddedIconBytes(_icon)!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      directory.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
        const MaterialApp(home: VaultShell(initiallyUnlocked: true)));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    state.setState(() {
      state.spbWallet = source;
      state.applySpbSnapshot(source.loadSnapshot());
    });
    await tester.pumpAndSettle();
    final path = '${directory.path}/export.swl';
    await tester.runAsync(() async {
      await state.createSpbItemsExportFile(List<SecretItem>.from(state.items),
          password: 'export-password',
          categoryPath: 'Source',
          targetPath: path);
    });
    final exported = SpbWalletDatabase.open(path, 'export-password');
    try {
      final snapshot = exported.loadSnapshot();
      expect(exported.readEmbeddedIconBytes(_icon), originalBytes);
      expect(snapshot.templates.single.iconId, templateIcon);
      expect(exported.readEmbeddedIconBytes(templateIcon),
          source.readEmbeddedIconBytes(templateIcon));
      expect(exported.readEmbeddedIconBytes(folderIcon),
          source.readEmbeddedIconBytes(folderIcon));
      expect(snapshot.cards.single.iconId, _icon);
      for (final category in snapshot.categories) {
        expect(exported.readEmbeddedIconBytes(category.iconId), isNotNull);
        if (category.name == 'Source' || category.name == 'Empty') {
          expect(category.iconId, folderIcon);
        }
      }
      expect(snapshot.categories.map((entry) => entry.name),
          containsAll(['Source', 'Empty']));
      expect(
          snapshot.categories
              .firstWhere((entry) => entry.name == 'Source')
              .colorId,
          'template_green');
      final card = snapshot.cards.single;
      final fieldId = snapshot.templates.single.fields.single.id;
      expect(card.fieldValues[fieldId], 'user@example.test');
      expect(card.fieldOrder, [fieldId]);
      expect(card.hiddenFieldIds, {fieldId});
      expect(card.description, 'Description');
      expect(exported.readAttachmentBytes(card.attachments.single.id),
          [1, 2, 3, 4]);
      expect(source.readEmbeddedIconBytes(_icon), originalBytes);
    } finally {
      exported.close();
    }
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets(
        'import keeps colliding icons and offers a missing template on ${platform.name}',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final directory = Directory.systemTemp.createTempSync('portable-import-');
      final sourceFile = File('${directory.path}/source.swl');
      final source = SpbWalletDatabase.create(sourceFile.path, '');
      _populate(source, _png(10, 180, 30));
      source.saveExportedFolderPath('Source');
      final sourceIcon = source.readEmbeddedIconBytes(_icon)!;
      source.close();
      final destination =
          SpbWalletDatabase.create('${directory.path}/destination.swl', '');
      destination.saveTemplate(const SpbWalletTemplateDraft(
          id: _template,
          name: 'Source template',
          fields: [
            SpbWalletTemplateFieldRecord(
                id: _field, templateId: _template, name: 'Different schema'),
          ]));
      destination.saveIcon(_icon, _png(200, 20, 10));
      destination.saveCard(const SpbWalletCardDraft(
          id: _card,
          title: 'Existing card',
          description: '',
          fieldValues: {},
          templateId: _template,
          categoryPath: 'Existing',
          iconId: _icon));
      final existingIcon = destination.readEmbeddedIconBytes(_icon)!;
      final previousPicker = FilePicker.platform;
      FilePicker.platform = _Picker(sourceFile);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        FilePicker.platform = previousPicker;
        debugDefaultTargetPlatformOverride = null;
        await tester.binding.setSurfaceSize(null);
        directory.deleteSync(recursive: true);
      });
      try {
        await tester.binding.setSurfaceSize(platform == TargetPlatform.windows
            ? const Size(1280, 900)
            : const Size(390, 844));
        await tester.pumpWidget(
            const MaterialApp(home: VaultShell(initiallyUnlocked: true)));
        await tester.pumpAndSettle();
        final dynamic state = tester.state(find.byType(VaultShell));
        state.setState(() {
          state.spbWallet = destination;
          state.applySpbSnapshot(destination.loadSnapshot());
        });
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await state.importSpbWalletCards(destinationCategoryPath: 'Target');
        });
        await tester.pumpAndSettle();
        final snapshot = destination.loadSnapshot();
        final imported = snapshot.cards
            .singleWhere((card) => card.title == 'Transferred card');
        expect(snapshot.cards.length, 2);
        expect(imported.iconId, isNot(_icon));
        expect(destination.readEmbeddedIconBytes(imported.iconId), sourceIcon);
        expect(destination.readEmbeddedIconBytes(_icon), existingIcon);
        expect(imported.templateId, isNot(_template));
        expect(imported.fieldValues.values, contains('user@example.test'));
        expect(
            snapshot.categories
                .firstWhere((entry) => entry.name == 'Empty')
                .iconId,
            imported.iconId);
        final templateFolder = snapshot.categories
            .firstWhere((entry) => entry.name == 'Templates');
        expect(templateFolder.iconId, imported.iconId);
        expect(templateFolder.colorId, 'template_red');
        expect(destination.readAttachmentBytes(imported.attachments.single.id),
            [1, 2, 3, 4]);
        expect(
            find.byKey(const Key('importedTemplateProposal')), findsOneWidget);
        if (platform == TargetPlatform.windows) {
          await tester.tap(find.byKey(const Key('createImportedTemplate')));
          await tester
              .runAsync(() async => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();
          expect(find.byType(TemplateEditorDialog), findsOneWidget);
          await tester.enterText(find.byKey(const Key('templateNameField')),
              'Created after import');
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('templateSaveButton')));
          await tester.runAsync(() async =>
              Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pumpAndSettle();
          expect(
              destination
                  .loadSnapshot()
                  .templates
                  .singleWhere((entry) => entry.id == imported.templateId)
                  .name,
              'Created after import');
        } else {
          await tester.tap(find.byKey(const Key('skipImportedTemplate')));
          await tester.pumpAndSettle();
        }
        expect(destination.loadSnapshot().cards.length, 2);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
