import 'package:sqlite3/sqlite3.dart';

import '../spb_wallet/spb_wallet_attachment_codec.dart';
import '../spb_wallet/spb_wallet_crypto.dart';

abstract final class WalletRekeyService {
  static const Map<String, List<String>> _encryptedTextColumns = {
    'actitpass_TemplateFolder': ['Name'],
    'spbwlt_Category': ['Name', 'Description'],
    'spbwlt_Card': ['Name', 'Description'],
    'spbwlt_CardAttachment': ['Name'],
    'spbwlt_CardFieldValue': ['ValueString'],
    'spbwlt_Icon': ['Name'],
    'spbwlt_Image': ['Name'],
    'spbwlt_Template': ['Name', 'Description'],
    'spbwlt_TemplateField': ['Name'],
  };

  static const Map<String, List<String>> _encryptedPayloadColumns = {
    'spbwlt_CardAttachment': ['Data'],
    'spbwlt_Icon': ['Data'],
    'spbwlt_Image': ['Data'],
  };

  static void rekeyFile(
    String path, {
    required String oldPassword,
    required String newPassword,
  }) {
    final database = sqlite3.open(path);
    final oldCrypto = SpbWalletCrypto(oldPassword);
    final newCrypto = SpbWalletCrypto(newPassword);
    final oldAttachments = SpbWalletAttachmentCodec(oldCrypto);
    final newAttachments = SpbWalletAttachmentCodec(newCrypto);
    try {
      _validatePassword(database, oldCrypto);
      database.execute('BEGIN IMMEDIATE');
      try {
        for (final tableEntry in _encryptedTextColumns.entries) {
          if (!_hasTable(database, tableEntry.key)) continue;
          final columns = _columns(database, tableEntry.key);
          for (final column in tableEntry.value.where(columns.contains)) {
            final rows = database.select(
              'SELECT rowid AS source_rowid, "$column" AS encrypted '
              'FROM "${tableEntry.key}" WHERE "$column" IS NOT NULL',
            );
            for (final row in rows) {
              final plain = oldCrypto.decryptText(row['encrypted']);
              database.execute(
                'UPDATE "${tableEntry.key}" SET "$column" = ? WHERE rowid = ?',
                [newCrypto.encryptText(plain), row['source_rowid']],
              );
            }
          }
        }
        for (final tableEntry in _encryptedPayloadColumns.entries) {
          if (!_hasTable(database, tableEntry.key)) continue;
          final columns = _columns(database, tableEntry.key);
          for (final column in tableEntry.value.where(columns.contains)) {
            final rows = database.select(
              'SELECT rowid AS source_rowid, "$column" AS encrypted '
              'FROM "${tableEntry.key}" WHERE "$column" IS NOT NULL',
            );
            for (final row in rows) {
              final plain = oldAttachments.decode(row['encrypted']).bytes;
              database.execute(
                'UPDATE "${tableEntry.key}" SET "$column" = ? WHERE rowid = ?',
                [newAttachments.encode(plain), row['source_rowid']],
              );
            }
          }
        }
        final integrity =
            database.select('PRAGMA integrity_check').first.values.first;
        if (integrity != 'ok') {
          throw StateError('SQLite integrity check failed: $integrity');
        }
        database.execute('COMMIT');
      } catch (_) {
        database.execute('ROLLBACK');
        rethrow;
      }
    } finally {
      database.dispose();
    }
  }

  static void _validatePassword(Database database, SpbWalletCrypto crypto) {
    final samples = <Object?>[];
    for (final pair in const [
      ('spbwlt_Category', 'Name'),
      ('spbwlt_Card', 'Name'),
      ('spbwlt_TemplateField', 'Name'),
    ]) {
      if (!_hasTable(database, pair.$1)) continue;
      samples.addAll(
        database
            .select('SELECT "${pair.$2}" AS value FROM "${pair.$1}" LIMIT 3')
            .map((row) => row['value']),
      );
    }
    if (samples.isEmpty) return;
    final valid = samples.where(crypto.looksLikeValidText).length;
    if (valid < (samples.length >= 3 ? 2 : 1)) {
      throw const SpbWalletCryptoException(
        'Пароль SPB Wallet не подходит или база повреждена.',
      );
    }
  }

  static bool _hasTable(Database database, String name) => database.select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
        [name],
      ).isNotEmpty;

  static Set<String> _columns(Database database, String table) => database
      .select('PRAGMA table_info("$table")')
      .map((row) => row['name'].toString())
      .toSet();
}
