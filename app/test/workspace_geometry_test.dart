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
        final navigator = find.byKey(const Key('spbVaultTitle'));
        expect(tester.getSize(navigator), const Size(247, 25));
        final firstRow = find.byKey(const ValueKey('spbTreeFolderIconRow-A'));
        final secondRow = find.byKey(const ValueKey('spbTreeFolderIconRow-B'));
        expect(tester.getSize(firstRow).height, 20);
        expect(
            tester.getCenter(secondRow).dy - tester.getCenter(firstRow).dy, 20);
        final treeIcon =
            find.descendant(of: firstRow, matching: find.byType(Icon));
        expect(tester.getSize(treeIcon.last), const Size(16, 16));
        final treeFolderLabel = tester.widget<Text>(find.descendant(
          of: find.byKey(const ValueKey('spbTreeFolder-A')),
          matching: find.text('A'),
        ));
        expect(treeFolderLabel.style?.fontSize, 14);
        expect(treeFolderLabel.style?.fontWeight, FontWeight.normal);
        final treeCardLabel = tester.widget<Text>(find.descendant(
          of: find.byKey(const ValueKey('spbTreeCard-geometry-0')),
          matching: find.text('A long card caption that wraps onto two lines'),
        ));
        expect(treeCardLabel.style?.fontSize, 13);
        expect(treeCardLabel.style?.fontWeight, FontWeight.normal);
        final grid = find.descendant(
          of: find.byKey(const Key('spbCentralWorkspace')),
          matching: find.byType(GridView),
        );
        expect(tester.getSize(grid).width, 781);
        expect(tester.widget<GridView>(grid).gridDelegate,
            isA<WorkspaceGridDelegate>());
        final firstCard =
            find.byKey(const ValueKey('spbCentralCard-geometry-0'));
        expect(tester.getSize(firstCard), const Size(75, 75));
        final secondCard =
            find.byKey(const ValueKey('spbCentralCard-geometry-1'));
        final nextRow = find.byKey(const ValueKey('spbCentralCard-geometry-7'));
        expect(tester.getCenter(secondCard).dx - tester.getCenter(firstCard).dx,
            75);
        expect(
            tester.getCenter(nextRow).dy - tester.getCenter(firstCard).dy, 75);
        final label = tester.widget<Text>(
          find.byKey(const ValueKey('spbCardGridLabel-geometry-0')),
        );
        expect(label.style!.fontSize, 13);
        expect(
          label.style!.height! * label.style!.fontSize!,
          closeTo(15, 0.000001),
        );
        expect(label.style!.fontWeight, FontWeight.normal);
        expect(label.maxLines, 2);
        expect(label.overflow, TextOverflow.ellipsis);
        final gridFolderLabel = tester.widget<Text>(find.descendant(
          of: find.byKey(const ValueKey('spbCentralFolder-A')),
          matching: find.text('A'),
        ));
        expect(gridFolderLabel.style?.fontSize, 14);
        expect(gridFolderLabel.style?.fontWeight, FontWeight.normal);
        final actions = find.byKey(const Key('spbActionsPanelScrollbar'));
        expect(tester.getSize(actions).width, 244);
        expect(tester.widget<Scrollbar>(actions).thickness, 19);
        final taskHeader = find.byKey(const ValueKey('spbCollapseЗадачи'));
        expect(tester.getSize(taskHeader), const Size(18, 18));
        final taskLabel = state.spbTasksForCurrentMode().first.$2 as String;
        final taskIcon = find.byKey(ValueKey('spbActionIcon-$taskLabel'));
        expect(tester.getSize(taskIcon), const Size.square(22));
        final frequentIcon = find.byKey(
          ValueKey('spbActionIcon-${state.frequentItems().first.title}'),
        );
        expect(tester.getSize(frequentIcon), const Size.square(22));
        state.searchController.text = 'Card 01';
        state.setState(() => state.spbSubmittedSearchQuery = 'Card 01');
        await tester.pumpAndSettle();
        final foundIcon = find.byKey(
          const ValueKey('spbFoundIcon-Card 01'),
        );
        expect(tester.getSize(foundIcon), const Size.square(22));
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
        expect(tester.getSize(template), const Size(75, 75));
        final templateLabel = tester.widget<Text>(find.descendant(
          of: template,
          matching: find.text(state.templates.first.name),
        ));
        expect(templateLabel.style?.fontSize, 13);
        expect(templateLabel.style?.fontWeight, FontWeight.normal);
        final treeTemplateLabel = tester.widget<Text>(find.descendant(
          of: find.byKey(ValueKey('spbTemplate-${state.templates.first.id}')),
          matching: find.text(state.templates.first.name),
        ));
        expect(treeTemplateLabel.style?.fontSize, 13);
        expect(treeTemplateLabel.style?.fontWeight, FontWeight.normal);
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
    expect(tester.getSize(card).height, 20);
    final ScrollController horizontal = state.spbTreeHorizontalScrollController;
    expect(horizontal.position.maxScrollExtent, greaterThan(0));
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android narrow panes keep V1 cells and reachable controls',
      (tester) async {
    final dynamic state = await pumpWorkspace(
      tester,
      platform: TargetPlatform.android,
      size: const Size(360, 800),
      scale: 2,
    );
    expect(find.byKey(const Key('spbNavigatorSplitter')), findsNothing);
    state.setState(() => state.mobilePane = 1);
    await tester.pumpAndSettle();
    expect(
        tester.getSize(find.byKey(const ValueKey('spbCentralCard-geometry-0'))),
        const Size(75, 75));
    expect(tester.takeException(), isNull);
    await capture(tester, 'android-narrow-200', 2);
    state.setState(() => state.mobilePane = 2);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('spbCollapseЗадачи')), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
