import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';

Future<void> settleStorage(
    WidgetTester tester, bool Function() completed) async {
  final elapsed = Stopwatch()..start();
  while (!completed()) {
    if (elapsed.elapsed > const Duration(seconds: 30)) {
      fail('Timed out waiting for the card/template storage operation');
    }
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final width in [390.0, 1280.0]) {
    for (final action in ['decline', 'create', 'update']) {
      final accept = action != 'decline';
      final updateExisting = action == 'update';
      testWidgets('save card then $action template at $width', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final directory = Directory.systemTemp.createTempSync('card_template_');
        final wallet =
            SpbWalletDatabase.create('${directory.path}/test.swl', '');
        addTearDown(() {
          wallet.close();
          directory.deleteSync(recursive: true);
        });
        const originalId = '1111111111111111';
        const originalField = '2222222222222222';
        const cardId = '3333333333333333';
        const customField = '4444444444444444';
        wallet.saveTemplate(const SpbWalletTemplateDraft(
          id: originalId,
          name: 'Original',
          categoryPath: 'Original folder',
          fields: [
            SpbWalletTemplateFieldRecord(
                id: originalField,
                name: 'Login',
                templateId: originalId,
                fieldTypeId: 1)
          ],
        ));
        wallet.saveCard(const SpbWalletCardDraft(
          id: cardId,
          title: 'Card',
          description: 'Keep notes',
          categoryPath: 'Cards',
          templateId: originalId,
          fieldValues: {
            originalField: 'old-login',
            customField: '+79991234567'
          },
          customFields: [
            {'id': customField, 'label': 'Phone', 'type': 'phone'}
          ],
          fieldOrder: [originalField, customField],
        ));
        wallet.saveCard(const SpbWalletCardDraft(
          id: '5555555555555555',
          title: 'Other card',
          description: '',
          categoryPath: '',
          templateId: originalId,
          fieldValues: {originalField: 'other-login'},
        ));
        await tester.pumpWidget(
            const MaterialApp(home: VaultShell(initiallyUnlocked: true)));
        await tester.pumpAndSettle();
        final dynamic state = tester.state(find.byType(VaultShell));
        state.spbWallet = wallet;
        state.spbWalletPath = wallet.path;
        state.applySpbSnapshot(wallet.loadSnapshot());
        state.setState(() {});
        await tester.pumpAndSettle();
        final card = (state.items as List<SecretItem>)
            .firstWhere((card) => card.id == cardId);
        var flowCompleted = false;
        Object? flowError;
        StackTrace? flowStack;
        final flow = state.openItemDialog(item: card) as Future<SecretItem?>;
        unawaited(flow.then<void>((_) => flowCompleted = true,
            onError: (Object error, StackTrace stack) {
          flowError = error;
          flowStack = stack;
          flowCompleted = true;
        }));
        await tester.pumpAndSettle();
        final dynamic editor = tester.state(find.byType(ItemEditorDialog));
        editor.values[originalField].text = 'new-login';
        editor.saveCard();
        await settleStorage(
            tester,
            () =>
                flowCompleted ||
                find
                    .byKey(const Key('cardTemplateProposalText'))
                    .evaluate()
                    .isNotEmpty);
        if (flowError != null) {
          Error.throwWithStackTrace(flowError!, flowStack!);
        }
        expect(
            find.byKey(const Key('cardTemplateProposalText')), findsOneWidget);
        expect(
            wallet
                .loadSnapshot()
                .cards
                .firstWhere((card) => card.id == cardId)
                .fieldValues[originalField],
            'new-login');
        expect(find.byKey(const ValueKey('cardTemplateField-$customField')),
            findsOneWidget);
        expect(
            find.byKey(const Key('templateSpbDefaultButton')), findsOneWidget);
        expect(find.byKey(const Key('cardTemplateFolder')), findsOneWidget);
        expect(find.byKey(const Key('cardTemplateUpdate')), findsOneWidget);
        expect(find.text('Изменить шаблон'), findsOneWidget);
        expect(find.text('Создать новый шаблон'), findsOneWidget);
        expect(find.byKey(const Key('cardTemplateMode')), findsNothing);
        for (final key in [
          'cardTemplateUpdate',
          'cardTemplateConfirm',
          'cardTemplateDecline'
        ]) {
          final bounds = tester.getRect(find.byKey(Key(key)));
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(width));
        }
        if (accept) {
          await tester.enterText(
              find.byKey(const Key('templateNameField')), 'My custom template');
          final dynamic templateEditor =
              tester.state(find.byType(TemplateEditorDialog));
          templateEditor.changeIcon('phone');
          await tester.tap(find.byKey(const Key('cardTemplateFolder')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Без папки').last);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(Key(updateExisting
            ? 'cardTemplateUpdate'
            : accept
                ? 'cardTemplateConfirm'
                : 'cardTemplateDecline')));
        await settleStorage(tester, () => flowCompleted);
        if (flowError != null) {
          Error.throwWithStackTrace(flowError!, flowStack!);
        }
        final snapshot = wallet.loadSnapshot();
        final stored = snapshot.cards.firstWhere((card) => card.id == cardId);
        final other =
            snapshot.cards.firstWhere((card) => card.id == '5555555555555555');
        expect(other.templateId, originalId);
        expect(other.fieldValues[originalField], 'other-login');
        expect(stored.description, 'Keep notes');
        expect(
            snapshot.templates
                .firstWhere((t) => t.id == originalId)
                .fields
                .length,
            updateExisting ? 2 : 1);
        if (accept) {
          expect(stored.templateId,
              updateExisting ? originalId : isNot(originalId));
          final created =
              snapshot.templates.firstWhere((t) => t.id == stored.templateId);
          expect(created.name, 'My custom template');
          expect(created.fields.map((field) => field.name), ['Login', 'Phone']);
          expect(created.fields.last.fieldTypeId, 8);
          expect(stored.fieldValues[created.fields.first.id], 'new-login');
          expect(stored.fieldValues[created.fields.last.id], '+79991234567');
          expect(stored.customFields, isEmpty);
          expect(stored.fieldValues.containsKey(originalField), updateExisting);
          expect(snapshot.templates.length, updateExisting ? 1 : 2);
          final native = sqlite3.open(wallet.path);
          try {
            final viewFields = native
                .select(
                  'SELECT hex(f.TemplateFieldID) AS ID FROM spbwlt_Card c '
                  'JOIN spbwlt_CardViewField f ON c.CardViewID=f.CardViewID '
                  'WHERE hex(c.ID)=?',
                  [cardId],
                )
                .map((row) => row['ID'])
                .toSet();
            expect(viewFields,
                containsAll(created.fields.map((field) => field.id)));
            expect(native.select('SELECT * FROM actitpass_CardField'), isEmpty);
          } finally {
            native.dispose();
          }
        } else {
          expect(snapshot.templates.length, 1);
          expect(stored.templateId, originalId);
          expect(stored.fieldValues[customField], '+79991234567');
          expect(stored.customFields.single['label'], 'Phone');
        }
        state.spbWallet = null;
        state.clearSessionUndoHistory();
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      });
    }
  }
}
