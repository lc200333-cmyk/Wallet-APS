import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.iOS,
  ]) {
    for (final size in [const Size(360, 800), const Size(1000, 800)]) {
      testWidgets(
        '${platform.name} card icon changes on the first confirmation at $size',
        (tester) async {
          final previousManagedFuture = managedIconLibraryFuture;
          debugDefaultTargetPlatformOverride = platform;
          managedIconLibraryFuture = Future<void>.value();
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          try {
            await tester.pumpWidget(
              MaterialApp(
                home: ItemEditorDialog(
                  templates: builtInTemplates(),
                  categories: const [],
                ),
              ),
            );
            await tester.pumpAndSettle();
            final dynamic editor = tester.state(find.byType(ItemEditorDialog));
            final original = editor.iconId as String;
            final ids = managedIconIdsFor(IconCatalogKind.pictograms).toList()
              ..sort();
            final picked = ids.firstWhere((id) => id != original);
            final target = find.byKey(const Key('cardBoundIcon'));

            if (platform == TargetPlatform.windows ||
                platform == TargetPlatform.linux ||
                platform == TargetPlatform.macOS) {
              await tester.tap(target, buttons: kSecondaryMouseButton);
            } else {
              await tester.longPress(target);
            }
            await tester.pumpAndSettle();
            await tester.tap(find.text('Значки'));
            await tester.pumpAndSettle();
            expect(find.byType(ManagedIconSelectionDialog), findsOneWidget);

            await tester.tap(
              find.byKey(ValueKey('selectManagedIcon-$picked')),
            );
            // Confirm immediately. The selected value must not depend on a
            // second tap or on an intervening rendered frame.
            await tester.tap(find.byKey(const Key('confirmIconSelection')));
            await tester.pumpAndSettle();

            expect(find.byType(ManagedIconSelectionDialog), findsNothing);
            expect(editor.iconId, picked);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            debugDefaultTargetPlatformOverride = null;
            managedIconLibraryFuture = previousManagedFuture;
            tester.view.resetDevicePixelRatio();
            tester.view.resetPhysicalSize();
          }
        },
      );
    }
  }
}
