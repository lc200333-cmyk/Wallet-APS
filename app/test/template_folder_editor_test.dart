import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/features/templates/template_folders.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/services/wallet_rekey_service.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';

void main() {
  test('template folder edits persist, preserve cards and survive rekey', () {
    final directory =
        Directory.systemTemp.createTempSync('template-folder-edit-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}/synthetic.swl';
    var wallet = SpbWalletDatabase.create(path, '');
    const templateId = 'A123456789ABCDEF';
    const fieldId = 'B123456789ABCDEF';
    wallet.saveTemplate(const SpbWalletTemplateDraft(
      id: templateId,
      name: 'Компьютеры: Сеть',
      fields: [
        SpbWalletTemplateFieldRecord(
            id: fieldId, templateId: templateId, name: 'Сервер'),
      ],
    ));
    wallet.saveCard(const SpbWalletCardDraft(
        id: 'C123456789ABCDEF',
        title: 'Сервер',
        description: 'Описание',
        categoryPath: 'Компьютеры',
        templateId: templateId,
        fieldValues: {fieldId: 'Значение'}));
    final categoryId = wallet.loadSnapshot().categories.single.id;
    wallet.editTemplateFolder('Компьютеры', 'Работа',
        iconId: 'key', colorId: 'template_green');
    wallet.editTemplateFolder('Заметки', 'Мои заметки',
        iconId: 'folder', colorId: 'template_white');
    expect(
        () => wallet.editTemplateFolder('Работа', 'Интернет',
            iconId: 'key', colorId: 'template_red'),
        throwsA(isA<SpbWalletOpenException>()));
    expect(
        () => wallet.editTemplateFolder('Работа', 'Нельзя: имя',
            iconId: 'key', colorId: 'template_red'),
        throwsA(isA<SpbWalletOpenException>()));
    wallet.close(flush: true);
    WalletRekeyService.rekeyFile(path,
        oldPassword: '', newPassword: 'synthetic-password');
    wallet = SpbWalletDatabase.open(path, 'synthetic-password');
    try {
      final snapshot = wallet.loadSnapshot();
      final template = snapshot.templates.single;
      expect(template.id, templateId);
      expect(templateFolderFor(template.name, template.categoryPath), 'Работа');
      expect(templateLabelInFolder(template.name, 'Работа'), 'Сеть');
      expect(template.fields.single.id, fieldId);
      expect(snapshot.cards.single.templateId, templateId);
      expect(snapshot.cards.single.fieldValues[fieldId], 'Значение');
      expect(snapshot.cards.single.categoryPath, 'Компьютеры');
      expect(snapshot.categories.single.id, categoryId);
      expect(snapshot.categories.single.name, 'Компьютеры');
      final folders = wallet.loadTemplateFolders();
      expect(folders.singleWhere((f) => f.name == 'Компьютеры').hidden, isTrue);
      final edited = folders.singleWhere((f) => f.name == 'Работа');
      expect(edited.hidden, isFalse);
      expect(edited.iconId, 'key');
      expect(edited.colorId, 'template_green');
      expect(
          folders.singleWhere((f) => f.name == 'Мои заметки').hidden, isFalse);
    } finally {
      wallet.close();
    }
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('folder context opens shared editor on ${platform.name}',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.binding.setSurfaceSize(platform == TargetPlatform.windows
          ? const Size(1280, 900)
          : const Size(360, 800));
      final directory =
          Directory.systemTemp.createTempSync('template-folder-ui-');
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.binding.setSurfaceSize(null);
        directory.deleteSync(recursive: true);
      });
      final path = '${directory.path}/synthetic.swl';
      final wallet = SpbWalletDatabase.create(path, '');
      await tester.pumpWidget(
          const MaterialApp(home: VaultShell(initiallyUnlocked: true)));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(VaultShell));
      state.setState(() {
        state.spbWallet = wallet;
        state.applySpbSnapshot(wallet.loadSnapshot());
      });
      await tester.tap(find.byKey(const Key('spbTemplatesModeButton')));
      await tester.pumpAndSettle();
      Future<void> openEditor(String folder) async {
        final row = find.byKey(ValueKey('spbTemplateFolder-$folder'));
        await tester.ensureVisible(row);
        if (platform == TargetPlatform.windows) {
          await tester.tap(row, buttons: kSecondaryMouseButton);
        } else {
          await tester.longPress(row);
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('createTemplateContextAction')),
            findsOneWidget);
        expect(find.byKey(const Key('importTemplateContextAction')),
            findsOneWidget);
        await tester
            .tap(find.byKey(const Key('editTemplateFolderContextAction')));
        await tester.pumpAndSettle();
        expect(find.byType(CategoryEditorDialog), findsOneWidget);
        expect(find.byKey(const Key('categoryDeleteButton')), findsNothing);
        expect(find.text('Редактировать папку'), findsOneWidget);
        expect(
            tester
                .widget<TextField>(find.byKey(const Key('categoryNameField')))
                .controller!
                .text,
            folder);
      }

      await openEditor('Заметки');
      await tester.enterText(
          find.byKey(const Key('categoryNameField')), 'Не сохранять');
      await tester.tap(find.byKey(const Key('categoryCloseButton')));
      await tester.pumpAndSettle();
      expect(wallet.loadTemplateFolders(), isEmpty);
      await openEditor('Заметки');
      await tester.enterText(
          find.byKey(const Key('categoryNameField')), 'Мои заметки');
      final dynamic editor = tester.state(find.byType(CategoryEditorDialog));
      editor.setState(() {
        editor.iconId = 'key';
        editor.colorId = 'template_green';
      });
      await tester.pump();
      await tester.tap(find.byKey(const Key('categorySaveButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('spbTemplateFolder-Заметки')),
          findsNothing);
      expect(find.byKey(const ValueKey('spbTemplateFolder-Мои заметки')),
          findsOneWidget);
      expect(state.selectedTemplateFolder, 'Мои заметки');
      await openEditor('Мои заметки');
      final reopened = tester
          .widget<CategoryEditorDialog>(find.byType(CategoryEditorDialog));
      expect(reopened.initialIconId, 'key');
      expect(reopened.initialColorId, 'template_green');
      await tester.tap(find.byKey(const Key('categoryCloseButton')));
      await tester.pumpAndSettle();
      await state.restoreSessionUndoAt(0);
      await tester.pumpAndSettle();
      expect(state.selectedTemplateFolder, isNull);
      expect(find.byKey(const ValueKey('spbTemplateFolder-Заметки')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('spbTemplateFolder-Мои заметки')),
          findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
