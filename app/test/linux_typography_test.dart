import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/ui/skin/app_skin.dart';
import 'package:wallet_aps/widgets/workspace_geometry.dart';

// Linux is drawn with the font metrics and sizes of the Windows version.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Linux themes use Wallet Sans, other platforms the system font', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(platformFontFamily, 'WalletSans');
    expect(isDesktopTargetPlatform, isTrue);
    for (final brightness in Brightness.values) {
      final theme = buildModernTheme(brightness);
      expect(theme.textTheme.bodyMedium!.fontFamily, 'WalletSans');
      expect(theme.textTheme.titleLarge!.fontFamily, 'WalletSans');
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(platformFontFamily, isNull);
    expect(isDesktopTargetPlatform, isTrue);
    expect(buildModernTheme(Brightness.dark).textTheme.bodyMedium!.fontFamily,
        'Segoe UI');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(platformFontFamily, isNull);
    expect(isDesktopTargetPlatform, isFalse);
  });

  testWidgets('Wallet Sans lines are as tall and wide as Segoe UI lines',
      (tester) async {
    await tester.runAsync(() async {
      final loader = FontLoader('WalletSansProbe');
      for (final weight in ['regular', 'semibold', 'bold']) {
        loader.addFont(Future.value(ByteData.sublistView(
            File('assets/fonts/WalletSans-$weight.ttf').readAsBytesSync())));
      }
      await loader.load();
    });
    for (final size in [12.0, 14.0, 17.0]) {
      final painter = TextPainter(
        text: TextSpan(
          text: 'Мои записи',
          style: TextStyle(fontFamily: 'WalletSansProbe', fontSize: size),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Segoe UI: ascender 2210 + descender 514 of 2048 units per em.
      expect(painter.height, closeTo(size * 2724 / 2048, 1));
      painter.dispose();
    }
    // Widths of this line at 14 px in Segoe UI, Semibold and Bold (Windows).
    const sample = 'Мои записи Шаблоны Банковский счёт Кредитная карта '
        'Паспорт 1234 Settings';
    for (final (weight, segoeWidth) in [
      (FontWeight.w400, 509.0),
      (FontWeight.w600, 522.5),
      (FontWeight.w700, 544.1),
    ]) {
      final painter = TextPainter(
        text: TextSpan(
          text: sample,
          style: TextStyle(
              fontFamily: 'WalletSansProbe', fontSize: 14, fontWeight: weight),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(painter.width, closeTo(segoeWidth, segoeWidth * 0.01),
          reason: '$weight');
      painter.dispose();
    }
  });
}
