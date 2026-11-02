import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:wallet_aps/main.dart';

Future<void> settleCatalogIo(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('custom catalog metadata icon and membership survive reload',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('aps-catalog-test-');
    managedIconCatalogStateDirectoryOverride = temp;
    userThirdPartyIconDirectoryOverride = Directory('${temp.path}/icons');
    managedIconLibraryFuture = null;
    addTearDown(() {
      managedIconCatalogStateDirectoryOverride = null;
      userThirdPartyIconDirectoryOverride = null;
      managedIconLibraryFuture = null;
      customIconCatalogs = [];
      managedIconLocations = {};
      temp.deleteSync(recursive: true);
    });
    await tester.runAsync(loadManagedIconLibrary);
    final bytes =
        Uint8List.fromList(image.encodePng(image.Image(width: 16, height: 16)));
    final iconId = registerEmbeddedIcon(bytes);
    final folder = IconCatalogKind('custom-test', 'Мои значки',
        iconId: iconId, colorId: templateColorPalette.last.id);
    customIconCatalogs = [folder];
    final member = thirdPartyIconAssets.first;
    managedIconLocations[member] = folder;
    await tester.runAsync(saveManagedIconLibraryState);
    customIconCatalogs = [];
    managedIconLocations = {};
    spbEmbeddedIconPngs.remove(iconId.toUpperCase());
    managedIconLibraryFuture = null;
    await tester.runAsync(loadManagedIconLibrary);
    expect(customIconCatalogs.single.label, 'Мои значки');
    expect(customIconCatalogs.single.colorId, templateColorPalette.last.id);
    expect(spbEmbeddedIconPngs[iconId.toUpperCase()], bytes);
    expect(managedIconIdsFor(customIconCatalogs.single), contains(member));
    final state =
        jsonDecode(File('${temp.path}/catalog.json').readAsStringSync()) as Map;
    expect(state['version'], 2);
  });

  for (final width in [360.0, 1280.0]) {
    testWidgets('editor colors align with icon at width $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
      });
      final editors = <(Widget, String, String)>[
        (
          ItemEditorDialog(templates: builtInTemplates(), categories: const []),
          'cardBoundIcon',
          'cardColor'
        ),
        (const TemplateEditorDialog(), 'templateBoundIcon', 'templateColor'),
        (
          const CategoryEditorDialog(
              editing: false, initialName: '', initialIconId: 'folder'),
          'categoryBoundIcon',
          'categoryColor'
        ),
      ];
      for (final (editor, icon, palette) in editors) {
        await tester.pumpWidget(MaterialApp(
            home: MediaQuery(
                data: MediaQueryData(size: Size(width, 900)), child: editor)));
        await tester.pumpAndSettle();
        final iconRect = tester.getRect(find.byKey(Key(icon)));
        final first = tester.getRect(
            find.byKey(ValueKey('$palette-${templateColorPalette.first.id}')));
        final last = tester.getRect(
            find.byKey(ValueKey('$palette-${templateColorPalette.last.id}')));
        expect(first.height, 27);
        expect(first.left, greaterThan(iconRect.right));
        expect(first.bottom, closeTo(iconRect.bottom, 0.1), reason: icon);
        expect(last.right, lessThanOrEqualTo(width));
        expect(find.byType(SpbGrayPickerButton), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets(
      'icon menu opens on long press and selection requires confirmation',
      (tester) async {
    managedIconLibraryFuture = Future.value();
    customIconCatalogs = [
      const IconCatalogKind('custom-menu', 'Тестовый сборник')
    ];
    final id = templateIcons.first.id;
    managedIconLocations = {id: customIconCatalogs.single};
    String? chosen;
    addTearDown(() {
      managedIconLibraryFuture = null;
      customIconCatalogs = [];
      managedIconLocations = {};
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: IconEditorTarget(
      onImage: (_, __) {},
      onSelected: (value) => chosen = value,
      child: Container(
          key: const Key('target'),
          color: Colors.white,
          width: 100,
          height: 100),
    ))));
    await tester.longPress(find.byKey(const Key('target')));
    await tester.pumpAndSettle();
    expect(find.text('Вставить'), findsOneWidget);
    expect(find.text('Выбрать файл'), findsOneWidget);
    await tester.tap(find.text('Тестовый сборник'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('selectManagedIcon-$id')));
    await tester.pump();
    expect(chosen, isNull);
    await tester.tap(find.byKey(const Key('cancelIconSelection')));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
    await tester.longPress(find.byKey(const Key('target')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тестовый сборник'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('selectManagedIcon-$id')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmIconSelection')));
    await tester.pumpAndSettle();
    expect(chosen, id);
  });

  testWidgets('SVG import renders a centered PNG icon', (tester) async {
    final png = await tester.runAsync(() => decodeIconFileToPng(
        Uint8List.fromList(utf8.encode(
            '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="40" height="20" fill="#ff0000"/></svg>')),
        'test.svg'));
    final decoded = image.decodePng(png!)!;
    expect(decoded.width, 128);
    expect(decoded.height, 128);
    expect(decoded.getPixel(64, 64).r, 255);
    expect(decoded.getPixel(64, 0).a, 0);
  });

  testWidgets('create rename and delete icon folder keeps its icons',
      (tester) async {
    final temp = Directory.systemTemp.createTempSync('aps-folder-ui-');
    managedIconCatalogStateDirectoryOverride = temp;
    userThirdPartyIconDirectoryOverride = Directory('${temp.path}/icons');
    managedIconLibraryFuture = null;
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      managedIconCatalogStateDirectoryOverride = null;
      userThirdPartyIconDirectoryOverride = null;
      customIconCatalogs = [];
      managedIconLocations = {};
      managedIconLibraryFuture = null;
      temp.deleteSync(recursive: true);
    });
    await tester.runAsync(loadManagedIconLibrary);
    await tester.pumpWidget(
        const MaterialApp(home: VaultShell(initiallyUnlocked: true)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('spbIconsModeButton')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('createIconFolderButton')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('categoryNameField')), 'Коллекция');
    await tester.pump();
    await tester.tap(find.byKey(const Key('categorySaveButton')));
    await settleCatalogIo(tester);
    await tester.pumpAndSettle();
    final folder = customIconCatalogs.single;
    expect(folder.label, 'Коллекция');
    final dynamic shell = tester.state(find.byType(VaultShell));
    final member = thirdPartyIconAssets.first;
    final Future<void> moving = shell.moveManagedIconTo(member, folder);
    await settleCatalogIo(tester);
    await moving;
    await tester.pumpAndSettle();
    final row = find.byKey(ValueKey('spbIconCatalog-${folder.storageKey}'));
    await tester.tap(row, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Редактировать папку'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('categoryNameField')), 'Новая коллекция');
    await tester.tap(find.byKey(const Key('categorySaveButton')));
    await settleCatalogIo(tester);
    await tester.pumpAndSettle();
    expect(customIconCatalogs.single.label, 'Новая коллекция');
    expect(managedIconIdsFor(customIconCatalogs.single), contains(member));
    await tester.longPress(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить папку'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Удалить'));
    await settleCatalogIo(tester);
    await tester.pumpAndSettle();
    expect(customIconCatalogs, isEmpty);
    expect(managedIconIdsFor(IconCatalogKind.thirdParty), contains(member));
    expect(tester.takeException(), isNull);
  });
}
