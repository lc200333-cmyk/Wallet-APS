import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/ui/skin/app_skin.dart';

void main() {
  for (final skin in AppSkin.values) {
    for (final width in [390.0, 1280.0]) {
      for (final create in [true, false]) {
        testWidgets(
            '$skin $width create=$create password keypad returns values',
            (tester) async {
          appSkin.value = skin;
          debugDefaultTargetPlatformOverride =
              width < 700 ? TargetPlatform.android : TargetPlatform.windows;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(() {
            appSkin.value = AppSkin.retro;
            debugDefaultTargetPlatformOverride = null;
            tester.view.resetDevicePixelRatio();
            tester.view.resetPhysicalSize();
          });
          await tester.pumpWidget(
              MaterialApp(home: VaultShell(initiallyUnlocked: !create)));
          await tester.pumpAndSettle();
          final dynamic shell = tester.state(find.byType(VaultShell));
          shell.passwordController.text = 'original-login';
          if (create) {
            shell.createNewVaultFromLogin();
          } else {
            shell.openChangePasswordDialog();
          }
          await tester.pumpAndSettle();

          Finder field(String key) => find.descendant(
              of: find.byKey(Key(key)), matching: find.byType(TextField));
          final firstKey = create ? 'newVaultPassword' : 'changePasswordNew';
          final repeatKey =
              create ? 'newVaultPasswordRepeat' : 'changePasswordRepeat';
          final dialog = find.byKey(const Key('passwordKeypadDialog'));
          Finder keypad(String key) =>
              find.descendant(of: dialog, matching: find.byKey(Key(key)));
          Future<void> tap(String key) async {
            await tester.ensureVisible(keypad(key));
            await tester.tap(keypad(key));
            await tester.pumpAndSettle();
          }

          await tester.tap(field(firstKey));
          await tester.pumpAndSettle();
          expect(dialog, findsOneWidget);
          final entry = keypad('passwordKeypadInput');
          expect(
              tester.widget<TextField>(entry).keyboardType, TextInputType.none);
          expect(
              find.descendant(
                  of: dialog, matching: find.byIcon(Icons.question_mark)),
              findsNothing);
          await tap('keypad1');
          await tap('keypad2');
          await tap('keypadClear');
          await tap('keypad1');
          await tap('keypad2');
          await tap('keypadBackspace');
          await tap('keypadModeUppercase');
          await tap('keypadLetterQ');
          await tap('keypadModeLowercase');
          await tap('keypadLetterw');
          await tap('keypadModeSymbols');
          await tap('keypadSymbol!');
          await tap('keypadModeNumeric');
          await tap('keypad9');
          expect(tester.widget<TextField>(entry).controller!.text, '1Qw!9');
          await tap('passwordKeypadVisibility');
          expect(tester.widget<TextField>(entry).obscureText, isFalse);
          await tap('passwordKeypadConfirm');
          expect(dialog, findsNothing);
          expect(tester.widget<TextField>(field(firstKey)).controller!.text,
              '1Qw!9');
          expect(tester.widget<TextField>(field(repeatKey)).controller!.text,
              isEmpty);
          expect(shell.passwordController.text, 'original-login');

          await tester.tap(field(repeatKey));
          await tester.pumpAndSettle();
          await tester.enterText(entry, '1Qw!9');
          await tap('passwordKeypadConfirm');
          expect(tester.widget<TextField>(field(repeatKey)).controller!.text,
              '1Qw!9');

          // Reopening starts with the saved value. Back cancels local edits.
          await tester.tap(field(firstKey));
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(entry).controller!.text, '1Qw!9');
          await tap('keypadClear');
          Navigator.of(tester.element(entry)).pop();
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(field(firstKey)).controller!.text,
              '1Qw!9');
          final hintKey =
              create ? 'newVaultPasswordHint' : 'changePasswordHint';
          expect(
              tester.widget<TextField>(find.byKey(Key(hintKey))).keyboardType,
              isNot(TextInputType.none));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          debugDefaultTargetPlatformOverride = null;
        });
      }
    }
  }
}
