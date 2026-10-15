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
        await tester.binding.setSurfaceSize(size);
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          tester.binding.setSurfaceSize(null);
        });
        await tester
            .pumpWidget(const MaterialApp(home: TemplateEditorDialog()));
        await tester.pumpAndSettle();
        final dynamic editor = tester.state(find.byType(TemplateEditorDialog));
        final original = editor.iconId as String;
        await tester.tap(find.byKey(const Key('templatePictogramsButton')));
        await tester.pumpAndSettle();
        final dialog = find.byKey(const Key('pictogramPickerDialog'));
        if (platform == TargetPlatform.android || size.width < 700) {
          expect(tester.getSize(dialog), size);
        } else {
          expect(tester.widget(dialog), isA<AlertDialog>());
        }
        expect(
            find.byKey(const Key('pictogramPickerScrollbar')), findsOneWidget);
        final picked = templateIcons.firstWhere((icon) => icon.id != original);
        await tester.tap(find.byTooltip(picked.label).first);
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
        expect(editor.iconId, picked.id);
        await tester.tap(find.byKey(const Key('templateUndoButton')));
        await tester.pumpAndSettle();
        expect(editor.iconId, original);
        await tester.tap(find.byKey(const Key('templatePictogramsButton')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('iconPickerCloseButton')));
        await tester.pumpAndSettle();
        expect(editor.iconId, original);
        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
