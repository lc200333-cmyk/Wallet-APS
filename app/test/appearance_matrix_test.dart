import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/appearance/appearance.dart';
import 'package:wallet_aps/appearance/appearance_controller.dart';
import 'package:wallet_aps/main.dart';
import 'appearance_test.dart' show themed;
import 'appearance_visual_test.dart'
    show captureAppearance, loadAppearanceFonts;

void main() {
  setUpAll(loadAppearanceFonts);
  for (final size in [
    const Size(320, 480),
    const Size(360, 800),
    const Size(412, 900),
    const Size(1280, 900),
    const Size(1600, 1000)
  ]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets(
          'login ${size.width}x${size.height}, text $scale, all themes and keyboards',
          (tester) async {
        debugDefaultTargetPlatformOverride =
            size.width < 700 ? TargetPlatform.android : TargetPlatform.windows;
        await tester.binding.setSurfaceSize(size);
        final c = AppearanceController();
        try {
          await tester.pumpWidget(themed(
              c,
              MediaQuery(
                  data: MediaQueryData(
                      size: size,
                      textScaler: TextScaler.linear(scale),
                      viewInsets: size.height < 500
                          ? const EdgeInsets.only(bottom: 160)
                          : EdgeInsets.zero),
                  child: const VaultShell())));
          await tester.pumpAndSettle();
          final dynamic state = tester.state(find.byType(VaultShell));
          state.setState(() {
            state.message = 'Тестовая ошибка';
            state.loginHintVisible = true;
          });
          for (final mode in AppAppearance.values) {
            c.choose(mode);
            await tester.pumpAndSettle();
            for (final keyboard in VirtualKeyboardMode.values) {
              state.setState(() {
                state.virtualKeyboardMode = keyboard;
              });
              await tester.pumpAndSettle();
              // The selector and pre-existing bottom commands must be reachable
              // through normal scrolling, even with a visible software keyboard.
              await tester.ensureVisible(
                  find.byKey(ValueKey('appearance-${mode.name}')));
              await tester.ensureVisible(find.byKey(const Key('loginOk')));
              expect(tester.takeException(), isNull,
                  reason: '${mode.name}/${keyboard.name}');
            }
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          debugDefaultTargetPlatformOverride = null;
          await tester.binding.setSurfaceSize(null);
        }
      });
    }
  }
  testWidgets('Enter and Space activate theme buttons, not the password form',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    final c = AppearanceController();
    try {
      await tester.pumpWidget(WalletApsApp(appearance: c));
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(VaultShell));
      state.passwordController.text = 'synthetic';
      for (final entry in [
        (AppAppearance.light, 'Светлая тема', LogicalKeyboardKey.enter),
        (AppAppearance.dark, 'Тёмная тема', LogicalKeyboardKey.space)
      ]) {
        final node = Focus.of(tester.element(find.text(entry.$2)));
        node.requestFocus();
        await tester.pump();
        expect(node.hasFocus, isTrue);
        await tester.sendKeyEvent(entry.$3);
        await tester.pumpAndSettle();
        expect(c.mode, entry.$1);
        expect(state.unlocked, isFalse);
        expect(state.passwordController.text, 'synthetic');
        expect(state.message, isNull);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await tester.binding.setSurfaceSize(null);
    }
  });
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final mode in AppAppearance.values) {
      testWidgets(
          '${platform.name}/${mode.name}: existing menus and maintenance dialogs',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        await tester.binding.setSurfaceSize(platform == TargetPlatform.windows
            ? const Size(1280, 900)
            : const Size(360, 800));
        final c = AppearanceController(initial: mode);
        try {
          await tester
              .pumpWidget(themed(c, const VaultShell(initiallyUnlocked: true)));
          await tester.pumpAndSettle();
          final dynamic state = tester.state(find.byType(VaultShell));
          final context = tester.element(find.byType(VaultShell));
          final template = builtInTemplates().first;
          final item = SecretItem(
              id: 'synthetic-menu',
              templateId: template.id,
              title: 'Тестовая запись',
              category: '',
              colorId: 'template_white',
              values: const {},
              modifiedAt: DateTime.utc(2026));
          state.setState(() {
            state.items = [item];
          });
          await tester.pumpAndSettle();
          Future<void> inspect(String name, void Function() open) async {
            open();
            await tester.pumpAndSettle();
            expect(Navigator.of(context).canPop(), isTrue, reason: name);
            await captureAppearance(
                tester, 'catalog-${mode.name}-${platform.name}-$name');
            expect(tester.takeException(), isNull, reason: name);
            Navigator.of(context).pop();
            await tester.pumpAndSettle();
          }

          const position = Offset(120, 120);
          await inspect('card-menu',
              () => unawaited(state.showSpbCardMenu(item, position)));
          await inspect('template-menu',
              () => unawaited(state.showSpbTemplateMenu(template, position)));
          await inspect(
              'template-folder-menu',
              () => unawaited(
                  state.showSpbTemplateImportMenu(position, folder: 'Другие')));
          await inspect('creation-menu',
              () => unawaited(state.showSpbCreationMenu(position)));
          await inspect(
              'undo-menu', () => unawaited(state.showSessionUndoMenu()));
          await inspect(
              'new-database', () => unawaited(state.createNewVaultFromLogin()));
          await inspect('change-password',
              () => unawaited(state.openChangePasswordDialog()));
          await inspect(
              'inactivity', () => unawaited(state.showInactivityWarning()));
          await inspect('delete-card',
              () => unawaited(state.deleteItemWithConfirmation(item)));
          expect(state.items, contains(item));
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          debugDefaultTargetPlatformOverride = null;
          await tester.binding.setSurfaceSize(null);
        }
      });
    }
  }
}
