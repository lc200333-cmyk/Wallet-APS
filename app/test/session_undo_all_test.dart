import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';

void main() {
  testWidgets('undo all restores session start after history limit',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = Directory.systemTemp.createTempSync('undo_all_');
    final wallet = SpbWalletDatabase.create('${directory.path}/test.swl', '');
    addTearDown(() {
      wallet.close();
      directory.deleteSync(recursive: true);
    });
    const templateId = '1111111111111111';
    const fieldId = '2222222222222222';
    const cardId = '3333333333333333';
    wallet.saveTemplate(const SpbWalletTemplateDraft(
      id: templateId,
      name: 'Template',
      fields: [
        SpbWalletTemplateFieldRecord(
            id: fieldId, name: 'Value', templateId: templateId, fieldTypeId: 1),
      ],
    ));
    wallet.saveCard(const SpbWalletCardDraft(
      id: cardId,
      title: 'Card',
      description: '',
      categoryPath: '',
      templateId: templateId,
      fieldValues: {fieldId: 'initial'},
    ));
    await tester.pumpWidget(
        const MaterialApp(home: VaultShell(initiallyUnlocked: true)));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    state.spbWallet = wallet;
    state.spbWalletPath = wallet.path;
    state.applySpbSnapshot(wallet.loadSnapshot());
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(() async {
        await state.saveSpbItem(SecretItem(
          id: cardId,
          title: 'Card',
          category: '',
          templateId: templateId,
          colorId: 'template_white',
          values: {fieldId: 'edit-$i'},
          modifiedAt: DateTime(2026),
        ));
      });
    }
    await tester.pumpAndSettle();
    expect((state.sessionUndoHistory as List).length, 12);
    expect(wallet.loadSnapshot().cards.single.fieldValues[fieldId], 'edit-14');
    ScaffoldMessenger.of(tester.element(find.byType(VaultShell)))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Отменить изменения этой сессии'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sessionUndoAll')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sessionUndoAll')));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
    expect(wallet.loadSnapshot().cards.single.fieldValues[fieldId], 'initial');
    expect(state.sessionUndoHistory as List, isEmpty);
    expect(find.text('Отменены все изменения этой сессии'), findsOneWidget);
    state.spbWallet = null;
    expect(tester.takeException(), isNull);
  });
}
