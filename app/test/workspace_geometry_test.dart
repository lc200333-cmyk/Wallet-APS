import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/widgets/workspace_geometry.dart';

const screenshotKey = Key('geometryScreenshot');

Future<dynamic> pumpWorkspace(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.windows,
  double scale = 1,
  Size size = const Size(1280, 746.5),
}) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.devicePixelRatio = scale;
  tester.view.physicalSize = size * scale;
  addTearDown(() {
    debugDefaultTargetPlatformOverride = null;
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: const RepaintBoundary(
        key: screenshotKey,
        child: VaultShell(initiallyUnlocked: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final dynamic state = tester.state(find.byType(VaultShell));
  final CardTemplate template = state.templates.first as CardTemplate;
  final cards = <SecretItem>[
    for (var index = 0; index < 30; index++)
      SecretItem(
        id: 'geometry-$index',
        templateId: template.id,
        title: index == 0
            ? 'A long card caption that wraps onto two lines'
            : 'Card ${index.toString().padLeft(2, '0')}',
        category: '',
        colorId: template.colorId,
        values: const {},
        modifiedAt: DateTime(2026),
      ),
    SecretItem(
      id: 'nested-geometry',
      templateId: template.id,
      title: 'A very long tree name that must remain fully scrollable',
      category: 'A / Nested',
      colorId: template.colorId,
      values: const {},
      modifiedAt: DateTime(2026),
    ),
  ];
  state.setState(() {
    state.items = cards;
    state.itemsById = {for (final card in cards) card.id: card};
    state.categoryPaths = <String>{'A', 'A / Nested', 'B', 'C'};
    state.recentlyOpenedItemIds.addAll(cards.take(3).map((item) => item.id));
  });
  await tester.pumpAndSettle();
  return state;
}

Future<void> capture(WidgetTester tester, String name, double scale) async {
  if (!const bool.fromEnvironment('GEOMETRY_SCREENSHOTS')) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(screenshotKey),
    );
    final image = await boundary.toImage(pixelRatio: scale);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    final directory = Directory('../output/geometry-v1')
      ..createSync(recursive: true);
    File('${directory.path}/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    if (const bool.fromEnvironment('GEOMETRY_SCREENSHOTS')) {
      const fonts = String.fromEnvironment('GEOMETRY_FONT_DIR');
      if (fonts.isNotEmpty) {
        const windowsFont = String.fromEnvironment('GEOMETRY_WINDOWS_FONT');
        if (windowsFont.isNotEmpty && File(windowsFont).existsSync()) {
          await (FontLoader('Segoe UI')
                ..addFont(Future.value(
                    ByteData.sublistView(File(windowsFont).readAsBytesSync()))))
              .load();
        }
        for (final family in ['Roboto', 'MaterialIcons']) {
          final file = File(
              '$fonts/${family == 'Roboto' ? 'Roboto/Roboto-Regular.ttf' : 'MaterialIcons-Regular.otf'}');
          if (file.existsSync()) {
            final loader = FontLoader(family)
              ..addFont(
                  Future.value(ByteData.sublistView(file.readAsBytesSync())));
            await loader.load();
          }
        }
        final bold = File('$fonts/Roboto/Roboto-Bold.ttf');
        if (bold.existsSync()) {
          await (FontLoader('Roboto')
                ..addFont(
                    Future.value(ByteData.sublistView(bold.readAsBytesSync()))))
              .load();
        }
      }
      await loadSpb64PngIconAssets();
    }
  });
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.android,
  ]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('${platform.name} V1 geometry at ${scale * 100}%',
          (tester) async {
        final dynamic state = await pumpWorkspace(
          tester,
          platform: platform,
          scale: scale,
        );
        final wideAndroid = platform == TargetPlatform.android;
        final windows = platform == TargetPlatform.windows;
        final enlargedControls = wideAndroid || windows;
        final desktopFolderLayout = platform == TargetPlatform.windows ||
            platform == TargetPlatform.linux;
        final sideRowHeight = wideAndroid
            ? WorkspaceGeometry.androidListRowHeight
            : desktopFolderLayout
                ? (windows
                    ? WorkspaceGeometry.desktopTreeIcon * 1.15
                    : WorkspaceGeometry.desktopFolderRowHeight)
                : WorkspaceGeometry.rowHeight;
        final sideIconSize = wideAndroid
            ? WorkspaceGeometry.androidListSmallIcon * 1.15
            : desktopFolderLayout
                ? WorkspaceGeometry.desktopTreeIcon * (windows ? 1.15 : 1)
                : WorkspaceGeometry.smallIcon;
        final centerCellWidth = wideAndroid
            ? WorkspaceGeometry.wideAndroidGridCell
            : desktopFolderLayout
                ? WorkspaceGeometry.desktopCenterCellWidth
                : WorkspaceGeometry.gridCell;
        final centerCellHeight = wideAndroid
            ? WorkspaceGeometry.wideAndroidGridCell
            : WorkspaceGeometry.gridCell;
        final actionIconSize = wideAndroid
            ? WorkspaceGeometry.narrowActionIcon
            : WorkspaceGeometry.actionIcon;
        final navigator = find.byKey(const Key('spbVaultTitle'));
        expect(tester.getSize(navigator), const Size(247, 25));
        final search = find.byKey(const Key('spbSearchInput'));
        expect(tester.widget<TextField>(search).style?.fontSize,
            enlargedControls ? 16.5 : 15);
        expect(tester.widget<Text>(find.text('Поиск')).style?.fontSize,
            enlargedControls ? 16.5 : 15);
        final submit = find.byKey(const Key('spbSubmitSearchButton'));
        final close = find.byKey(const Key('spbForceCloseButton'));
        expect(tester.getSize(submit).width,
            closeTo(enlargedControls ? 29.7 : 27, 0.01));
        if (enlargedControls) {
          expect(tester.getTopRight(close).dx, closeTo(1280, 0.01));
          // The three controls stay together at the right, including landscape.
          expect(tester.getTopRight(close).dx - tester.getTopLeft(submit).dx,
              closeTo(3 * 29.7 + 8, 0.01));
        }
        for (final key in [
          'spbMyCardsModeButton',
          'spbTemplatesModeButton',
          'spbIconsModeButton',
        ]) {
          final mode = find.byKey(Key(key));
          expect(tester.getSize(mode).height,
              closeTo(enlargedControls ? 35.2 : 32, 0.01));
          final label = tester.widget<Text>(
              find.descendant(of: mode, matching: find.byType(Text)));
          expect(label.style?.fontSize,
              closeTo(enlargedControls ? 15.4 : 14, 0.01));
        }
        final firstRow = find.byKey(const ValueKey('spbTreeFolderIconRow-A'));
        final secondRow = find.byKey(const ValueKey('spbTreeFolderIconRow-B'));
        expect(tester.getSize(firstRow).height, sideRowHeight);
        expect(
          tester.getCenter(secondRow).dy - tester.getCenter(firstRow).dy,
          closeTo(sideRowHeight, 0.01),
        );
        final treeIcon =
            find.descendant(of: firstRow, matching: find.byType(Icon));
        expect(tester.getSize(treeIcon.last), Size.square(sideIconSize));
        final treeFolderLabel = tester.widget<Text>(find.descendant(
          of: find.byKey(const ValueKey('spbTreeFolder-A')),
          matching: find.text('A'),
        ));
        expect(
          treeFolderLabel.style?.fontSize,
          wideAndroid
              ? 17 * 1.15
              : desktopFolderLayout
                  ? 16 * (windows ? 1.15 : 1)
                  : 14,
        );
        expect(treeFolderLabel.style?.fontWeight, FontWeight.normal);
        final treeCardLabel = tester.widget<Text>(find.descendant(
          of: find.byKey(const ValueKey('spbTreeCard-geometry-0')),
          matching: find.text('A long card caption that wraps onto two lines'),
        ));
        expect(treeCardLabel.style?.fontSize, desktopFolderLayout ? 14 : 13);
        expect(treeCardLabel.style?.fontWeight, FontWeight.normal);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('spbTreeCard-geometry-0')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SizedBox &&
                  widget.width == sideIconSize &&
                  widget.height == sideIconSize,
            ),
          ),
          findsWidgets,
        );
        final grid = find.descendant(
          of: find.byKey(const Key('spbCentralWorkspace')),
          matching: find.byType(GridView),
        );
        expect(tester.getSize(grid).width, 781);
        if (wideAndroid) {
          expect(tester.widget<GridView>(grid).gridDelegate,
              isA<WideAndroidGridDelegate>());
        } else if (desktopFolderLayout) {
          expect(tester.widget<GridView>(grid).gridDelegate,
              isA<DesktopCardGridDelegate>());
        } else {
          expect(tester.widget<GridView>(grid).gridDelegate,
              isA<WorkspaceGridDelegate>());
        }
        final firstCard =
            find.byKey(const ValueKey('spbCentralCard-geometry-0'));
        expect(
          tester.getSize(firstCard),
          Size(centerCellWidth, centerCellHeight),
        );
        final centerIconSize = wideAndroid
            ? WorkspaceGeometry.wideAndroidGridIcon
            : desktopFolderLayout
                ? WorkspaceGeometry.desktopCenterIcon
                : WorkspaceGeometry.largeIcon;
        expect(
          find.descendant(
            of: firstCard,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SizedBox &&
                  widget.width == centerIconSize &&
                  widget.height == centerIconSize,
            ),
          ),
          findsWidgets,
        );
        final secondCard =
            find.byKey(const ValueKey('spbCentralCard-geometry-1'));
        final nextRow = find.byKey(ValueKey(
          wideAndroid || desktopFolderLayout
              ? 'spbCentralCard-geometry-5'
              : 'spbCentralCard-geometry-7',
        ));
        expect(tester.getCenter(secondCard).dx - tester.getCenter(firstCard).dx,
            centerCellWidth);
        expect(
          tester.getCenter(nextRow).dy - tester.getCenter(firstCard).dy,
          centerCellHeight,
        );
        final label = tester.widget<Text>(
          find.byKey(const ValueKey('spbCardGridLabel-geometry-0')),
        );
        expect(
          label.style!.fontSize,
          wideAndroid
              ? 16
              : desktopFolderLayout
                  ? 14
                  : 13,
        );
        expect(
          label.style!.height! * label.style!.fontSize!,
          closeTo(wideAndroid ? 18 : 15, 0.000001),
        );
        expect(label.style!.fontWeight, FontWeight.normal);
        expect(label.maxLines, 2);
        expect(label.overflow, TextOverflow.ellipsis);
        final gridFolderLabel = tester.widget<Text>(find.descendant(
          of: find.byKey(const ValueKey('spbCentralFolder-A')),
          matching: find.text('A'),
        ));
        expect(gridFolderLabel.style?.fontSize, wideAndroid ? 18 : 14);
        expect(gridFolderLabel.style?.fontWeight, FontWeight.normal);
        final actions = find.byKey(const Key('spbActionsPanelScrollbar'));
        expect(tester.getSize(actions).width, 244);
        expect(tester.widget<Scrollbar>(actions).thickness, 19);
        final taskHeader = find.byKey(const ValueKey('spbCollapseЗадачи'));
        expect(
          tester.getSize(taskHeader),
          Size.square(wideAndroid
              ? WorkspaceGeometry.narrowCollapseSize
              : WorkspaceGeometry.collapseSize),
        );
        final taskLabel = state.spbTasksForCurrentMode().first.$2 as String;
        final taskIcon = find.byKey(ValueKey('spbActionIcon-$taskLabel'));
        expect(tester.getSize(taskIcon), Size.square(actionIconSize));
        expect(
          tester.widget<Text>(find.text(taskLabel)).style?.fontSize,
          wideAndroid ? 16 : (windows ? 15 : 14),
        );
        final frequentIcon = find.byKey(
          ValueKey('spbActionIcon-${state.frequentItems().first.title}'),
        );
        expect(tester.getSize(frequentIcon), Size.square(actionIconSize));
        state.searchController.text = 'Card 01';
        state.setState(() => state.spbSubmittedSearchQuery = 'Card 01');
        await tester.pumpAndSettle();
        final foundIcon = find.byKey(
          const ValueKey('spbFoundIcon-Card 01'),
        );
        expect(tester.getSize(foundIcon), Size.square(actionIconSize));
        final foundTitle = tester.widget<Text>(find.descendant(
          of: find.byKey(const Key('spbSearchResults')),
          matching: find.text('Card 01'),
        ));
        expect(foundTitle.style?.fontSize, wideAndroid ? 16 : 15);
        final foundSubtitle = tester
            .widgetList<Text>(find.descendant(
              of: find.byKey(const Key('spbSearchResults')),
              matching: find.text('Карточка'),
            ))
            .first;
        expect(foundSubtitle.style?.fontSize, wideAndroid ? 15 : 14);
        state.searchController.clear();
        state.setState(() => state.spbSubmittedSearchQuery = '');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(
            tester, '${platform.name}-${(scale * 100).round()}', scale);

        // The same metrics apply when switching the existing sections.
        state.setState(() => state.mobileTemplatesOpen = true);
        await tester.pumpAndSettle();
        final template = find.byKey(
          ValueKey('spbCentralTemplate-${state.templates.first.id}'),
        );
        expect(
            tester.getSize(template), Size(centerCellWidth, centerCellHeight));
        final templateLabel = tester.widget<Text>(find.descendant(
          of: template,
          matching: find.text(state.templates.first.name),
        ));
        expect(templateLabel.style, label.style);
        expect(templateLabel.strutStyle, label.strutStyle);
        expect(templateLabel.maxLines, label.maxLines);
        expect(templateLabel.overflow, label.overflow);
        expect(templateLabel.style?.fontWeight, FontWeight.normal);
        final treeTemplateLabel = tester.widget<Text>(find.descendant(
          of: find.byKey(ValueKey('spbTemplate-${state.templates.first.id}')),
          matching: find.text(state.templates.first.name),
        ));
        expect(treeTemplateLabel.style?.fontSize,
            treeCardLabel.style!.fontSize! * 1.15);
        expect(treeTemplateLabel.strutStyle?.fontSize,
            treeCardLabel.strutStyle!.fontSize! * 1.15);
        expect(treeTemplateLabel.style?.fontWeight, FontWeight.normal);
        final treeTemplateTile = tester.widget<ListTile>(find.descendant(
          of: find.byKey(
            ValueKey('spbTemplate-${state.templates.first.id}'),
          ),
          matching: find.byType(ListTile),
        ));
        expect(
            treeTemplateTile.minTileHeight,
            (desktopFolderLayout
                    ? WorkspaceGeometry.desktopFolderRowHeight
                    : sideRowHeight) *
                1.2);
        final treeTemplateIcon = find.descendant(
          of: find.byKey(
            ValueKey('spbTemplate-${state.templates.first.id}'),
          ),
          matching: find.byType(Icon),
        );
        expect(
          tester.getSize(treeTemplateIcon.last),
          Size.square(sideIconSize),
        );
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  testWidgets('resize retains side widths and working splitters',
      (tester) async {
    await pumpWorkspace(tester);
    tester.view.physicalSize = const Size(1500, 900);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('spbVaultTitle'))).width, 247);
    expect(
        tester.getSize(find.byKey(const Key('spbActionsPanelScrollbar'))).width,
        244);
    // Include Flutter's 20 px drag recognition threshold.
    await tester.drag(
        find.byKey(const Key('spbNavigatorSplitter')), const Offset(45, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('spbVaultTitle'))).width, 272);
    await tester.drag(
        find.byKey(const Key('spbActionsPanelSplitter')), const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(
        tester.getSize(find.byKey(const Key('spbActionsPanelScrollbar'))).width,
        264);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('nested tree scrolls complete names horizontally',
      (tester) async {
    final dynamic state = await pumpWorkspace(tester);
    await tester.tap(find.byKey(const ValueKey('spbTreeFolderIconRow-A')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('spbTreeFolderIconRow-A / Nested')));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('spbTreeCard-nested-geometry'));
    expect(
      tester.getSize(card).height,
      WorkspaceGeometry.desktopTreeIcon * 1.15,
    );
    final ScrollController horizontal = state.spbTreeHorizontalScrollController;
    expect(horizontal.position.maxScrollExtent, greaterThan(0));
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android narrow panes use enlarged type and three grid columns',
      (tester) async {
    final dynamic state = await pumpWorkspace(
      tester,
      platform: TargetPlatform.android,
      size: const Size(360, 800),
      scale: 2,
    );
    expect(find.byKey(const Key('spbNavigatorSplitter')), findsNothing);
    final firstTreeRow = find.byKey(const ValueKey('spbTreeFolderIconRow-A'));
    final secondTreeRow = find.byKey(const ValueKey('spbTreeFolderIconRow-B'));
    expect(tester.getSize(firstTreeRow).height,
        closeTo(WorkspaceGeometry.androidListRowHeight, 0.01));
    expect(
      tester.getCenter(secondTreeRow).dy - tester.getCenter(firstTreeRow).dy,
      closeTo(WorkspaceGeometry.androidListRowHeight, 0.01),
    );
    final treeIcon =
        find.descendant(of: firstTreeRow, matching: find.byType(Icon));
    expect(tester.getSize(treeIcon.last).width,
        closeTo(WorkspaceGeometry.androidListSmallIcon * 1.15, 0.01));
    final treeFolderLabel = tester.widget<Text>(find.descendant(
      of: find.byKey(const ValueKey('spbTreeFolder-A')),
      matching: find.text('A'),
    ));
    expect(treeFolderLabel.style?.fontSize, 17 * 1.15);
    expect(treeFolderLabel.style?.fontWeight, FontWeight.normal);
    final treeCardLabel = tester.widget<Text>(find.descendant(
      of: find.byKey(const ValueKey('spbTreeCard-geometry-0')),
      matching: find.text('A long card caption that wraps onto two lines'),
    ));
    expect(treeCardLabel.style?.fontSize, 16);

    state.setState(() => state.mobilePane = 1);
    await tester.pumpAndSettle();
    final centerHeader = tester.widget<Text>(find.text('Мои карточки'));
    expect(centerHeader.style?.fontSize, 15);
    final grid = find.descendant(
      of: find.byKey(const Key('spbCentralWorkspace')),
      matching: find.byType(GridView),
    );
    expect(tester.widget<GridView>(grid).gridDelegate,
        isA<NarrowAndroidGridDelegate>());
    final firstFolder = find.byKey(const ValueKey('spbCentralFolder-A'));
    final secondFolder = find.byKey(const ValueKey('spbCentralFolder-B'));
    final thirdFolder = find.byKey(const ValueKey('spbCentralFolder-C'));
    final firstCard = find.byKey(const ValueKey('spbCentralCard-geometry-0'));
    final nextCardRow = find.byKey(const ValueKey('spbCentralCard-geometry-3'));
    final firstCardSize = tester.getSize(firstCard);
    expect(firstCardSize.width, closeTo((360 - 16) / 3, 0.01));
    expect(
        firstCardSize.height, closeTo(WorkspaceGeometry.narrowGridCell, 0.01));
    expect(
      tester.getCenter(secondFolder).dx - tester.getCenter(firstFolder).dx,
      closeTo(firstCardSize.width, 0.01),
    );
    expect(
      tester.getCenter(thirdFolder).dx - tester.getCenter(secondFolder).dx,
      closeTo(firstCardSize.width, 0.01),
    );
    expect(
      tester.getCenter(nextCardRow).dy - tester.getCenter(firstCard).dy,
      closeTo(WorkspaceGeometry.narrowGridCell, 0.01),
    );
    final cardLabel = tester.widget<Text>(
      find.byKey(const ValueKey('spbCardGridLabel-geometry-0')),
    );
    expect(cardLabel.style?.fontSize, 15);
    final centralFolderLabel = tester.widget<Text>(find.descendant(
      of: firstFolder,
      matching: find.text('A'),
    ));
    expect(centralFolderLabel.style?.fontSize, 17);
    expect(tester.takeException(), isNull);
    await capture(tester, 'android-narrow-200', 2);

    state.setState(() => state.mobilePane = 2);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('spbCollapseЗадачи')), findsOneWidget);
    final taskHeader = tester.widget<Text>(find.text('Задачи'));
    expect(taskHeader.style?.fontSize, 17);
    final taskLabel = state.spbTasksForCurrentMode().first.$2 as String;
    final taskIcon = find.byKey(ValueKey('spbActionIcon-$taskLabel'));
    expect(tester.getSize(taskIcon).width,
        closeTo(WorkspaceGeometry.narrowActionIcon, 0.01));
    final taskText = tester.widget<Text>(find.text(taskLabel));
    expect(taskText.style?.fontSize, 16);
    final frequentTitle = state.frequentItems().first.title as String;
    final frequentText = tester.widget<Text>(find.text(frequentTitle));
    expect(frequentText.style?.fontSize, 16);

    state.searchController.text = 'Card 01';
    state.setState(() => state.spbSubmittedSearchQuery = 'Card 01');
    await tester.pumpAndSettle();
    final foundIcon = find.byKey(const ValueKey('spbFoundIcon-Card 01'));
    expect(tester.getSize(foundIcon).width,
        closeTo(WorkspaceGeometry.narrowActionIcon, 0.01));
    final foundTitle = tester.widget<Text>(find.descendant(
      of: find.byKey(const Key('spbSearchResults')),
      matching: find.text('Card 01'),
    ));
    expect(foundTitle.style?.fontSize, 16);
    final foundSubtitle = tester
        .widgetList<Text>(find.descendant(
          of: find.byKey(const Key('spbSearchResults')),
          matching: find.text('Карточка'),
        ))
        .first;
    expect(foundSubtitle.style?.fontSize, 15);

    state.searchController.clear();
    state.setState(() {
      state.spbSubmittedSearchQuery = '';
      state.mobileTemplatesOpen = true;
      state.mobilePane = 0;
    });
    await tester.pumpAndSettle();
    final templateRow = find.byKey(
      ValueKey('spbTemplate-${state.templates.first.id}'),
    );
    final templateTile = tester.widget<ListTile>(
      find.descendant(of: templateRow, matching: find.byType(ListTile)),
    );
    expect(templateTile.minTileHeight,
        WorkspaceGeometry.androidListRowHeight * 1.2);
    final templateIcon = find.descendant(
      of: templateRow,
      matching: find.byType(Icon),
    );
    expect(
      tester.getSize(templateIcon.last),
      const Size.square(WorkspaceGeometry.androidListSmallIcon * 1.15),
    );
    final templateLabel = tester.widget<Text>(
      find.descendant(
        of: templateRow,
        matching: find.text(state.templates.first.name),
      ),
    );
    expect(templateLabel.style?.fontSize, 16 * 1.15);
    state.setState(() => state.mobilePane = 1);
    await tester.pumpAndSettle();
    final templateGrid = find.descendant(
      of: find.byKey(const Key('spbTemplateWorkspace')),
      matching: find.byType(GridView),
    );
    expect(tester.widget<GridView>(templateGrid).gridDelegate,
        isA<NarrowAndroidGridDelegate>());
    final centralTemplate = find.byKey(
      ValueKey('spbCentralTemplate-${state.templates.first.id}'),
    );
    final centralTemplateLabel = tester.widget<Text>(find.descendant(
      of: centralTemplate,
      matching: find.text(state.templates.first.name),
    ));
    expect(tester.getSize(centralTemplate), firstCardSize);
    expect(centralTemplateLabel.style, cardLabel.style);
    expect(centralTemplateLabel.strutStyle, cardLabel.strutStyle);
    expect(centralTemplateLabel.maxLines, cardLabel.maxLines);
    expect(centralTemplateLabel.overflow, cardLabel.overflow);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
