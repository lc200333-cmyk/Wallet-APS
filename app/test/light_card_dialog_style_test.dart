import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/ui/skin/app_skin.dart';

const _urlField = FieldDefinition(id: 'web', label: 'WEB', type: 'url');
const _template = CardTemplate(
  id: 'web-template',
  name: 'WEB',
  iconId: 'globe',
  colorId: 'template_gray',
  fields: [_urlField],
);

Widget _lightDialog(Widget child) => MaterialApp(
      theme: buildModernTheme(Brightness.light),
      home: Builder(
        builder: (context) => skinCardFieldsTheme(context, child),
      ),
    );

Color _fieldOutline(WidgetTester tester, Finder field) => tester
    .widget<InputDecorator>(
      find.descendant(of: field, matching: find.byType(InputDecorator)),
    )
    .decoration
    .enabledBorder!
    .borderSide
    .color;

void main() {
  testWidgets(
      'Light card and template windows use lighter surfaces and darker fields',
      (tester) async {
    final expectedOutline =
        Color.lerp(WalletSkinTokens.light.outline, Colors.black, 0.20)!;
    final expectedCardBackground = Color.lerp(
      skinTileForPalette(
        WalletSkinTokens.light,
        colorById(_template.colorId),
      ).tile,
      Colors.white,
      0.05,
    );
    final item = SecretItem(
      id: 'web-card',
      templateId: _template.id,
      title: 'Site',
      category: '',
      colorId: _template.colorId,
      values: const {'web': 'example.com'},
      modifiedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      _lightDialog(CardPreviewDialog(item: item, template: _template)),
    );
    await tester.pumpAndSettle();
    final cardPreview = tester.widget<DecoratedBox>(
      find.byKey(const Key('cardPreviewBackground')),
    );
    expect((cardPreview.decoration as BoxDecoration).color,
        expectedCardBackground);
    expect(
      _fieldOutline(
        tester,
        find.byKey(const ValueKey('cardPreviewField-web')),
      ),
      expectedOutline,
    );

    await tester.pumpWidget(
      _lightDialog(
        const ItemEditorDialog(
          templates: [_template],
          categories: [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cardEditor = tester.widget<DecoratedBox>(
      find.byKey(const Key('cardEditorBackground')),
    );
    expect(
        (cardEditor.decoration as BoxDecoration).color, expectedCardBackground);
    final webEditor = find.byKey(const ValueKey('cardField-web'));
    expect(_fieldOutline(tester, webEditor), expectedOutline);
    expect(tester.widget<TextField>(webEditor).controller!.text, 'http://');
    await tester.enterText(webEditor, '');
    await tester.pump();
    expect(tester.widget<TextField>(webEditor).controller!.text, isEmpty);

    await tester.pumpWidget(
      _lightDialog(const TemplatePreviewDialog(template: _template)),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const Key('templatePreviewBackground')),
          )
          .color,
      Color.lerp(
        templateDisplayBackground(_template),
        Colors.white,
        0.05,
      ),
    );
    expect(
      _fieldOutline(
        tester,
        find.byKey(const ValueKey('templatePreviewField-web')),
      ),
      expectedOutline,
    );

    await tester.pumpWidget(
      _lightDialog(const TemplateEditorDialog(initial: _template)),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const Key('templateEditorBackground')),
          )
          .color,
      expectedCardBackground,
    );
    expect(
      _fieldOutline(
        tester,
        find.byKey(const ValueKey('templateFieldName-web')),
      ),
      expectedOutline,
    );
  });

  test('bare removable web prefix is not saved as a URL', () {
    expect(initialCardFieldText(_urlField, ''), 'http://');
    expect(initialCardFieldText(_urlField, 'example.com'), 'example.com');
    expect(normalizeUrlInput('http://'), isEmpty);
    expect(normalizeUrlInput('HTTP://'), isEmpty);
    expect(normalizeUrlInput('example.com'), 'https://example.com');
  });
}
