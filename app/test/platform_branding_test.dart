import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

bool iconReferenceExists(String reference) {
  final uri = Uri.tryParse(reference);
  if (uri != null && const {'spb', 'third-party'}.contains(uri.scheme)) {
    return true;
  }
  return File(reference).existsSync();
}

void main() {
  test('virtual icon references are not treated as filesystem paths', () {
    expect(iconReferenceExists('spb://card/key.png'), isTrue);
    expect(iconReferenceExists('third-party://icos/icon_01.png'), isTrue);
    expect(iconReferenceExists('missing/icon.png'), isFalse);
  });

  test('transparent Wallet APS icon and title are wired into Windows', () {
    final sourceBytes = File(
      'windows/runner/resources/app_icon.source.png',
    ).readAsBytesSync();
    final source = image.decodePng(sourceBytes);
    expect(source, isNotNull);
    expect(source!.width, greaterThanOrEqualTo(256));
    expect(source.height, greaterThanOrEqualTo(256));
    expect(source.numChannels, 4);
    expect(source.getPixel(0, 0).a, 0);

    final ico = File(
      'windows/runner/resources/app_icon.ico',
    ).readAsBytesSync();
    final icoHeader = ByteData.sublistView(ico);
    expect(icoHeader.getUint16(0, Endian.little), 0);
    expect(icoHeader.getUint16(2, Endian.little), 1);
    expect(icoHeader.getUint16(4, Endian.little), 7);
    final largestIco = image.IcoDecoder().decodeImageLargest(ico);
    expect(largestIco, isNotNull);
    expect(largestIco!.getPixel(0, 0).a, 0);

    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:label="Wallet APS"'));
    expect(
      manifest,
      contains('android:icon="@mipmap/launcher_icon"'),
    );
    expect(
      manifest,
      contains('android:roundIcon="@mipmap/launcher_icon"'),
    );
    expect(
      File(
        'android/app/src/main/res/mipmap-anydpi-v26/launcher_icon.xml',
      ).existsSync(),
      isTrue,
    );
    final androidSource = image.decodePng(
      File('assets/branding/wallet_android.png').readAsBytesSync(),
    );
    expect(androidSource, isNotNull);
    expect(
      File('assets/branding/wallet_android.png').readAsBytesSync(),
      orderedEquals(sourceBytes),
    );
    expect(androidSource!.numChannels, 4);
    expect(androidSource.getPixel(0, 0).a, 0);
    expect(androidSource.getPixel(androidSource.width - 1, 0).a, 0);
    expect(androidSource.getPixel(0, androidSource.height - 1).a, 0);
    expect(
      androidSource
          .getPixel(androidSource.width - 1, androidSource.height - 1)
          .a,
      0,
    );
    final androidLauncher = image.decodePng(
      File(
        'android/app/src/main/res/mipmap-xxxhdpi/launcher_icon.png',
      ).readAsBytesSync(),
    );
    expect(androidLauncher, isNotNull);
    expect(androidLauncher!.getPixel(0, 0).a, 0);

    final installer = File(
      '../tools/windows/Wallet-APS.iss',
    ).readAsStringSync();
    expect(installer, contains('app_icon.ico'));
    expect(installer, contains('#define MyAppName "Wallet APS"'));
    expect(installer, contains('#define MyAppExeName "wallet_aps.exe"'));
    expect(
      installer,
      contains('AppPublisherURL=https://github.com/lc200333-cmyk/Wallet-APS'),
    );
    expect(installer, contains(r'UninstallFilesDir={app}\Uninstall'));
    expect(installer, contains('UninstallDisplayIcon={uninstallexe}'));
    final runner = File('windows/runner/main.cpp').readAsStringSync();
    expect(runner, contains('window.Create(L"Wallet APS"'));
    final resources = File('windows/runner/Runner.rc').readAsStringSync();
    expect(resources, contains('VALUE "ProductName", "Wallet APS"'));
    expect(resources, contains('VALUE "OriginalFilename", "wallet_aps.exe"'));
    final windowsBuild = File('windows/CMakeLists.txt').readAsStringSync();
    expect(windowsBuild, contains('set(BINARY_NAME "wallet_aps")'));
    final linuxPackage = File(
      '../tools/build_linux_deb.sh',
    ).readAsStringSync();
    expect(
      linuxPackage,
      contains('windows/runner/resources/app_icon.source.png'),
    );
  });
}
