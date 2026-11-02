import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';
import 'package:wallet_aps/services/wallet_rekey_service.dart';
import 'package:wallet_aps/ui/skin/app_skin.dart';

const template = CardTemplate(
  id: '1111111111111111',
  name: 'Test',
  iconId: 'globe',
  colorId: 'template_white',
  fields: [
    FieldDefinition(id: '2222222222222222', label: 'Text', type: 'text')
  ],
);

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('add a card-only field and undo at width $width',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(
        home: ItemEditorDialog(templates: [template], categories: []),
      ));
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('cardAddFieldButton'));
      expect(
          tester.getTopLeft(button).dy,
          greaterThanOrEqualTo(tester
              .getBottomLeft(find.byKey(const Key('cardTemplateField')))
              .dy));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cardNewFieldType')), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('cardNewFieldName')), 'Extension');
      await tester.pump();
      await tester.tap(find.byKey(const Key('cardNewFieldType')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Телефон').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cardNewFieldConfirm')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(ItemEditorDialog));
      final fields = state.allCardFields as List<FieldDefinition>;
      expect(fields.last.label, 'Extension');
      expect(fields.last.type, 'phone');
      expect(template.fields.length, 1);
      final id = fields.last.id;
      expect(find.byKey(ValueKey('cardField-$id')), findsOneWidget);
      state.undoLastAction();
      await tester.pumpAndSettle();
      expect((state.allCardFields as List).length, 1);
      expect(find.byKey(ValueKey('cardField-$id')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  test('custom field name type and value survive reopen and password change',
      () async {
    final directory = await Directory.systemTemp.createTemp('custom_fields_');
    final path = '${directory.path}/test.swl';
    var wallet = SpbWalletDatabase.create(path, 'old-password');
    addTearDown(() {
      wallet.close();
      directory.deleteSync(recursive: true);
    });
    wallet.saveTemplate(const SpbWalletTemplateDraft(
      id: '1111111111111111',
      name: 'Test',
      fields: [
        SpbWalletTemplateFieldRecord(
            id: '2222222222222222',
            name: 'Text',
            templateId: '1111111111111111',
            fieldTypeId: 1)
      ],
    ));
    wallet.saveCard(const SpbWalletCardDraft(
      id: '3333333333333333',
      title: 'Card',
      description: '',
      categoryPath: '',
      templateId: '1111111111111111',
      fieldValues: {'4444444444444444': 'confidential-value'},
      customFields: [
        {'id': '4444444444444444', 'label': 'Private phone', 'type': 'phone'}
      ],
      fieldOrder: ['2222222222222222', '4444444444444444'],
    ));
    wallet.flushToDisk();
    wallet.close();
    WalletRekeyService.rekeyFile(path,
        oldPassword: 'old-password', newPassword: 'new-password');
    wallet = SpbWalletDatabase.open(path, 'new-password');
    final snapshot = wallet.loadSnapshot();
    final card = snapshot.cards.single;
    expect(card.customFields.single['label'], 'Private phone');
    expect(card.customFields.single['type'], 'phone');
    expect(card.fieldValues['4444444444444444'], 'confidential-value');
    expect(snapshot.templates.single.fields.length, 1);
    final bytes = File(path).readAsBytesSync();
    expect(String.fromCharCodes(bytes), isNot(contains('confidential-value')));
  });

  testWidgets('white swatches stay white in every skin', (tester) async {
    for (final skin in AppSkin.values) {
      await tester.pumpWidget(MaterialApp(
        theme: skin == AppSkin.retro
            ? ThemeData()
            : buildModernTheme(
                skin == AppSkin.dark ? Brightness.dark : Brightness.light),
        home: Scaffold(
            body: ColorPicker(value: 'template_white', onChanged: (_) {})),
      ));
      final sample = tester.widget<Container>(
          find.byKey(const ValueKey('cardColor-template_white')));
      expect((sample.decoration as BoxDecoration).color, Colors.white);
    }
  });
}
