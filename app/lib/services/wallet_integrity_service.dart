// SQL fragments are composed from private constant table/column allowlists.
// ignore_for_file: prefer_interpolation_to_compose_strings, prefer_single_quotes

import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../data/legacy_swl/legacy_swl_codec.dart';
import '../spb_wallet/spb_wallet_attachment_codec.dart';
import '../spb_wallet/spb_wallet_crypto.dart';

class WalletIntegrityReport {
  const WalletIntegrityReport({
    required this.orphanCards,
    required this.orphanValues,
    required this.blobIds,
    required this.nonIntegerColors,
    required this.pngIcons,
    this.repairedTemplates = 0,
    this.repairedFields = 0,
    this.resizedIcons = 0,
  });

  final int orphanCards;
  final int orphanValues;
  final int blobIds;
  final int nonIntegerColors;
  final int pngIcons;
  final int repairedTemplates;
  final int repairedFields;

  /// Stored icons larger than 128×128 that the repair reduced to 128×128.
  final int resizedIcons;

  bool get hasProblems =>
      orphanCards + orphanValues + blobIds + nonIntegerColors + pngIcons > 0;

  String get userMessage {
    final base = _baseMessage;
    if (resizedIcons == 0) return base;
    return base +
        ' Иконок уменьшено до 128×128: ' +
        resizedIcons.toString() +
        '.';
  }

  String get _baseMessage {
    if (!hasProblems && repairedTemplates == 0 && repairedFields == 0) {
      return 'Проверка базы завершена: структура совместима.';
    }
    if (repairedTemplates > 0 || repairedFields > 0) {
      return 'База восстановлена: шаблонов — ' +
          repairedTemplates.toString() +
          ', полей — ' +
          repairedFields.toString() +
          '. Формат приведён к SPB Wallet 2.1.';
    }
    return 'Найдены данные для восстановления: карточек без шаблона — ' +
        orphanCards.toString() +
        ', полей без описания — ' +
        orphanValues.toString() +
        '. Они будут восстановлены при следующем сохранении.';
  }
}

abstract final class WalletIntegrityService {
  static const Map<String, List<String>> _idColumns = {
    'spbwlt_Wallet': ['ID'],
    'spbwlt_Card': [
      'ID',
      'CardViewID',
      'TemplateID',
      'ParentCategoryID',
      'IconID',
    ],
    'spbwlt_CardAttachment': ['ID', 'CardID'],
    'spbwlt_CardFieldValue': ['ID', 'CardID', 'TemplateFieldID'],
    'spbwlt_CardView': ['ID', 'IconID', 'ImageID'],
    'spbwlt_Category': [
      'ID',
      'IconID',
      'DefaultTemplateID',
      'ParentCategoryID',
    ],
    'spbwlt_Icon': ['ID'],
    'spbwlt_Image': ['ID'],
    'spbwlt_Template': ['ID', 'CardViewID'],
    'spbwlt_TemplateField': ['ID', 'TemplateID'],
    'spbwlt_CardViewField': ['ID', 'CardViewID', 'TemplateFieldID'],
  };

  static WalletIntegrityReport inspect(
    Database database, {
    SpbWalletAttachmentCodec? attachments,
  }) {
    final orphanCards = _count(
      database,
      'SELECT COUNT(*) AS n FROM spbwlt_Card c '
      'LEFT JOIN spbwlt_Template t ON t.ID=c.TemplateID WHERE t.ID IS NULL',
    );
    final orphanValues = _count(
      database,
      'SELECT COUNT(*) AS n FROM spbwlt_CardFieldValue v '
      'LEFT JOIN spbwlt_TemplateField f ON f.ID=v.TemplateFieldID '
      'WHERE f.ID IS NULL',
    );
    var blobIds = 0;
    for (final entry in _idColumns.entries) {
      if (!_hasTable(database, entry.key)) continue;
      final columns = _columns(database, entry.key);
      for (final column in entry.value.where(columns.contains)) {
        blobIds += _count(
          database,
          'SELECT COUNT(*) AS n FROM "' +
              entry.key +
              '" WHERE "' +
              column +
              '" IS NOT NULL AND typeof("' +
              column +
              '")=\'blob\'',
        );
      }
    }
    final nonIntegerColors = _count(
      database,
      "SELECT COUNT(*) AS n FROM spbwlt_CardView "
      "WHERE typeof(CardColor)<>'integer'",
    );
    var pngIcons = 0;
    if (attachments != null && _hasTable(database, 'spbwlt_Icon')) {
      for (final row in database
          .select('SELECT Data FROM spbwlt_Icon WHERE Data IS NOT NULL')) {
        try {
          final data = attachments.decode(row['Data']).bytes;
          if (!LegacySwlCodec.isIco(data)) pngIcons++;
        } catch (_) {
          pngIcons++;
        }
      }
    }
    return WalletIntegrityReport(
      orphanCards: orphanCards,
      orphanValues: orphanValues,
      blobIds: blobIds,
      nonIntegerColors: nonIntegerColors,
      pngIcons: pngIcons,
    );
  }

  static WalletIntegrityReport repair(
    Database database,
    SpbWalletCrypto crypto,
    SpbWalletAttachmentCodec attachments,
  ) {
    final before = inspect(database, attachments: attachments);
    var repairedTemplates = 0;
    var repairedFields = 0;
    var resizedIcons = 0;
    database.execute('BEGIN IMMEDIATE');
    try {
      // Normalize storage classes first. SQLite does not consider a BLOB and
      // TEXT value equal even when their bytes are identical, which made
      // newly written cards look as if their templates and fields vanished.
      for (final entry in _idColumns.entries) {
        if (!_hasTable(database, entry.key)) continue;
        final columns = _columns(database, entry.key);
        for (final column in entry.value.where(columns.contains)) {
          database.execute(
            'UPDATE "' +
                entry.key +
                '" SET "' +
                column +
                '"=CAST("' +
                column +
                '" AS TEXT) WHERE "' +
                column +
                '" IS NOT NULL AND typeof("' +
                column +
                '")=\'blob\'',
          );
        }
      }
      final orphanCards = database.select(
        'SELECT c.rowid AS card_rowid, c.TemplateID AS TemplateID, '
        'c.CardViewID AS CardViewID, c.Name AS Name '
        'FROM spbwlt_Card c LEFT JOIN spbwlt_Template t '
        'ON t.ID=c.TemplateID WHERE t.ID IS NULL',
      );
      for (final card in orphanCards) {
        final title = crypto.decryptText(card['Name']);
        database.execute(
          'INSERT INTO spbwlt_Template '
          '(ID, Name, Description, CardViewID, SyncID, CreateSyncID) '
          'VALUES (CAST(? AS TEXT), ?, NULL, CAST(? AS TEXT), -1, -1)',
          [
            _bytes(card['TemplateID']),
            crypto.encryptText('Восстановлено: ' + title),
            _bytes(card['CardViewID']),
          ],
        );
        repairedTemplates++;
        final fields = database.select(
          'SELECT DISTINCT v.TemplateFieldID AS FieldID '
          'FROM spbwlt_CardFieldValue v '
          'LEFT JOIN spbwlt_TemplateField f ON f.ID=v.TemplateFieldID '
          'WHERE v.CardID=(SELECT ID FROM spbwlt_Card WHERE rowid=?) '
          'AND f.ID IS NULL ORDER BY hex(v.TemplateFieldID)',
          [card['card_rowid']],
        );
        for (var index = 0; index < fields.length; index++) {
          final fieldId = _bytes(fields[index]['FieldID']);
          database.execute(
            'INSERT INTO spbwlt_TemplateField '
            '(ID, Name, TemplateID, FieldTypeID, Priority, SyncID, CreateSyncID) '
            'VALUES (CAST(? AS TEXT), ?, CAST(? AS TEXT), 1, ?, -1, -1)',
            [
              fieldId,
              crypto.encryptText('Сохранённое поле ' + (index + 1).toString()),
              _bytes(card['TemplateID']),
              index,
            ],
          );
          database.execute(
            'INSERT INTO spbwlt_CardViewField '
            '(ID, CardViewID, TemplateFieldID, PositionX, PositionY, '
            'FontFamily, FontSize, FontColor, TextStyle, TextAlign, '
            'ShowFieldName, SyncID, CreateSyncID) '
            'VALUES (CAST(? AS TEXT), CAST(? AS TEXT), CAST(? AS TEXT), '
            '0, ?, \'Tahoma\', 10, \'0\', 0, 0, 1, -1, -1)',
            [
              LegacySwlCodec.idBytes(LegacySwlCodec.makeHexId()),
              _bytes(card['CardViewID']),
              fieldId,
              index * 24,
            ],
          );
          repairedFields++;
        }
      }

      for (final entry in _idColumns.entries) {
        if (!_hasTable(database, entry.key)) continue;
        final columns = _columns(database, entry.key);
        for (final column in entry.value.where(columns.contains)) {
          database.execute(
            'UPDATE "' +
                entry.key +
                '" SET "' +
                column +
                '"=CAST("' +
                column +
                '" AS TEXT) WHERE "' +
                column +
                '" IS NOT NULL AND typeof("' +
                column +
                '")=\'blob\'',
          );
        }
      }
      database.execute(
        'UPDATE spbwlt_CardView '
        'SET CardColor=CAST(CAST(CardColor AS TEXT) AS INTEGER) '
        'WHERE typeof(CardColor)<>\'integer\'',
      );
      if (_hasTable(database, 'spbwlt_Icon')) {
        for (final row in database.select(
          'SELECT rowid AS source_rowid, Name, Data FROM spbwlt_Icon '
          'WHERE Data IS NOT NULL',
        )) {
          final decoded = attachments.decode(row['Data']).bytes;
          if (LegacySwlCodec.isIco(decoded)) continue;
          final ico = LegacySwlCodec.embeddedIconIco(decoded);
          final oldName = crypto.decryptText(row['Name']);
          final dot = oldName.lastIndexOf('.');
          final name = (dot < 0 ? oldName : oldName.substring(0, dot)) + '.ico';
          database.execute(
            'UPDATE spbwlt_Icon SET Name=?, Data=? WHERE rowid=?',
            [
              crypto.encryptText(name),
              attachments.encode(ico),
              row['source_rowid'],
            ],
          );
        }
        resizedIcons = _shrinkIcons(database, attachments);
      }
      final remaining = inspect(database, attachments: attachments);
      if (remaining.orphanCards != 0 || remaining.orphanValues != 0) {
        throw StateError('Не удалось восстановить все связи базы.');
      }
      final integrity =
          database.select('PRAGMA integrity_check').first.values.first;
      if (integrity != 'ok') {
        throw StateError(
            'SQLite integrity check failed: ' + integrity.toString());
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
    return WalletIntegrityReport(
      orphanCards: before.orphanCards,
      orphanValues: before.orphanValues,
      blobIds: before.blobIds,
      nonIntegerColors: before.nonIntegerColors,
      pngIcons: before.pngIcons,
      repairedTemplates: repairedTemplates,
      repairedFields: repairedFields,
      resizedIcons: resizedIcons,
    );
  }

  /// Stored icons wider or taller than 128 px.
  static int countOversizedIcons(
    Database database,
    SpbWalletAttachmentCodec attachments,
  ) {
    if (!_hasTable(database, 'spbwlt_Icon')) return 0;
    var count = 0;
    for (final row in database
        .select('SELECT Data FROM spbwlt_Icon WHERE Data IS NOT NULL')) {
      try {
        final data = attachments.decode(row['Data']).bytes;
        // The directory check is cheap; only icons it flags are decoded, and
        // only icons that really can be reduced count, so a base is not
        // backed up and rewritten on every opening for nothing.
        if (LegacySwlCodec.iconExceedsLimit(data) &&
            LegacySwlCodec.shrinkOversizedIcon(data) != null) {
          count++;
        }
      } catch (_) {
        // An unreadable icon is reported by the load report, not here.
      }
    }
    return count;
  }

  /// Reduces stored icons larger than 128×128 to 128×128 in one transaction
  /// and returns their number; smaller icons stay unchanged.
  static int shrinkOversizedIcons(
    Database database,
    SpbWalletAttachmentCodec attachments,
  ) {
    if (!_hasTable(database, 'spbwlt_Icon')) return 0;
    database.execute('BEGIN IMMEDIATE');
    try {
      final resized = _shrinkIcons(database, attachments);
      database.execute('COMMIT');
      return resized;
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  static int _shrinkIcons(
    Database database,
    SpbWalletAttachmentCodec attachments,
  ) {
    var resized = 0;
    for (final row in database.select(
      'SELECT rowid AS source_rowid, Data FROM spbwlt_Icon '
      'WHERE Data IS NOT NULL',
    )) {
      final Uint8List decoded;
      try {
        decoded = attachments.decode(row['Data']).bytes;
      } catch (_) {
        continue;
      }
      if (!LegacySwlCodec.iconExceedsLimit(decoded)) continue;
      final shrunk = LegacySwlCodec.shrinkOversizedIcon(decoded);
      if (shrunk == null) continue;
      database.execute(
        'UPDATE spbwlt_Icon SET Data=? WHERE rowid=?',
        [attachments.encode(shrunk), row['source_rowid']],
      );
      resized++;
    }
    return resized;
  }

  static Uint8List _bytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    if (value is String) return Uint8List.fromList(value.codeUnits);
    throw StateError('Некорректный legacy ID.');
  }

  static int _count(Database database, String sql) =>
      database.select(sql).first['n'] as int;

  static bool _hasTable(Database database, String name) => database.select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
        [name],
      ).isNotEmpty;

  static Set<String> _columns(Database database, String table) => database
      .select('PRAGMA table_info("' + table + '")')
      .map((row) => row['name'].toString())
      .toSet();
}
