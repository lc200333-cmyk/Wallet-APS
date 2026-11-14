import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';

void main() {
  test('persistent vault references are limited to mobile and Apple targets',
      () {
    expect(platformUsesPersistentVaultReferences(TargetPlatform.iOS), isTrue);
    expect(
      platformUsesPersistentVaultReferences(TargetPlatform.macOS),
      isTrue,
    );
    expect(
      platformUsesPersistentVaultReferences(TargetPlatform.android),
      isTrue,
    );
    expect(
      platformUsesPersistentVaultReferences(TargetPlatform.windows),
      isFalse,
    );
    expect(
      platformUsesPersistentVaultReferences(TargetPlatform.linux),
      isFalse,
    );
  });

  test('Apple unlock resumes when password arrives during bookmark restore',
      () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      expect(
        shouldResumeAppleVaultUnlock(
          platform,
          vaultUri: 'apple-bookmark:test',
          password: '2468',
        ),
        isTrue,
      );
    }
    expect(
      shouldResumeAppleVaultUnlock(
        TargetPlatform.windows,
        vaultUri: 'apple-bookmark:test',
        password: '2468',
      ),
      isFalse,
    );
    expect(
      shouldResumeAppleVaultUnlock(
        TargetPlatform.iOS,
        vaultUri: 'apple-bookmark:test',
        password: '',
      ),
      isFalse,
    );
  });

  test('Apple runners persist and restore security-scoped bookmarks', () {
    final macSource =
        File('macos/Runner/MainFlutterWindow.swift').readAsStringSync();
    final iosSource = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    for (final source in [macSource, iosSource]) {
      expect(source, contains('case "pickSpbWallet"'));
      expect(source, contains('case "copySpbWallet"'));
      expect(source, contains('case "writeSpbWallet"'));
      expect(source, contains('startAccessingSecurityScopedResource()'));
      expect(source, contains('stopAccessingSecurityScopedResource()'));
    }
    expect(macSource, contains('options: .withSecurityScope'));
  });
}
