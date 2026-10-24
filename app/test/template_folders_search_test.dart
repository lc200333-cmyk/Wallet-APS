import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';

const folders = [
  'Банковские счета',
  'Другие',
  'Заметки',
  'Интернет',
  'Карточки',
  'Компьютеры',
  'Кредитная карта',
  'Личные',
  'Путешествия',
  'Семейные',
  'Финансы',
];

CardTemplate fixture(String id, String name, {String category = ''}) =>
    CardTemplate(
      id: id,
      name: name,
      categoryPath: category,
      iconId: 'key',
      colorId: 'template_white',
      fields: const [],
    );

Future<dynamic> pumpShell(WidgetTester tester, TargetPlatform platform) async {
  debugDefaultTargetPlatformOverride = platform;
  await tester.binding.setSurfaceSize(
    platform == TargetPlatform.android
        ? const Size(360, 800)
        : const Size(1280, 900),
  );
  addTearDown(() {
    debugDefaultTargetPlatformOverride = null;
    tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
  );
  await tester.pumpAndSettle();
  return tester.state(find.byType(VaultShell));
}

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('Enter is substring, blue search is exact on ${platform.name}',
        (tester) async {
      final dynamic state = await pumpShell(tester, platform);
      final CardTemplate template = state.templates.first as CardTemplate;
      state.setState(() {
        state.items = <SecretItem>[
          for (final name in ['Банк', 'Мой банк'])
            SecretItem(
              id: name,
              title: name,
              templateId: template.id,
              category: '',
              colorId: template.colorId,
              values: const {},
              modifiedAt: DateTime.utc(2026),
            ),
        ];
      });
      await tester.pumpAndSettle();
      final input = find.byKey(const Key('spbSearchInput'));
      final submit = find.byKey(const Key('spbSubmitSearchButton'));
      await tester.enterText(input, 'банк');
      await tester.pumpAndSettle();
      expect(state.spbExactSearch, isFalse);
      expect(state.spbMatchingCards('банк'), hasLength(2));
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(state.spbExactSearch, isFalse);
      expect(state.spbMatchingCards('банк'), hasLength(2));
      expect(state.filteredItems(), hasLength(2));

      expect(find.byTooltip('Точное совпадение'), findsOneWidget);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(state.spbExactSearch, isTrue);
      expect(state.spbMatchingCards('банк'), hasLength(1));
      expect(state.filteredItems(), hasLength(1));
      final exactInk = tester.widget<Ink>(
        find.descendant(of: submit, matching: find.byType(Ink)),
      );
      expect(
        ((exactInk.decoration! as BoxDecoration).border! as Border).top.width,
        2,
      );
      await tester.tap(input);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(state.spbExactSearch, isFalse);
      expect(state.spbMatchingCards('банк'), hasLength(2));

      await tester.tap(submit);
      await tester.pumpAndSettle();
      await tester.enterText(input, 'бан');
      await tester.pumpAndSettle();
      expect(state.spbExactSearch, isFalse);
      expect(state.spbMatchingCards('бан'), hasLength(2));
      await tester.tap(find.byKey(const Key('spbClearSearchButton')));
      await tester.pumpAndSettle();
      expect(state.spbSubmittedSearchQuery, isEmpty);
      expect(state.spbExactSearch, isFalse);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(state.spbExactSearch, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('template folders expand and filter on ${platform.name}',
        (tester) async {
      final dynamic state = await pumpShell(tester, platform);
      final templates = [
        fixture('z', 'Компьютеры: Ярлык'),
        fixture('a', 'компьютеры: Архив'),
        fixture('note', 'Обычный шаблон'),
        fixture('explicit', 'Сайт', category: 'Интернет'),
      ];
      state.setState(() {
        state.templates = templates;
        state.templatesById = {for (final t in templates) t.id: t};
      });
      await tester.tap(find.byKey(const Key('spbTemplatesModeButton')));
      await tester.pumpAndSettle();
      var previousY = 0.0;
      for (final folder in folders) {
        final row = find.byKey(ValueKey('spbTemplateFolder-$folder'));
        expect(row, findsOneWidget);
        final y = tester.getTopLeft(row).dy;
        expect(y, greaterThan(previousY));
        previousY = y;
      }
      expect(find.byKey(const ValueKey('spbTemplate-a')), findsNothing);
      final computers =
          find.byKey(const ValueKey('spbTemplateFolder-Компьютеры'));
      await tester.tap(computers);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('spbTemplate-a')), findsOneWidget);
      expect(find.byKey(const ValueKey('spbTemplate-z')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('spbTemplate-a'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('spbTemplate-z'))).dy,
        ),
      );
      expect(templates.first.name, 'Компьютеры: Ярлык');
      expect(templates.last.categoryPath, 'Интернет');
      if (platform == TargetPlatform.android) {
        await tester.tap(find.byKey(const Key('mobilePaneForward')));
        await tester.pumpAndSettle();
      }
      expect(
          find.byKey(const ValueKey('spbCentralTemplate-a')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('spbCentralTemplate-z')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('spbCentralTemplate-note')), findsNothing);
      if (platform == TargetPlatform.android) {
        await tester.tap(find.byKey(const Key('mobilePaneBack')));
        await tester.pumpAndSettle();
      }
      await tester.tap(computers);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('spbTemplate-a')), findsNothing);
      // A context action in another expanded folder must use its own template.
      await tester
          .tap(find.byKey(const ValueKey('spbTemplateFolder-Интернет')));
      await tester.pumpAndSettle();
      await tester.tap(computers);
      await tester.pumpAndSettle();
      expect(state.selectedTemplateFolder, 'Компьютеры');
      final otherTemplate = find.byKey(const ValueKey('spbTemplate-explicit'));
      await tester.ensureVisible(otherTemplate);
      if (platform == TargetPlatform.android) {
        await tester.longPress(otherTemplate);
      } else {
        await tester.tap(otherTemplate, buttons: kSecondaryMouseButton);
      }
      await tester.pumpAndSettle();
      expect(state.selectedTemplateFolder, 'Интернет');
      expect(state.selectedSpbTemplate().id, 'explicit');
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      // The section header returns to all templates, without changing folders.
      await tester.tap(find.byKey(const Key('spbTemplatesModeButton')));
      await tester.pumpAndSettle();
      expect(state.selectedTemplateFolder, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'empty template folder creates in that folder on ${platform.name}',
        (tester) async {
      final dynamic state = await pumpShell(tester, platform);
      final other = fixture('other', 'Другой шаблон');
      state.setState(() {
        state.templates = <CardTemplate>[other];
        state.templatesById = <String, CardTemplate>{other.id: other};
      });
      await tester.tap(find.byKey(const Key('spbTemplatesModeButton')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('spbTemplateFolder-Интернет')));
      await tester.pumpAndSettle();
      expect(state.selectedSpbTemplate(), isNull);
      if (platform == TargetPlatform.android) {
        await tester.tap(find.byKey(const Key('mobilePaneForward')));
        await tester.pumpAndSettle();
      }
      expect(find.text('В этой папке пока нет шаблонов.'), findsOneWidget);
      if (platform == TargetPlatform.android) {
        await tester.tap(find.byKey(const Key('mobilePaneBack')));
        await tester.pumpAndSettle();
        await tester
            .tap(find.byKey(const ValueKey('spbTemplateFolder-Другие')));
        await tester.pumpAndSettle();
        await tester.longPress(
          find.byKey(const ValueKey('spbTemplateFolder-Интернет')),
        );
      } else {
        await tester
            .tap(find.byKey(const ValueKey('spbTemplateFolder-Другие')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('spbTemplateFolder-Интернет')),
          buttons: kSecondaryMouseButton,
        );
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createTemplateContextAction')));
      await tester.pumpAndSettle();
      final dynamic editor = tester.state(find.byType(TemplateEditorDialog));
      expect(editor.categoryPath, 'Интернет');
      expect(find.byKey(const Key('templateSaveButton')), findsNothing);
      await tester.tap(find.byKey(const Key('templateCloseButton')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('template search stays in section on ${platform.name}',
        (tester) async {
      final dynamic state = await pumpShell(tester, platform);
      final templates = [
        fixture('exact', 'Интернет: Банк'),
        fixture('partial', 'Интернет: Мой банк'),
      ];
      state.setState(() {
        state.templates = templates;
        state.templatesById = {for (final t in templates) t.id: t};
      });
      await tester.tap(find.byKey(const Key('spbTemplatesModeButton')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('spbTemplateFolder-Интернет')));
      await tester.pumpAndSettle();
      final input = find.byKey(const Key('spbSearchInput'));
      await tester.enterText(input, 'банк');
      await tester.pumpAndSettle();
      expect(state.mobileTemplatesOpen, isTrue);
      expect(find.byKey(const ValueKey('spbCentralTemplate-exact')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('spbCentralTemplate-partial')),
          findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(state.spbExactSearch, isFalse);
      expect(find.byKey(const ValueKey('spbCentralTemplate-partial')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('spbSubmitSearchButton')));
      await tester.pumpAndSettle();
      expect(state.spbExactSearch, isTrue);
      expect(find.byKey(const ValueKey('spbCentralTemplate-exact')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('spbCentralTemplate-partial')),
          findsNothing);
      await tester.enterText(input, 'несуществующее название');
      await tester.pumpAndSettle();
      expect(state.spbExactSearch, isFalse);
      expect(
        find.descendant(
          of: find.byKey(const Key('spbTemplateWorkspace')),
          matching: find.text('Совпадений нет'),
        ),
        findsOneWidget,
      );
      expect(find.text('В этой папке пока нет шаблонов.'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
