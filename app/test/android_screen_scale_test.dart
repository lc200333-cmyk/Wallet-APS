import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/widgets/android_screen_scale.dart';

void main() {
  testWidgets('phone proportions, dialogs and touch targets scale together',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in [
      const Size(360, 800),
      const Size(412, 915),
      const Size(480, 1040),
      const Size(915, 412),
    ]) {
      await tester.binding.setSurfaceSize(size);
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => AndroidScreenScale(child: child!),
        home: Builder(builder: (context) {
          return Scaffold(
            body: Center(
              child: SizedBox(
                key: const Key('target'),
                width: 180,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const Dialog(
                      child: SizedBox(
                        key: Key('dialog'),
                        width: 200,
                        height: 100,
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          );
        }),
      ));
      await tester.pumpAndSettle();
      final box =
          tester.renderObject<RenderBox>(find.byKey(const Key('target')));
      final actualWidth = (box.localToGlobal(const Offset(180, 0)) -
              box.localToGlobal(Offset.zero))
          .distance;
      expect(actualWidth, closeTo(size.shortestSide / 2, 0.01));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dialog')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('keyboard and safe areas stay in physical alignment',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(432, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late MediaQueryData scaled;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
        size: Size(432, 960),
        padding: EdgeInsets.only(top: 24),
        viewPadding: EdgeInsets.only(top: 24, bottom: 24),
        viewInsets: EdgeInsets.only(bottom: 300),
        textScaler: TextScaler.linear(1.3),
      ),
      child: AndroidScreenScale(child: Builder(builder: (context) {
        scaled = MediaQuery.of(context);
        return const SizedBox.expand();
      })),
    ));
    expect(scaled.size, const Size(360, 800));
    expect(scaled.padding.top * 1.2, 24);
    expect(scaled.viewInsets.bottom * 1.2, 300);
    expect(scaled.textScaler.scale(10), 13);
    debugDefaultTargetPlatformOverride = null;
  });
}
