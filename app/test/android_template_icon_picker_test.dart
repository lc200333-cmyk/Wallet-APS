import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final size in [const Size(360, 800), const Size(1000, 800)]) {
      testWidgets('${platform.name} template icon selection at $size can undo',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final previousManagedFuture = managedIconLibraryFuture;
        managedIconLibraryFuture = Future<void>.value();
        await tester.binding.setSurfaceSize(size);
        try {
          await tester
              .pumpWidget(const MaterialApp(home: TemplateEditorDialog()));
          await tester.pumpAndSettle();
          final dynamic editor =
              tester.state(find.byType(TemplateEditorDialog));
          final original = editor.iconId as String;
          final ids = managedIconIdsFor(IconCatalogKind.pictograms).toList()
            ..sort();
          final picked = ids.firstWhere((id) => id != original);

          await tester.longPress(find.byKey(const Key('templateBoundIcon')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Значки'));
          await tester.pumpAndSettle();
          expect(find.byType(ManagedIconSelectionDialog), findsOneWidget);
          await tester.tap(find.byKey(ValueKey('selectManagedIcon-$picked')));
          await tester.pump();
          expect(editor.iconId, original);
          await tester.tap(find.byKey(const Key('confirmIconSelection')));
          await tester.pumpAndSettle();
          expect(find.byType(ManagedIconSelectionDialog), findsNothing);
          expect(editor.iconId, picked);

          await tester.tap(find.byKey(const Key('templateUndoButton')));
          await tester.pumpAndSettle();
          expect(editor.iconId, original);

          await tester.longPress(find.byKey(const Key('templateBoundIcon')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Значки'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey('selectManagedIcon-$picked')));
          await tester.pump();
          await tester.tap(find.byKey(const Key('cancelIconSelection')));
          await tester.pumpAndSettle();
          expect(editor.iconId, original);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
          managedIconLibraryFuture = previousManagedFuture;
          await tester.binding.setSurfaceSize(null);
        }
      });
    }
  }
}
