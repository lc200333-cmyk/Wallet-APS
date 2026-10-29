import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';

// Card fields with a web or e-mail address open it outside the program.
void main() {
  test('only web and mail addresses become links', () {
    Uri? site(String value) => cardFieldLinkUri(CardFieldLink.website, value);
    Uri? mail(String value) => cardFieldLinkUri(CardFieldLink.email, value);
    expect(site('example.com/login').toString(), 'https://example.com/login');
    expect(site('http://bank.ru').toString(), 'http://bank.ru');
    expect(site(' https://x.org ').toString(), 'https://x.org');
    expect(site('file:///C:/Windows/system32/calc.exe'), isNull);
    expect(site('javascript:alert(1)'), isNull);
    expect(site('two words'), isNull);
    expect(site(''), isNull);
    expect(mail('user@mail.ru').toString(), 'mailto:user@mail.ru');
    expect(mail('mailto:a@b.cz').toString(), 'mailto:a@b.cz');
    expect(mail('not an address'), isNull);
    expect(mail('user@host'), isNull);
  });

  test('phone numbers keep their digits and leading plus', () {
    expect(phoneNumberForLinks('+7 (999) 123-45-67'), '+79991234567');
    expect(phoneNumberForLinks('8 999 123 45 67'), '89991234567');
    expect(phoneNumberForLinks('123'), isNull);
    expect(phoneNumberForLinks('звонить вечером'), isNull);
    expect(phoneNumberForLinks('+7 999; calc.exe'), isNull);
    expect(
      cardFieldLinkUri(CardFieldLink.phone, '+7 999 123-45-67').toString(),
      'tel:+79991234567',
    );
    String action(PhoneLinkAction value) =>
        phoneLinkActionUri(value, '+79991234567').toString();
    expect(action(PhoneLinkAction.whatsApp), 'https://wa.me/79991234567');
    expect(action(PhoneLinkAction.telegram), 'https://t.me/+79991234567');
    expect(action(PhoneLinkAction.call), 'tel:+79991234567');
    expect(action(PhoneLinkAction.sms), 'sms:+79991234567');
    expect(action(PhoneLinkAction.other), 'tel:+79991234567');
  });

  testWidgets('the phone button offers messengers, the dialer and others',
      (tester) async {
    const phone = FieldDefinition(id: 'tel', label: 'Телефон', type: 'phone');
    const template = CardTemplate(
      id: 'phone-template',
      name: 'Телефон',
      iconId: 'phone',
      colorId: 'template_gray',
      fields: [phone],
    );
    final item = SecretItem(
      id: 'phone-card',
      templateId: template.id,
      title: 'Телефон',
      category: '',
      colorId: template.colorId,
      values: const {'tel': '+7 (999) 123-45-67'},
      modifiedAt: DateTime(2026),
    );
    final opened = <(String, bool)>[];
    final previousOpener = cardFieldLinkOpener;
    cardFieldLinkOpener =
        (uri, {chooser = false}) async => opened.add((uri.toString(), chooser));
    addTearDown(() => cardFieldLinkOpener = previousOpener);

    await tester.pumpWidget(
      MaterialApp(home: CardPreviewDialog(item: item, template: template)),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('cardPreviewOpenLink-tel'));
    expect(
        find.descendant(
            of: button, matching: find.byIcon(Icons.phone_outlined)),
        findsOneWidget);

    for (final action in PhoneLinkAction.values) {
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('phoneLinkDialog')), findsOneWidget);
      expect(find.text('+79991234567'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('phoneLinkAction-${action.name}')));
      await tester.pumpAndSettle();
    }
    expect(opened, [
      ('https://wa.me/79991234567', false),
      ('https://t.me/+79991234567', false),
      ('tel:+79991234567', false),
      ('sms:+79991234567', false),
      ('tel:+79991234567', true),
    ]);
  });

  test('field kind comes from the type or the label', () {
    expect(
      cardFieldLinkKind(
          const FieldDefinition(id: 'u', label: 'Адрес', type: 'url')),
      CardFieldLink.website,
    );
    expect(
      cardFieldLinkKind(
          const FieldDefinition(id: 's', label: 'Веб-сайт', type: 'text')),
      CardFieldLink.website,
    );
    expect(
      cardFieldLinkKind(
          const FieldDefinition(id: 'e', label: 'Почта', type: 'text')),
      CardFieldLink.email,
    );
    expect(
      cardFieldLinkKind(
          const FieldDefinition(id: 'p', label: 'Пароль', type: 'password')),
      isNull,
    );
  });

  testWidgets('globe and envelope open the address left of copy',
      (tester) async {
    const site = FieldDefinition(id: 'site', label: 'Веб-сайт', type: 'url');
    const mail = FieldDefinition(id: 'mail', label: 'Email', type: 'email');
    const note = FieldDefinition(id: 'note', label: 'Заметка', type: 'text');
    const template = CardTemplate(
      id: 'link-template',
      name: 'Ссылки',
      iconId: 'globe',
      colorId: 'template_gray',
      fields: [site, mail, note],
    );
    final item = SecretItem(
      id: 'link-card',
      templateId: template.id,
      title: 'Ссылки',
      category: '',
      colorId: template.colorId,
      values: const {
        'site': 'example.com',
        'mail': 'user@mail.ru',
        'note': 'example.org',
      },
      modifiedAt: DateTime(2026),
    );
    final opened = <Uri>[];
    final previousOpener = cardFieldLinkOpener;
    cardFieldLinkOpener = (uri, {chooser = false}) async => opened.add(uri);
    addTearDown(() => cardFieldLinkOpener = previousOpener);

    await tester.pumpWidget(
      MaterialApp(home: CardPreviewDialog(item: item, template: template)),
    );
    await tester.pumpAndSettle();

    final globe = find.byKey(const ValueKey('cardPreviewOpenLink-site'));
    final envelope = find.byKey(const ValueKey('cardPreviewOpenLink-mail'));
    expect(find.descendant(of: globe, matching: find.byIcon(Icons.public)),
        findsOneWidget);
    expect(
        find.descendant(
            of: envelope, matching: find.byIcon(Icons.mail_outline)),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('cardPreviewOpenLink-note')), findsNothing);
    expect(
      tester.getCenter(globe).dx,
      lessThan(tester
          .getCenter(find.byKey(const ValueKey('cardPreviewCopy-site')))
          .dx),
    );

    await tester.tap(globe);
    await tester.tap(envelope);
    await tester.pump();
    expect(opened.map((uri) => uri.toString()),
        ['https://example.com', 'mailto:user@mail.ru']);
  });
}
