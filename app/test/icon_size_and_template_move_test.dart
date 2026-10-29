import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:sqlite3/sqlite3.dart';
import 'package:wallet_aps/data/legacy_swl/legacy_swl_codec.dart';
import 'package:wallet_aps/features/templates/template_folders.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/services/wallet_integrity_service.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_attachment_codec.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_crypto.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';

// Stored icons are at most 128×128, and templates move between folders by
// dragging. Synthetic data only.

Uint8List _png(int width, int height) => Uint8List.fromList(image.encodePng(
      image.Image(width: width, height: height, numChannels: 4)
        ..clear(image.ColorRgba8(200, 30, 30, 255)),
    ));

Uint8List _ico(int side) => image.encodeIco(
      image.Image(width: side, height: side, numChannels: 4)
        ..clear(image.ColorRgba8(30, 30, 200, 255)),
    );

image.Image _decodeIco(Uint8List bytes) =>
    image.IcoDecoder().decodeImageLargest(bytes)!;

/// The wallet is written to disk with real I/O, which the fake clock of
/// pumpAndSettle does not wait for.
Future<void> _settleWrites(WidgetTester tester) async {
  for (var pass = 0; pass < 3; pass++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  group('icon size limit', () {
    test('larger icons become 128×128, smaller ones stay unchanged', () {
      final big = _decodeIco(LegacySwlCodec.shrinkOversizedIcon(_ico(256))!);
      expect((big.width, big.height), (128, 128));
      final wide = _decodeIco(
        LegacySwlCodec.shrinkOversizedIcon(_png(300, 150))!,
      );
      expect((wide.width, wide.height), (128, 128));
      // Proportions are kept: the strip above the 128×64 picture is empty.
      expect(wide.getPixel(64, 10).a, 0);
      expect(wide.getPixel(64, 64).a, 255);
      expect(LegacySwlCodec.shrinkOversizedIcon(_ico(128)), isNull);
      expect(LegacySwlCodec.shrinkOversizedIcon(_ico(48)), isNull);
      expect(LegacySwlCodec.shrinkOversizedIcon(_png(100, 128)), isNull);
    });

    test('a newly stored ICO icon larger than 128×128 is reduced', () {
      final stored = _decodeIco(LegacySwlCodec.embeddedIconIco(_ico(256)));
      expect((stored.width, stored.height), (128, 128));
      final small = _ico(64);
      expect(LegacySwlCodec.embeddedIconIco(small), small);
    });

    test('"Проверить и восстановить базу" reduces stored large icons', () {
      final dir = Directory.systemTemp.createTempSync('wallet-icon-size-');
      final path = '${dir.path}/icons.swl';
      SpbWalletDatabase.create(path, 'test-password').close();
      final crypto = SpbWalletCrypto('test-password');
      final codec = SpbWalletAttachmentCodec(crypto);
      final db = sqlite3.open(path);
      try {
        final small = _ico(64);
        for (final (id, bytes) in [
          ('bigIcon', _ico(256)),
          ('smallIcon', small)
        ]) {
          db.execute(
            'INSERT INTO spbwlt_Icon (ID, Name, Data) VALUES (?, ?, ?)',
            [id, crypto.encryptText('$id.ico'), codec.encode(bytes)],
          );
        }
        final report = WalletIntegrityService.repair(db, crypto, codec);
        expect(report.resizedIcons, 1);
        expect(report.userMessage, contains('Иконок уменьшено до 128×128: 1.'));
        Uint8List stored(String id) => codec
            .decode(db.select('SELECT Data FROM spbwlt_Icon WHERE ID = ?',
                [id]).single['Data'])
            .bytes;
        final big = _decodeIco(stored('bigIcon'));
        expect((big.width, big.height), (128, 128));
        expect(stored('smallIcon'), small);
        expect(
            WalletIntegrityService.repair(db, crypto, codec).resizedIcons, 0);
      } finally {
        db.dispose();
        dir.deleteSync(recursive: true);
      }
    });

    test('a multi-frame ICO with a 256 px frame is reduced from that frame',
        () {
      image.Image frame(int side) =>
          image.Image(width: side, height: side, numChannels: 4)
            ..clear(image.ColorRgba8(10, 120, 10, 255));
      for (final sides in const [
        [256, 48],
        [16, 256],
        [256, 128, 32],
      ]) {
        final ico = Uint8List.fromList(
          image.IcoEncoder().encodeImages([for (final s in sides) frame(s)]),
        );
        expect(LegacySwlCodec.largestIcoFrame(ico)!.width, 256);
        final shrunk = LegacySwlCodec.shrinkOversizedIcon(ico);
        expect(shrunk, isNotNull, reason: '$sides');
        expect(_decodeIco(shrunk!).width, 128);
        // The result is not flagged again, so a base is rewritten once.
        expect(LegacySwlCodec.iconExceedsLimit(shrunk), isFalse);
      }
    });

    test('the size check reads the ICO directory', () {
      expect(LegacySwlCodec.iconExceedsLimit(_ico(256)), isTrue);
      expect(LegacySwlCodec.iconExceedsLimit(_ico(200)), isTrue);
      expect(LegacySwlCodec.iconExceedsLimit(_ico(128)), isFalse);
      expect(LegacySwlCodec.iconExceedsLimit(_ico(32)), isFalse);
      expect(LegacySwlCodec.iconExceedsLimit(_png(300, 100)), isTrue);
      expect(LegacySwlCodec.iconExceedsLimit(_png(64, 64)), isFalse);
    });

    test('large icons of a base are counted and reduced in one step', () {
      final dir = Directory.systemTemp.createTempSync('wallet-icon-open-');
      final path = '${dir.path}/icons.swl';
      SpbWalletDatabase.create(path, 'test-password').close();
      final crypto = SpbWalletCrypto('test-password');
      final codec = SpbWalletAttachmentCodec(crypto);
      final small = _ico(48);
      final db = sqlite3.open(path);
      for (final (id, bytes) in [
        ('big1', _ico(256)),
        ('big2', _ico(160)),
        ('small', small),
      ]) {
        db.execute(
          'INSERT INTO spbwlt_Icon (ID, Name, Data) VALUES (?, ?, ?)',
          [id, crypto.encryptText('$id.ico'), codec.encode(bytes)],
        );
      }
      db.dispose();
      final wallet = SpbWalletDatabase.open(path, 'test-password');
      try {
        expect(wallet.countOversizedIcons(), 2);
        expect(wallet.shrinkOversizedIcons(), 2);
        expect(wallet.countOversizedIcons(), 0);
        expect(wallet.shrinkOversizedIcons(), 0);
      } finally {
        wallet.close();
      }
      final check = sqlite3.open(path);
      try {
        Uint8List stored(String id) => codec
            .decode(check.select('SELECT Data FROM spbwlt_Icon WHERE ID = ?',
                [id]).single['Data'])
            .bytes;
        for (final id in ['big1', 'big2']) {
          final icon = _decodeIco(stored(id));
          expect((icon.width, icon.height), (128, 128));
        }
        expect(stored('small'), small);
      } finally {
        check.dispose();
        dir.deleteSync(recursive: true);
      }
    });
  });

  test('a moved template name follows its new folder', () {
    expect(templateNameInFolder('Финансы: Мой банк', 'Интернет'),
        'Интернет: Мой банк');
    expect(templateNameInFolder('Мой банк', 'Интернет'), 'Мой банк');
  });

  testWidgets('templates are dragged with the mouse between folders',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    final temp = Directory.systemTemp.createTempSync('wallet-template-move-');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.binding.setSurfaceSize(null);
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });
    try {
      final wallet = SpbWalletDatabase.create(
        '${temp.path}${Platform.pathSeparator}templates.swl',
        '1234',
      );
      final templateId = SpbWalletDatabase.makeId();
      wallet.saveTemplate(SpbWalletTemplateDraft(
        id: templateId,
        name: 'Финансы: Мой банк',
        fields: const [],
      ));
      await tester.pumpWidget(
        const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
      );
      await tester.pumpAndSettle();
      final dynamic state = tester.state(find.byType(VaultShell));
      state.setState(() {
        state.spbWallet = wallet;
        state.spbWalletPath = wallet.path;
        state.spbWalletDisplayPath = wallet.path;
        state.spbWalletWritable = true;
        state.applySpbSnapshot(wallet.loadSnapshot());
      });
      state.showSpbTemplatesMode();
      await tester.pumpAndSettle();
      state.openSpbTemplateFolder('Финансы');
      await tester.pumpAndSettle();

      SpbWalletTemplateRecord stored() => wallet
          .loadSnapshot()
          .templates
          .singleWhere((template) => template.id == templateId);

      final source = find.byKey(ValueKey('spbCentralTemplate-$templateId'));
      expect(source, findsOneWidget);
      final target =
          find.byKey(const ValueKey('spbTemplateFolderDrop-Интернет'));
      final mouse = await tester.startGesture(
        tester.getCenter(source),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(24, 0));
      await tester.pump();
      await mouse.moveTo(tester.getCenter(target));
      await tester.pump();
      await mouse.up();
      await _settleWrites(tester);
      expect(stored().name, 'Интернет: Мой банк');
      expect(state.selectedTemplateFolder, 'Интернет');

      // Dropping on the folder it is already in changes nothing.
      final CardTemplate current = (state.templates as List)
          .cast<CardTemplate>()
          .singleWhere((template) => template.id == templateId);
      await state.moveSpbTemplatesToFolder(current, 'Интернет');
      await _settleWrites(tester);
      expect(stored().name, 'Интернет: Мой банк');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
