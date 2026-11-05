import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/widgets/mobile_fixed_text_scale.dart';

void main() {
  testWidgets('Android and iOS always use text scale 1.0', (tester) async {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final systemScale in [0.8, 1.0, 1.3, 2.0, 3.2]) {
        debugDefaultTargetPlatformOverride = platform;
        late TextScaler effectiveScaler;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(systemScale)),
            child: MobileFixedTextScale(
              child: Builder(
                builder: (context) {
                  effectiveScaler = MediaQuery.textScalerOf(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        expect(
          effectiveScaler.scale(10),
          10,
          reason: '$platform must ignore system text scale $systemScale',
        );
      }
    }

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows and Linux preserve the system text scale',
      (tester) async {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
      for (final systemScale in [0.8, 1.0, 1.3, 2.0, 3.2]) {
        debugDefaultTargetPlatformOverride = platform;
        late TextScaler effectiveScaler;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(systemScale)),
            child: MobileFixedTextScale(
              child: Builder(
                builder: (context) {
                  effectiveScaler = MediaQuery.textScalerOf(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        expect(
          effectiveScaler.scale(10),
          closeTo(10 * systemScale, 0.001),
          reason: '$platform must preserve system text scale $systemScale',
        );
      }
    }

    debugDefaultTargetPlatformOverride = null;
  });
}
