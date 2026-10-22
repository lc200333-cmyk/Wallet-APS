import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wallet_aps/controllers/entity_index.dart';
import 'package:wallet_aps/data/legacy_swl/legacy_swl_codec.dart';
import 'package:wallet_aps/domain/card_layout.dart';
import 'package:wallet_aps/features/cards/field_projection.dart';
import 'package:wallet_aps/features/categories/category_path_index.dart';
import 'package:wallet_aps/features/templates/template_order.dart';
import 'package:wallet_aps/services/wallet_rekey_service.dart';
import 'package:wallet_aps/services/wallet_integrity_service.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_attachment_codec.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_crypto.dart';

void main() {
  test(
      'synthetic legacy repair restores orphan references without losing values',
      () {
    final dir = Directory.systemTemp.createTempSync('wallet-repair-test-');
    final path = '${dir.path}/synthetic.swl';
    SpbWalletDatabase.create(path, 'test-password').close();
    final crypto = SpbWalletCrypto('test-password');
    final codec = SpbWalletAttachmentCodec(crypto);
    final db = sqlite3.open(path);
    try {
      db.execute('INSERT INTO spbwlt_CardView '
          '(ID, CardColor, CornerType, ShowHiddenFields, IconID, ImageID) '
          "VALUES ('view1', '123', 0, 0, '', '')");
      db.execute(
          'INSERT INTO spbwlt_Card '
          '(ID, Name, CardViewID, TemplateID, ParentCategoryID, IconID) '
          "VALUES ('card1', ?, 'view1', 'missing', '', '')",
          [crypto.encryptText('Synthetic card')]);
      final encryptedValue = crypto.encryptText('Keep this synthetic value');
      db.execute(
          'INSERT INTO spbwlt_CardFieldValue '
          '(ID, CardID, TemplateFieldID, ValueString) '
          "VALUES ('value1', 'card1', 'field1', ?)",
          [encryptedValue]);
      final before = WalletIntegrityService.inspect(db, attachments: codec);
      expect(before.orphanCards, 1);
      expect(before.orphanValues, 1);
      expect(before.nonIntegerColors, 1);
      final repair = WalletIntegrityService.repair(db, crypto, codec);
      expect(repair.repairedTemplates, 1);
      expect(repair.repairedFields, 1);
      expect(WalletIntegrityService.inspect(db, attachments: codec).hasProblems,
          isFalse);
      expect(
          db
              .select('SELECT ValueString FROM spbwlt_CardFieldValue')
              .single['ValueString'],
          encryptedValue);
      expect(
          db
              .select('SELECT TemplateID FROM spbwlt_TemplateField')
              .single['TemplateID'],
          'missing');
      expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
      final repeated = WalletIntegrityService.repair(db, crypto, codec);
      expect(repeated.repairedTemplates, 0);
      expect(repeated.repairedFields, 0);
    } finally {
      db.dispose();
      dir.deleteSync(recursive: true);
    }
  });

  test('category cycles terminate and missing parents preserve names', () {
    final paths = buildCategoryPathsById(
      [('a', 'b', ' A '), ('b', 'a', 'B'), ('c', 'absent', ' AC/DC ')],
      idOf: (row) => row.$1,
      parentIdOf: (row) => row.$2,
      nameOf: (row) => row.$3,
    );
    expect(paths, {'a': 'B / A', 'b': 'A / B', 'c': 'AC/DC'});
  });

  test('duplicate entity ID retains last entry', () {
    expect(indexEntitiesById([('x', 1), ('x', 2)], (row) => row.$1),
        {'x': ('x', 2)});
  });

  test('field projection preserves orphan values and removes duplicates', () {
    expect(
      projectVisibleFieldIds(
        definedIds: ['a', 'b', 'a'],
        valueIds: ['orphan', 'b'],
        preferredOrder: ['missing', 'orphan', 'orphan'],
        hiddenIds: {'b'},
      ),
      ['orphan', 'a'],
    );
  });

  test('case-insensitive template names use ID as tie breaker', () {
    expect(compareNamedEntities('ABC', '1', 'abc', '2'), lessThan(0));
    expect(compareNamedEntities('b', '1', 'A', '9'), greaterThan(0));
  });

  test('layout serializes hidden IDs deterministically and preserves date', () {
    final original = CardLayoutState(
      fieldOrder: ['b', 'a'],
      hiddenFieldIds: {'z', 'a'},
      modifiedAt: DateTime.utc(2020),
    );
    expect(original.encodeLayout(), '{"order":["b","a"],"hidden":["a","z"]}');
    final decoded =
        CardLayoutState.decodeLayout(original.encodeLayout(), original);
    expect(decoded.fieldOrder, ['b', 'a']);
    expect(decoded.hiddenFieldIds, {'a', 'z'});
    expect(decoded.modifiedAt, original.modifiedAt);
    for (final malformed in ['{', '[]', '{"order":[1]}']) {
      expect(CardLayoutState.decodeLayout(malformed, original), same(original));
    }
  });

  test('legacy ID bytes and color masking keep format conventions', () {
    expect(LegacySwlCodec.idBytes('0041ff'), [0, 65, 255]);
    expect(() => LegacySwlCodec.idBytes('abc'), throwsFormatException);
    expect(() => LegacySwlCodec.idBytes('zz'), throwsFormatException);
    expect(LegacySwlCodec.cardColor(0xff123456), 0x123456);
  });

  test('attachment round trips empty and binary data across AES boundaries',
      () {
    final codec =
        SpbWalletAttachmentCodec(SpbWalletCrypto('synthetic-password'));
    for (final length in [0, 1, 15, 16, 17, 255, 4096]) {
      final bytes = List.generate(length, (i) => i % 256);
      expect(codec.decode(codec.encode(bytes)).bytes, bytes);
    }
  });

  test('attachment rejects wrong declared length and malformed ciphertext', () {
    final crypto = SpbWalletCrypto('synthetic-password');
    final codec = SpbWalletAttachmentCodec(crypto);
    final compressed = zlib.encode([1, 2, 3]);
    final payload = Uint8List(4 + compressed.length)..setAll(4, compressed);
    ByteData.sublistView(payload).setUint32(0, 99, Endian.little);
    expect(() => codec.decode(crypto.encryptRawWithOuterPrefix(payload)),
        throwsA(isA<SpbWalletAttachmentException>()));
    expect(() => codec.decode(Uint8List.fromList([1, 2])),
        throwsA(isA<SpbWalletCryptoException>()));
  });

  for (final corrupt in [false, true]) {
    test(
        'synthetic SQLite rekey ${corrupt ? 'rolls back on corruption' : 'preserves data and unknown metadata'}',
        () {
      final dir = Directory.systemTemp.createTempSync('wallet-rekey-test-');
      final path = '${dir.path}/synthetic.swl';
      final oldCrypto = SpbWalletCrypto('old-test-password');
      final originalName = oldCrypto.encryptText('Synthetic category');
      final originalPayload = corrupt
          ? Uint8List.fromList([1, 2])
          : SpbWalletAttachmentCodec(oldCrypto).encode([0, 1, 255]);
      var db = sqlite3.open(path);
      try {
        db.execute('CREATE TABLE spbwlt_Category (Name BLOB)');
        db.execute('CREATE TABLE spbwlt_CardAttachment (Data BLOB)');
        db.execute('CREATE TABLE custom_metadata (value TEXT)');
        db.execute('INSERT INTO spbwlt_Category VALUES (?)', [originalName]);
        db.execute(
            'INSERT INTO spbwlt_CardAttachment VALUES (?)', [originalPayload]);
        db.execute("INSERT INTO custom_metadata VALUES ('preserve-me')");
      } finally {
        db.dispose();
      }
      try {
        void rekey() => WalletRekeyService.rekeyFile(path,
            oldPassword: 'old-test-password', newPassword: 'new-test-password');
        if (corrupt) {
          expect(rekey, throwsA(isA<SpbWalletCryptoException>()));
        } else {
          rekey();
        }
        db = sqlite3.open(path);
        try {
          final name =
              db.select('SELECT Name FROM spbwlt_Category').single['Name'];
          final data = db
              .select('SELECT Data FROM spbwlt_CardAttachment')
              .single['Data'];
          expect(db.select('SELECT value FROM custom_metadata').single['value'],
              'preserve-me');
          expect(
              db.select('PRAGMA integrity_check').single.values.single, 'ok');
          if (corrupt) {
            expect(name, originalName);
            expect(data, originalPayload);
          } else {
            expect(name, isNot(originalName));
            final newCrypto = SpbWalletCrypto('new-test-password');
            expect(newCrypto.decryptText(name), 'Synthetic category');
            expect(SpbWalletAttachmentCodec(newCrypto).decode(data).bytes,
                [0, 1, 255]);
          }
        } finally {
          db.dispose();
        }
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  }
}
