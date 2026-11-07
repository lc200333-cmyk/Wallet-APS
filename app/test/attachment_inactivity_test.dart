import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/ui/skin/app_skin.dart';

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    for (final skin in AppSkin.values) {
      testWidgets('$platform $skin locks with inline attachment open',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        appSkin.value = skin;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize =
            Size(platform == TargetPlatform.android ? 390 : 1280, 900);
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          appSkin.value = AppSkin.retro;
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
        });
        await tester.pumpWidget(const AppUserActivityRegion(
          child: MaterialApp(home: VaultShell(initiallyUnlocked: true)),
        ));
        await tester.pumpAndSettle();
        final dynamic state = tester.state(find.byType(VaultShell));
        final template = builtInTemplates().first;
        final card = SecretItem(
          id: 'idle-card',
          templateId: template.id,
          title: 'Idle card',
          category: '',
          colorId: template.colorId,
          values: const {},
          modifiedAt: DateTime(2026),
          attachments: [
            SecretAttachment(
              id: 'idle-attachment',
              fileName: 'idle.txt',
              size: 6,
              pendingBytes: Uint8List.fromList(utf8.encode('Secret')),
            ),
          ],
        );
        unawaited(showDialog<void>(
          context: tester.element(find.byType(VaultShell)),
          builder: (_) => CardPreviewDialog(item: card, template: template),
        ));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const ValueKey('cardPreviewInlineAttachment-idle.txt')),
            findsOneWidget);
        await tester.pump(const Duration(minutes: 2, seconds: 45));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const Key('inactivityContinueButton')), findsOneWidget);
        await tester.pump(const Duration(seconds: 15));
        await tester.pumpAndSettle();
        expect(state.unlocked, isFalse);
        expect(find.byType(CardPreviewDialog), findsNothing);
        expect(find.byKey(const Key('passwordInput')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  testWidgets('locking arms exit timer without waiting for a rendered frame',
      (tester) async {
    var exited = false;
    await tester.pumpWidget(MaterialApp(
      home: VaultShell(
        initiallyUnlocked: true,
        onExitRequested: () async => exited = true,
      ),
    ));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    await state.closeAfterInactivity();
    // Android does not render the locked shell while an external viewer is up.
    expect(state.unlocked, isFalse);
    expect(state.lockedExitTimer, isNotNull);
    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();
    expect(exited, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resuming after suspended timers includes the locked exit delay',
      (tester) async {
    var exited = false;
    await tester.pumpWidget(MaterialApp(
      home: VaultShell(
        initiallyUnlocked: true,
        onExitRequested: () async => exited = true,
      ),
    ));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    state.lastUserActivityAt =
        DateTime.now().subtract(const Duration(minutes: 8, seconds: 1));
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(exited, isTrue);
    expect(find.byKey(const Key('inactivityContinueButton')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resuming before exit keeps the original inactivity deadline',
      (tester) async {
    var exited = false;
    await tester.pumpWidget(MaterialApp(
      home: VaultShell(
        initiallyUnlocked: true,
        onExitRequested: () async => exited = true,
      ),
    ));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    state.lastUserActivityAt =
        DateTime.now().subtract(const Duration(minutes: 4, seconds: 1));
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(state.unlocked, isFalse);
    expect(exited, isFalse);
    await tester.pump(const Duration(minutes: 4));
    await tester.pumpAndSettle();
    expect(exited, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
