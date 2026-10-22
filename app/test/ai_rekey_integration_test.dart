import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wallet_aps/services/wallet_rekey_service.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_attachment_codec.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_crypto.dart';

// Synthetic minimal legacy schema: never reads a personal wallet or fixture.
void main() {
  late Directory directory;
  late String path;
  final oldCrypto = SpbWalletCrypto('synthetic-old');
  final newCrypto = SpbWalletCrypto('synthetic-new');

  setUp(() {
    directory = Directory.systemTemp.createTempSync('aps_rekey_test_');
    path = '${directory.path}/synthetic.swl';
    final db = sqlite3.open(path);
    try {
      db.execute('CREATE TABLE spbwlt_Category (Name BLOB, Description BLOB)');
      db.execute('CREATE TABLE spbwlt_CardAttachment (Name BLOB, Data BLOB)');
      db.execute('CREATE TABLE unknown_metadata (value TEXT)');
      db.execute("INSERT INTO unknown_metadata VALUES ('preserve me')");
      for (final name in [
        'Category Alpha',
        'Category Beta',
        'Category Gamma'
      ]) {
        db.execute('INSERT INTO spbwlt_Category VALUES (?, NULL)',
            [oldCrypto.encryptText(name)]);
      }
      db.execute('INSERT INTO spbwlt_CardAttachment VALUES (?, ?)', [
        oldCrypto.encryptText('sample.bin'),
        SpbWalletAttachmentCodec(oldCrypto).encode([0, 1, 127, 255]),
      ]);
    } finally {
      db.dispose();
    }
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('rekey persists text and attachment bytes and retains unknown tables',
      () {
    WalletRekeyService.rekeyFile(path,
        oldPassword: 'synthetic-old', newPassword: 'synthetic-new');
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      expect(
        db
            .select('SELECT Name FROM spbwlt_Category ORDER BY rowid')
            .map((row) => newCrypto.decryptText(row['Name'])),
        ['Category Alpha', 'Category Beta', 'Category Gamma'],
      );
      final attachment =
          db.select('SELECT * FROM spbwlt_CardAttachment').single;
      expect(newCrypto.decryptText(attachment['Name']), 'sample.bin');
      expect(
          SpbWalletAttachmentCodec(newCrypto).decode(attachment['Data']).bytes,
          [0, 1, 127, 255]);
      expect(db.select('SELECT value FROM unknown_metadata').single['value'],
          'preserve me');
      expect(
          db
              .select('SELECT Description FROM spbwlt_Category')
              .first['Description'],
          isNull);
      expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
    } finally {
      db.dispose();
    }
  });

  test('corrupt attachment rolls back text already re-encrypted in transaction',
      () {
    final db = sqlite3.open(path);
    late Uint8List before;
    try {
      before = Uint8List.fromList(db
          .select('SELECT Name FROM spbwlt_Category')
          .first['Name'] as List<int>);
      db.execute('UPDATE spbwlt_CardAttachment SET Data = ?', [Uint8List(3)]);
    } finally {
      db.dispose();
    }
    expect(
      () => WalletRekeyService.rekeyFile(path,
          oldPassword: 'synthetic-old', newPassword: 'synthetic-new'),
      throwsA(isA<SpbWalletCryptoException>()),
    );
    final reopened = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final row = reopened.select('SELECT Name FROM spbwlt_Category').first;
      expect(row['Name'], before);
      expect(oldCrypto.decryptText(row['Name']), 'Category Alpha');
      expect(
          reopened.select('PRAGMA integrity_check').single.values.single, 'ok');
    } finally {
      reopened.dispose();
    }
  });
}
