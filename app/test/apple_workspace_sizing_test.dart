import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/ui/skin/app_skin.dart';
import 'package:wallet_aps/widgets/workspace_geometry.dart';

Future<dynamic> pumpWorkspace(
  WidgetTester tester,
  TargetPlatform platform,
) async {
  debugDefaultTargetPlatformOverride = platform;
  appSkin.value = AppSkin.light;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = platform == TargetPlatform.iOS
      ? const Size(390, 844)
      : const Size(1280, 800);
  await tester.pumpWidget(const WalletApsApp());
  await tester.pumpAndSettle();
  final dynamic state = tester.state(find.byType(VaultShell));
  final CardTemplate template = state.templates.first as CardTemplate;
  final String folder = state.spbTemplateFolderFor(template) as String;
  state.setState(() {
    state.unlocked = true;
    state.mobileTemplatesOpen = true;
    state.iconLibraryOpen = false;
    state.selectedTemplateFolder = folder;
    state.expandedTemplateFolders.add(folder);
  });
  await tester.pumpAndSettle();
  return (state, template, folder);
}

void sizingTest(
  String name,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      appSkin.value = AppSkin.retro;
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    }
  });
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    sizingTest(
      '${platform.name} enlarges template panes and icon folders only',
      (tester) async {
        final result = await pumpWorkspace(tester, platform);
        final dynamic state = result.$1;
        final CardTemplate template = result.$2 as CardTemplate;
        final String folder = result.$3 as String;

        expect(state.spbAppleWorkspaceSizing, isTrue);
        expect(
          state.spbTemplateTreeIconSize,
          closeTo(state.spbEntryTreeIconSize * 1.25, 0.001),
        );
        expect(
          state.spbTemplateTreeLabelStyle.fontSize,
          closeTo(state.spbTemplateTreeStyle.fontSize * 1.25, 0.001),
        );
        expect(
          state.spbTemplateFolderLabelStyle.fontSize,
          closeTo(state.spbTreeFolderStyle.fontSize * 1.25, 0.001),
        );

        final folderTile = tester.widget<ListTile>(
          find.descendant(
            of: find.byKey(ValueKey('spbTemplateFolder-$folder')),
            matching: find.byType(ListTile),
          ),
        );
        expect(
          folderTile.minLeadingWidth,
          closeTo(state.spbEntryTreeIconSize * 1.25, 0.001),
        );
        final folderLabel = tester.widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey('spbTemplateFolder-$folder')),
            matching: find.text(folder),
          ),
        );
        expect(
          folderLabel.style?.fontSize,
          closeTo(state.spbTreeFolderStyle.fontSize * 1.25, 0.001),
        );

        final workspace = find.byKey(const Key('spbTemplateWorkspace'));
        final grid = tester.widget<GridView>(
          find.descendant(of: workspace, matching: find.byType(GridView)),
        );
        expect(grid.gridDelegate, isA<WorkspaceGridDelegate>());
        expect(
          (grid.gridDelegate as WorkspaceGridDelegate).cell,
          closeTo(WorkspaceGeometry.gridCell * 1.25, 0.001),
        );
        final centralTemplate = find.byKey(
          ValueKey('spbCentralTemplate-${template.id}'),
        );
        expect(
          tester.getSize(centralTemplate),
          const Size.square(WorkspaceGeometry.gridCell * 1.25),
        );
        final centralLabel = tester.widget<Text>(
          find.descendant(
            of: centralTemplate,
            matching: find.text(template.displayName),
          ),
        );
        expect(
          centralLabel.style?.fontSize,
          closeTo(WorkspaceGeometry.itemNameFontSize * 1.20, 0.001),
        );
        expect(
          find.descendant(
            of: centralTemplate,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SizedBox &&
                  widget.width == WorkspaceGeometry.largeIcon * 1.25 &&
                  widget.height == WorkspaceGeometry.largeIcon * 1.25,
            ),
          ),
          findsWidgets,
        );

        state.setState(() {
          state.mobileTemplatesOpen = false;
          state.iconLibraryOpen = true;
          state.iconLibraryLoading = false;
        });
        await tester.pump();
        final catalog = find.byKey(const ValueKey('spbIconCatalog-spb'));
        final catalogTile = tester.widget<ListTile>(
          find.descendant(of: catalog, matching: find.byType(ListTile)),
        );
        expect(
          catalogTile.minLeadingWidth,
          closeTo(state.spbEntryTreeIconSize * 1.2 * 1.25, 0.001),
        );
        final catalogLabel = tester.widget<Text>(
          find.descendant(of: catalog, matching: find.text('Базовые')),
        );
        expect(
          catalogLabel.style?.fontSize,
          closeTo(state.spbIconCatalogStyle.fontSize * 1.25, 0.001),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    sizingTest('${platform.name} retains existing template and icon sizing', (
      tester,
    ) async {
      final result = await pumpWorkspace(tester, platform);
      final dynamic state = result.$1;

      expect(state.spbAppleWorkspaceSizing, isFalse);
      expect(state.spbAppleTopScale, 1);
      expect(state.spbAppleTemplateBottomFontScale, 1);
      expect(state.spbTemplateTreeIconSize, state.spbEntryTreeIconSize);
      expect(
        state.spbTemplateTreeLabelStyle.fontSize,
        state.spbTemplateTreeStyle.fontSize,
      );
      expect(state.spbTemplateGridIconSize, state.spbEntryGridIconSize);
      expect(state.spbTemplateGridCellSize, state.spbEntryGridHeight);
      expect(state.spbIconCatalogIconSize, state.spbEntryTreeIconSize * 1.2);
      expect(tester.takeException(), isNull);
    });
  }
}
