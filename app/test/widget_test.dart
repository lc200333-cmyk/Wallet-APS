import 'dart:async';
import 'dart:io';

import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Offset textOffsetPosition(
  WidgetTester tester,
  Finder editableText,
  int offset,
) {
  final root = tester.renderObject<RenderObject>(editableText);
  RenderEditable? editable;
  void findEditable(RenderObject child) {
    if (child is RenderEditable) {
      editable = child;
      return;
    }
    child.visitChildren(findEditable);
  }

  root.visitChildren(findEditable);
  final renderEditable = editable!;
  final endpoint = renderEditable
      .getEndpointsForSelection(TextSelection.collapsed(offset: offset))
      .single;
  return renderEditable.localToGlobal(endpoint.point) - const Offset(0, 2);
}

void main() {
  testWidgets('replacement third-party icon bundle is available',
      (tester) async {
    addTearDown(() => thirdPartyIconAssetsFuture = null);
    final icons = await loadThirdPartyIconAssets();

    expect(icons, hasLength(957));
    expect(icons, contains('third-party://NewIcons/Icons0001.png'));
    expect(icons, contains('third-party://NewIcons/Icons0957.png'));
    expect(thirdPartyIconPngs[icons.first], isNotEmpty);
  });
  test('selected template icon survives the stored IconID round trip', () {
    const selected = 'spb://third_party/custom_icon.png';
    final previousAssets = spb64PngIconAssets;
    spb64PngIconAssets = const [selected];
    addTearDown(() => spb64PngIconAssets = previousAssets);
    final storedIconId = syntheticSpbIconIdForUi(selected);
    final loadedIconId = spbTemplateIconForUi(
      SpbWalletTemplateRecord(
        id: 'template',
        name: 'Название не определяет иконку',
        iconId: storedIconId,
        fields: const [],
      ),
    );

    expect(loadedIconId, selected);
  });

  test('stored custom folder icon has priority over the folder name', () {
    const iconId = 'A1B2C3D4E5F60708';
    final previousIcons = spbEmbeddedIconPngs;
    spbEmbeddedIconPngs = {
      iconId: Uint8List.fromList([1, 2, 3])
    };
    addTearDown(() => spbEmbeddedIconPngs = previousIcons);

    expect(spbFolderIconAsset('bank', iconId), iconId);
  });

  test('pictogram keeps the background hue and is slightly darker', () {
    const background = Color(0xffc8e4f6);
    final pictogram = pictogramColorForBackground(background);
    final backgroundHsl = HSLColor.fromColor(background);
    final pictogramHsl = HSLColor.fromColor(pictogram);
    final backgroundArgb = background.toARGB32();
    final pictogramArgb = pictogram.toARGB32();
    int channel(int value, int shift) => (value >> shift) & 0xff;

    expect(pictogramHsl.hue, closeTo(backgroundHsl.hue, 1.0));
    expect(pictogramHsl.lightness, lessThan(backgroundHsl.lightness));
    for (final shift in const [16, 8, 0]) {
      expect(
        channel(pictogramArgb, shift),
        closeTo(channel(backgroundArgb, shift) * 0.8, 1.1),
      );
    }
  });

  testWidgets('template editor uses SPB layout and supports local undo',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final template = builtInTemplates().first;

    await tester.pumpWidget(
      MaterialApp(home: TemplateEditorDialog(initial: template)),
    );
    await tester.pumpAndSettle();

    final templateSurfaceSize =
        tester.getSize(find.byKey(const Key('templateEditorSurface')));
    expect(templateSurfaceSize.width, 360);
    expect(templateSurfaceSize.height, greaterThanOrEqualTo(500));
    expect(find.byKey(const Key('templateNameField')), findsOneWidget);
    expect(find.byKey(const Key('templateBoundIcon')), findsOneWidget);
    expect(find.text('Выбрать иконку'), findsOneWidget);
    expect(find.byKey(const Key('templateSpbDefaultButton')), findsOneWidget);
    expect(find.byKey(const Key('templatePictogramsButton')), findsOneWidget);
    expect(find.byKey(const Key('templateIconsButton')), findsOneWidget);
    expect(find.byKey(const Key('templateUploadIconButton')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('templateColor-'),
      ),
      findsNWidgets(16),
    );
    expect(find.byKey(const Key('templateUndoButton')), findsOneWidget);
    expect(find.byKey(const Key('templateSaveButton')), findsOneWidget);
    expect(find.byKey(const Key('templateCloseButton')), findsOneWidget);
    final externalIcons = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('templateIconsButton')),
        matching: find.byType(InkWell),
      ),
    );
    expect(externalIcons.onTap, isNotNull);
    final uploadIcon = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('templateUploadIconButton')),
        matching: find.byType(InkWell),
      ),
    );
    expect(uploadIcon.onTap, isNotNull);
    final iconFrame = tester.widget<Container>(
      find.byKey(const Key('templateBoundIcon')),
    );
    final iconDecoration = iconFrame.decoration! as BoxDecoration;
    expect((iconDecoration.border! as Border).top.width, 2);
    expect(iconDecoration.borderRadius, BorderRadius.circular(5));
    expect(iconDecoration.boxShadow, isNotEmpty);

    await tester.tap(
      find.byKey(const ValueKey('templateColor-template_sky')),
    );
    await tester.pump();
    final coloredNameField = tester.widget<TextField>(
      find.byKey(ValueKey('templateFieldName-${template.fields.first.id}')),
    );
    final coloredTypeField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(ValueKey('templateFieldType-${template.fields.first.id}')),
    );
    expect(
        coloredNameField.decoration!.fillColor, colorById('template_sky').bg);
    expect(coloredTypeField.decoration.fillColor, colorById('template_sky').bg);
    final coloredPictogram = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('templateBoundIcon')),
        matching: find.byType(Icon),
      ),
    );
    expect(coloredPictogram.color, templatePictogramColor('template_sky'));
    expect(tester.takeException(), isNull);

    final firstField =
        find.byKey(ValueKey('templateField-${template.fields.first.id}'));
    final secondField =
        find.byKey(ValueKey('templateField-${template.fields[1].id}'));
    final firstFieldId = template.fields.first.id;
    final deleteButton =
        find.byKey(ValueKey('templateFieldDelete-$firstFieldId'));
    final upButton = find.byKey(ValueKey('templateFieldUp-$firstFieldId'));
    expect(tester.getSize(deleteButton).width, tester.getSize(upButton).width);
    expect(
      tester
          .getTopRight(
            find.byKey(ValueKey('templateFieldName-$firstFieldId')),
          )
          .dx,
      tester
          .getTopRight(
            find.byKey(ValueKey('templateFieldType-$firstFieldId')),
          )
          .dx,
    );
    expect(
      tester.getTopLeft(firstField).dy,
      lessThan(tester.getTopLeft(secondField).dy),
    );
    await tester.tap(
      find.byKey(ValueKey('templateFieldDown-${template.fields.first.id}')),
    );
    await tester.pump();
    expect(
      tester.getTopLeft(firstField).dy,
      greaterThan(tester.getTopLeft(secondField).dy),
    );
    await tester.tap(find.byKey(const Key('templateUndoButton')));
    await tester.pump();
    expect(
      tester.getTopLeft(firstField).dy,
      lessThan(tester.getTopLeft(secondField).dy),
    );
    final nameField = find.byKey(const Key('templateNameField'));
    await tester.tap(nameField);
    await tester.enterText(nameField, 'Изменённый шаблон');
    await tester.pump();
    await tester.tap(find.byKey(const Key('templateUndoButton')));
    await tester.pump();

    final field = tester.widget<TextField>(nameField);
    expect(field.controller!.text, template.name);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide card editor matches the compact reference header layout',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(720, 900)),
          child: ItemEditorDialog(
            templates: builtInTemplates(),
            categories: const ['Finance'],
            categoryIcons: const {'Finance': 'bank'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cardEditorSurface')), findsOneWidget);
    expect(find.byKey(const Key('cardTitleField')), findsOneWidget);
    expect(find.byKey(const Key('cardBoundIcon')), findsOneWidget);
    expect(find.byKey(const Key('cardUndoButton')), findsOneWidget);
    expect(find.byKey(const Key('cardCloseButton')), findsOneWidget);
    expect(find.byKey(const Key('cardSaveButton')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('cardTitleField')))
          .contextMenuBuilder,
      isNotNull,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('cardTitleField')))
          .style
          ?.fontWeight,
      FontWeight.bold,
    );
    final original = find.byKey(const Key('spbCardIconPicker'));
    final pictogram = find.byKey(const Key('cardPictogramPicker'));
    final thirdParty = find.byKey(const Key('cardThirdPartyPicker'));
    final upload = find.byKey(const Key('cardUploadIconButton'));
    expect(original, findsOneWidget);
    expect(pictogram, findsOneWidget);
    expect(thirdParty, findsOneWidget);
    expect(upload, findsOneWidget);
    expect(tester.getTopLeft(original).dx,
        lessThan(tester.getTopLeft(pictogram).dx));
    for (final color in templateColorPalette) {
      expect(find.byKey(ValueKey('cardColor-${color.id}')), findsOneWidget);
    }
    final iconBottom = tester
        .getBottomLeft(
          find.byKey(const Key('cardBoundIcon')),
        )
        .dy;
    final iconTop =
        tester.getTopLeft(find.byKey(const Key('cardBoundIcon'))).dy;
    final iconLeft =
        tester.getTopLeft(find.byKey(const Key('cardBoundIcon'))).dx;
    final pickerBottom = tester.getBottomLeft(upload).dy;
    final pickerTop = tester.getTopLeft(upload).dy;
    final colorTop = tester
        .getTopLeft(
          find.byKey(ValueKey('cardColor-${templateColorPalette.first.id}')),
        )
        .dy;
    final titleTop =
        tester.getTopLeft(find.byKey(const Key('cardTitleField'))).dy;
    final templateTop =
        tester.getTopLeft(find.byKey(const Key('cardTemplateField'))).dy;
    final templatePreview = find.byKey(
      const Key('cardTemplatePreviewIcon'),
    );
    final categoryField = find.byKey(const Key('cardCategoryField'));
    final categoryPreview = find.byKey(
      const Key('cardCategoryPreviewIcon'),
    );
    expect(templatePreview, findsOneWidget);
    expect(categoryField, findsOneWidget);
    expect(categoryPreview, findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('cardBoundIcon'))),
      const Size(100, 100),
    );
    expect(titleTop, closeTo(iconTop, 0.01));
    expect(
      pickerTop -
          tester.getBottomLeft(find.byKey(const Key('cardTitleField'))).dy,
      closeTo(7, 0.01),
    );
    expect(pickerBottom, closeTo(iconBottom, 0.01));
    expect(colorTop, greaterThan(iconBottom));
    expect(templateTop, greaterThan(colorTop));
    expect(tester.getSize(templatePreview), const Size(41, 41));
    expect(tester.getSize(categoryPreview), const Size(41, 41));
    expect(
      tester.getSize(find.byKey(const Key('cardTemplatePreviewContent'))),
      const Size(33, 33),
    );
    expect(
      tester.getSize(find.byKey(const Key('cardCategoryPreviewContent'))),
      const Size(33, 33),
    );
    expect(
      tester.getTopLeft(templatePreview).dy,
      closeTo(templateTop, 0.01),
    );
    expect(
      tester.getTopLeft(categoryPreview).dy,
      closeTo(templateTop, 0.01),
    );
    expect(
      tester.getBottomLeft(find.byKey(const Key('cardTemplateField'))).dy -
          tester.getBottomLeft(templatePreview).dy,
      closeTo(4, 0.01),
    );
    expect(
      tester.getBottomLeft(categoryField).dy -
          tester.getBottomLeft(categoryPreview).dy,
      closeTo(4, 0.01),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('cardTemplateField'))).dx -
          tester.getTopRight(templatePreview).dx,
      closeTo(5, 0.01),
    );
    expect(
      tester.getTopLeft(categoryPreview).dx -
          tester.getTopRight(categoryField).dx,
      closeTo(5, 0.01),
    );
    expect(
      tester.getSize(find.byKey(const Key('cardTemplateField'))).width,
      closeTo(tester.getSize(categoryField).width, 0.01),
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(
              ValueKey('cardColor-${templateColorPalette.first.id}'),
            ),
          )
          .dx,
      closeTo(iconLeft, 0.01),
    );
    expect(
      tester
          .getTopRight(
            find.byKey(
              ValueKey('cardColor-${templateColorPalette.last.id}'),
            ),
          )
          .dx,
      closeTo(tester.getTopRight(categoryPreview).dx, 0.01),
    );
    await tester.tap(find.byKey(const Key('cardTemplateField')));
    await tester.pumpAndSettle();
    final templateMenuIcon = find.byKey(
      ValueKey('cardTemplateIcon-${builtInTemplates().first.id}'),
    );
    expect(templateMenuIcon, findsOneWidget);
    await tester.tap(templateMenuIcon);
    await tester.pumpAndSettle();

    await tester.tap(categoryField);
    await tester.pumpAndSettle();
    final categoryMenuIcon = find.byKey(
      const ValueKey('cardCategoryMenuIcon-Finance'),
    );
    expect(categoryMenuIcon, findsOneWidget);
    await tester.tap(categoryMenuIcon);
    await tester.pumpAndSettle();
    expect(find.text('Папка / каталог'), findsOneWidget);
    final firstFieldId = builtInTemplates().first.fields.first.id;
    final secondFieldId = builtInTemplates().first.fields[1].id;
    expect(
      tester
          .widget<TextField>(find.byKey(ValueKey('cardField-$firstFieldId')))
          .contextMenuBuilder,
      isNotNull,
    );
    expect(
      find.byKey(ValueKey('cardFieldUp-$firstFieldId')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('cardFieldDown-$firstFieldId')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('cardFieldDelete-$firstFieldId')),
      findsOneWidget,
    );
    final firstField = find.byKey(ValueKey('cardField-$firstFieldId'));
    final secondField = find.byKey(ValueKey('cardField-$secondFieldId'));
    final moveDown = find.byKey(ValueKey('cardFieldDown-$firstFieldId'));
    await tester.ensureVisible(moveDown);
    await tester.pumpAndSettle();
    await tester.tap(moveDown);
    await tester.pump();
    expect(
      tester.getTopLeft(firstField).dy,
      greaterThan(tester.getTopLeft(secondField).dy),
    );
    await tester.tap(find.byKey(const Key('cardUndoButton')));
    await tester.pump();
    expect(
      tester.getTopLeft(firstField).dy,
      lessThan(tester.getTopLeft(secondField).dy),
    );

    final notesId = builtInTemplates()
        .first
        .fields
        .firstWhere((field) => field.type == 'multiline_note')
        .id;
    final notesField = find.byKey(ValueKey('cardField-$notesId'));
    final notesUp = find.byKey(ValueKey('cardFieldUp-$notesId'));
    final notesDown = find.byKey(ValueKey('cardFieldDown-$notesId'));
    final notesDelete = find.byKey(ValueKey('cardFieldDelete-$notesId'));
    final notesControls = find.byKey(ValueKey('cardFieldControls-$notesId'));
    final firstDelete = find.byKey(ValueKey('cardFieldDelete-$firstFieldId'));
    await tester.ensureVisible(notesField);
    await tester.pumpAndSettle();
    final longNote =
        List.generate(80, (index) => 'Строка ${index + 1}').join('\n');
    await tester.tap(notesField);
    await tester.enterText(notesField, longNote);
    await tester.pump();

    final notesWidget = tester.widget<TextField>(notesField);
    expect(notesWidget.controller!.text, longNote);
    expect(notesWidget.keyboardType, TextInputType.multiline);
    expect(notesWidget.textInputAction, TextInputAction.newline);
    expect(tester.getSize(notesField).height, 180);
    expect(notesControls, findsNothing);
    expect(notesUp, findsNothing);
    expect(notesDown, findsNothing);
    expect(notesDelete, findsNothing);
    expect(
      tester.getTopLeft(notesField).dx,
      closeTo(tester.getTopLeft(firstField).dx, 0.01),
    );
    expect(
      tester.getTopRight(notesField).dx,
      closeTo(tester.getTopRight(firstDelete).dx, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow card editor matches the adaptive reference layout',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(500, 900)),
          child: ItemEditorDialog(
            templates: builtInTemplates(),
            categories: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundIcon = find.byKey(const Key('cardBoundIcon'));
    final titleField = find.byKey(const Key('cardTitleField'));
    final original = find.byKey(const Key('spbCardIconPicker'));
    final upload = find.byKey(const Key('cardUploadIconButton'));
    final firstColor = find.byKey(
      ValueKey('cardColor-${templateColorPalette.first.id}'),
    );
    final lastColor = find.byKey(
      ValueKey('cardColor-${templateColorPalette.last.id}'),
    );
    final templateField = find.byKey(const Key('cardTemplateField'));
    final categoryField = find.byKey(const Key('cardCategoryField'));
    final templatePreview = find.byKey(
      const Key('cardTemplatePreviewIcon'),
    );
    final categoryPreview = find.byKey(
      const Key('cardCategoryPreviewIcon'),
    );
    final iconTop = tester.getTopLeft(boundIcon).dy;
    final iconBottom = tester.getBottomLeft(boundIcon).dy;
    final colorTop = tester.getTopLeft(firstColor).dy;
    final titleTop =
        tester.getTopLeft(find.byKey(const Key('cardTitleField'))).dy;
    final templateTop = tester.getTopLeft(templateField).dy;
    final categoryTop = tester.getTopLeft(categoryField).dy;

    expect(tester.getSize(boundIcon), const Size(88, 88));
    expect(templatePreview, findsOneWidget);
    expect(categoryPreview, findsOneWidget);
    expect(tester.getSize(templatePreview), const Size(41, 41));
    expect(tester.getSize(categoryPreview), const Size(41, 41));
    expect(
      tester.widget<TextField>(titleField).style?.fontWeight,
      FontWeight.bold,
    );
    expect(tester.widget<SpbGrayPickerButton>(original).compact, isTrue);
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: original,
              matching: find.byIcon(Icons.photo_library_outlined),
            ),
          )
          .size,
      28,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: upload,
              matching: find.text('загрузить иконку'),
            ),
          )
          .style
          ?.fontSize,
      10,
    );
    expect(titleTop, lessThan(iconTop));
    expect(
      tester.getTopLeft(titleField).dx,
      closeTo(tester.getTopLeft(boundIcon).dx, 0.01),
    );
    expect(
      tester.getTopRight(titleField).dx,
      closeTo(tester.getTopRight(categoryField).dx, 0.01),
    );
    expect(tester.getSize(original).height, closeTo(88, 0.01));
    expect(tester.getSize(upload).height, closeTo(88, 0.01));
    expect(tester.getTopLeft(original).dy, closeTo(iconTop, 0.01));
    expect(tester.getBottomLeft(upload).dy, closeTo(iconBottom, 0.01));
    expect(
      iconTop - tester.getBottomLeft(titleField).dy,
      closeTo(14, 0.01),
    );
    expect(colorTop - iconBottom, closeTo(10, 0.01));
    expect(tester.getSize(firstColor).height, 27);
    expect(
      tester.getSize(firstColor).width,
      closeTo(tester.getSize(lastColor).width, 0.01),
    );
    expect(
      tester.getTopLeft(firstColor).dx,
      closeTo(tester.getTopLeft(boundIcon).dx, 0.01),
    );
    expect(
      tester.getTopRight(lastColor).dx,
      closeTo(tester.getTopRight(templateField).dx, 0.01),
    );
    expect(tester.getTopLeft(templatePreview).dy, closeTo(templateTop, 0.01));
    expect(
      categoryTop - tester.getBottomLeft(templateField).dy,
      closeTo(9, 0.01),
    );
    expect(tester.getTopLeft(categoryPreview).dy, closeTo(categoryTop, 0.01));
    final narrowFirstField = find.byKey(
      ValueKey('cardField-${builtInTemplates().first.fields.first.id}'),
    );
    final narrowNotesId = builtInTemplates()
        .first
        .fields
        .firstWhere((field) => field.type == 'multiline_note')
        .id;
    final narrowNotesField = find.byKey(ValueKey('cardField-$narrowNotesId'));
    final narrowNotesControls = find.byKey(
      ValueKey('cardFieldControls-$narrowNotesId'),
    );
    final narrowFirstDelete = find.byKey(
      ValueKey(
        'cardFieldDelete-${builtInTemplates().first.fields.first.id}',
      ),
    );
    expect(narrowNotesControls, findsNothing);
    expect(
      find.byKey(ValueKey('cardFieldUp-$narrowNotesId')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('cardFieldDown-$narrowNotesId')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('cardFieldDelete-$narrowNotesId')),
      findsNothing,
    );
    expect(
      tester.getTopLeft(narrowNotesField).dx,
      closeTo(tester.getTopLeft(narrowFirstField).dx, 0.01),
    );
    expect(
      tester.getTopRight(narrowNotesField).dx,
      closeTo(tester.getTopRight(narrowFirstDelete).dx, 0.01),
    );
    final singleLineTitleHeight = tester.getSize(titleField).height;
    await tester.enterText(
      titleField,
      'Очень длинное название карточки, которое не помещается в одну строку '
      'и должно автоматически переноситься на следующие строки',
    );
    await tester.pump();
    expect(singleLineTitleHeight, closeTo(45, 0.01));
    expect(
        tester.getSize(titleField).height, greaterThan(singleLineTitleHeight));

    final editorContext = tester.element(
      find.byKey(const Key('cardEditorSurface')),
    );
    Future<void> expectFullScreenPicker({
      required Future<String?> Function() open,
      required Key dialogKey,
      required String title,
    }) async {
      open();
      for (var attempt = 0;
          attempt < 20 && find.byKey(dialogKey).evaluate().isEmpty;
          attempt++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(dialogKey)), const Size(500, 900));
      final titleWidget = tester.widget<Text>(find.text(title));
      expect(titleWidget.maxLines, 1);
      expect(titleWidget.softWrap, isFalse);
    }

    await expectFullScreenPicker(
      open: () => showSpbOriginalIconPickerDialog(editorContext, ''),
      dialogKey: const Key('spbIconPickerDialog'),
      title: 'Иконки SPB Wallet',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
    await tester.pumpAndSettle();

    await expectFullScreenPicker(
      open: () => showIconPickerDialog(editorContext, ''),
      dialogKey: const Key('pictogramPickerDialog'),
      title: 'Все пиктограммы',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
    await tester.pumpAndSettle();

    await expectFullScreenPicker(
      open: () => showThirdPartyIconPickerDialog(editorContext),
      dialogKey: const Key('thirdPartyIconPickerDialog'),
      title: 'Сторонние иконки',
    );
    expect(find.byKey(const Key('thirdPartyIconSearch')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vertical editors keep their size when keyboard opens and closes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final template = builtInTemplates().first;

    Widget templateEditor(double keyboardHeight) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 800),
              viewInsets: EdgeInsets.only(bottom: keyboardHeight),
            ),
            child: TemplateEditorDialog(initial: template),
          ),
        );

    await tester.pumpWidget(templateEditor(0));
    await tester.pumpAndSettle();
    final initialTemplateSize =
        tester.getSize(find.byKey(const Key('templateEditorSurface')));
    await tester.pumpWidget(templateEditor(224));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('templateEditorSurface'))),
      initialTemplateSize,
    );
    final lastField = find.byKey(
      ValueKey('templateFieldName-${template.fields.last.id}'),
    );
    await tester.ensureVisible(lastField);
    await tester.pumpAndSettle();
    await tester.tap(lastField);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(lastField).dy, lessThan(560));
    await tester.pumpWidget(templateEditor(0));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('templateEditorSurface'))),
      initialTemplateSize,
    );

    Widget cardEditor(double keyboardHeight) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 800),
              viewInsets: EdgeInsets.only(bottom: keyboardHeight),
            ),
            child: ItemEditorDialog(
              templates: builtInTemplates(),
              categories: const [],
            ),
          ),
        );
    await tester.pumpWidget(cardEditor(0));
    await tester.pumpAndSettle();
    final initialCardSize =
        tester.getSize(find.byKey(const Key('cardEditorSurface')));
    await tester.pumpWidget(cardEditor(224));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('cardEditorSurface'))),
      initialCardSize,
    );
    await tester.pumpWidget(cardEditor(0));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('cardEditorSurface'))),
      initialCardSize,
    );
  });

  testWidgets('card preview uses template design and skips empty fields',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    final template = builtInTemplates().first;
    final item = SecretItem(
      id: 'preview-card',
      templateId: template.id,
      title: 'Карточка просмотра',
      category: '',
      colorId: template.colorId,
      values: {
        template.fields[0].id: 'Заполнено',
        template.fields[1].id: '',
        template.fields[2].id: 'Заметка',
      },
      modifiedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CardPreviewDialog(
          item: item,
          template: template,
          onAddAttachment: (item) async => item,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final previewSize =
        tester.getSize(find.byKey(const Key('cardPreviewSurface')));
    expect(previewSize.width, 360);
    expect(previewSize.height, greaterThan(500));
    expect(find.byKey(const Key('cardPreviewTitle')), findsOneWidget);
    expect(find.byKey(const Key('cardPreviewModifiedAt')), findsOneWidget);
    expect(find.text('01.01.2026 00:00'), findsOneWidget);
    expect(find.byKey(const Key('cardPreviewIcon')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('cardPreviewIcon'))),
      const Size(88, 88),
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(const Key('cardPreviewIcon')),
              matching: find.byType(Icon),
            ),
          )
          .size,
      80,
    );
    expect(
      find.byKey(ValueKey('cardPreviewField-${template.fields[0].id}')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<EditableText>(find.descendant(
            of: find.byKey(
              ValueKey('cardPreviewField-${template.fields[0].id}'),
            ),
            matching: find.byType(EditableText),
          ))
          .contextMenuBuilder,
      isNotNull,
    );
    expect(
      find.byKey(ValueKey('cardPreviewField-${template.fields[1].id}')),
      findsNothing,
    );
    expect(find.byKey(const Key('cardPreviewBackButton')), findsOneWidget);
    expect(find.byKey(const Key('cardPreviewEditButton')), findsOneWidget);
    expect(find.byKey(const Key('cardPreviewDeleteButton')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('cardPreviewBackButton')),
        matching: find.byIcon(Icons.close),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('cardPreviewDeleteButton')),
        matching: find.byIcon(Icons.delete_outline),
      ),
      findsOneWidget,
    );
    expect(
      tester.getCenter(find.byKey(const Key('cardPreviewEditButton'))).dx,
      lessThan(
        tester.getCenter(find.byKey(const Key('cardPreviewDeleteButton'))).dx,
      ),
    );
    expect(
      tester.getCenter(find.byKey(const Key('cardPreviewDeleteButton'))).dx,
      lessThan(
        tester.getCenter(find.byKey(const Key('cardPreviewBackButton'))).dx,
      ),
    );
    expect(
      find.byKey(const Key('cardPreviewSaveAttachmentButton')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('cardPreviewAddAttachmentButton')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('desktop selected text menu shows Cut Copy Paste Share',
      (tester) async {
    final controller = TextEditingController(text: 'Alpha Beta');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: TextField(
                key: const Key('desktopContextMenuField'),
                controller: controller,
                contextMenuBuilder: desktopCardTextContextMenu,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('desktopContextMenuField')));
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('desktopContextMenuField')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('android long press opens text menu in editor and preview',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(480, 900));
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    const field = FieldDefinition(
      id: 'value',
      label: 'Поле',
      type: 'text',
    );
    const template = CardTemplate(
      id: 'android-context-template',
      name: 'Android menu',
      iconId: 'key',
      colorId: 'blue',
      fields: [field],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: ItemEditorDialog(templates: [template], categories: []),
      ),
    );
    await tester.pumpAndSettle();
    final editorField = find.byKey(const ValueKey('cardField-value'));
    await tester.enterText(editorField, 'Alpha Beta');
    await tester.pumpAndSettle();
    final editorText = find.descendant(
      of: editorField,
      matching: find.byType(EditableText),
    );
    await tester.longPressAt(textOffsetPosition(tester, editorText, 2));
    await tester.pumpAndSettle();

    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);

    final item = SecretItem(
      id: 'android-context-card',
      templateId: template.id,
      title: 'Карточка',
      category: '',
      colorId: template.colorId,
      values: const {'value': 'Alpha Beta'},
      modifiedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      MaterialApp(home: CardPreviewDialog(item: item, template: template)),
    );
    await tester.pumpAndSettle();
    final previewField = find.byKey(const ValueKey('cardPreviewField-value'));
    final previewText = find.descendant(
      of: previewField,
      matching: find.byType(EditableText),
    );
    await tester.longPressAt(textOffsetPosition(tester, previewText, 2));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.byKey(const Key('copyAllCardFieldsAction')), findsNothing);
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('preview selected field keeps its desktop text menu',
      (tester) async {
    const field = FieldDefinition(
      id: 'value',
      label: 'Поле',
      type: 'text',
    );
    const template = CardTemplate(
      id: 'context-template',
      name: 'Контекстное меню',
      iconId: 'key',
      colorId: 'blue',
      fields: [field],
    );
    final item = SecretItem(
      id: 'context-card',
      templateId: template.id,
      title: 'Карточка',
      category: '',
      colorId: template.colorId,
      values: const {'value': 'Alpha Beta'},
      modifiedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      MaterialApp(home: CardPreviewDialog(item: item, template: template)),
    );
    await tester.pumpAndSettle();

    final previewField = find.byKey(const ValueKey('cardPreviewField-value'));
    final editable = find.descendant(
      of: previewField,
      matching: find.byType(EditableText),
    );
    final editableState = tester.state<EditableTextState>(editable);
    await tester.tap(previewField);
    await tester.pump();
    editableState.userUpdateTextEditingValue(
      const TextEditingValue(
        text: 'Alpha Beta',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      ),
      SelectionChangedCause.keyboard,
    );
    await tester.pump();
    await tester.tapAt(
      tester.getTopLeft(previewField) + const Offset(24, 24),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.byKey(const Key('copyAllCardFieldsAction')), findsNothing);
  });
  testWidgets('every populated preview field has a gray copy action',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final template = builtInTemplates().first;
    final copiedField = template.fields.first;
    final emptyField = template.fields[1];
    final item = SecretItem(
      id: 'field-copy-preview-card',
      templateId: template.id,
      title: 'Копирование поля',
      category: '',
      colorId: template.colorId,
      values: {
        copiedField.id: 'Значение для буфера',
        emptyField.id: '',
      },
      modifiedAt: DateTime(2026),
    );
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText =
            (call.arguments as Map<dynamic, dynamic>)['text'] as String;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(home: CardPreviewDialog(item: item, template: template)),
    );
    await tester.pumpAndSettle();

    final copyButton =
        find.byKey(ValueKey('cardPreviewCopy-${copiedField.id}'));
    expect(copyButton, findsOneWidget);
    expect(
      find.byKey(ValueKey('cardPreviewCopy-${emptyField.id}')),
      findsNothing,
    );
    final icon = tester.widget<Icon>(
      find.descendant(
          of: copyButton, matching: find.byIcon(Icons.copy_outlined)),
    );
    expect(icon.color, const Color(0xff777777));

    await tester.tap(copyButton);
    await tester.pump();
    expect(copiedText, 'Значение для буфера');
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('card preview copies all labeled values from context menu',
      (tester) async {
    final template = builtInTemplates().first;
    final item = SecretItem(
      id: 'copy-preview-card',
      templateId: template.id,
      title: 'Карточка для копирования',
      category: 'Работа',
      colorId: template.colorId,
      values: {
        template.fields[0].id: 'Пользователь',
        template.fields[1].id: 'Секрет',
      },
      modifiedAt: DateTime(2026),
    );
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText =
            (call.arguments as Map<dynamic, dynamic>)['text'] as String;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(home: CardPreviewDialog(item: item, template: template)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('cardPreviewIcon')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('copyAllCardFieldsAction')), findsOneWidget);
    await tester.tap(find.byKey(const Key('copyAllCardFieldsAction')));
    await tester.pumpAndSettle();

    expect(copiedText, contains('Название:\nКарточка для копирования'));
    expect(copiedText, contains('Категория:\nРабота'));
    expect(copiedText, contains('${template.fields[0].label}:\nПользователь'));
    expect(copiedText, contains('${template.fields[1].label}:\nСекрет'));

    await tester.longPress(find.byKey(const Key('cardPreviewIcon')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('copyAllCardFieldsAction')), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
  });

  testWidgets('card attachment controls use requested colors and file names',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final template = builtInTemplates().first;
    final attachments = [
      const SecretAttachment(
        id: '',
        fileName: 'описание.txt',
        size: 4,
        pendingBytes: [116, 101, 115, 116],
      ),
      const SecretAttachment(
        id: '',
        fileName: 'звук.mp3',
        size: 3,
        pendingBytes: [5, 6, 7],
      ),
      const SecretAttachment(
        id: '',
        fileName: 'фото.png',
        size: 4,
        pendingBytes: [137, 80, 78, 71],
      ),
    ];
    final item = SecretItem(
      id: 'attachment-card',
      templateId: template.id,
      title: 'Вложения',
      category: '',
      colorId: template.colorId,
      values: const {},
      attachments: attachments,
      modifiedAt: DateTime(2026),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ItemEditorDialog(
          templates: builtInTemplates(),
          categories: const [],
          initial: item,
          supportsAttachments: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('описание.txt'), findsOneWidget);
    expect(find.text('звук.mp3'), findsOneWidget);
    expect(find.text('Вложения .swl'), findsNothing);
    expect(find.byKey(const Key('cardEditorModifiedAt')), findsOneWidget);
    expect(
      find.byKey(const Key('cardEditorSaveAttachmentButton')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cardEditorAddAttachmentButton')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cardEditorDeleteAttachmentButton')),
      findsOneWidget,
    );
    final editorName = find.byKey(
      const ValueKey('cardEditorAttachment-описание.txt'),
    );
    final editorNameTap = tester.widget<InkWell>(
      find.descendant(of: editorName, matching: find.byType(InkWell)),
    );
    expect(editorNameTap.onTap, isNotNull);
    expect(editorNameTap.onSecondaryTap, isNotNull);
    expect(editorNameTap.onLongPress, isNotNull);
    expect(
      find.byKey(const ValueKey('cardEditorInlineAttachment-фото.png')),
      findsOneWidget,
    );

    final deleteAttachment =
        find.byKey(const Key('cardEditorDeleteAttachmentButton'));
    expect(
      find.descendant(
        of: deleteAttachment,
        matching: find.byIcon(Icons.delete),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(deleteAttachment);
    await tester.pumpAndSettle();
    await tester.tap(deleteAttachment);
    await tester.pumpAndSettle();
    expect(find.text('Удалить вложение'), findsOneWidget);
    await tester.tap(find.text('описание.txt').last);
    await tester.pumpAndSettle();
    expect(find.text('описание.txt'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: CardPreviewDialog(
          item: item,
          template: template,
          onAddAttachment: (item) async => item,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('cardPreviewSaveAttachmentButton')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cardPreviewAddAttachmentButton')),
      findsNothing,
    );
    final previewSaveButton = tester.widget<SpbGradientActionButton>(
      find.byKey(const Key('cardPreviewSaveAttachmentButton')),
    );
    expect(
      previewSaveButton.colors,
      const [Color(0xff555555), Color(0xff050505)],
    );
    expect(
      tester
          .getCenter(find.byKey(const Key('cardPreviewSaveAttachmentButton')))
          .dx,
      lessThan(
        tester.getCenter(find.byKey(const Key('cardPreviewEditButton'))).dx,
      ),
    );
    final previewName = find.byKey(
      const ValueKey('cardPreviewAttachment-описание.txt'),
    );
    final previewNameTap = tester.widget<InkWell>(
      find.descendant(of: previewName, matching: find.byType(InkWell)),
    );
    expect(previewNameTap.onTap, isNotNull);
    expect(previewNameTap.onSecondaryTap, isNotNull);
    expect(previewNameTap.onLongPress, isNotNull);
    expect(
      find.byKey(
        const ValueKey('cardPreviewInlineAttachment-описание.txt'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('cardPreviewInlineAttachment-звук.mp3'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('cardPreviewInlineAttachment-фото.png'),
      ),
      findsOneWidget,
    );
    expect(find.text('test'), findsNothing);
    expect(find.textContaining('MP3 ·'), findsNothing);
  });

  testWidgets('category editor uses template design and fills narrow screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: CategoryEditorDialog(
          editing: true,
          initialName: 'Работа',
          initialIconId: 'folder',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editorSize =
        tester.getSize(find.byKey(const Key('categoryEditorSurface')));
    expect(editorSize.width, 360);
    expect(editorSize.height, greaterThanOrEqualTo(500));
    expect(find.byKey(const Key('categoryBoundIcon')), findsOneWidget);
    expect(find.byKey(const Key('spbFolderIconPicker')), findsOneWidget);
    expect(find.byKey(const Key('categoryPictogramPicker')), findsOneWidget);
    expect(find.byKey(const Key('categoryThirdPartyPicker')), findsOneWidget);
    expect(find.byKey(const Key('categoryUploadIconButton')), findsOneWidget);
    expect(find.byKey(const Key('categoryDeleteButton')), findsOneWidget);
    expect(find.byKey(const Key('categorySaveButton')), findsOneWidget);
    expect(find.byKey(const Key('categoryCloseButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new folder asks for a name before showing save', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: CategoryEditorDialog(
          editing: false,
          initialName: '',
          initialIconId: 'folder',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nameField = find.byKey(const Key('categoryNameField'));
    final field = tester.widget<TextField>(nameField);
    expect(field.autofocus, isTrue);
    expect(field.decoration!.hintText, 'Введите имя папки');
    expect(find.byKey(const Key('categorySaveButton')), findsNothing);

    await tester.enterText(nameField, 'Архив');
    await tester.pump();
    expect(find.byKey(const Key('categorySaveButton')), findsOneWidget);
  });

  testWidgets('compact move picker uses folder list and standard actions',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(576, 1024));
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    state.setState(() => state.categoryPaths = <String>{'Работа', 'Архив'});
    await tester.pump();

    final Future<String?> result = state.showMoveTargetDialog(
      initialPath: '',
    );
    await tester.pumpAndSettle();
    final moveSurfaceSize =
        tester.getSize(find.byKey(const Key('moveTargetSurface')));
    expect(moveSurfaceSize.width, 576);
    expect(moveSurfaceSize.height, greaterThanOrEqualTo(552));
    expect(find.byKey(const ValueKey('moveTarget-Работа')), findsOneWidget);
    final cancel = find.byKey(const Key('cancelMoveButton'));
    final confirm = find.byKey(const Key('confirmMoveButton'));
    expect(
        tester.getTopLeft(cancel).dx, lessThan(tester.getTopLeft(confirm).dx));
    await tester.tap(find.byKey(const ValueKey('moveTarget-Работа')));
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(await result, 'Работа');
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('desktop vault uses the W1 three-column layout', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.binding.setSurfaceSize(const Size(1280, 1010));
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    final desktopSearch = find.byKey(const Key('spbSearchInput'));
    final desktopSubmit = find.byKey(const Key('spbSubmitSearchButton'));
    expect(tester.getSize(desktopSearch).width, closeTo(250.445, 0.1));
    expect(
      tester.getTopLeft(desktopSearch).dy - tester.getTopLeft(desktopSubmit).dy,
      closeTo(1.1, 0.1),
    );
    expect(
      tester.getTopLeft(desktopSubmit).dx,
      greaterThan(tester.getTopRight(desktopSearch).dx + 5),
    );

    expect(find.text('Мои карточки'), findsNWidgets(2));
    expect(find.text('Задачи'), findsOneWidget);
    expect(find.text('Создать кошелёк'), findsOneWidget);
    expect(find.byKey(const Key('spbCreateWalletAppIcon')), findsOneWidget);
    expect(find.text('Создать новую папку'), findsOneWidget);
    expect(find.text('Сделать архивную копию'), findsOneWidget);
    final undo = find.byTooltip('Отменить изменения этой сессии');
    final trash = find.byTooltip('Восстановить удалённые');
    final forceClose = find.byKey(const Key('spbForceCloseButton'));
    expect(undo, findsOneWidget);
    expect(trash, findsNothing);
    expect(forceClose, findsOneWidget);
    expect(
      tester.getTopLeft(undo).dx,
      lessThan(tester.getTopLeft(forceClose).dx),
    );
    expect(
      tester.getCenter(forceClose).dy,
      closeTo(tester.getCenter(undo).dy, 0.1),
    );
    await tester.tap(
      find.byKey(const Key('spbCentralWorkspace')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Создать карточку'), findsOneWidget);
    expect(find.text('Создать папку'), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    expect(state.spbSearchMatches('Привет мир', 'ghbdtn'), isTrue);
    expect(state.spbSearchMatches('Привет мир', 'privet'), isTrue);
    expect(state.spbSearchMatches('Привет мир', 'превет'), isTrue);
    expect(state.spbSearchMatches('Привет мир', 'account'), isFalse);
    await tester.enterText(desktopSearch, 'live-search');
    await tester.pump();
    expect(state.spbSubmittedSearchQuery, 'live-search');
    await tester.enterText(desktopSearch, '');
    await tester.pump();
    expect(state.spbSubmittedSearchQuery, isEmpty);
    state.mobileTemplatesOpen = true;
    state.selectedTemplateId = state.templates.first.id;
    state.setState(() {});
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey('spbCentralTemplate-${state.templates.first.id}'),
      ),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('copyTemplateContextAction')), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('mobile center pane shows a persistent folder grid scrollbar',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(VaultShell));
    final CardTemplate template = state.templates.first as CardTemplate;
    state.setState(() {
      state.mobilePane = 1;
      state.items = List<SecretItem>.generate(
        40,
        (index) => SecretItem(
          id: 'scroll-card-$index',
          templateId: template.id,
          title: 'Scroll card $index',
          category: '',
          colorId: template.colorId,
          values: const <String, String>{},
          modifiedAt: DateTime(2026),
        ),
      );
    });
    await tester.pumpAndSettle();

    final scrollbarFinder = find.byKey(const Key('spbFolderGridScrollbar'));
    expect(scrollbarFinder, findsOneWidget);
    final scrollbar = tester.widget<Scrollbar>(scrollbarFinder);
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.interactive, isTrue);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('spbCentralCard-scroll-card-0')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Draggable<SecretItem>,
        ),
      ),
      findsNothing,
    );
    expect(state.spbFolderGridScrollController.hasClients, isTrue);
    expect(
      state.spbFolderGridScrollController.position.maxScrollExtent,
      greaterThan(0),
    );

    await tester.drag(
      find.descendant(
        of: find.byKey(const Key('spbCentralWorkspace')),
        matching: find.byType(GridView),
      ),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    expect(state.spbFolderGridScrollController.offset, greaterThan(0));
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('desktop center pane keeps card dragging', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(VaultShell));
    final CardTemplate template = state.templates.first as CardTemplate;
    state.setState(() {
      state.items = <SecretItem>[
        SecretItem(
          id: 'desktop-draggable-card',
          templateId: template.id,
          title: 'Desktop draggable card',
          category: '',
          colorId: template.colorId,
          values: const <String, String>{},
          modifiedAt: DateTime(2026),
        ),
      ];
    });
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('spbCentralCard-desktop-draggable-card'),
        ),
        matching: find.byWidgetPredicate(
          (widget) => widget is Draggable<SecretItem>,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('central card reacts only on its icon and label', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(VaultShell));
    final CardTemplate template = state.templates.first as CardTemplate;
    state.setState(() {
      state.selectedItemId = 'card-hit-area';
      state.items = <SecretItem>[
        SecretItem(
          id: 'card-hit-area',
          templateId: template.id,
          title: 'Card hit area',
          category: '',
          colorId: template.colorId,
          values: const <String, String>{},
          modifiedAt: DateTime(2026),
        ),
      ];
    });
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('spbCentralCard-card-hit-area'));
    final activeRegions = find.descendant(
      of: card,
      matching: find.byWidgetPredicate(
        (widget) => widget is GestureDetector && widget.onTap != null,
      ),
    );
    expect(activeRegions, findsNWidgets(2));
    expect(tester.getSize(activeRegions.at(0)), const Size(68, 67));
    expect(tester.getSize(activeRegions.at(1)).width, 73.3125);
    final selectedBackgrounds = find.descendant(
      of: card,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).gradient != null,
      ),
    );
    expect(selectedBackgrounds, findsNWidgets(2));
    expect(
      tester.getSize(selectedBackgrounds.at(0)),
      const Size(50.25, 50.25),
    );
    expect(
      tester.getSize(selectedBackgrounds.at(1)).width,
      lessThanOrEqualTo(73.3125),
    );

    final cardRect = tester.getRect(card);
    await tester.tapAt(Offset(cardRect.left + 1, cardRect.top + 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cardPreviewSurface')), findsNothing);

    await tester.tap(activeRegions.at(0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cardPreviewSurface')), findsOneWidget);
  });

  testWidgets('wide vault header shows the file modified date beside the title',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final temp = Directory.systemTemp.createTempSync('wallet-aps-wide-date-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}/wide-wallet.swl')
      ..writeAsStringSync('test');
    file.setLastModifiedSync(DateTime(2026, 9, 26, 14, 35));

    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(VaultShell));
    state.setState(() {
      state.spbWalletPath = file.path;
      state.spbWalletDisplayPath = file.path;
    });
    await tester.pumpAndSettle();

    final header = find.byKey(const Key('spbVaultTitle'));
    final title = find.descendant(
      of: header,
      matching: find.text('wide-wallet'),
    );
    final modified = find.byKey(const Key('spbDesktopVaultModified'));
    expect(title, findsOneWidget);
    expect(modified, findsOneWidget);
    expect(tester.widget<Text>(modified).data, '26.09.26 14.35');
    expect(tester.widget<Text>(modified).style?.fontSize, 13.6);
    expect(tester.widget<Text>(modified).style?.fontWeight, FontWeight.normal);
    final baselineRow = find.ancestor(
      of: modified,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Row &&
            widget.crossAxisAlignment == CrossAxisAlignment.baseline &&
            widget.textBaseline == TextBaseline.alphabetic,
      ),
    );
    expect(baselineRow, findsOneWidget);
    expect(find.descendant(of: baselineRow, matching: title), findsOneWidget);
    expect(
        tester.getCenter(modified).dx, greaterThan(tester.getCenter(title).dx));
  });

  testWidgets('narrow vault header shows a thirty percent smaller file date',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final temp = Directory.systemTemp.createTempSync('wallet-aps-narrow-date-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}/narrow-wallet.swl')
      ..writeAsStringSync('test');
    file.setLastModifiedSync(DateTime(2026, 9, 26, 8, 7));

    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(VaultShell));
    state.setState(() {
      state.spbWalletPath = file.path;
      state.spbWalletDisplayPath = file.path;
    });
    await tester.pumpAndSettle();

    final title = find.byKey(const Key('spbMobileWalletTitle'));
    final modified = find.byKey(const Key('spbMobileVaultModified'));
    expect(title, findsOneWidget);
    expect(tester.widget<Text>(title).data, 'narrow-wallet');
    expect(modified, findsOneWidget);
    expect(tester.widget<Text>(modified).data, '26.09.26 08.07');
    expect(tester.widget<Text>(modified).style?.fontSize, 15.4);
    expect(tester.widget<Text>(modified).style?.fontWeight, FontWeight.normal);
    final baselineRow = find.ancestor(
      of: modified,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Row &&
            widget.crossAxisAlignment == CrossAxisAlignment.baseline &&
            widget.textBaseline == TextBaseline.alphabetic,
      ),
    );
    expect(baselineRow, findsOneWidget);
    expect(find.descendant(of: baselineRow, matching: title), findsOneWidget);
    expect(
        tester.getCenter(modified).dx, greaterThan(tester.getCenter(title).dx));
  });

  testWidgets('wide top-level folders keep two pixels between icons',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(VaultShell));
    final CardTemplate template = state.templates.first as CardTemplate;
    state.setState(() {
      state.items = <SecretItem>[
        SecretItem(
          id: 'folder-spacing-card-a',
          templateId: template.id,
          title: 'Card A',
          category: 'Folder spacing A',
          colorId: template.colorId,
          values: const <String, String>{},
          modifiedAt: DateTime(2026),
        ),
        SecretItem(
          id: 'folder-spacing-card-b',
          templateId: template.id,
          title: 'Card B',
          category: 'Folder spacing B',
          colorId: template.colorId,
          values: const <String, String>{},
          modifiedAt: DateTime(2026),
        ),
        SecretItem(
          id: 'nested-folder-spacing-card-a',
          templateId: template.id,
          title: 'Nested card A',
          category: 'Expanded folder / Nested folder A',
          colorId: template.colorId,
          values: const <String, String>{},
          modifiedAt: DateTime(2026),
        ),
        SecretItem(
          id: 'nested-folder-spacing-card-b',
          templateId: template.id,
          title: 'Nested card B',
          category: 'Expanded folder / Nested folder B',
          colorId: template.colorId,
          values: const <String, String>{},
          modifiedAt: DateTime(2026),
        ),
      ];
      state.expandedCategoryPaths.add('Expanded folder');
      state.selectedCategoryPath = 'Folder spacing A';
    });
    await tester.pumpAndSettle();

    final firstFolderFinder =
        find.byKey(const ValueKey('spbTreeFolder-Folder spacing A'));
    final firstFolderTile = tester.widget<ExpansionTile>(
      find.descendant(
        of: firstFolderFinder,
        matching: find.byType(ExpansionTile),
      ),
    );
    expect(firstFolderTile.minTileHeight, 40);
    final topLevelHighlight = tester.widget<CustomPaint>(
      find.byKey(
        const ValueKey('spbTreeFolderHighlight-Folder spacing A'),
      ),
    );
    expect(
      (topLevelHighlight.painter as SpbFolderHighlightPainter).highlightHeight,
      40,
    );
    final firstFolderIcon = find.byKey(
      const ValueKey('spbTreeFolderIconRow-Folder spacing A'),
    );
    final secondFolderIcon = find.byKey(
      const ValueKey('spbTreeFolderIconRow-Folder spacing B'),
    );
    expect(
      tester.getRect(secondFolderIcon).top -
          tester.getRect(firstFolderIcon).bottom,
      closeTo(2, 0.1),
    );
    final firstNestedFolder = find.byKey(
        const ValueKey('spbTreeFolder-Expanded folder / Nested folder A'));
    final secondNestedFolder = find.byKey(
        const ValueKey('spbTreeFolder-Expanded folder / Nested folder B'));
    expect(firstNestedFolder, findsOneWidget);
    expect(secondNestedFolder, findsOneWidget);
    state.setState(() {
      state.selectedCategoryPath = 'Expanded folder / Nested folder A';
    });
    await tester.pump();
    final firstNestedTile = tester.widget<ExpansionTile>(
      find.descendant(
        of: firstNestedFolder,
        matching: find.byType(ExpansionTile),
      ),
    );
    expect(firstNestedTile.minTileHeight, 44);
    final nestedHighlight = tester.widget<CustomPaint>(
      find.byKey(const ValueKey(
        'spbTreeFolderHighlight-Expanded folder / Nested folder A',
      )),
    );
    expect(
      (nestedHighlight.painter as SpbFolderHighlightPainter).highlightHeight,
      44,
    );
    expect(
      tester.getCenter(secondNestedFolder).dy -
          tester.getCenter(firstNestedFolder).dy,
      greaterThanOrEqualTo(40),
    );
  });

  testWidgets('narrow top-level folder spacing stays unchanged',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(VaultShell));
    final CardTemplate template = state.templates.first as CardTemplate;
    state.setState(() {
      state.items = <SecretItem>[
        SecretItem(
          id: 'narrow-unchanged-folder-card',
          templateId: template.id,
          title: 'Card',
          category: 'Narrow unchanged folder',
          colorId: template.colorId,
          values: const <String, String>{},
          modifiedAt: DateTime(2026),
        ),
      ];
      state.selectedCategoryPath = 'Narrow unchanged folder';
    });
    await tester.pumpAndSettle();

    final folder = find.byKey(
      const ValueKey('spbTreeFolder-Narrow unchanged folder'),
    );
    final tile = tester.widget<ExpansionTile>(
      find.descendant(of: folder, matching: find.byType(ExpansionTile)),
    );
    expect(tile.minTileHeight, 30.2);
    final highlight = tester.widget<CustomPaint>(
      find.byKey(const ValueKey(
        'spbTreeFolderHighlight-Narrow unchanged folder',
      )),
    );
    expect(
      (highlight.painter as SpbFolderHighlightPainter).highlightHeight,
      30.2,
    );
  });

  testWidgets('narrow Windows center pane disables card dragging',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(VaultShell));
    final CardTemplate template = state.templates.first as CardTemplate;
    state.setState(() {
      state.mobilePane = 1;
      state.items = <SecretItem>[
        SecretItem(
          id: 'narrow-windows-card',
          templateId: template.id,
          title: 'Narrow Windows card',
          category: '',
          colorId: template.colorId,
          values: const <String, String>{},
          modifiedAt: DateTime(2026),
        ),
      ];
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('spbNavigatorSplitter')), findsNothing);
    expect(find.byKey(const Key('spbFolderGridScrollbar')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey('spbCentralCard-narrow-windows-card'),
        ),
        matching: find.byWidgetPredicate(
          (widget) => widget is Draggable<SecretItem>,
        ),
      ),
      findsNothing,
    );
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('mobile search opens the center pane and shows matching cards',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(576, 1024));
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(VaultShell));
    final CardTemplate template = state.templates.first as CardTemplate;
    state.setState(() {
      state.items = <SecretItem>[
        SecretItem(
          id: 'mobile-search-card',
          templateId: template.id,
          title: 'Alpha Search Card',
          category: '',
          colorId: template.colorId,
          values: const <String, String>{},
          modifiedAt: DateTime(2026),
        ),
      ];
    });
    await tester.pump();

    expect(state.mobilePane, 0);
    await tester.enterText(
      find.byKey(const Key('spbSearchInput')),
      'Alpha Search',
    );
    await tester.pumpAndSettle();

    expect(state.mobilePane, 1);
    expect(find.byKey(const Key('spbCentralWorkspace')), findsOneWidget);
    expect(find.text('Alpha Search Card'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('mobile vault initially shows only the A1 tree', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(576, 1024));
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    final tabletSearch = find.byKey(const Key('spbSearchInput'));
    final tabletSubmit = find.byKey(const Key('spbSubmitSearchButton'));
    expect(
      tester.getTopLeft(tabletSearch).dy - tester.getTopLeft(tabletSubmit).dy,
      closeTo(1.1, 0.1),
    );
    expect(
      tester.getTopLeft(tabletSubmit).dx,
      closeTo(tester.getTopRight(tabletSearch).dx + 5, 0.1),
    );

    expect(find.text('Мои карточки'), findsNWidgets(2));
    expect(find.text('Шаблоны'), findsOneWidget);
    expect(find.text('Задачи'), findsNothing);
    expect(find.text('−'), findsNothing);
    expect(find.byKey(const Key('spbWalletRoot')), findsNothing);
    expect(find.byKey(const Key('spbClearSearchButton')), findsNothing);
    expect(find.byKey(const Key('spbSubmitSearchButton')), findsOneWidget);
    expect(
      find.byTooltip('Отменить изменения этой сессии'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('spbForceCloseButton')), findsOneWidget);
    expect(find.byKey(const Key('mobilePaneBack')), findsOneWidget);
    expect(find.byKey(const Key('mobileFolderUp')), findsOneWidget);
    expect(find.byKey(const Key('mobilePaneForward')), findsOneWidget);
    await tester.tap(find.byKey(const Key('spbMobilePaneHeader')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobilePaneBack')), findsOneWidget);
    expect(find.byKey(const Key('mobilePaneForward')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mobilePaneForward')));
    await tester.pumpAndSettle();
    expect(find.text('Задачи'), findsOneWidget);
    expect(find.byKey(const ValueKey('spbCollapseЗадачи')), findsOneWidget);
    expect(find.byKey(const ValueKey('spbCollapseНайдено')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('spbCollapseЧасто используемые')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('mobilePaneBack')), findsOneWidget);
    expect(find.byKey(const Key('mobilePaneForward')), findsOneWidget);
    await tester.tap(find.byKey(const Key('mobilePaneBack')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilePaneBack')));
    await tester.pumpAndSettle();
    expect(find.text('Мои карточки'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('editor returns to preview and preview returns to card folder',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.binding.setSurfaceSize(const Size(1280, 1010));
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    final template = builtInTemplates().first;
    final card = SecretItem(
      id: 'highlighted-card',
      templateId: template.id,
      title: 'Просмотренная карточка',
      category: 'Работа',
      colorId: template.colorId,
      values: const {},
      modifiedAt: DateTime.utc(2026),
    );
    state.setState(() {
      state.templates = [template];
      state.items = [card];
      state.itemsById[card.id] = card;
      state.categoryPaths.add('Работа');
      state.categoryIdsByPath['Работа'] = 'work-folder';
      state.expandedCategoryPaths.add('Работа');
    });
    await tester.pumpAndSettle();
    final String cardId = card.id;
    final treeCard = find.byKey(ValueKey('spbTreeCard-$cardId'));

    await tester.tap(treeCard);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cardPreviewEditButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cardCloseButton')), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cardCloseButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cardCloseButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cardPreviewBackButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cardPreviewBackButton')));
    await tester.pumpAndSettle();

    expect(state.selectedCategoryPath, 'Работа');
    expect(find.byKey(ValueKey('spbCentralCard-$cardId')), findsOneWidget);
    final tile = tester.widget<ListTile>(
      find.descendant(of: treeCard, matching: find.byType(ListTile)),
    );
    expect(tile.selected, isTrue);
    expect(tile.selectedTileColor, const Color(0xffcfe9fb));
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('change password uses compact standard action buttons',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1010));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    state.openChangePasswordDialog();
    await tester.pumpAndSettle();

    final cancel = find.byKey(const Key('cancelChangePassword'));
    final save = find.byKey(const Key('confirmChangePassword'));
    final newPasswordField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('changePasswordNew')),
        matching: find.byType(TextField),
      ),
    );
    expect(newPasswordField.autocorrect, isFalse);
    expect(newPasswordField.enableSuggestions, isFalse);
    expect(newPasswordField.keyboardType, TextInputType.visiblePassword);
    expect(tester.getSize(cancel), const Size(48, 48));
    expect(tester.getSize(save), const Size(48, 48));
    expect(
      find.descendant(of: cancel, matching: find.byIcon(Icons.close)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: save, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    await tester.tap(cancel);
    await tester.pumpAndSettle();
  });

  testWidgets('change password fits narrow Android screen and keyboard',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetViewInsets();
      tester.binding.setSurfaceSize(null);
    });

    Widget host() => const MaterialApp(
          home: VaultShell(initiallyUnlocked: true),
        );

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    state.openChangePasswordDialog();
    await tester.pumpAndSettle();

    final dialog = find.byKey(const Key('changePasswordDialog'));
    expect(tester.getSize(dialog).width, greaterThanOrEqualTo(352));
    expect(find.byKey(const Key('changePasswordOld')), findsOneWidget);
    expect(find.byKey(const Key('changePasswordNew')), findsOneWidget);
    expect(find.byKey(const Key('changePasswordRepeat')), findsOneWidget);
    expect(find.byKey(const Key('changePasswordHint')), findsOneWidget);

    tester.view.viewInsets = FakeViewPadding(
      bottom: 260 * tester.view.devicePixelRatio,
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.byKey(const Key('confirmChangePassword'))).dy,
      lessThanOrEqualTo(380),
    );
    await tester.ensureVisible(find.byKey(const Key('changePasswordHint')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('damaged cards produce a visible report instead of disappearing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1010));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    const snapshot = SpbWalletSnapshot(
      templates: [],
      cards: [],
      categories: [],
      cardLoadFailures: [
        SpbWalletCardLoadFailure(
          cardId: 'BAD-CARD-ID',
          reason: 'Ошибка расшифровки тестовой карточки',
        ),
      ],
    );
    state.setState(() => state.applySpbSnapshot(snapshot));
    await tester.pumpAndSettle();

    expect(find.text('Не удалось отобразить 1 карточек'), findsOneWidget);
    await tester.tap(find.text('Не удалось отобразить 1 карточек'));
    await tester.pumpAndSettle();
    expect(find.text('Карточка BAD-CARD-ID'), findsOneWidget);
    expect(find.text('Экспортировать исправные'), findsOneWidget);
    expect(find.text('Проверить и восстановить'), findsOneWidget);
  });

  testWidgets('vault layout adapts to phones, landscape and tablet',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    const mobileSizes = [
      Size(320, 640),
      Size(360, 800),
      Size(412, 915),
      Size(640, 360),
    ];
    for (final size in mobileSizes) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('spbMobilePaneHeader')), findsOneWidget,
          reason: 'Размер $size должен использовать мобильную компоновку.');
      expect(find.byKey(const Key('spbMobileWalletTitle')), findsOneWidget);
      expect(find.byKey(const Key('spbMobileAppIcon')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Размер $size');
      await tester.pumpWidget(const SizedBox.shrink());
    }

    await tester.binding.setSurfaceSize(const Size(800, 1280));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spbMobilePaneHeader')), findsOneWidget);
    expect(find.byKey(const Key('spbNavigatorSplitter')), findsNothing);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('mobile templates have one header and reachable tasks',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Шаблоны'));
    await tester.pumpAndSettle();
    // Первая панель содержит список шаблонов.
    expect(find.text('Шаблоны'), findsNWidgets(2));
    final templateTreeEntries = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('spbTemplate-'),
    );
    expect(templateTreeEntries, findsWidgets);
    expect(find.byKey(const Key('mobilePaneBack')), findsOneWidget);
    expect(find.byKey(const Key('mobilePaneForward')), findsOneWidget);

    // В средней панели левая кнопка активна и возвращает к списку.
    await tester.tap(find.byKey(const Key('mobilePaneForward')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spbTemplateWorkspace')), findsOneWidget);
    final backInk = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('mobilePaneBack')),
        matching: find.byType(InkWell),
      ),
    );
    expect(backInk.onTap, isNotNull);
    await tester.tap(find.byKey(const Key('mobilePaneBack')));
    await tester.pumpAndSettle();
    expect(templateTreeEntries, findsWidgets);

    await tester.tap(find.byKey(const Key('mobilePaneForward')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilePaneForward')));
    await tester.pumpAndSettle();
    expect(find.text('Задачи'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
    expect(find.text('Создать новый шаблон'), findsOneWidget);
    expect(find.byKey(const Key('mobilePaneBack')), findsOneWidget);

    await tester.tap(find.text('Создать новый шаблон'));
    await tester.pumpAndSettle();
    final mobileTemplateSurfaceSize =
        tester.getSize(find.byKey(const Key('templateEditorSurface')));
    expect(mobileTemplateSurfaceSize.width, 360);
    expect(mobileTemplateSurfaceSize.height, greaterThanOrEqualTo(500));
    expect(find.byKey(const Key('templateBoundIcon')), findsOneWidget);
    expect(find.byKey(const Key('templateUndoButton')), findsOneWidget);
    expect(find.byKey(const Key('templateSaveButton')), findsOneWidget);
    expect(find.byKey(const Key('templateCloseButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('password screen remains usable at narrow phone sizes',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    for (final size in const [Size(320, 640), Size(360, 800), Size(412, 915)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(const WalletApsApp());
      await tester.pump();
      expect(find.byKey(const Key('passwordInput')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('keypad1'))).height,
        greaterThanOrEqualTo(60),
        reason: 'Кнопки не должны уменьшаться на экране $size.',
      );
      expect(tester.takeException(), isNull, reason: 'Размер $size');
      await tester.pumpWidget(const SizedBox.shrink());
    }
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('renders vault entry screen', (tester) async {
    await tester.pumpWidget(const WalletApsApp());
    await tester.pump();

    expect(find.text('Пароль'), findsOneWidget);
    expect(find.byKey(const Key('passwordPrompt')), findsOneWidget);
    expect(find.byKey(const Key('passwordInput')), findsOneWidget);
    expect(
      find.byKey(const Key('loginPasswordVisibility')),
      findsOneWidget,
    );
    expect(find.text('CLR'), findsOneWidget);
    expect(find.text('<-'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('loginCancel')),
        matching: find.byIcon(Icons.power_settings_new),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('createVault')), findsOneWidget);
    expect(find.text('ABC'), findsOneWidget);
    expect(find.text('abc'), findsOneWidget);
    expect(find.text('123'), findsOneWidget);
    expect(find.text('#!?'), findsOneWidget);
  });

  testWidgets('login password eye toggles password visibility', (tester) async {
    await tester.pumpWidget(const WalletApsApp());
    await tester.pump();

    TextField passwordField() => tester.widget<TextField>(
          find.byKey(const Key('passwordInput')),
        );

    expect(passwordField().obscureText, isTrue);
    expect(find.byIcon(Icons.visibility), findsOneWidget);

    await tester.tap(find.byKey(const Key('loginPasswordVisibility')));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);

    await tester.tap(find.byKey(const Key('loginPasswordVisibility')));
    await tester.pump();
    expect(passwordField().obscureText, isTrue);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });

  testWidgets('touch keypad edits the focused password', (tester) async {
    await tester.pumpWidget(const WalletApsApp());
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const Key('passwordInput')),
    );
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('keypad1')));
    field.controller!.selection = TextSelection(
      baseOffset: 0,
      extentOffset: field.controller!.text.length,
    );
    await tester.tap(find.byKey(const Key('keypad2')));
    expect(field.controller!.text, '12');

    await tester.tap(find.byKey(const Key('keypadBackspace')));
    expect(field.controller!.text, '1');

    await tester.tap(find.byKey(const Key('keypadClear')));
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('physical keyboard input is accepted', (tester) async {
    await tester.pumpWidget(const WalletApsApp());
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('passwordInput')),
      'Key!9',
    );

    final field = tester.widget<TextField>(
      find.byKey(const Key('passwordInput')),
    );
    expect(field.controller!.text, 'Key!9');
  });

  testWidgets('ABC mode enters uppercase letters and returns to digits',
      (tester) async {
    await tester.pumpWidget(const WalletApsApp());
    await tester.pump();

    await tester.tap(find.byKey(const Key('keypadModeUppercase')));
    await tester.pump();

    expect(find.byKey(const Key('keypadLetterQ')), findsOneWidget);
    expect(find.byKey(const Key('keypadLetterP')), findsOneWidget);
    expect(find.byKey(const Key('keypad1')), findsNothing);

    await tester.tap(find.byKey(const Key('keypadLetterQ')));
    await tester.tap(find.byKey(const Key('keypadLetterW')));
    final field = tester.widget<TextField>(
      find.byKey(const Key('passwordInput')),
    );
    expect(field.controller!.text, 'QW');

    await tester.tap(find.byKey(const Key('keypadBackspace')));
    expect(field.controller!.text, 'Q');
    await tester.tap(find.byKey(const Key('keypadClear')));
    expect(field.controller!.text, isEmpty);

    await tester.tap(find.byKey(const Key('keypadModeNumeric')));
    await tester.pump();
    expect(find.byKey(const Key('keypad1')), findsOneWidget);
  });

  testWidgets('abc mode enters lowercase letters', (tester) async {
    await tester.pumpWidget(const WalletApsApp());
    await tester.pump();

    await tester.tap(find.byKey(const Key('keypadModeLowercase')));
    await tester.pump();

    expect(find.byKey(const Key('keypadLetterq')), findsOneWidget);
    expect(find.byKey(const Key('keypadLetterp')), findsOneWidget);
    expect(find.byKey(const Key('keypad1')), findsNothing);

    await tester.tap(find.byKey(const Key('keypadLetterq')));
    await tester.tap(find.byKey(const Key('keypadLetterw')));
    final field = tester.widget<TextField>(
      find.byKey(const Key('passwordInput')),
    );
    expect(field.controller!.text, 'qw');

    await tester.tap(find.byKey(const Key('keypadBackspace')));
    expect(field.controller!.text, 'q');
    await tester.tap(find.byKey(const Key('keypadClear')));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('symbol mode enters special characters and returns to digits',
      (tester) async {
    await tester.pumpWidget(const WalletApsApp());
    await tester.pump();

    await tester.tap(find.byKey(const Key('keypadModeSymbols')));
    await tester.pump();

    expect(find.byKey(const Key('keypadSymbol+')), findsOneWidget);
    expect(find.byKey(const Key('keypadSymbol?')), findsOneWidget);
    expect(find.byKey(const Key('keypad1')), findsNothing);

    await tester.tap(find.byKey(const Key('keypadSymbol!')));
    await tester.tap(find.byKey(const Key('keypadSymbol@')));
    await tester.tap(find.byKey(const Key('keypadSymbol#')));
    final field = tester.widget<TextField>(
      find.byKey(const Key('passwordInput')),
    );
    expect(field.controller!.text, '!@#');

    await tester.tap(find.byKey(const Key('keypadBackspace')));
    expect(field.controller!.text, '!@');

    await tester.tap(find.byKey(const Key('keypadModeNumeric')));
    await tester.pump();
    expect(find.byKey(const Key('keypad1')), findsOneWidget);
  });

  testWidgets('file button opens the picker directly without a menu',
      (tester) async {
    await tester.pumpWidget(const WalletApsApp());
    await tester.pump();

    expect(find.byKey(const Key('fileMenu')), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('switching vault clears password and returns to login',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(VaultShell));
    state.passwordController.text = 'must-not-remain-in-memory';
    await state.closeCurrentVaultForPasswordPrompt();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passwordInput')), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const Key('passwordInput')),
    );
    expect(field.controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactivity warning locks the vault instead of closing the app',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(VaultShell));
    state.showInactivityWarning();
    await tester.pump();

    expect(find.text('Предупреждение'), findsOneWidget);
    expect(
      find.text('Хранилище будет заблокировано через 15 секунд'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('inactivityContinueButton')), findsOneWidget);

    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passwordInput')), findsOneWidget);
    expect(find.byType(VaultShell), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity inside an overlay restarts the inactivity timer',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const AppUserActivityRegion(
        child: MaterialApp(home: VaultShell(initiallyUnlocked: true)),
      ),
    );
    await tester.pumpAndSettle();

    final dynamic state = tester.state(find.byType(VaultShell));
    final initialTimer = state.inactivityTimer;
    await tester.pump(const Duration(minutes: 2, seconds: 44));

    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(VaultShell)),
        builder: (context) => AlertDialog(
          content: TextButton(
            key: const Key('overlayActivityButton'),
            onPressed: () {},
            child: const Text('Работа в диалоге'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('overlayActivityButton')));
    await tester.pump();

    expect(state.inactivityTimer, isNot(same(initialTimer)));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('inactivityContinueButton')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('password window has no warning before five minute exit',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const WalletApsApp());
    await tester.pump();

    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(find.byKey(const Key('lockedExitContinueButton')), findsNothing);
    expect(find.text('Предупреждение'), findsNothing);
    expect(find.byKey(const Key('passwordInput')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new vault dialog never reuses the current password',
      (tester) async {
    await tester.pumpWidget(const WalletApsApp());
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('passwordInput')),
      'old-password',
    );

    await tester.tap(find.byKey(const Key('createVault')));
    await tester.pumpAndSettle();

    expect(find.text('Создание новой базы'), findsOneWidget);
    expect(find.byKey(const Key('newVaultDialogDragHandle')), findsOneWidget);
    expect(find.byKey(const Key('newVaultPath')), findsOneWidget);
    expect(find.byKey(const Key('browseNewVaultPath')), findsOneWidget);
    expect(find.byKey(const Key('newVaultName')), findsOneWidget);
    expect(
      find.byKey(const Key('newVaultPasswordStrength')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('newVaultPasswordHint')), findsOneWidget);
    final confirmButton = find.byKey(const Key('confirmCreateVault'));
    final cancelButton = find.byKey(const Key('cancelCreateVault'));
    expect(
      find.descendant(of: confirmButton, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cancelButton, matching: find.byIcon(Icons.close)),
      findsOneWidget,
    );
    expect(tester.getSize(confirmButton), const Size.square(48));
    expect(tester.getSize(cancelButton), const Size.square(48));
    final newPassword = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('newVaultPassword')),
        matching: find.byType(TextField),
      ),
    );
    final repeatedPassword = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('newVaultPasswordRepeat')),
        matching: find.byType(TextField),
      ),
    );
    expect(newPassword.controller!.text, isEmpty);
    expect(repeatedPassword.controller!.text, isEmpty);
  });

  testWidgets('login password hint is shown only while yellow button is held',
      (tester) async {
    await tester.pumpWidget(const WalletApsApp());
    await tester.pump();

    expect(find.byKey(const Key('loginPasswordHintButton')), findsOneWidget);
    expect(find.byKey(const Key('loginPasswordHint')), findsNothing);
    final touch = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('loginPasswordHintButton'))),
    );
    await tester.pump();
    expect(find.byKey(const Key('loginPasswordHint')), findsOneWidget);
    expect(find.text('Подсказка не задана.'), findsOneWidget);
    await touch.up();
    await tester.pump();
    expect(find.byKey(const Key('loginPasswordHint')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete card confirmation uses blue and red 3D buttons',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    final template = builtInTemplates().first;
    final item = SecretItem(
      id: 'delete-dialog-card',
      templateId: template.id,
      title: 'Удаляемая карточка',
      category: '',
      colorId: template.colorId,
      values: const {},
      modifiedAt: DateTime(2026),
    );

    unawaited(state.deleteItemWithConfirmation(item));
    await tester.pumpAndSettle();

    final cancel = find.byKey(const Key('cancelDeleteCardButton'));
    final confirm = find.byKey(const Key('confirmDeleteCardButton'));
    expect(find.text('Удалить карточку'), findsOneWidget);
    expect(cancel, findsOneWidget);
    expect(confirm, findsOneWidget);
    expect(tester.getSize(cancel), const Size(124, 48));
    expect(tester.getSize(confirm), const Size(124, 48));

    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(confirm, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login error is shown below all action buttons', (tester) async {
    await tester.pumpWidget(const WalletApsApp());
    await tester.pump();

    await tester.tap(find.byKey(const Key('loginOk')));
    await tester.pumpAndSettle();

    final message = find.byKey(const Key('loginMessage'));
    expect(message, findsOneWidget);
    expect(
      tester.getTopLeft(message).dy,
      greaterThan(
          tester.getBottomRight(find.byKey(const Key('loginCancel'))).dy),
    );
  });
}
