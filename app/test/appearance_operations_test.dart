import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/appearance/appearance.dart';
import 'package:wallet_aps/appearance/appearance_controller.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';
import 'appearance_test.dart' show themed;

void main() {
  for (final mode in AppAppearance.values) {
    testWidgets(
        '${mode.name}: synthetic CRUD, copy, move, trash/undo, attachment, export and reopen',
        (tester) async {
      final temp =
          Directory.systemTemp.createTempSync('appearance-operations-');
      final path = '${temp.path}/synthetic.swl';
      final wallet = SpbWalletDatabase.create(path, 'test-only');
      final c = AppearanceController(initial: mode);
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      dynamic state;
      try {
        wallet.createCategory('Начало', '');
        wallet.createCategory('Назначение', '');
        await tester
            .pumpWidget(themed(c, const VaultShell(initiallyUnlocked: true)));
        await tester.pumpAndSettle();
        state = tester.state(find.byType(VaultShell));
        state.setState(() {
          state.spbWallet = wallet;
          state.applySpbSnapshot(wallet.loadSnapshot());
        });
        const template = CardTemplate(
            id: 'draft-template',
            name: 'Тест',
            iconId: SpbWalletDatabase.defaultCardIconId,
            colorId: 'template_white',
            spbColor: 0x8236ac,
            fields: [
              FieldDefinition(id: 'field-login', label: 'Логин', type: 'text')
            ]);
        final saved = await tester.runAsync<bool>(() async => await state
            .saveSpbTemplateDefinition(template, isNew: true) as bool);
        expect(saved, isTrue);
        await tester.pumpAndSettle();
        final CardTemplate storedTemplate = state.templates.single;
        final fieldId = storedTemplate.fields
            .firstWhere((f) => f.id != spbDescriptionFieldId)
            .id;
        SecretItem card(String title, String value,
                {String id = 'draft-card'}) =>
            SecretItem(
                id: id,
                templateId: storedTemplate.id,
                title: title,
                category: 'Начало',
                colorId: 'template_white',
                spbColor: 0x8236ac,
                iconId: SpbWalletDatabase.defaultCardIconId,
                values: {fieldId: value},
                modifiedAt: DateTime.utc(2026),
                fieldOrder: [fieldId]);
        final id = await tester.runAsync<String?>(() async =>
            await state.persistItem(card('Создана', 'user')) as String?);
        expect(id, isNotNull);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await state.persistItem(card('Изменена', 'edited', id: id!));
        });
        expect(state.items.single.values[fieldId], 'edited');
        wallet.saveAttachment(
            cardId: id!, fileName: 'тест.txt', bytes: const [1, 2, 3, 255]);
        state.setState(() {
          state.applySpbSnapshot(wallet.loadSnapshot());
        });
        await tester.pumpAndSettle();
        SecretItem current = state.items.single;
        await tester.runAsync(() async {
          await state.cloneSpbCard(current);
        });
        await tester.pumpAndSettle();
        expect(state.items, hasLength(2));
        await tester.runAsync(() async {
          await state.moveSpbCardTo(current, 'Назначение');
        });
        await tester.pumpAndSettle();
        current = state.itemById(id);
        expect(current.category, 'Назначение');
        expect(current.spbColor, 0x8236ac);
        unawaited(state.deleteItemWithConfirmation(current));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirmDeleteCardButton')));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        expect(state.sessionTrashCardIds, contains(id));
        expect(state.items, hasLength(1));
        final undoIndex = (state.sessionUndoHistory as List).length - 1;
        await tester.runAsync(() async {
          await state.restoreSessionUndoAt(undoIndex);
        });
        await tester.pumpAndSettle();
        expect(state.items, hasLength(2));
        expect(state.sessionTrashCardIds, isEmpty);
        current = state.itemById(id);
        expect(current.title, 'Изменена');
        expect(current.values[fieldId], 'edited');
        final exported = await tester.runAsync<File>(() async => await state
            .createSpbItemsExportFile([current],
                password: '', targetPath: '${temp.path}/export.swl') as File);
        final independent = SpbWalletDatabase.open(exported!.path, '');
        final snapshot = independent.loadSnapshot();
        expect(snapshot.cards.single.title, 'Изменена');
        expect(snapshot.cards.single.cardColor, 0x8236ac);
        expect(
            independent.readAttachmentBytes(
                snapshot.cards.single.attachments.single.id),
            [1, 2, 3, 255]);
        independent.close(flush: false);
        await tester.runAsync(() async {
          await wallet.backupTo('${temp.path}/archive.swl');
        });
        final archive =
            SpbWalletDatabase.open('${temp.path}/archive.swl', 'test-only');
        expect(archive.loadSnapshot().cards, hasLength(2));
        archive.close(flush: false);
        await tester.runAsync(() async {
          await state.cloneSpbTemplate(storedTemplate);
        });
        await tester.pumpAndSettle();
        expect(state.templates, hasLength(2));
        final CardTemplate unused = (state.templates as List<CardTemplate>)
            .firstWhere((t) => t.id != storedTemplate.id);
        unawaited(state.deleteTemplateWithConfirmation(unused));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirmDeleteTemplateButton')));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        expect(state.sessionTrashTemplateIds, contains(unused.id));
        await tester.runAsync(() async {
          await state.restoreSessionUndoAt(
              (state.sessionUndoHistory as List).length - 1);
        });
        expect(state.templates, hasLength(2));
        wallet.renameCategory('Начало', 'Переименовано', '');
        wallet.moveCategory('Переименовано', 'Назначение');
        wallet.createCategory('Удалить', '');
        final undo = await tester.runAsync(() => wallet.createUndoSnapshot());
        wallet.deleteCategory('Удалить');
        await tester.runAsync(() => wallet.restoreUndoSnapshot(undo!));
        undo!.dispose();
        state.clearSessionUndoHistory();
        state.spbWallet = null;
        wallet.close();
        final reopened = SpbWalletDatabase.open(path, 'test-only');
        final reopenedSnapshot = reopened.loadSnapshot();
        expect(reopenedSnapshot.cards, hasLength(2));
        expect(reopenedSnapshot.templates, hasLength(2));
        expect(
            reopenedSnapshot.cards.every((card) => card.cardColor == 0x8236ac),
            isTrue);
        reopened.close(flush: false);
        expect(tester.takeException(), isNull);
      } finally {
        if (state != null) {
          state.spbWallet = null;
          state.clearSessionUndoHistory();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        await tester.binding.setSurfaceSize(null);
        // close is idempotent only at the caller boundary, so failed assertions
        // still release the database handle before deleting the synthetic data.
        try {
          wallet.close(flush: false);
        } catch (_) {}
        temp.deleteSync(recursive: true);
      }
    });
  }
}
