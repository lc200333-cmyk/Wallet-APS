import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/app_version.dart';
import 'package:wallet_aps/design_distribution.dart';
import 'package:wallet_aps/main.dart';

class RejectNetwork extends HttpOverrides {
  int requests = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    requests++;
    throw StateError('Design must not fetch private updates anonymously');
  }
}

void main() {
  test('profile is a separate child without migrating stable settings', () {
    final base = Directory('synthetic-support');
    expect(
      designSupportDirectory(base).path,
      '${base.path}${Platform.pathSeparator}Wallet APS Design',
    );
    expect(
      designReleasesUrl,
      'https://github.com/lc200333-cmyk/Wallet-APS-Design/releases',
    );
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.android,
      TargetPlatform.linux,
    ]) {
      expect(
        updatePackageForPlatform(platform, '1.2.3')!.downloadUri.path,
        startsWith('/lc200333-cmyk/Wallet-APS-Design/releases/'),
      );
    }
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets(
      'private releases use browser, not network on ${platform.name}',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final previous = HttpOverrides.current;
        final network = RejectNetwork();
        HttpOverrides.global = network;
        var opened = 0;
        try {
          await tester.binding.setSurfaceSize(const Size(360, 640));
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PasswordVersionLabel(
                  releasesOpener: () async {
                    opened++;
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Design v. $currentAppVersion'), findsOneWidget);
          expect(find.byKey(const Key('availableGithubVersion')), findsNothing);
          await tester.tap(find.byKey(const Key('designReleasesButton')));
          await tester.pumpAndSettle();
          expect(opened, 1);
          expect(network.requests, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          HttpOverrides.global = previous;
          debugDefaultTargetPlatformOverride = null;
          await tester.binding.setSurfaceSize(null);
        }
      },
    );
  }
}
