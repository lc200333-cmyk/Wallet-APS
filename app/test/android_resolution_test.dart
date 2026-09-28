import 'package:wallet_aps/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef AndroidDisplayProfile = ({
  String name,
  Size physicalSize,
  double devicePixelRatio,
});

const androidDisplayProfiles = <AndroidDisplayProfile>[
  (
    name: 'HD+ 720x1600',
    physicalSize: Size(720, 1600),
    devicePixelRatio: 2,
  ),
  (
    name: 'FHD+ 1080x2340',
    physicalSize: Size(1080, 2340),
    devicePixelRatio: 3,
  ),
  (
    name: 'FHD+ 1080x2400',
    physicalSize: Size(1080, 2400),
    devicePixelRatio: 3,
  ),
  (
    name: 'QHD+ 1440x3200',
    physicalSize: Size(1440, 3200),
    devicePixelRatio: 4,
  ),
];

void expectInsideViewport(
  WidgetTester tester,
  Finder finder,
  Size viewport, {
  required String reason,
}) {
  expect(finder, findsOneWidget, reason: reason);
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0), reason: reason);
  expect(rect.top, greaterThanOrEqualTo(0), reason: reason);
  expect(rect.right, lessThanOrEqualTo(viewport.width), reason: reason);
  expect(rect.bottom, lessThanOrEqualTo(viewport.height), reason: reason);
}

void main() {
  for (final profile in androidDisplayProfiles) {
    testWidgets('${profile.name}: password and vault fit in portrait',
        (tester) async {
      tester.view.devicePixelRatio = profile.devicePixelRatio;
      tester.view.physicalSize = profile.physicalSize;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final viewport = Size(
        profile.physicalSize.width / profile.devicePixelRatio,
        profile.physicalSize.height / profile.devicePixelRatio,
      );

      await tester.pumpWidget(const WalletApsApp());
      await tester.pump();
      expect(
        find.byKey(const Key('compactPortraitScale')),
        findsNothing,
        reason: '${profile.name}: portrait uses native 100% scale',
      );
      expectInsideViewport(
        tester,
        find.byKey(const Key('passwordInput')),
        viewport,
        reason: '${profile.name}: поле пароля',
      );
      expectInsideViewport(
        tester,
        find.byKey(const Key('keypad1')),
        viewport,
        reason: '${profile.name}: цифровая клавиатура',
      );
      expectInsideViewport(
        tester,
        find.byKey(const Key('fileMenu')),
        viewport,
        reason: '${profile.name}: выбор файла',
      );
      expectInsideViewport(
        tester,
        find.byKey(const Key('createVault')),
        viewport,
        reason: '${profile.name}: создание базы',
      );
      expectInsideViewport(
        tester,
        find.byKey(const Key('loginOk')),
        viewport,
        reason: '${profile.name}: кнопка входа',
      );
      expectInsideViewport(
        tester,
        find.byKey(const Key('loginCancel')),
        viewport,
        reason: '${profile.name}: кнопка отмены',
      );
      expect(tester.takeException(), isNull, reason: profile.name);

      await tester.pumpWidget(
        const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('spbMobilePaneHeader')), findsNothing);
      expect(find.byKey(const Key('spbClearSearchButton')), findsNothing);
      expectInsideViewport(
        tester,
        find.byKey(const Key('spbSubmitSearchButton')),
        viewport,
        reason: '${profile.name}: запуск поиска',
      );
      expectInsideViewport(
        tester,
        find.text('Шаблоны'),
        viewport,
        reason: '${profile.name}: нижняя навигация',
      );
      expect(tester.takeException(), isNull, reason: profile.name);
    });

    testWidgets('${profile.name}: landscape uses bounded mobile layout',
        (tester) async {
      tester.view.devicePixelRatio = profile.devicePixelRatio;
      tester.view.physicalSize = Size(
        profile.physicalSize.height,
        profile.physicalSize.width,
      );
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const WalletApsApp());
      await tester.pump();
      expect(
        find.byKey(const Key('compactPortraitScale')),
        findsNothing,
        reason: '${profile.name}: landscape keeps the regular scale',
      );
      expect(find.byKey(const Key('passwordInput')), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(tester.takeException(), isNull, reason: profile.name);

      await tester.pumpWidget(
        const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('spbMobilePaneHeader')), findsNothing);
      expect(find.byKey(const Key('spbClearSearchButton')), findsNothing);
      expect(find.byKey(const Key('spbSubmitSearchButton')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: profile.name);
    });
  }
}
