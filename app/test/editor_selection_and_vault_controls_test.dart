import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/services/password_generator.dart';
import 'package:wallet_aps/services/platform/secure_clipboard_service.dart';
import 'package:wallet_aps/widgets/object_selection_menu_label.dart';
import 'package:wallet_aps/widgets/workspace_section_bar.dart';
import 'package:wallet_aps/widgets/workspace_geometry.dart';

Uint8List fixtureIcon(int red, int green, int blue) =>
    Uint8List.fromList(image.encodePng(image.Image(width: 4, height: 4)
      ..setPixelRgba(0, 0, red, green, blue, 255)));

Future<void> setLayout(WidgetTester tester, TargetPlatform platform) async {
  debugDefaultTargetPlatformOverride = platform;
  await tester.binding.setSurfaceSize(platform == TargetPlatform.windows
      ? const Size(1280, 900)
      : const Size(360, 800));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });
}

void expectOriginalImage(WidgetTester tester, Finder row, Uint8List bytes) {
  expect(row, findsOneWidget);
  final original = tester.widget<Image>(
      find.descendant(of: row, matching: find.byType(Image)).first);
  expect((original.image as MemoryImage).bytes, bytes);
  expect(original.width, 24);
  expect(original.height, 24);
  expect(original.fit, BoxFit.contain);
}

Future<void> finishLayout(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  test('generated passwords contain all groups and no whitespace', () {
    for (var i = 0; i < 10; i++) {
      final password = generateVaultPassword();
      expect(password.length, 20);
      for (final group in [r'[a-z]', r'[A-Z]', r'[0-9]', r'[!@#$%&*+\-=?_]']) {
        expect(RegExp(group).hasMatch(password), isTrue);
      }
      expect(RegExp(r'\s').hasMatch(password), isFalse);
    }
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('original template and folder images on ${platform.name}',
        (tester) async {
      await setLayout(tester, platform);
      final templateBytes = fixtureIcon(255, 0, 0);
      final folderBytes = fixtureIcon(0, 255, 0);
      spbEmbeddedIconPngs['SELECTION-FOLDER'] = folderBytes;
      addTearDown(() => spbEmbeddedIconPngs.remove('SELECTION-FOLDER'));
      final template = CardTemplate(
          id: 'original-template',
          name: 'Интернет: Почта',
          iconId: 'key',
          colorId: 'template_white',
          embeddedIconBase64: base64Encode(templateBytes),
          fields: const []);
      await tester.pumpWidget(MaterialApp(
          home: ItemEditorDialog(
              templates: [template],
              categories: const ['Личные'],
              categoryIcons: const {'Личные': 'selection-folder'})));
      await tester.pumpAndSettle();
      final templateField = find.byKey(const Key('cardTemplateField'));
      await tester.tap(templateField);
      await tester.pumpAndSettle();
      expectOriginalImage(
          tester,
          find.byKey(const ValueKey('cardTemplateIcon-original-template')),
          templateBytes);
      await tester.tap(
          find.byKey(const ValueKey('cardTemplateIcon-original-template')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cardCategoryField')));
      await tester.pumpAndSettle();
      final folderRow =
          find.byKey(const ValueKey('cardCategoryMenuIcon-Личные'));
      expectOriginalImage(tester, folderRow, folderBytes);
      await tester.tap(folderRow);
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(ItemEditorDialog));
      expect(state.category.text, 'Личные');
      expect(state.templateId, 'original-template');
      expect(tester.takeException(), isNull);
      await finishLayout(tester);
    });

    for (final card in [true, false]) {
      testWidgets(
          'catalog images in ${card ? 'card' : 'template'} icon menu '
          'on ${platform.name}', (tester) async {
        await setLayout(tester, platform);
        final oldFuture = managedIconLibraryFuture;
        final oldCatalogs = customIconCatalogs;
        final oldPngs = Map<String, Uint8List>.from(thirdPartyIconPngs);
        final oldBrands = Map<String, Uint8List>.from(brandIconPngs);
        final oldSpb = Map<String, Uint8List>.from(spbBundledIconPngs);
        managedIconLibraryFuture = Future<void>.value();
        final folderBytes = fixtureIcon(0, 0, 255);
        customIconCatalogs = [
          const IconCatalogKind('custom-choice', 'Свои',
              iconId: 'selection-custom')
        ];
        spbEmbeddedIconPngs['SELECTION-CUSTOM'] = folderBytes;
        final icons = {
          IconCatalogKind.spb: fixtureIcon(20, 40, 60),
          IconCatalogKind.pictograms: fixtureIcon(60, 40, 20),
          IconCatalogKind.brands: fixtureIcon(90, 20, 40),
          IconCatalogKind.thirdParty: fixtureIcon(30, 60, 90),
          customIconCatalogs.single: folderBytes,
        };
        spbBundledIconPngs[
                'spb://apk_icons/res/drawable-hdpi/icon_path_wallet.png'] =
            icons[IconCatalogKind.spb]!;
        thirdPartyIconPngs['third-party://NewIcons/Icons0401.png'] =
            icons[IconCatalogKind.pictograms]!;
        brandIconPngs['brand://BrendLogo-3D-inner/avg.png'] =
            icons[IconCatalogKind.brands]!;
        thirdPartyIconPngs['third-party://NewIcons/Icons0322.png'] =
            icons[IconCatalogKind.thirdParty]!;
        addTearDown(() {
          managedIconLibraryFuture = oldFuture;
          customIconCatalogs = oldCatalogs;
          thirdPartyIconPngs = oldPngs;
          brandIconPngs = oldBrands;
          spbBundledIconPngs = oldSpb;
          spbEmbeddedIconPngs.remove('SELECTION-CUSTOM');
        });
        await tester.pumpWidget(MaterialApp(
            home: card
                ? ItemEditorDialog(
                    templates: builtInTemplates(), categories: const [])
                : const TemplateEditorDialog()));
        await tester.pumpAndSettle();
        final target =
            find.byKey(Key(card ? 'cardBoundIcon' : 'templateBoundIcon'));
        if (platform == TargetPlatform.windows) {
          await tester.tap(target, buttons: kSecondaryMouseButton);
        } else {
          await tester.longPress(target);
        }
        await tester.pumpAndSettle();
        for (final entry in icons.entries) {
          final row =
              find.byKey(ValueKey('iconEditorFolder-${entry.key.storageKey}'));
          expect(tester.widget(row), isA<ObjectSelectionMenuLabel>());
          expectOriginalImage(tester, row, entry.value);
        }
        expect(find.text('Вставить'), findsOneWidget);
        expect(find.text('Выбрать файл'), findsOneWidget);
        Navigator.of(tester.element(target)).pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await finishLayout(tester);
      });
    }

    testWidgets('matching right section bars on ${platform.name}',
        (tester) async {
      await setLayout(tester, platform);
      final oldLibraryFuture = managedIconLibraryFuture;
      managedIconLibraryFuture = Future<void>.value();
      addTearDown(() => managedIconLibraryFuture = oldLibraryFuture);
      await tester.pumpWidget(
          const MaterialApp(home: VaultShell(initiallyUnlocked: true)));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(VaultShell));
      const counterparts = {
        'Действие': 'spbMyCardsModeButton',
        'Найденные': 'spbTemplatesModeButton',
        'Последние': 'spbIconsModeButton',
      };
      final leftHeights = <String, double>{};
      Border borderFor(Finder strip) {
        final bar = find.descendant(
            of: strip,
            matching: find.byType(WorkspaceSectionBar),
            matchRoot: true);
        final container = tester.widget<Container>(
            find.descendant(of: bar, matching: find.byType(Container)).first);
        return (container.decoration! as BoxDecoration).border! as Border;
      }

      final leftBorders = <String, BorderSide>{};
      for (final entry in counterparts.entries) {
        final left = find.byKey(Key(entry.value));
        leftHeights[entry.key] = tester.getSize(left).height;
        leftBorders[entry.key] = borderFor(left).top;
        expect(borderFor(left).bottom, borderFor(left).top);
        final leftBar = find.descendant(
            of: left, matching: find.byType(WorkspaceSectionBar));
        final decoration = tester
            .widget<Container>(find
                .descendant(of: leftBar, matching: find.byType(Container))
                .first)
            .decoration! as BoxDecoration;
        expect(decoration.color, const Color(0xffdbeaf5));
      }
      expect(find.text('Мои карточки'), findsNothing);
      expect(
          find.descendant(
              of: find.byKey(const Key('spbMyCardsModeButton')),
              matching: find.text('Мои записи')),
          findsOneWidget);
      state.setState(() => state.mobilePane = 2);
      await tester.pumpAndSettle();
      expect(find.text('Задачи'), findsNothing);
      expect(find.text('Найдено'), findsNothing);
      for (final title in ['Действие', 'Найденные', 'Последние']) {
        final header = find.byKey(ValueKey('spbActionHeader-$title'));
        final bar = tester.widget<WorkspaceSectionBar>(header);
        expect(bar.label, title);
        expect(tester.getSize(header).height, leftHeights[title]);
        expect(borderFor(header).bottom, leftBorders[title]);
        expect(borderFor(header).bottom.color, const Color(0xffb7b7b7));
        expect(borderFor(header).bottom.width, 1);
        final style = tester
            .widget<Text>(
                find.descendant(of: header, matching: find.text(title)))
            .style;
        expect(style!.fontSize,
            closeTo(WorkspaceGeometry.menuFontSize * 1.1, .01));
        expect(style.fontWeight, FontWeight.bold);
        await tester.tap(find.byKey(ValueKey('spbCollapse$title')));
        await tester.pumpAndSettle();
        expect(tester.widget<WorkspaceSectionBar>(header).selected, isFalse);
        expect(tester.getSize(header).height, leftHeights[title]);
        expect(borderFor(header).bottom, leftBorders[title]);
        await tester.tap(find.byKey(ValueKey('spbExpand$title')));
        await tester.pumpAndSettle();
        expect(tester.widget<WorkspaceSectionBar>(header).selected, isTrue);
        expect(tester.getSize(header).height, leftHeights[title]);
        expect(borderFor(header).bottom, leftBorders[title]);
      }
      final actionsHeader =
          find.byKey(const ValueKey('spbActionHeader-Действие'));
      final foundHeader =
          find.byKey(const ValueKey('spbActionHeader-Найденные'));
      final recentHeader =
          find.byKey(const ValueKey('spbActionHeader-Последние'));
      final lastActionTitle = state.spbTasksForCurrentMode().last.$2 as String;
      final lastAction = find
          .ancestor(
              of: find.byKey(ValueKey('spbActionIcon-$lastActionTitle')),
              matching: find.byType(InkWell))
          .first;
      expect(tester.getTopLeft(foundHeader).dy,
          closeTo(tester.getBottomLeft(lastAction).dy, .01));
      expect(tester.getTopLeft(recentHeader).dy,
          closeTo(tester.getBottomLeft(foundHeader).dy, .01));
      for (final title in counterparts.keys) {
        await tester.tap(find.byKey(ValueKey('spbCollapse$title')));
        await tester.pumpAndSettle();
      }
      expect(tester.getTopLeft(foundHeader).dy,
          closeTo(tester.getBottomLeft(actionsHeader).dy, .01));
      expect(tester.getTopLeft(recentHeader).dy,
          closeTo(tester.getBottomLeft(foundHeader).dy, .01));
      // Switching the navigator's open section must not resize its strips.
      for (final pane in ['templates', 'icons', 'cards']) {
        state.setState(() => state.mobilePane = 0);
        switch (pane) {
          case 'templates':
            state.showSpbTemplatesMode();
          case 'icons':
            state.showSpbIconsMode();
          case 'cards':
            state.showSpbCardsMode();
        }
        await tester.pumpAndSettle();
        for (final entry in counterparts.entries) {
          final strip = find.byKey(Key(entry.value));
          expect(strip, findsOneWidget, reason: '$pane: ${entry.value}');
          expect(tester.getSize(strip).height, leftHeights[entry.key]);
          expect(borderFor(strip).bottom, leftBorders[entry.key]);
        }
      }
      expect(tester.takeException(), isNull);
      await finishLayout(tester);
    });

    testWidgets('management heading and edge-to-edge panel on ${platform.name}',
        (tester) async {
      await setLayout(tester, platform);
      final width = platform == TargetPlatform.windows ? 1280.0 : 360.0;
      await tester.binding.setSurfaceSize(
          Size(width, platform == TargetPlatform.windows ? 540 : 480));
      await tester.pumpWidget(
          const MaterialApp(home: VaultShell(initiallyUnlocked: true)));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(VaultShell));
      BoxDecoration? centralDecoration;
      if (platform == TargetPlatform.windows) {
        state.setState(() => state.selectedCategoryPath = '');
        await tester.pumpAndSettle();
        final central = tester.widget<Container>(find
            .ancestor(
                of: find.descendant(
                    of: find.byKey(const Key('spbCentralWorkspaceFocus')),
                    matching: find.text('Мои записи')),
                matching: find.byType(Container))
            .first);
        centralDecoration = central.decoration! as BoxDecoration;
      }
      final CardTemplate template = state.templates.first as CardTemplate;
      final cards = List.generate(
          10,
          (index) => SecretItem(
              id: 'management-$index',
              templateId: template.id,
              title: 'Synthetic recent card $index with a long wrapping name',
              category: '',
              colorId: template.colorId,
              values: const {},
              modifiedAt: DateTime(2026)));
      state.setState(() {
        state.items = cards;
        state.itemsById = {for (final card in cards) card.id: card};
        state.recentlyOpenedItemIds
          ..clear()
          ..addAll(cards.map((card) => card.id));
        state.mobilePane = 2;
      });
      await tester.pumpAndSettle();
      final heading = find.byKey(const Key('spbManagementHeader'));
      expect(find.text('Управление'), findsOneWidget);
      expect(tester.getSize(heading).height, WorkspaceGeometry.headerHeight);
      expect(tester.getTopRight(heading).dx, closeTo(width, .01));
      final container = tester.widget<Container>(
          find.descendant(of: heading, matching: find.byType(Container)).first);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.gradient,
          const LinearGradient(colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)]));
      if (centralDecoration != null) expect(decoration, centralDecoration);
      expect(tester.widget<Text>(find.text('Управление')).style!.fontSize,
          WorkspaceGeometry.headingFontSize);
      final actionsHeader =
          find.byKey(const ValueKey('spbActionHeader-Действие'));
      expect(tester.getTopLeft(actionsHeader).dy,
          closeTo(tester.getBottomLeft(heading).dy, .01));
      for (final title in ['Действие', 'Найденные', 'Последние']) {
        final strip = find.byKey(ValueKey('spbActionHeader-$title'));
        expect(tester.getTopRight(strip).dx, closeTo(width, .01));
        final arrow = find.byKey(ValueKey('spbCollapse$title'));
        expect(tester.getTopRight(arrow).dx,
            lessThan(width - WorkspaceGeometry.actionsOverlayScrollbar));
      }
      final scrollbar = tester.widget<Scrollbar>(find.byKey(Key(
          platform == TargetPlatform.windows
              ? 'spbActionsPanelScrollbar'
              : 'spbMobileActionsScrollbar')));
      expect(scrollbar.thickness, WorkspaceGeometry.actionsOverlayScrollbar);
      expect(scrollbar.interactive, isTrue);
      final ScrollController scroll = scrollbar.controller!;
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      final headingRect = tester.getRect(heading);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.getRect(heading), headingRect,
          reason: 'The management heading stays above the scrolling content');
      final recentArrow = find.byKey(const ValueKey('spbCollapseПоследние'));
      await tester.ensureVisible(recentArrow);
      await tester.pumpAndSettle();
      await tester.tap(recentArrow);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('spbExpandПоследние')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finishLayout(tester);
    });

    testWidgets('generate and copy changed vault passwords on ${platform.name}',
        (tester) async {
      await setLayout(tester, platform);
      String? clipboard;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(
          const MaterialApp(home: VaultShell(initiallyUnlocked: true)));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(VaultShell));
      var replacements = 0;
      final saved = Completer<void>();
      String? submittedPassword;
      state.openChangePasswordDialog(replacePassword: ({
        required String oldPassword,
        required String newPassword,
        required String passwordHint,
      }) async {
        replacements++;
        expect(oldPassword, 'old-synthetic-password');
        expect(passwordHint, 'Synthetic hint');
        submittedPassword = newPassword;
        await saved.future;
      });
      await tester.pumpAndSettle();
      Finder input(String key) => find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(TextField),
          matchRoot: true);
      TextField field(String key) => tester.widget<TextField>(input(key));
      final button = find.byKey(const Key('generateChangedVaultPassword'));
      final cancel = find.byKey(const Key('cancelChangePassword'));
      final confirm = find.byKey(const Key('confirmChangePassword'));
      final generator = tester.widget<SpbGradientActionButton>(button);
      expect(generator.colors.last, Colors.black);
      expect(generator.hoverHighlight, isTrue);
      expect(generator.tooltip, 'Генератор паролей');
      expect(tester.getSize(button), const Size(48, 48));
      expect(
          tester.getCenter(button).dx, lessThan(tester.getCenter(cancel).dx));
      expect(
          tester.getCenter(cancel).dx, lessThan(tester.getCenter(confirm).dx));
      expect(tester.getCenter(button).dy, tester.getCenter(confirm).dy);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final generated = field('changePasswordNew').controller!.text;
      expect(generated.length, 20);
      expect(field('changePasswordRepeat').controller!.text, generated);
      expect(field('changePasswordOld').controller!.text, isEmpty);
      expect(clipboard, isNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('Введите старый пароль.'), findsOneWidget);
      expect(replacements, 0);
      await tester.enterText(
          input('changePasswordOld'), 'old-synthetic-password');
      await tester.enterText(input('changePasswordHint'), 'Synthetic hint');
      await tester.tap(button);
      await tester.pumpAndSettle();
      final regenerated = field('changePasswordNew').controller!.text;
      expect(regenerated, isNot(generated));
      expect(field('changePasswordRepeat').controller!.text, regenerated);
      expect(field('changePasswordOld').controller!.text,
          'old-synthetic-password');
      expect(field('changePasswordHint').controller!.text, 'Synthetic hint');
      expect(find.byKey(const Key('changePasswordError')), findsNothing);
      expect(
          tester
              .widget<PasswordStrengthBar>(
                  find.byKey(const Key('changePasswordStrength')))
              .password,
          regenerated);
      for (final key in ['changePasswordNew', 'changePasswordRepeat']) {
        expect(field(key).obscureText, isTrue);
        await tester.tapAt(tester.getTopLeft(input(key)) + const Offset(25, 20),
            buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        expect(find.text('Copy'), findsOneWidget);
        await tester.tap(find.text('Copy'));
        await tester.pumpAndSettle();
        expect(clipboard, regenerated);
      }
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(replacements, 1);
      expect(submittedPassword, regenerated);
      expect(tester.widget<SpbGradientActionButton>(button).onTap, isNull);
      await tester.tap(button);
      await tester.pump();
      expect(field('changePasswordNew').controller!.text, regenerated);
      saved.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('changePasswordDialog')), findsNothing);
      await SecureClipboardService.clear();
      expect(tester.takeException(), isNull);
      await finishLayout(tester);
    });

    testWidgets('cancel generated password change on ${platform.name}',
        (tester) async {
      await setLayout(tester, platform);
      await tester.pumpWidget(
          const MaterialApp(home: VaultShell(initiallyUnlocked: true)));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(VaultShell));
      var replacements = 0;
      state.openChangePasswordDialog(replacePassword: ({
        required String oldPassword,
        required String newPassword,
        required String passwordHint,
      }) async {
        replacements++;
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('generateChangedVaultPassword')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancelChangePassword')));
      await tester.pumpAndSettle();
      expect(replacements, 0);
      expect(find.byKey(const Key('changePasswordDialog')), findsNothing);
      expect(tester.takeException(), isNull);
      await finishLayout(tester);
    });

    testWidgets('generate and copy new vault passwords on ${platform.name}',
        (tester) async {
      await setLayout(tester, platform);
      String? clipboard;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(const MaterialApp(home: VaultShell()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('createVault')));
      await tester.pumpAndSettle();
      TextField field(String key) => tester.widget<TextField>(find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(TextField),
          matchRoot: true));
      expect(field('newVaultPath').decoration!.hintText, 'Назначить путь');
      expect(field('newVaultPassword').controller!.text, isEmpty);
      final button = find.byKey(const Key('generateNewVaultPassword'));
      final cancel = find.byKey(const Key('cancelCreateVault'));
      final confirm = find.byKey(const Key('confirmCreateVault'));
      expect(
          tester.getCenter(button).dx, lessThan(tester.getCenter(cancel).dx));
      expect(
          tester.getCenter(cancel).dx, lessThan(tester.getCenter(confirm).dx));
      expect(tester.getCenter(button).dy, tester.getCenter(confirm).dy);
      expect(tester.widget<SpbGradientActionButton>(button).colors.last,
          Colors.black);
      expect(find.byTooltip('Генератор паролей'), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final generated = field('newVaultPassword').controller!.text;
      expect(generated.length, 20);
      expect(field('newVaultPasswordRepeat').controller!.text, generated);
      expect(field('newVaultPassword').obscureText, isTrue);
      expect(field('newVaultPasswordRepeat').obscureText, isTrue);
      expect(
          tester
              .widget<PasswordStrengthBar>(
                  find.byKey(const Key('newVaultPasswordStrength')))
              .password,
          generated);
      expect(clipboard, isNull,
          reason: 'Generation alone must not copy a secret');
      for (final key in ['newVaultPassword', 'newVaultPasswordRepeat']) {
        final target = find.descendant(
            of: find.byKey(Key(key)), matching: find.byType(TextField));
        await tester.tapAt(tester.getTopLeft(target) + const Offset(25, 20),
            buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        expect(find.text('Copy'), findsOneWidget);
        await tester.tap(find.text('Copy'));
        await tester.pumpAndSettle();
        expect(clipboard, generated);
      }
      await tester.tap(button);
      await tester.pumpAndSettle();
      final regenerated = field('newVaultPassword').controller!.text;
      expect(regenerated, isNot(generated));
      expect(field('newVaultPasswordRepeat').controller!.text, regenerated);
      expect(field('newVaultName').controller!.text, 'Новая база');
      expect(field('newVaultPath').controller!.text, isEmpty);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('newVaultPassword')), findsNothing);
      await SecureClipboardService.clear();
      expect(tester.takeException(), isNull);
      await finishLayout(tester);
    });
  }
}
