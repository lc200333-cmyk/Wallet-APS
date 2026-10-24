import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';

void main() {
  for (final viewport in [
    (platform: TargetPlatform.windows, size: const Size(1200, 900)),
    (platform: TargetPlatform.android, size: const Size(360, 800)),
  ]) {
    for (final templateEditor in [false, true]) {
      final editorName = templateEditor ? 'template' : 'card';
      final nameKey = Key(
        templateEditor ? 'templateNameField' : 'cardTitleField',
      );
      final saveKey = Key(
        templateEditor ? 'templateSaveButton' : 'cardSaveButton',
      );
      final undoKey = Key(
        templateEditor ? 'templateUndoButton' : 'cardUndoButton',
      );
      final closeKey = Key(
        templateEditor ? 'templateCloseButton' : 'cardCloseButton',
      );

      testWidgets(
        'new $editorName confirmation follows name on ${viewport.platform.name}',
        (tester) async {
          debugDefaultTargetPlatformOverride = viewport.platform;
          await tester.binding.setSurfaceSize(viewport.size);
          addTearDown(() {
            debugDefaultTargetPlatformOverride = null;
            tester.binding.setSurfaceSize(null);
          });
          final template = builtInTemplates().first;
          await tester.pumpWidget(
            MaterialApp(
              home: templateEditor
                  ? const TemplateEditorDialog()
                  : ItemEditorDialog(
                      templates: [template],
                      categories: const [],
                    ),
            ),
          );
          await tester.pumpAndSettle();
          final nameField = find.byKey(nameKey);
          final save = find.byKey(saveKey);
          final close = find.byKey(closeKey);
          final closePosition = tester.getRect(close);
          expect(save, findsNothing);
          expect(find.byKey(undoKey), findsOneWidget);

          await tester.tap(nameField);
          await tester.enterText(nameField, '   ');
          await tester.pump();
          expect(save, findsNothing);

          await tester.enterText(nameField, 'Тестовое название');
          await tester.pump();
          expect(save, findsOneWidget);
          expect(tester.getRect(close), closePosition);
          expect(tester.getRect(save).overlaps(closePosition), isFalse);

          await tester.enterText(nameField, '');
          await tester.pump();
          expect(save, findsNothing);
          expect(tester.getRect(close), closePosition);

          // Controller changes also cover paste/undo-driven updates without
          // relying on TextField.onChanged to rebuild the whole dialog.
          final controller = tester.widget<TextField>(nameField).controller!;
          controller.text = 'Вставленное название';
          await tester.pump();
          expect(save, findsOneWidget);
          controller.clear();
          await tester.pump();
          expect(save, findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets(
        'new $editorName confirmation saves name on ${viewport.platform.name}',
        (tester) async {
          debugDefaultTargetPlatformOverride = viewport.platform;
          await tester.binding.setSurfaceSize(viewport.size);
          addTearDown(() {
            debugDefaultTargetPlatformOverride = null;
            tester.binding.setSurfaceSize(null);
          });
          Object? saved;
          final template = builtInTemplates().first;
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      saved = await showDialog<Object>(
                        context: context,
                        builder: (_) => templateEditor
                            ? const TemplateEditorDialog()
                            : ItemEditorDialog(
                                templates: [template],
                                categories: const [],
                              ),
                      );
                    },
                    child: const Text('Создать'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Создать'));
          await tester.pumpAndSettle();
          expect(find.byKey(saveKey), findsNothing);
          await tester.enterText(find.byKey(nameKey), '  Новое название  ');
          await tester.pump();
          await tester.tap(find.byKey(saveKey));
          await tester.pumpAndSettle();
          if (templateEditor) {
            expect(saved, isA<CardTemplate>());
            expect((saved! as CardTemplate).name, 'Новое название');
          } else {
            expect(saved, isA<SecretItem>());
            expect((saved! as SecretItem).title, 'Новое название');
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          debugDefaultTargetPlatformOverride = null;
        },
      );

      testWidgets(
        'existing $editorName keeps confirmation on ${viewport.platform.name}',
        (tester) async {
          debugDefaultTargetPlatformOverride = viewport.platform;
          await tester.binding.setSurfaceSize(viewport.size);
          addTearDown(() {
            debugDefaultTargetPlatformOverride = null;
            tester.binding.setSurfaceSize(null);
          });
          final template = builtInTemplates().first;
          await tester.pumpWidget(
            MaterialApp(
              home: templateEditor
                  ? TemplateEditorDialog(initial: template)
                  : ItemEditorDialog(
                      templates: [template],
                      categories: const [],
                      initial: SecretItem(
                        id: 'confirmation-test-card',
                        templateId: template.id,
                        title: 'Существующая карточка',
                        category: '',
                        colorId: template.colorId,
                        values: const {},
                        modifiedAt: DateTime.utc(2026),
                      ),
                    ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(saveKey), findsOneWidget);
          await tester.enterText(find.byKey(nameKey), '');
          await tester.pump();
          expect(find.byKey(saveKey), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}
