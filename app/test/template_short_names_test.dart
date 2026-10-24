import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets(
        'template names omit category throughout UI on ${platform.name}',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.binding.setSurfaceSize(platform == TargetPlatform.windows
          ? const Size(1280, 900)
          : const Size(360, 800));
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.binding.setSurfaceSize(null);
      });
      const template = CardTemplate(
        id: 'template-network',
        name: 'Компьютеры: Сеть',
        categoryPath: 'Интернет',
        iconId: 'key',
        colorId: 'template_white',
        fields: [FieldDefinition(id: 'host', label: 'Сервер', type: 'text')],
      );
      await tester.pumpWidget(
        const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(VaultShell));
      state.setState(() {
        state.templates = <CardTemplate>[template];
        state.templatesById = <String, CardTemplate>{template.id: template};
      });
      await tester.tap(find.byKey(const Key('spbTemplatesModeButton')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('spbTemplateFolder-Компьютеры')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('spbTemplate-template-network')),
          findsOneWidget);
      if (platform == TargetPlatform.android) {
        await tester.tap(find.byKey(const Key('mobilePaneForward')));
        await tester.pumpAndSettle();
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('spbCentralTemplate-template-network')),
          matching: find.text('Сеть'),
        ),
        findsOneWidget,
      );
      expect(find.text(template.name), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(home: TemplatePreviewDialog(template: template)),
      );
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const Key('templatePreviewTitle')))
              .data,
          'Сеть');
      await tester.pumpWidget(
        const MaterialApp(
          home: ItemEditorDialog(templates: [template], categories: []),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(template.name), findsNothing);
      expect(find.text('Сеть'), findsWidgets);

      CardTemplate? saved;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showDialog<CardTemplate>(
                  context: context,
                  builder: (_) => const TemplateEditorDialog(initial: template),
                );
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('templateNameField')))
            .controller!
            .text,
        'Сеть',
      );
      final dynamic editor = tester.state(find.byType(TemplateEditorDialog));
      expect(editor.categoryPath, 'Компьютеры');
      await tester.tap(find.byKey(const Key('templateSaveButton')));
      await tester.pumpAndSettle();
      expect(saved!.name, 'Сеть');
      expect(saved!.categoryPath, 'Компьютеры');
      expect(saved!.id, template.id);
      expect(saved!.fields.single.id, 'host');
      // Display/initialization must not mutate the original legacy object.
      expect(template.name, 'Компьютеры: Сеть');
      expect(template.categoryPath, 'Интернет');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
