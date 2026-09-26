import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as image;
import 'package:path_provider/path_provider.dart';

import 'data/spb_wallet_repository.dart';
import 'controllers/entity_index.dart';
import 'features/cards/field_projection.dart';
import 'features/categories/category_path_index.dart';
import 'features/templates/template_order.dart';
import 'services/wallet_rekey_service.dart';
import 'services/platform/secure_clipboard_service.dart';
import 'widgets/card_surface.dart';

void main(List<String> arguments) {
  final initialVaultPath = arguments.cast<String?>().firstWhere(
        (argument) =>
            argument != null &&
            argument.toLowerCase().endsWith('.swl') &&
            File(argument).existsSync(),
        orElse: () => null,
      );
  runApp(WalletApsApp(initialVaultPath: initialVaultPath));
}

final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
const spbIconBundleAsset = 'assets/spb_icons.bundle';
const thirdPartyIconBundleAsset = 'assets/third_party/NewIcons.zip';
List<String> spb64PngIconAssets = [];
Future<List<String>>? spb64PngIconAssetsFuture;
Map<String, Uint8List> spbBundledIconPngs = {};
Map<String, Uint8List> spbEmbeddedIconPngs = {};
List<String> thirdPartyIconAssets = [];
Future<List<String>>? thirdPartyIconAssetsFuture;
Map<String, Uint8List> thirdPartyIconPngs = {};

Future<List<String>> loadSpb64PngIconAssets() {
  return spb64PngIconAssetsFuture ??= () async {
    final data = await rootBundle.load(spbIconBundleAsset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final packedIcons = <String, Uint8List>{};
    String? pickerManifest;
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final normalizedName = file.name.replaceAll('\\', '/');
      if (normalizedName == 'icons_64x64.txt') {
        pickerManifest = utf8.decode(file.content, allowMalformed: true);
      } else if (normalizedName.toLowerCase().endsWith('.png')) {
        packedIcons['spb://$normalizedName'] = Uint8List.fromList(file.content);
      }
    }
    spbBundledIconPngs = packedIcons;
    final manifest = pickerManifest ?? '';
    spb64PngIconAssets = manifest
        .split(RegExp(r'\r?\n'))
        .map((path) => normalizeSpbPackedIconId(path.trim()))
        .where(
          (path) =>
              path.toLowerCase().endsWith('.png') &&
              packedIcons.containsKey(path),
        )
        .toSet()
        .toList(growable: false);
    return spb64PngIconAssets;
  }();
}

Future<List<String>> loadThirdPartyIconAssets() {
  return thirdPartyIconAssetsFuture ??= () async {
    final data = await rootBundle.load(thirdPartyIconBundleAsset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final packedIcons = <String, Uint8List>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final normalizedName = file.name.replaceAll('\\', '/');
      if (!normalizedName.toLowerCase().endsWith('.png')) continue;
      packedIcons['third-party://$normalizedName'] = Uint8List.fromList(
        file.content,
      );
    }
    thirdPartyIconPngs = packedIcons;
    thirdPartyIconAssets = packedIcons.keys.toList(growable: false)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return thirdPartyIconAssets;
  }();
}

String normalizeSpbPackedIconId(String iconId) {
  var normalized = iconId.replaceAll('\\', '/');
  const legacyPrefixes = <String>[
    'assets/spb_icons_package/',
    'assets/spb_wallet_libraries/icons/',
  ];
  for (final prefix in legacyPrefixes) {
    if (normalized.startsWith(prefix)) {
      normalized = normalized.substring(prefix.length);
      break;
    }
  }
  return normalized.startsWith('spb://') ? normalized : 'spb://$normalized';
}

Uint8List? spbPackedIconBytes(String iconId) =>
    spbBundledIconPngs[normalizeSpbPackedIconId(iconId)];

Widget spbPackedImage(
  String iconId, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  FilterQuality filterQuality = FilterQuality.medium,
  Widget? fallback,
}) {
  final bytes = spbPackedIconBytes(iconId);
  if (bytes == null) return fallback ?? const SizedBox.shrink();
  return Image.memory(
    bytes,
    width: width,
    height: height,
    fit: fit,
    filterQuality: filterQuality,
    gaplessPlayback: true,
    errorBuilder: fallback == null ? null : (_, __, ___) => fallback,
  );
}

Future<void> copySensitiveText(String value) async {
  await SecureClipboardService.copy(value);
}

Future<void> copyCardFieldValue(String value) async {
  await copySensitiveText(value);
  rootScaffoldMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Скопировано'),
        duration: Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

Widget desktopCardTextContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  final value = editableTextState.textEditingValue;
  final selection = value.selection;
  final selectedText = selection.isValid && !selection.isCollapsed
      ? selection.textInside(value.text)
      : '';
  final defaultItems = {
    for (final item in editableTextState.contextMenuButtonItems)
      item.type: item,
  };
  final items = <ContextMenuButtonItem>[
    ContextMenuButtonItem(
      type: ContextMenuButtonType.cut,
      label: 'Cut',
      onPressed: defaultItems[ContextMenuButtonType.cut]?.onPressed,
    ),
    ContextMenuButtonItem(
      type: ContextMenuButtonType.copy,
      label: 'Copy',
      onPressed: selectedText.isEmpty
          ? defaultItems[ContextMenuButtonType.copy]?.onPressed
          : () async {
              editableTextState.hideToolbar();
              await copyCardFieldValue(selectedText);
            },
    ),
    ContextMenuButtonItem(
      type: ContextMenuButtonType.paste,
      label: 'Paste',
      onPressed: defaultItems[ContextMenuButtonType.paste]?.onPressed,
    ),
    ContextMenuButtonItem(
      type: ContextMenuButtonType.share,
      label: 'Share',
      onPressed: selectedText.isEmpty
          ? null
          : () async {
              editableTextState.hideToolbar();
              await copyCardFieldValue(selectedText);
            },
    ),
  ];
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: items,
  );
}

bool get usesTouchTextSelection =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

class WalletApsApp extends StatelessWidget {
  const WalletApsApp({this.initialVaultPath, super.key});

  final String? initialVaultPath;

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff2d6f73),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xfff5f7f8),
      visualDensity: VisualDensity.standard,
      scrollbarTheme: const ScrollbarThemeData(
        thickness: WidgetStatePropertyAll<double>(13.6),
      ),
    );
    TextStyle enlarged(TextStyle? style, double defaultSize) =>
        (style ?? const TextStyle()).copyWith(
          fontSize: (style?.fontSize ?? defaultSize) + 2,
          fontWeight: FontWeight.normal,
        );
    final baseText = baseTheme.textTheme;
    final enlargedText = TextTheme(
      displayLarge: enlarged(baseText.displayLarge, 57),
      displayMedium: enlarged(baseText.displayMedium, 45),
      displaySmall: enlarged(baseText.displaySmall, 36),
      headlineLarge: enlarged(baseText.headlineLarge, 32),
      headlineMedium: enlarged(baseText.headlineMedium, 28),
      headlineSmall: enlarged(baseText.headlineSmall, 24),
      titleLarge: enlarged(baseText.titleLarge, 22),
      titleMedium: enlarged(baseText.titleMedium, 16),
      titleSmall: enlarged(baseText.titleSmall, 14),
      bodyLarge: enlarged(baseText.bodyLarge, 16),
      bodyMedium: enlarged(baseText.bodyMedium, 14),
      bodySmall: enlarged(baseText.bodySmall, 12),
      labelLarge: enlarged(baseText.labelLarge, 14),
      labelMedium: enlarged(baseText.labelMedium, 12),
      labelSmall: enlarged(baseText.labelSmall, 11),
    );
    return MaterialApp(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      title: 'Wallet APS',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => child ?? const SizedBox.shrink(),
      theme: baseTheme.copyWith(textTheme: enlargedText),
      home: VaultShell(initialVaultPath: initialVaultPath),
    );
  }
}

class PaletteColor {
  const PaletteColor(this.id, this.label, this.bg, this.fg);

  final String id;
  final String label;
  final Color bg;
  final Color fg;
}

class EnsureVisibleWhenFocused extends StatelessWidget {
  const EnsureVisibleWhenFocused({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        if (!focused) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: 0.3,
          );
        });
      },
      child: child,
    );
  }
}

class TemplateIcon {
  const TemplateIcon(this.id, this.label, this.symbol);

  final String id;
  final String label;
  final String symbol;
}

class FieldDefinition {
  const FieldDefinition({
    required this.id,
    required this.label,
    required this.type,
    this.required = false,
    this.secret = false,
  });

  final String id;
  final String label;
  final String type;
  final bool required;
  final bool secret;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'type': type,
        'required': required,
        'secret': secret,
      };

  factory FieldDefinition.fromJson(Map<String, dynamic> json) =>
      FieldDefinition(
        id: json['id'] as String,
        label: json['label'] as String,
        type: json['type'] as String,
        required: json['required'] == true,
        secret: json['secret'] == true,
      );
}

class CardTemplate {
  const CardTemplate({
    required this.id,
    required this.name,
    required this.iconId,
    required this.colorId,
    required this.fields,
    this.builtIn = false,
    this.embeddedIconBase64,
    this.iconFileName,
    this.spbColor,
    this.categoryPath = '',
  });

  final String id;
  final String name;
  final String iconId;
  final String colorId;
  final List<FieldDefinition> fields;
  final bool builtIn;
  final String? embeddedIconBase64;
  final String? iconFileName;
  final int? spbColor;
  final String categoryPath;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconId': iconId,
        'colorId': colorId,
        'builtIn': builtIn,
        'embeddedIconBase64': embeddedIconBase64,
        'iconFileName': iconFileName,
        'spbColor': spbColor,
        'categoryPath': categoryPath,
        'fields': fields.map((field) => field.toJson()).toList(),
      };

  factory CardTemplate.fromJson(Map<String, dynamic> json) => CardTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        iconId: json['iconId'] as String,
        colorId: json['colorId'] as String,
        builtIn: json['builtIn'] == true,
        embeddedIconBase64: json['embeddedIconBase64'] as String?,
        iconFileName: json['iconFileName'] as String?,
        spbColor: json['spbColor'] as int?,
        categoryPath: json['categoryPath'] as String? ?? '',
        fields: (json['fields'] as List<dynamic>)
            .map((field) =>
                FieldDefinition.fromJson(field as Map<String, dynamic>))
            .toList(),
      );
}

class SecretItem {
  const SecretItem({
    required this.id,
    required this.templateId,
    required this.title,
    required this.category,
    required this.colorId,
    required this.values,
    required this.modifiedAt,
    this.attachments = const [],
    this.hitCount = 0,
    this.iconId,
    this.backgroundImageBase64,
    this.spbColor,
    this.fieldOrder = const [],
    this.hiddenFieldIds = const {},
  });

  final String id;
  final String templateId;
  final String title;
  final String category;
  final String colorId;
  final Map<String, String> values;
  final DateTime modifiedAt;
  final List<SecretAttachment> attachments;
  final int hitCount;
  final String? iconId;
  final String? backgroundImageBase64;
  // Точный RGB-цвет карточки, как он хранится в .swl (spbwlt_CardView.CardColor).
  // Если задан, имеет приоритет над colorId при отрисовке и сохранении, чтобы
  // не "квантовать" оригинальный цвет SPB Wallet до одного из 7 пресетов палитры.
  final int? spbColor;
  final List<String> fieldOrder;
  final Set<String> hiddenFieldIds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'templateId': templateId,
        'title': title,
        'category': category,
        'colorId': colorId,
        'values': values,
        'modifiedAt': modifiedAt.toIso8601String(),
        'attachments':
            attachments.map((attachment) => attachment.toJson()).toList(),
        'hitCount': hitCount,
        'iconId': iconId,
        'backgroundImageBase64': backgroundImageBase64,
        'spbColor': spbColor,
        'fieldOrder': fieldOrder,
        'hiddenFieldIds': hiddenFieldIds.toList(),
      };

  factory SecretItem.fromJson(Map<String, dynamic> json) => SecretItem(
        id: json['id'] as String,
        templateId: json['templateId'] as String,
        title: json['title'] as String,
        category: json['category'] as String? ?? '',
        colorId: json['colorId'] as String? ?? 'neutral',
        values:
            Map<String, String>.from(json['values'] as Map<dynamic, dynamic>),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
        attachments: (json['attachments'] as List<dynamic>? ?? [])
            .map(
              (attachment) =>
                  SecretAttachment.fromJson(attachment as Map<String, dynamic>),
            )
            .toList(),
        hitCount: json['hitCount'] as int? ?? 0,
        iconId: json['iconId'] as String?,
        backgroundImageBase64: json['backgroundImageBase64'] as String?,
        spbColor: json['spbColor'] as int?,
        fieldOrder: List<String>.from(json['fieldOrder'] as List? ?? const []),
        hiddenFieldIds: Set<String>.from(
          json['hiddenFieldIds'] as List? ?? const [],
        ),
      );
}

int _swtUint32(Uint8List bytes, int offset) {
  if (offset < 0 || offset + 4 > bytes.length) {
    throw const FormatException('Повреждённый файл шаблона.');
  }
  return ByteData.sublistView(
    bytes,
    offset,
    offset + 4,
  ).getUint32(0, Endian.little);
}

String _swtUtf16(Uint8List bytes, int offset, int length) {
  if (length < 0 || offset < 0 || offset + length * 2 > bytes.length) {
    throw const FormatException('Повреждённая строка шаблона.');
  }
  final data = ByteData.sublistView(bytes, offset, offset + length * 2);
  return String.fromCharCodes([
    for (var index = 0; index < length; index++)
      data.getUint16(index * 2, Endian.little),
  ]);
}

bool _swtBytesEqual(Uint8List bytes, int offset, Uint8List expected) {
  if (offset < 0 || offset + expected.length > bytes.length) return false;
  for (var index = 0; index < expected.length; index++) {
    if (bytes[offset + index] != expected[index]) return false;
  }
  return true;
}

CardTemplate decodeSwtTemplate(Uint8List bytes) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    final envelope = Map<String, dynamic>.from(decoded as Map);
    final value = envelope['template'] ?? envelope;
    final template = CardTemplate.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    return CardTemplate(
      id: template.id,
      name: template.name,
      iconId: template.iconId,
      colorId: template.colorId,
      fields: template.fields,
      embeddedIconBase64: template.embeddedIconBase64,
      iconFileName: template.iconFileName,
      spbColor: template.spbColor,
    );
  } catch (_) {
    return decodeLegacySpbSwtTemplate(bytes);
  }
}

CardTemplate decodeLegacySpbSwtTemplate(Uint8List bytes) {
  const signature = 'serialization::archive';
  if (bytes.length < 80 ||
      _swtUint32(bytes, 0) != signature.length ||
      ascii.decode(bytes.sublist(4, 4 + signature.length)) != signature) {
    throw const FormatException('Неподдерживаемый формат SWT.');
  }

  Uint8List? templateId;
  String? templateName;
  var fieldsStart = 0;
  for (var offset = 30; offset + 20 < min(bytes.length, 180); offset++) {
    if (_swtUint32(bytes, offset) != 8) continue;
    final nameLength = _swtUint32(bytes, offset + 12);
    if (nameLength < 1 || nameLength > 200) continue;
    final nameEnd = offset + 16 + nameLength * 2;
    if (nameEnd > bytes.length) continue;
    final candidate = _swtUtf16(bytes, offset + 16, nameLength).trim();
    if (candidate.isEmpty || candidate.contains('\u0000')) continue;
    templateId = Uint8List.fromList(bytes.sublist(offset + 4, offset + 12));
    templateName = candidate;
    fieldsStart = nameEnd;
    break;
  }
  if (templateId == null || templateName == null) {
    throw const FormatException('В SWT не найден шаблон.');
  }

  final fieldsByPriority = <int, FieldDefinition>{};
  for (var offset = fieldsStart; offset + 36 <= bytes.length; offset++) {
    if (_swtUint32(bytes, offset) != 8) continue;
    final nameLength = _swtUint32(bytes, offset + 12);
    if (nameLength < 1 || nameLength > 200) continue;
    final nameOffset = offset + 16;
    final templateLengthOffset = nameOffset + nameLength * 2;
    if (templateLengthOffset + 24 > bytes.length ||
        _swtUint32(bytes, templateLengthOffset) != 8 ||
        !_swtBytesEqual(bytes, templateLengthOffset + 4, templateId)) {
      continue;
    }
    final fieldTypeId = _swtUint32(bytes, templateLengthOffset + 12);
    final priority = _swtUint32(bytes, templateLengthOffset + 16);
    if (fieldTypeId < 1 || fieldTypeId > 8 || priority > 500) continue;
    final name = _swtUtf16(bytes, nameOffset, nameLength).trim();
    if (name.isEmpty || name.contains('\u0000')) continue;
    final fieldId = bytes
        .sublist(offset + 4, offset + 12)
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    final type = spbFieldTypeToUi(fieldTypeId, name);
    fieldsByPriority.putIfAbsent(
      priority,
      () => FieldDefinition(
        id: fieldId,
        label: name,
        type: type,
        secret: fieldTypeIsSecret(type),
      ),
    );
  }
  final priorities = fieldsByPriority.keys.toList()..sort();
  final fields = [
    for (final priority in priorities) fieldsByPriority[priority]!,
  ];
  if (fields.isEmpty) {
    throw const FormatException('В SWT не найдены поля шаблона.');
  }
  return CardTemplate(
    id: makeId('tpl'),
    name: templateName,
    iconId: defaultIconForTemplateName(
      templateName,
      fields.map((field) => field.label),
    ),
    colorId: 'neutral',
    fields: fields,
  );
}

class SecretAttachment {
  const SecretAttachment({
    required this.id,
    required this.fileName,
    required this.size,
    this.decodeError,
    this.pendingBytes,
    this.deleted = false,
  });

  final String id;
  final String fileName;
  final int size;
  final String? decodeError;
  final List<int>? pendingBytes;
  final bool deleted;

  SecretAttachment copyWith({
    String? id,
    String? fileName,
    int? size,
    String? decodeError,
    List<int>? pendingBytes,
    bool? deleted,
  }) =>
      SecretAttachment(
        id: id ?? this.id,
        fileName: fileName ?? this.fileName,
        size: size ?? this.size,
        decodeError: decodeError,
        pendingBytes: pendingBytes ?? this.pendingBytes,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'size': size,
        'decodeError': decodeError,
      };

  factory SecretAttachment.fromJson(Map<String, dynamic> json) =>
      SecretAttachment(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        size: json['size'] as int? ?? -1,
        decodeError: json['decodeError'] as String?,
      );
}

class CategoryTreeNode {
  CategoryTreeNode(
    this.name, {
    this.path = '',
    this.iconId,
    this.colorId,
    this.id,
  });

  final String name;
  final String path;
  final String? iconId;
  final String? colorId;
  final String? id;
  final Map<String, CategoryTreeNode> children = {};
  final List<SecretItem> cards = [];

  bool get isEmpty => children.isEmpty && cards.isEmpty;
}

enum SessionTrashKind { card, folder, template }

class SessionTrashEntry {
  const SessionTrashEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.iconId,
  });

  final SessionTrashKind kind;
  final String id;
  final String title;
  final String iconId;
}

class SessionUndoEntry {
  const SessionUndoEntry({
    required this.label,
    required this.iconId,
    required this.databaseSnapshot,
    required this.trash,
    required this.trashCardIds,
    required this.trashFolderPaths,
    required this.trashTemplateIds,
  });

  final String label;
  final String iconId;
  final SpbWalletUndoSnapshot databaseSnapshot;
  final List<SessionTrashEntry> trash;
  final Set<String> trashCardIds;
  final Set<String> trashFolderPaths;
  final Set<String> trashTemplateIds;
}

class ExistingVault {
  const ExistingVault({
    required this.title,
    this.path,
    this.uri,
    this.displayPath,
  });

  final String title;
  final String? path;
  final String? uri;
  final String? displayPath;

  String get key => uri ?? path ?? title;

  Map<String, dynamic> toJson() => {
        'title': title,
        if (path != null) 'path': path,
        if (uri != null) 'uri': uri,
        if (displayPath != null) 'displayPath': displayPath,
      };

  factory ExistingVault.fromJson(Map<String, dynamic> json) {
    final title = json['title']?.toString();
    final path = json['path']?.toString();
    final uri = json['uri']?.toString();
    final displayPath = json['displayPath']?.toString();
    return ExistingVault(
      title: title == null || title.isEmpty
          ? _vaultTitleFromPath(displayPath ?? path ?? uri ?? '.swl база')
          : title,
      path: path,
      uri: uri,
      displayPath: displayPath,
    );
  }
}

String _vaultTitleFromPath(String path) {
  if (path.startsWith('content://')) return '.swl база';
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? path : normalized.substring(slash + 1);
}

abstract class VaultSession {
  Future<void> load();
  Future<void> saveItem(SecretItem item);
  Future<void> deleteItem(String itemId);
  Future<void> saveTemplate(CardTemplate template);
  Future<void> saveAttachment(String itemId, SecretAttachment attachment);
  Future<void> close();
}

class SpbWalletSession implements VaultSession {
  SpbWalletSession(this.database);

  final SpbWalletDatabase database;
  late SpbWalletSnapshot snapshot;

  @override
  Future<void> load() async {
    snapshot = database.loadSnapshot();
  }

  @override
  Future<void> saveItem(SecretItem item) async {
    database.saveCard(
      SpbWalletCardDraft(
        id: item.id,
        title: item.title,
        description: item.values[spbDescriptionFieldId] ?? '',
        categoryPath: item.category,
        templateId: item.templateId,
        fieldValues: {
          for (final entry in item.values.entries)
            if (entry.key != spbDescriptionFieldId) entry.key: entry.value,
        },
        cardColor: item.spbColor ?? paletteColorToSpb(item.colorId),
        iconId:
            item.iconId == null ? null : syntheticSpbIconIdForUi(item.iconId!),
        backgroundImageBase64: item.backgroundImageBase64,
        fieldOrder: item.fieldOrder,
        hiddenFieldIds: item.hiddenFieldIds,
        modifiedAt: item.modifiedAt,
      ),
    );
    await load();
  }

  @override
  Future<void> deleteItem(String itemId) async {
    database.deleteCard(itemId);
    await load();
  }

  @override
  Future<void> saveTemplate(CardTemplate template) async {
    database.saveTemplate(
      SpbWalletTemplateDraft(
        id: template.id,
        name: template.name,
        iconId: syntheticSpbIconIdForUi(template.iconId),
        fields: template.fields
            .where((field) => field.id != spbDescriptionFieldId)
            .map(
              (field) => SpbWalletTemplateFieldRecord(
                id: field.id,
                name: field.label,
                templateId: template.id,
                fieldTypeId: spbFieldTypeId(field),
              ),
            )
            .toList(),
      ),
    );
    await load();
  }

  @override
  Future<void> saveAttachment(
    String itemId,
    SecretAttachment attachment,
  ) async {
    final bytes = attachment.pendingBytes;
    if (attachment.deleted && attachment.id.isNotEmpty) {
      database.deleteAttachment(attachment.id);
    } else if (bytes != null) {
      database.saveAttachment(
        cardId: itemId,
        attachmentId: attachment.id.isEmpty ? null : attachment.id,
        fileName: attachment.fileName,
        bytes: bytes,
      );
    }
    await load();
  }

  @override
  Future<void> close() async {
    database.close();
  }
}

class ConflictRecord {
  const ConflictRecord({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    this.reviewed = false,
  });

  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final bool reviewed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'reviewed': reviewed,
      };

  factory ConflictRecord.fromJson(Map<String, dynamic> json) => ConflictRecord(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        reviewed: json['reviewed'] == true,
      );
}

const palette = [
  PaletteColor('neutral', 'Серый', Color(0xffe7eaee), Color(0xff222831)),
  PaletteColor('blue', 'Синий', Color(0xffd9e6f6), Color(0xff17375f)),
  PaletteColor('green', 'Зеленый', Color(0xffdcebdc), Color(0xff1f4d32)),
  PaletteColor('teal', 'Бирюзовый', Color(0xffd8eceb), Color(0xff1f5052)),
  PaletteColor('violet', 'Фиолетовый', Color(0xffe6def0), Color(0xff4a3568)),
  PaletteColor('red', 'Красный', Color(0xfff2dddc), Color(0xff6a2b2b)),
  PaletteColor('amber', 'Янтарный', Color(0xfff3e7ca), Color(0xff5d4318)),
];

const templateColorPalette = [
  PaletteColor(
    'template_gray',
    'Бледно-серый',
    Color(0xffe8e8e8),
    Color(0xff242424),
  ),
  PaletteColor(
    'template_red',
    'Бледно-красный',
    Color(0xfff8d7da),
    Color(0xff54292d),
  ),
  PaletteColor(
    'template_coral',
    'Бледно-коралловый',
    Color(0xfff9ddd2),
    Color(0xff583329),
  ),
  PaletteColor(
    'template_orange',
    'Бледно-оранжевый',
    Color(0xfffbe5c8),
    Color(0xff583c20),
  ),
  PaletteColor(
    'template_yellow',
    'Бледно-жёлтый',
    Color(0xfffbf3c4),
    Color(0xff51491e),
  ),
  PaletteColor(
    'template_lime',
    'Бледно-салатовый',
    Color(0xffedf5c8),
    Color(0xff414b22),
  ),
  PaletteColor(
    'template_green',
    'Бледно-зелёный',
    Color(0xffdaf1d8),
    Color(0xff294b2a),
  ),
  PaletteColor(
    'template_mint',
    'Бледно-мятный',
    Color(0xffd5f1e3),
    Color(0xff24493a),
  ),
  PaletteColor(
    'template_cyan',
    'Бледно-бирюзовый',
    Color(0xffd5f2f2),
    Color(0xff21494b),
  ),
  PaletteColor(
    'template_sky',
    'Бледно-голубой',
    Color(0xffd8ecfa),
    Color(0xff24445a),
  ),
  PaletteColor(
    'template_blue',
    'Бледно-синий',
    Color(0xffdce4fa),
    Color(0xff293b61),
  ),
  PaletteColor(
    'template_indigo',
    'Бледно-индиго',
    Color(0xffe2dff7),
    Color(0xff39345e),
  ),
  PaletteColor(
    'template_violet',
    'Бледно-фиолетовый',
    Color(0xffeaddf6),
    Color(0xff49335c),
  ),
  PaletteColor(
    'template_pink',
    'Бледно-розовый',
    Color(0xfff5ddf0),
    Color(0xff58344f),
  ),
  PaletteColor(
    'template_rose',
    'Бледно-розово-серый',
    Color(0xfff7e1e8),
    Color(0xff583943),
  ),
  PaletteColor('template_white', 'Белый', Color(0xffffffff), Color(0xff222222)),
];

const templateIcons = [
  TemplateIcon('key', 'Ключ', '🔑'),
  TemplateIcon('note', 'Заметка', '📝'),
  TemplateIcon('card', 'Банковская карта', '💳'),
  TemplateIcon('id', 'Документ', '🪪'),
  TemplateIcon('server', 'Сервер', '🖥️'),
  TemplateIcon('license', 'Лицензия', '🏷️'),
  TemplateIcon('wifi', 'Wi-Fi', '📶'),
  TemplateIcon('bank', 'Банк', '🏦'),
  TemplateIcon('mail', 'Почта', '✉️'),
  TemplateIcon('shield', 'Защита', '🛡️'),
  TemplateIcon('lock', 'Замок', '🔒'),
  TemplateIcon('unlock', 'Открытый замок', '🔓'),
  TemplateIcon('safe', 'Сейф', '🧰'),
  TemplateIcon('briefcase', 'Портфель', '💼'),
  TemplateIcon('folder', 'Папка', '📁'),
  TemplateIcon('file', 'Файл', '📄'),
  TemplateIcon('bookmark', 'Закладка', '🔖'),
  TemplateIcon('tag', 'Метка', '🏷️'),
  TemplateIcon('receipt', 'Чек', '🧾'),
  TemplateIcon('money', 'Деньги', '💵'),
  TemplateIcon('coin', 'Монеты', '🪙'),
  TemplateIcon('wallet', 'Кошелек', '👛'),
  TemplateIcon('chart', 'График', '📈'),
  TemplateIcon('calculator', 'Калькулятор', '🧮'),
  TemplateIcon('home', 'Дом', '🏠'),
  TemplateIcon('car', 'Авто', '🚗'),
  TemplateIcon('plane', 'Самолет', '✈️'),
  TemplateIcon('train', 'Поезд', '🚆'),
  TemplateIcon('passport', 'Паспорт', '🛂'),
  TemplateIcon('ticket', 'Билет', '🎫'),
  TemplateIcon('phone', 'Телефон', '📱'),
  TemplateIcon('desktop', 'Компьютер', '🖥️'),
  TemplateIcon('laptop', 'Ноутбук', '💻'),
  TemplateIcon('printer', 'Принтер', '🖨️'),
  TemplateIcon('keyboard', 'Клавиатура', '⌨️'),
  TemplateIcon('mouse', 'Мышь', '🖱️'),
  TemplateIcon('disk', 'Диск', '💾'),
  TemplateIcon('cd', 'Диск', '💿'),
  TemplateIcon('camera', 'Камера', '📷'),
  TemplateIcon('video', 'Видео', '🎥'),
  TemplateIcon('tv', 'Телевизор', '📺'),
  TemplateIcon('game', 'Игры', '🎮'),
  TemplateIcon('headphones', 'Наушники', '🎧'),
  TemplateIcon('watch', 'Часы', '⌚'),
  TemplateIcon('satellite', 'Связь', '📡'),
  TemplateIcon('globe', 'Сайт', '🌐'),
  TemplateIcon('link', 'Ссылка', '🔗'),
  TemplateIcon('cloud', 'Облако', '☁️'),
  TemplateIcon('database', 'База данных', '🗄️'),
  TemplateIcon('gear', 'Настройки', '⚙️'),
  TemplateIcon('tool', 'Инструмент', '🛠️'),
  TemplateIcon('wrench', 'Ключ', '🔧'),
  TemplateIcon('bug', 'Багтрекер', '🐞'),
  TemplateIcon('code', 'Код', '💻'),
  TemplateIcon('package', 'Пакет', '📦'),
  TemplateIcon('rocket', 'Проект', '🚀'),
  TemplateIcon('lab', 'Лаборатория', '🧪'),
  TemplateIcon('medical', 'Медицина', '⚕️'),
  TemplateIcon('heart', 'Здоровье', '❤️'),
  TemplateIcon('pill', 'Лекарства', '💊'),
  TemplateIcon('school', 'Учеба', '🎓'),
  TemplateIcon('book', 'Книга', '📚'),
  TemplateIcon('pen', 'Ручка', '🖊️'),
  TemplateIcon('clipboard', 'Буфер', '📋'),
  TemplateIcon('calendar', 'Календарь', '📅'),
  TemplateIcon('clock', 'Время', '⏰'),
  TemplateIcon('pin', 'PIN', '📌'),
  TemplateIcon('location', 'Адрес', '📍'),
  TemplateIcon('map', 'Карта', '🗺️'),
  TemplateIcon('house_key', 'Ключи дома', '🗝️'),
  TemplateIcon('building', 'Компания', '🏢'),
  TemplateIcon('shop', 'Магазин', '🏬'),
  TemplateIcon('factory', 'Производство', '🏭'),
  TemplateIcon('hammer', 'Работа', '🔨'),
  TemplateIcon('scales', 'Документы', '⚖️'),
  TemplateIcon('certificate', 'Сертификат', '📜'),
  TemplateIcon('medal', 'Награда', '🏅'),
  TemplateIcon('star', 'Избранное', '⭐'),
  TemplateIcon('warning', 'Важно', '⚠️'),
  TemplateIcon('bell', 'Напоминание', '🔔'),
  TemplateIcon('gift', 'Подарок', '🎁'),
  TemplateIcon('cart', 'Покупки', '🛒'),
  TemplateIcon('food', 'Еда', '🍽️'),
  TemplateIcon('coffee', 'Кофе', '☕'),
  TemplateIcon('hotel', 'Отель', '🏨'),
  TemplateIcon('taxi', 'Такси', '🚕'),
  TemplateIcon('fuel', 'Топливо', '⛽'),
  TemplateIcon('bicycle', 'Велосипед', '🚲'),
  TemplateIcon('ship', 'Корабль', '🚢'),
  TemplateIcon('anchor', 'Якорь', '⚓'),
  TemplateIcon('crypto', 'Крипто', '₿'),
  TemplateIcon('diamond', 'Ценности', '💎'),
  TemplateIcon('gem', 'Драгоценности', '💍'),
  TemplateIcon('mailbox', 'Почтовый ящик', '📫'),
  TemplateIcon('inbox', 'Входящие', '📥'),
  TemplateIcon('outbox', 'Исходящие', '📤'),
  TemplateIcon('chat', 'Чат', '💬'),
  TemplateIcon('contact', 'Контакт', '👤'),
  TemplateIcon('group', 'Группа', '👥'),
  TemplateIcon('family', 'Семья', '👪'),
  TemplateIcon('fingerprint', 'Биометрия', '🫆'),
  TemplateIcon('magnifier', 'Поиск', '🔎'),
  TemplateIcon('battery', 'Питание', '🔋'),
  TemplateIcon('plug', 'Подключение', '🔌'),
  TemplateIcon('fire', 'Срочно', '🔥'),
  TemplateIcon('snowflake', 'Архив', '❄️'),
  TemplateIcon('plant', 'Сад', '🌱'),
  TemplateIcon('tree', 'Участок', '🌳'),
  TemplateIcon('sun', 'Свет', '☀️'),
  TemplateIcon('moon', 'Ночь', '🌙'),
  TemplateIcon('umbrella', 'Страховка', '☂️'),
  TemplateIcon('magnet', 'Магнит', '🧲'),
  TemplateIcon('dna', 'Данные', '🧬'),
  TemplateIcon('microchip', 'Чип', '🔬'),
  TemplateIcon('qr', 'QR', '▪️'),
  TemplateIcon('check', 'Проверено', '✅'),
  TemplateIcon('cross', 'Ошибка', '❌'),
  TemplateIcon('plus', 'Дополнительно', '➕'),
  TemplateIcon('minus', 'Вычет', '➖'),
  TemplateIcon('question', 'Вопрос', '❓'),
  TemplateIcon('info', 'Информация', 'ℹ️'),
];

const templateIconGlyphs = {
  'key': Icons.vpn_key_outlined,
  'note': Icons.notes_outlined,
  'card': Icons.credit_card,
  'id': Icons.badge_outlined,
  'server': Icons.dns_outlined,
  'license': Icons.sell_outlined,
  'wifi': Icons.wifi,
  'bank': Icons.account_balance,
  'mail': Icons.mail_outline,
  'shield': Icons.security,
  'lock': Icons.lock_outline,
  'unlock': Icons.lock_open,
  'safe': Icons.inventory_2_outlined,
  'briefcase': Icons.business_center_outlined,
  'folder': Icons.folder_outlined,
  'file': Icons.insert_drive_file_outlined,
  'bookmark': Icons.bookmark_border,
  'tag': Icons.label_outline,
  'receipt': Icons.receipt_long,
  'money': Icons.attach_money,
  'coin': Icons.monetization_on_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
  'chart': Icons.trending_up,
  'calculator': Icons.calculate_outlined,
  'home': Icons.home_outlined,
  'car': Icons.directions_car,
  'plane': Icons.flight_takeoff,
  'train': Icons.train,
  'passport': Icons.assignment_ind_outlined,
  'ticket': Icons.confirmation_number_outlined,
  'phone': Icons.phone_iphone,
  'desktop': Icons.desktop_windows,
  'laptop': Icons.laptop_mac,
  'printer': Icons.print,
  'keyboard': Icons.keyboard,
  'mouse': Icons.mouse,
  'disk': Icons.save,
  'cd': Icons.album,
  'camera': Icons.photo_camera,
  'video': Icons.videocam,
  'tv': Icons.tv,
  'game': Icons.sports_esports,
  'headphones': Icons.headphones,
  'watch': Icons.watch,
  'satellite': Icons.settings_input_antenna,
  'globe': Icons.public,
  'link': Icons.link,
  'cloud': Icons.cloud_outlined,
  'database': Icons.storage,
  'gear': Icons.settings,
  'tool': Icons.construction,
  'wrench': Icons.build,
  'bug': Icons.bug_report_outlined,
  'code': Icons.code,
  'package': Icons.inventory_2,
  'rocket': Icons.rocket_launch,
  'lab': Icons.science,
  'medical': Icons.medical_services,
  'heart': Icons.favorite_border,
  'pill': Icons.medication,
  'school': Icons.school,
  'book': Icons.menu_book,
  'pen': Icons.edit,
  'clipboard': Icons.assignment,
  'calendar': Icons.calendar_month,
  'clock': Icons.schedule,
  'pin': Icons.push_pin,
  'location': Icons.place,
  'map': Icons.map_outlined,
  'house_key': Icons.key,
  'building': Icons.business,
  'shop': Icons.local_mall,
  'factory': Icons.factory,
  'hammer': Icons.hardware,
  'scales': Icons.balance,
  'certificate': Icons.workspace_premium,
  'medal': Icons.emoji_events,
  'star': Icons.star_border,
  'warning': Icons.warning_amber,
  'bell': Icons.notifications_none,
  'gift': Icons.card_giftcard,
  'cart': Icons.shopping_cart,
  'food': Icons.restaurant,
  'coffee': Icons.local_cafe,
  'hotel': Icons.hotel,
  'taxi': Icons.local_taxi,
  'fuel': Icons.local_gas_station,
  'bicycle': Icons.directions_bike,
  'ship': Icons.directions_boat,
  'anchor': Icons.anchor,
  'crypto': Icons.currency_bitcoin,
  'diamond': Icons.diamond_outlined,
  'gem': Icons.diamond,
  'mailbox': Icons.markunread_mailbox_outlined,
  'inbox': Icons.move_to_inbox,
  'outbox': Icons.outbox,
  'chat': Icons.chat_bubble_outline,
  'contact': Icons.person_outline,
  'group': Icons.group_outlined,
  'family': Icons.family_restroom,
  'fingerprint': Icons.fingerprint,
  'magnifier': Icons.search,
  'battery': Icons.battery_full,
  'plug': Icons.power,
  'fire': Icons.local_fire_department,
  'snowflake': Icons.ac_unit,
  'plant': Icons.grass,
  'tree': Icons.park,
  'sun': Icons.wb_sunny,
  'moon': Icons.dark_mode,
  'umbrella': Icons.beach_access,
  'magnet': Icons.tungsten,
  'dna': Icons.biotech,
  'microchip': Icons.memory,
  'qr': Icons.qr_code,
  'check': Icons.check_circle_outline,
  'cross': Icons.cancel_outlined,
  'plus': Icons.add_circle_outline,
  'minus': Icons.remove_circle_outline,
  'question': Icons.help_outline,
  'info': Icons.info_outline,
};

const quickTemplateIconIds = [
  'key',
  'note',
  'card',
  'id',
  'server',
  'license',
  'wifi',
  'bank',
  'mail',
  'shield',
];

const navEntries = [
  NavEntry('cards', Icons.credit_card, 'Карточки'),
  NavEntry('frequent', Icons.star_outline, 'Частые'),
  NavEntry('templates', Icons.dashboard_customize_outlined, 'Шаблоны'),
  NavEntry('settings', Icons.settings_outlined, 'Настройки'),
];

class NavEntry {
  const NavEntry(this.id, this.icon, this.label);

  final String id;
  final IconData icon;
  final String label;
}

List<TemplateIcon> quickTemplateIcons(String selectedIconId) {
  final selected = iconById(selectedIconId);
  final icons = [
    ...quickTemplateIconIds.map(iconById),
    if (!quickTemplateIconIds.contains(selected.id)) selected,
  ];
  final seen = <String>{};
  return [
    for (final icon in icons)
      if (seen.add(icon.id)) icon,
  ];
}

List<CardTemplate> builtInTemplates() => const [
      CardTemplate(
        id: 'tpl_password',
        name: 'Пароль',
        iconId: 'key',
        colorId: 'blue',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'username', label: 'Логин', type: 'username'),
          FieldDefinition(
            id: 'password',
            label: 'Пароль',
            type: 'password',
            required: true,
            secret: true,
          ),
          FieldDefinition(id: 'url', label: 'Сайт', type: 'url'),
          FieldDefinition(
              id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_note',
        name: 'Защищенная заметка',
        iconId: 'note',
        colorId: 'neutral',
        builtIn: true,
        fields: [
          FieldDefinition(
            id: 'note',
            label: 'Текст заметки',
            type: 'multiline_note',
            required: true,
          ),
        ],
      ),
      CardTemplate(
        id: 'tpl_payment_card',
        name: 'Банковская карта',
        iconId: 'card',
        colorId: 'teal',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'holder', label: 'Владелец карты', type: 'text'),
          FieldDefinition(
            id: 'number',
            label: 'Номер карты',
            type: 'custom_secret',
            required: true,
          ),
          FieldDefinition(id: 'expires', label: 'Действует до', type: 'date'),
          FieldDefinition(
              id: 'cvv', label: 'CVV', type: 'password', secret: true),
        ],
      ),
      CardTemplate(
        id: 'tpl_identity',
        name: 'Документ',
        iconId: 'id',
        colorId: 'violet',
        builtIn: true,
        fields: [
          FieldDefinition(
            id: 'full_name',
            label: 'ФИО',
            type: 'text',
            required: true,
          ),
          FieldDefinition(
            id: 'document_number',
            label: 'Номер документа',
            type: 'custom_secret',
            required: true,
          ),
          FieldDefinition(id: 'issued_at', label: 'Дата выдачи', type: 'date'),
          FieldDefinition(
              id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_server',
        name: 'Доступ к серверу',
        iconId: 'server',
        colorId: 'green',
        builtIn: true,
        fields: [
          FieldDefinition(
              id: 'host', label: 'Хост', type: 'url', required: true),
          FieldDefinition(
            id: 'username',
            label: 'Пользователь',
            type: 'username',
            required: true,
          ),
          FieldDefinition(
            id: 'password',
            label: 'Пароль или фраза ключа',
            type: 'password',
            secret: true,
          ),
          FieldDefinition(
              id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_license',
        name: 'Лицензия ПО',
        iconId: 'license',
        colorId: 'amber',
        builtIn: true,
        fields: [
          FieldDefinition(
            id: 'product',
            label: 'Продукт',
            type: 'text',
            required: true,
          ),
          FieldDefinition(
            id: 'license_key',
            label: 'Лицензионный ключ',
            type: 'custom_secret',
            required: true,
          ),
          FieldDefinition(id: 'email', label: 'Email аккаунта', type: 'email'),
        ],
      ),
      CardTemplate(
        id: 'tpl_wifi',
        name: 'Wi-Fi',
        iconId: 'wifi',
        colorId: 'green',
        builtIn: true,
        fields: [
          FieldDefinition(
            id: 'ssid',
            label: 'Название сети',
            type: 'text',
            required: true,
          ),
          FieldDefinition(
            id: 'password',
            label: 'Пароль Wi-Fi',
            type: 'password',
            required: true,
            secret: true,
          ),
          FieldDefinition(id: 'security', label: 'Тип защиты', type: 'text'),
        ],
      ),
      CardTemplate(
        id: 'tpl_bank_account',
        name: 'Банковский счет',
        iconId: 'bank',
        colorId: 'blue',
        builtIn: true,
        fields: [
          FieldDefinition(
              id: 'bank', label: 'Банк', type: 'text', required: true),
          FieldDefinition(
            id: 'account',
            label: 'Номер счета',
            type: 'custom_secret',
            required: true,
          ),
          FieldDefinition(
            id: 'login',
            label: 'Логин интернет-банка',
            type: 'username',
          ),
          FieldDefinition(
            id: 'password',
            label: 'Пароль интернет-банка',
            type: 'password',
            secret: true,
          ),
        ],
      ),
      CardTemplate(
        id: 'tpl_email_account',
        name: 'Email аккаунт',
        iconId: 'mail',
        colorId: 'green',
        builtIn: true,
        fields: [
          FieldDefinition(
            id: 'email',
            label: 'Email',
            type: 'email',
            required: true,
          ),
          FieldDefinition(
            id: 'password',
            label: 'Пароль',
            type: 'password',
            required: true,
            secret: true,
          ),
          FieldDefinition(
              id: 'recovery', label: 'Резервная почта', type: 'email'),
          FieldDefinition(
              id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_api_key',
        name: 'API ключ',
        iconId: 'code',
        colorId: 'violet',
        builtIn: true,
        fields: [
          FieldDefinition(
            id: 'service',
            label: 'Сервис',
            type: 'text',
            required: true,
          ),
          FieldDefinition(id: 'url', label: 'Панель', type: 'url'),
          FieldDefinition(
            id: 'token',
            label: 'Токен',
            type: 'custom_secret',
            required: true,
          ),
          FieldDefinition(
            id: 'notes',
            label: 'Права и ограничения',
            type: 'multiline_note',
          ),
        ],
      ),
      CardTemplate(
        id: 'tpl_crypto_wallet',
        name: 'Криптокошелек',
        iconId: 'crypto',
        colorId: 'amber',
        builtIn: true,
        fields: [
          FieldDefinition(
              id: 'wallet', label: 'Название кошелька', type: 'text'),
          FieldDefinition(id: 'address', label: 'Адрес', type: 'text'),
          FieldDefinition(
            id: 'seed',
            label: 'Seed-фраза',
            type: 'custom_secret',
            required: true,
          ),
          FieldDefinition(id: 'pin', label: 'PIN', type: 'password'),
          FieldDefinition(
              id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_contact',
        name: 'Контакт',
        iconId: 'contact',
        colorId: 'neutral',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'name', label: 'Имя', type: 'text'),
          FieldDefinition(id: 'phone', label: 'Телефон', type: 'phone'),
          FieldDefinition(id: 'email', label: 'Email', type: 'email'),
          FieldDefinition(
              id: 'address', label: 'Адрес', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_subscription',
        name: 'Подписка',
        iconId: 'ticket',
        colorId: 'blue',
        builtIn: true,
        fields: [
          FieldDefinition(
            id: 'service',
            label: 'Сервис',
            type: 'text',
            required: true,
          ),
          FieldDefinition(id: 'login', label: 'Логин', type: 'username'),
          FieldDefinition(id: 'renewal', label: 'Дата продления', type: 'date'),
          FieldDefinition(id: 'price', label: 'Стоимость', type: 'number'),
          FieldDefinition(
              id: 'notes', label: 'Условия', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_insurance',
        name: 'Страховка',
        iconId: 'umbrella',
        colorId: 'teal',
        builtIn: true,
        fields: [
          FieldDefinition(
            id: 'company',
            label: 'Компания',
            type: 'text',
            required: true,
          ),
          FieldDefinition(
            id: 'policy',
            label: 'Номер полиса',
            type: 'custom_secret',
            required: true,
          ),
          FieldDefinition(id: 'valid_to', label: 'Действует до', type: 'date'),
          FieldDefinition(
              id: 'phone', label: 'Телефон поддержки', type: 'phone'),
          FieldDefinition(
              id: 'notes', label: 'Условия', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_travel',
        name: 'Поездка',
        iconId: 'plane',
        colorId: 'violet',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'carrier', label: 'Перевозчик', type: 'text'),
          FieldDefinition(id: 'booking', label: 'Бронь/PNR', type: 'text'),
          FieldDefinition(id: 'date', label: 'Дата', type: 'date'),
          FieldDefinition(
              id: 'document', label: 'Документ', type: 'custom_secret'),
          FieldDefinition(
              id: 'notes', label: 'Заметки', type: 'multiline_note'),
        ],
      ),
      CardTemplate(
        id: 'tpl_home_access',
        name: 'Домашний доступ',
        iconId: 'house_key',
        colorId: 'green',
        builtIn: true,
        fields: [
          FieldDefinition(id: 'object', label: 'Объект', type: 'text'),
          FieldDefinition(id: 'code', label: 'Код доступа', type: 'password'),
          FieldDefinition(id: 'contact', label: 'Контакт', type: 'phone'),
          FieldDefinition(
              id: 'notes', label: 'Инструкции', type: 'multiline_note'),
        ],
      ),
    ];

PaletteColor colorById(String id) {
  for (final color in [...palette, ...templateColorPalette]) {
    if (color.id == id) return color;
  }
  return palette.first;
}

int paletteColorToSpb(String colorId) =>
    colorById(colorId).bg.toARGB32() & 0x00ffffff;

String spbColorToPaletteId(int color) {
  final normalized = color & 0x00ffffff;
  if (normalized == 0xffffff) return 'neutral';
  var best = palette.first;
  var bestDistance = 1 << 62;
  for (final candidate in palette) {
    final value = candidate.bg.toARGB32() & 0x00ffffff;
    final dr = ((normalized >> 16) & 0xff) - ((value >> 16) & 0xff);
    final dg = ((normalized >> 8) & 0xff) - ((value >> 8) & 0xff);
    final db = (normalized & 0xff) - (value & 0xff);
    final distance = dr * dr + dg * dg + db * db;
    if (distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best.id;
}

String spbTemplateColorToPaletteId(int color) {
  final normalized = color & 0x00ffffff;
  for (final candidate in templateColorPalette) {
    if ((candidate.bg.toARGB32() & 0x00ffffff) == normalized) {
      return candidate.id;
    }
  }
  return spbColorToPaletteId(color);
}

/// Цвет для отрисовки карточки: если известен точный RGB из SPB Wallet
/// (`item.spbColor`), используется он напрямую, без округления до одного из
/// 7 пресетов палитры. Иначе — прежнее поведение через colorId/пресет.
PaletteColor itemDisplayColor(SecretItem item, CardTemplate template) {
  final rawColor = item.spbColor;
  if (rawColor == null) {
    return colorById(item.colorId.isEmpty ? template.colorId : item.colorId);
  }
  final bg = Color(0xff000000 | (rawColor & 0x00ffffff));
  final fg =
      bg.computeLuminance() > 0.55 ? const Color(0xff222831) : Colors.white;
  return PaletteColor('custom', 'Свой цвет', bg, fg);
}

TemplateIcon iconById(String id) => templateIcons.firstWhere(
      (icon) => icon.id == id,
      orElse: () => templateIcons.first,
    );

IconData templateIconGlyph(String id) =>
    templateIconGlyphs[id] ?? Icons.vpn_key_outlined;

Color templatePictogramColor(String colorId) {
  return pictogramColorForBackground(colorById(colorId).bg);
}

Color pictogramColorForBackground(Color background) {
  return Color.lerp(background, Colors.black, 0.20)!;
}

Color categoryPictogramColor(String? colorId) => pictogramColorForBackground(
      colorById(colorId == null || colorId.isEmpty ? 'template_gray' : colorId)
          .bg,
    );

Color itemPictogramColor(SecretItem item, CardTemplate template) =>
    pictogramColorForBackground(itemDisplayColor(item, template).bg);

Color templateDisplayBackground(CardTemplate template) =>
    template.spbColor == null
        ? colorById(template.colorId).bg
        : Color(0xff000000 | (template.spbColor! & 0x00ffffff));

Color templateDisplayPictogramColor(CardTemplate template) =>
    pictogramColorForBackground(templateDisplayBackground(template));

Widget templateIconWidget(String id, {double size = 20, Color? color}) {
  final embeddedBytes = spbEmbeddedIconPngs[id.toUpperCase()];
  if (embeddedBytes != null) {
    return Image.memory(
      embeddedBytes,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) =>
          Icon(Icons.vpn_key_outlined, size: size, color: color),
    );
  }
  final originalAsset = spbPngIconAsset(id);
  if (originalAsset != null) {
    // Original SPB Wallet icons are 64x64. Do not scale them down to the
    // Material icon size requested by compact callers.
    return SizedBox(
      width: 64,
      height: 64,
      child: spbPackedImage(
        originalAsset,
        width: 64,
        height: 64,
        fit: BoxFit.none,
        filterQuality: FilterQuality.none,
        fallback: Icon(Icons.vpn_key_outlined, size: size, color: color),
      ),
    );
  }
  return Icon(templateIconGlyph(id), size: size, color: color);
}

String registerEmbeddedIcon(Uint8List bytes) {
  final id = SpbWalletDatabase.makeId();
  spbEmbeddedIconPngs[id.toUpperCase()] = bytes;
  return id;
}

Uint8List normalizeUserIconPng(image.Image source, {int size = 128}) {
  final scale = min(size / source.width, size / source.height);
  final width = max(1, (source.width * scale).round());
  final height = max(1, (source.height * scale).round());
  final resized = image.copyResize(
    source,
    width: width,
    height: height,
    interpolation: image.Interpolation.cubic,
  );
  final canvas = image.Image(width: size, height: size, numChannels: 4);
  final offsetX = (size - width) ~/ 2;
  final offsetY = (size - height) ~/ 2;
  final radius = max(1, (min(width, height) * 0.10).round());
  final cornerCenter = radius - 0.5;
  final radiusSquared = radius * radius;

  for (final pixel in resized) {
    final x = pixel.x;
    final y = pixel.y;
    final cornerX = x < radius
        ? cornerCenter
        : x >= width - radius
            ? width - radius - 0.5
            : null;
    final cornerY = y < radius
        ? cornerCenter
        : y >= height - radius
            ? height - radius - 0.5
            : null;
    final outsideRoundedCorner = cornerX != null &&
        cornerY != null &&
        ((x - cornerX) * (x - cornerX) + (y - cornerY) * (y - cornerY) >
            radiusSquared);
    canvas.setPixelRgba(
      offsetX + x,
      offsetY + y,
      pixel.r,
      pixel.g,
      pixel.b,
      outsideRoundedCorner ? 0 : pixel.a,
    );
  }
  return Uint8List.fromList(image.encodePng(canvas));
}

Future<({Uint8List bytes, String fileName})?> pickUserIconFile(
  BuildContext context,
) async {
  try {
    final picked = Platform.isAndroid
        ? await FilePicker.platform.pickFiles(
            type: FileType.image,
            withData: true,
            // Android converts gallery formats such as HEIC into an image
            // that the Dart decoder can reliably read.
            compressionQuality: 95,
          )
        : await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: const [
              'png',
              'ico',
              'jpg',
              'jpeg',
              'bmp',
              'gif',
              'webp',
            ],
            withData: true,
          );
    final file = picked?.files.single;
    if (file == null) return null;
    Uint8List? bytes = file.bytes;
    if ((bytes == null || bytes.isEmpty) && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Выбранный файл пуст или недоступен.');
    }
    image.Image? decoded;
    try {
      decoded = image.IcoDecoder().decodeImageLargest(bytes);
    } catch (_) {
      // The selected file can be a regular bitmap rather than ICO.
    }
    decoded ??= image.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Формат изображения не поддерживается.');
    }
    final pngBytes = normalizeUserIconPng(decoded);
    final baseName = file.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return (
      bytes: pngBytes,
      fileName: '${baseName.isEmpty ? 'icon' : baseName}.png',
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить изображение: $error')),
      );
    }
    return null;
  }
}

String attachmentMimeType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.bmp')) return 'image/bmp';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.doc')) return 'application/msword';
  if (lower.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
  if (lower.endsWith('.xlsx')) {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  if (lower.endsWith('.odt')) {
    return 'application/vnd.oasis.opendocument.text';
  }
  if (lower.endsWith('.ods')) {
    return 'application/vnd.oasis.opendocument.spreadsheet';
  }
  if (lower.endsWith('.rtf')) return 'application/rtf';
  if (lower.endsWith('.txt') ||
      lower.endsWith('.log') ||
      lower.endsWith('.csv') ||
      lower.endsWith('.json') ||
      lower.endsWith('.xml') ||
      lower.endsWith('.md') ||
      lower.endsWith('.yaml') ||
      lower.endsWith('.yml')) {
    return 'text/plain';
  }
  if (lower.endsWith('.mp3')) return 'audio/mpeg';
  if (lower.endsWith('.wav')) return 'audio/wav';
  if (lower.endsWith('.ogg')) return 'audio/ogg';
  if (lower.endsWith('.m4a')) return 'audio/mp4';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.webm')) return 'video/webm';
  return 'application/octet-stream';
}

({String fileName, Uint8List bytes}) gallerySafeAttachmentExport(
  String originalFileName,
  Uint8List bytes, {
  bool? isAndroid,
}) {
  final lowerName = originalFileName.toLowerCase();
  final isGalleryImage = const <String>[
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
    '.heic',
    '.heif',
    '.tif',
    '.tiff',
    '.avif',
    '.dng',
    '.svg',
  ].any(lowerName.endsWith);
  if (!(isAndroid ?? Platform.isAndroid) || !isGalleryImage) {
    return (fileName: originalFileName, bytes: bytes);
  }
  final safeOriginal = originalFileName
      .replaceAll(RegExp(r'[\\/:*?<>|]'), '_')
      .replaceAll(String.fromCharCode(34), '_')
      .trim();
  final archiveName = safeOriginal.isEmpty ? 'attachment' : safeOriginal;
  final baseName = archiveName.replaceFirst(RegExp(r'\.[^.]+$'), '');
  final archive = Archive()..addFile(ArchiveFile.bytes(archiveName, bytes));
  return (
    fileName: '${baseName.isEmpty ? 'attachment' : baseName}.apsattachment.zip',
    bytes: Uint8List.fromList(ZipEncoder().encode(archive)),
  );
}

Future<void> openAttachmentBytesWithSystem(
  String fileName,
  Uint8List bytes,
) async {
  final directory = await getTemporaryDirectory();
  final safeName = fileName
      .replaceAll(RegExp(r'[\\/:*?<>|]'), '_')
      .replaceAll(String.fromCharCode(34), '_');
  // FileProvider supplies the real MIME type. The service extension prevents
  // gallery applications from treating the private working copy as a photo.
  final temporaryName = Platform.isAndroid
      ? 'wallet_aps_${safeName.hashCode.toUnsigned(32)}.apsblob'
      : 'wallet_aps_$safeName';
  final file = File('${directory.path}${Platform.pathSeparator}$temporaryName');
  await file.writeAsBytes(bytes, flush: true);
  if (Platform.isAndroid) {
    final opened = await spbWalletChannel.invokeMethod<bool>('openFile', {
      'path': file.path,
      'mimeType': attachmentMimeType(fileName),
    });
    if (opened != true) {
      throw StateError('Android не смог открыть файл системным приложением.');
    }
    return;
  }
  if (Platform.isWindows) {
    await Process.start(
        'cmd',
        [
          '/c',
          'start',
          '',
          file.path,
        ],
        runInShell: true);
  } else if (Platform.isMacOS) {
    await Process.start('open', [file.path]);
  } else {
    await Process.start('xdg-open', [file.path]);
  }
}

Widget templateMenuIconLabel(
  String iconId,
  String text, {
  double iconScale = 1,
}) {
  final icon = templateIconWidget(iconId, size: 18);
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (iconScale == 1)
        icon
      else
        SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Transform.scale(scale: iconScale, child: icon),
          ),
        ),
      const SizedBox(width: 8),
      Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
    ],
  );
}

String defaultIconForTemplateName(String name, Iterable<String> fieldLabels) {
  final text = ([name, ...fieldLabels]).join(' ').toLowerCase();
  if (text.contains('банк') ||
      text.contains('bank') ||
      text.contains('счет') ||
      text.contains('account')) {
    return 'bank';
  }
  if (text.contains('карта') || text.contains('card') || text.contains('cvv')) {
    return 'card';
  }
  if (text.contains('wi-fi') ||
      text.contains('wifi') ||
      text.contains('ssid')) {
    return 'wifi';
  }
  if (text.contains('почт') ||
      text.contains('mail') ||
      text.contains('email')) {
    return 'mail';
  }
  if (text.contains('паспорт') ||
      text.contains('документ') ||
      text.contains('удостовер') ||
      text.contains('document') ||
      text.contains('identity')) {
    return 'id';
  }
  if (text.contains('сервер') ||
      text.contains('server') ||
      text.contains('ssh') ||
      text.contains('host')) {
    return 'server';
  }
  if (text.contains('лиценз') ||
      text.contains('license') ||
      text.contains('ключ продукта')) {
    return 'license';
  }
  if (text.contains('замет') ||
      text.contains('note') ||
      text.contains('memo')) {
    return 'note';
  }
  if (text.contains('телефон') || text.contains('phone')) return 'phone';
  if (text.contains('сайт') ||
      text.contains('url') ||
      text.contains('web') ||
      text.contains('internet')) {
    return 'globe';
  }
  if (text.contains('облак') || text.contains('cloud')) return 'cloud';
  if (text.contains('база') || text.contains('database')) return 'database';
  if (text.contains('крипт') ||
      text.contains('bitcoin') ||
      text.contains('crypto')) {
    return 'crypto';
  }
  if (text.contains('pin') ||
      text.contains('парол') ||
      text.contains('password') ||
      text.contains('логин')) {
    return 'key';
  }
  return 'key';
}

String itemIconId(SecretItem item, CardTemplate template) {
  final iconId = item.iconId;
  return iconId == null || iconId.isEmpty ? template.iconId : iconId;
}

String syntheticSpbIconIdForUi(String uiIconId) {
  // A legacy icon selected from an existing .swl must retain its real ID.
  // Hashing it would make the old database point at a different icon.
  if (RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(uiIconId)) {
    return uiIconId.toUpperCase();
  }
  var first = 2166136261;
  var second = 2166136261 ^ 0x9e3779b9;
  for (final codeUnit in 'wallet-aps-icon:$uiIconId'.codeUnits) {
    first ^= codeUnit;
    first = (first * 16777619) & 0xffffffff;
    second ^= codeUnit + 31;
    second = (second * 16777619) & 0xffffffff;
  }
  return first.toRadixString(16).padLeft(8, '0').toUpperCase() +
      second.toRadixString(16).padLeft(8, '0').toUpperCase();
}

String? uiIconIdFromSyntheticSpbIcon(String spbIconId) {
  final normalized = spbIconId.toUpperCase();
  for (final icon in templateIcons) {
    if (syntheticSpbIconIdForUi(icon.id) == normalized) return icon.id;
  }
  for (final asset in spb64PngIconAssets) {
    if (syntheticSpbIconIdForUi(asset) == normalized) return asset;
    final relative = asset.startsWith('spb://') ? asset.substring(6) : asset;
    // Releases up to v0.1.18 hashed the loose-file asset path. Recognize
    // those IDs after moving the images into the single packed asset.
    if (syntheticSpbIconIdForUi('assets/spb_icons_package/$relative') ==
            normalized ||
        syntheticSpbIconIdForUi(
              'assets/spb_wallet_libraries/icons/$relative',
            ) ==
            normalized) {
      return asset;
    }
  }
  return null;
}

const _spbOriginalIconAssetDirectory = 'spb://apk_icons/res/drawable-hdpi';

// Built-in Spb Wallet IconID values are stable identifiers, not row numbers.
// Keep the correspondence explicit: database order differs from icons_NNN.png.
const spbOriginalIconAssets = <String, String>{
  // Finance.
  'A74FE6691728757D': '$_spbOriginalIconAssetDirectory/icons_010.png', // Visa
  'E4186A7B247E2B1D': '$_spbOriginalIconAssetDirectory/icons_068.png', // Bank
  '4428DBE8E0FDBEF5':
      '$_spbOriginalIconAssetDirectory/icons_011.png', // MasterCard
  'BD097D2EE2FA614A': '$_spbOriginalIconAssetDirectory/icons_012.png', // Cirrus
  '6FCAF114B73422CF':
      '$_spbOriginalIconAssetDirectory/icons_013.png', // Diners Club
  '490FA51A66910C69':
      '$_spbOriginalIconAssetDirectory/icons_014.png', // American Express
  '556D5E8F02589023':
      '$_spbOriginalIconAssetDirectory/icons_025.png', // Traveller cheque
  '7291F51A432B6530':
      '$_spbOriginalIconAssetDirectory/icons_052.png', // Loan / mortgage
  '40F61F0CE55A0757':
      '$_spbOriginalIconAssetDirectory/icons_053.png', // Investments
  'D3AB05E94F9E4C18':
      '$_spbOriginalIconAssetDirectory/icons_026.png', // Calling card
  '52AB4DC040DF39EA':
      '$_spbOriginalIconAssetDirectory/icons_027.png', // Personal insurance
  'AD817751F169F5F9':
      '$_spbOriginalIconAssetDirectory/icons_024.png', // Insurance policy
  'CEBAB052995FF2BA':
      '$_spbOriginalIconAssetDirectory/icons_017.png', // Generic card
  '71076D75AD9AD080':
      '$_spbOriginalIconAssetDirectory/icons_015.png', // Discover
  '26DAEC5D7E4E6715':
      '$_spbOriginalIconAssetDirectory/icons_016.png', // Maestro
  // Personal records.
  '289B3CF7980A951E':
      '$_spbOriginalIconAssetDirectory/icons_041.png', // Automobile
  '20678C366BED420F':
      '$_spbOriginalIconAssetDirectory/icons_055.png', // Clothing sizes
  'E8950204C5B13337':
      '$_spbOriginalIconAssetDirectory/icons_051.png', // Glasses
  '9DEB9BC675EC569A':
      '$_spbOriginalIconAssetDirectory/icons_033.png', // Voter card
  'AC2FDDB9D988A96E':
      '$_spbOriginalIconAssetDirectory/icons_018.png', // Driver license
  'F7F133A9EDA8AD3E':
      '$_spbOriginalIconAssetDirectory/icons_019.png', // Passport
  '364C9DE41B5927E4':
      '$_spbOriginalIconAssetDirectory/icons_035.png', // Personal card
  'C0F3D5137928104F':
      '$_spbOriginalIconAssetDirectory/icons_020.png', // Social security
  'D8466DC42C598628':
      '$_spbOriginalIconAssetDirectory/icons_036.png', // Library card
  'F1DF61C4072919F4':
      '$_spbOriginalIconAssetDirectory/icons_037.png', // Membership
  '55B25AA977BBABA0':
      '$_spbOriginalIconAssetDirectory/icons_056.png', // Prescription
  '5DB82F9F9859FF2C':
      '$_spbOriginalIconAssetDirectory/icons_058.png', // Meal delivery
  '7650B2DDF2971084':
      '$_spbOriginalIconAssetDirectory/icons_057.png', // Restaurant
  'D0A03FA49259E894':
      '$_spbOriginalIconAssetDirectory/icons_065.png', // Combination lock
  '6ACC0F32AAB28ED8': '$_spbOriginalIconAssetDirectory/icons_050.png', // Event
  'CAACFBE92AAC7C7D':
      '$_spbOriginalIconAssetDirectory/icons_028.png', // Frequent flyer
  'AB540457E8E62887':
      '$_spbOriginalIconAssetDirectory/icons_029.png', // Garage door
  'E610927897C0F039': '$_spbOriginalIconAssetDirectory/icons_060.png', // Pet
  'EDE2A1A2E3B172D5':
      '$_spbOriginalIconAssetDirectory/icons_066.png', // Warranty
  '38A06822A088D80F':
      '$_spbOriginalIconAssetDirectory/icons_067.png', // Training
  'BC8395AF3885E099':
      '$_spbOriginalIconAssetDirectory/icons_030.png', // Password history
  '28A67DABE33DA42B':
      '$_spbOriginalIconAssetDirectory/icons_046.png', // Mobile phone
  // Contacts, Internet and computers.
  '14BD44DE9F2F4F99':
      '$_spbOriginalIconAssetDirectory/icons_034.png', // Contact
  'B8058FF4BA946340':
      '$_spbOriginalIconAssetDirectory/icons_045.png', // Home service
  'E5442EED85AD0572':
      '$_spbOriginalIconAssetDirectory/icons_063.png', // Emergency
  '62767D3E1BC8E2C8':
      '$_spbOriginalIconAssetDirectory/icons_061.png', // Note / file
  '867CA874B9508C95': '$_spbOriginalIconAssetDirectory/icons_021.png', // Email
  'A6E0F0CFDFAF6928':
      '$_spbOriginalIconAssetDirectory/icons_022.png', // Website
  '087CF65FC366A122':
      '$_spbOriginalIconAssetDirectory/icons_038.png', // Serial number
  'B7D8EDDF4E4F493E':
      '$_spbOriginalIconAssetDirectory/icons_023.png', // Software serial
  '27445EACFC5DD8D9':
      '$_spbOriginalIconAssetDirectory/icons_062.png', // Voice mail
  '31785C316B046C3F':
      '$_spbOriginalIconAssetDirectory/icons_039.png', // Internet settings
  '24760DEDF9C71546':
      '$_spbOriginalIconAssetDirectory/icons_047.png', // Network
  '508A24D5C6B90C54': '$_spbOriginalIconAssetDirectory/icons_031.png', // Server
  'BC51FC021F344286':
      '$_spbOriginalIconAssetDirectory/icons_040.png', // Hosting
  '243B78A1D8C7E32C':
      '$_spbOriginalIconAssetDirectory/icons_032.png', // Online shopping
  // Travel.
  '97973FA7389FFE1C':
      '$_spbOriginalIconAssetDirectory/icons_054.png', // Car rental
  '68E51FEE9B8D4E7C': '$_spbOriginalIconAssetDirectory/icons_044.png', // Flight
  '06D4F7F69F1E42E5': '$_spbOriginalIconAssetDirectory/icons_049.png', // Hotel
  'DAECE1D88696E125':
      '$_spbOriginalIconAssetDirectory/icons_064.png', // Ground transport
  '5DEF85654F9DC2CD': '$_spbOriginalIconAssetDirectory/icons_042.png', // ISIC
  'A06AD15403B46BAB': '$_spbOriginalIconAssetDirectory/icons_043.png', // ITIC
  '30E614ECB34BA668':
      '$_spbOriginalIconAssetDirectory/icons_048.png', // Travel visa
  // Default folders.
  '54320B4412A08007':
      '$_spbOriginalIconAssetDirectory/icons_003.png', // Credit cards
  'E864A803F91DA5C4':
      '$_spbOriginalIconAssetDirectory/icons_005.png', // Finance
  '4863F2D4E9D399F6':
      '$_spbOriginalIconAssetDirectory/icons_006.png', // Personal
  '96DAFC9A4C1F55F6': '$_spbOriginalIconAssetDirectory/icons_004.png', // Family
  '5D595FE47887E6C9': '$_spbOriginalIconAssetDirectory/icons_008.png', // Work
  '6E4AAD6B4F39E378':
      '$_spbOriginalIconAssetDirectory/icons_002.png', // Computers
  '0C1E037B56E9E59B':
      '$_spbOriginalIconAssetDirectory/icons_001.png', // Leisure
};

const spbDefaultOriginalIconAsset =
    '$_spbOriginalIconAssetDirectory/icons_001.png';
const spbPasswordTemplateIconAsset =
    '$_spbOriginalIconAssetDirectory/icons_030.png';

const spbFolderIconAssetsById = <String, String>{
  '54320B4412A08007': '$_spbOriginalIconAssetDirectory/icons_003.png',
  'E864A803F91DA5C4': '$_spbOriginalIconAssetDirectory/icons_005.png',
  '4863F2D4E9D399F6': '$_spbOriginalIconAssetDirectory/icons_006.png',
  '96DAFC9A4C1F55F6': '$_spbOriginalIconAssetDirectory/icons_004.png',
  '5D595FE47887E6C9': '$_spbOriginalIconAssetDirectory/icons_008.png',
  '6E4AAD6B4F39E378': '$_spbOriginalIconAssetDirectory/icons_002.png',
  '0C1E037B56E9E59B': '$_spbOriginalIconAssetDirectory/icons_001.png',
};

const spbFolderIconAssetsByName = <String, String>{
  'air': '$_spbOriginalIconAssetDirectory/icons_007.png',
  'auto': '$_spbOriginalIconAssetDirectory/icons_009.png',
  'bank': '$_spbOriginalIconAssetDirectory/icons_005.png',
  'business': '$_spbOriginalIconAssetDirectory/icons_008.png',
  'internet': '$_spbOriginalIconAssetDirectory/icons_002.png',
};

String spbFolderIconAsset(String path, String iconId) {
  final normalizedIconId = iconId.toUpperCase();
  if (spbEmbeddedIconPngs.containsKey(normalizedIconId)) {
    return normalizedIconId;
  }
  final selectedUiIcon = uiIconIdFromSyntheticSpbIcon(normalizedIconId);
  if (selectedUiIcon != null) return selectedUiIcon;
  final storedFolderIcon = spbFolderIconAssetsById[normalizedIconId];
  if (storedFolderIcon != null) return storedFolderIcon;
  final originalIcon = spbOriginalIconAsset(normalizedIconId);
  if (originalIcon != null) return originalIcon;
  final name = path.split(RegExp(r'\s*/\s*')).last.trim().toLowerCase();
  return spbFolderIconAssetsByName[name] ?? spbDefaultOriginalIconAsset;
}

String formatCardModifiedAt(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(local.day)}.${twoDigits(local.month)}.${local.year} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

String spbTemplateIconForUi(SpbWalletTemplateRecord template) {
  final iconId = template.iconId.toUpperCase();
  if (spbEmbeddedIconPngs.containsKey(iconId)) return iconId;
  final normalizedName = template.name.toLowerCase();
  if (iconId == '62767D3E1BC8E2C8' &&
      (normalizedName.contains('парол') ||
          normalizedName.contains('password'))) {
    return spbPasswordTemplateIconAsset;
  }
  if (spbOriginalIconAsset(iconId) != null) return iconId;
  final selectedUiIcon = uiIconIdFromSyntheticSpbIcon(iconId);
  if (selectedUiIcon != null) return selectedUiIcon;
  return defaultIconForTemplateName(
    template.name,
    template.fields.map((field) => field.name),
  );
}

String? spbOriginalIconAsset(String iconId) {
  return spbOriginalIconAssets[iconId.toUpperCase()];
}

String? spbPngIconAsset(String iconId) {
  if ((iconId.startsWith('spb://') ||
          iconId.startsWith('assets/spb_icons_package/') ||
          iconId.startsWith('assets/spb_wallet_libraries/icons/')) &&
      iconId.toLowerCase().endsWith('.png')) {
    return normalizeSpbPackedIconId(iconId);
  }
  return spbOriginalIconAsset(iconId);
}

bool spbIconCanRender(String iconId) =>
    spbEmbeddedIconPngs.containsKey(iconId.toUpperCase()) ||
    spbPngIconAsset(iconId) != null;

String spbCardIconForUi(String cardIconId, String templateIconId) {
  if (cardIconId.isEmpty) return templateIconId;
  final normalized = cardIconId.toUpperCase();
  if (spbIconCanRender(normalized)) return normalized;
  return uiIconIdFromSyntheticSpbIcon(cardIconId) ?? templateIconId;
}

String makeId(String prefix) {
  final random = Random.secure();
  final suffix = List.generate(
    12,
    (_) => random.nextInt(16).toRadixString(16),
  ).join();
  return '${prefix}_$suffix';
}

enum EntryMode { openSwl, createSwl }

enum VirtualKeyboardMode { numeric, uppercase, lowercase, symbols }

const spbDescriptionFieldId = '__spb_description';
const spbWalletChannel = MethodChannel('wallet_aps/spb_wallet');
const windowChannel = MethodChannel('wallet_aps/window');

bool isNotesLabel(String label) {
  final normalized = label.trim().toLowerCase();
  return normalized == 'note' ||
      normalized == 'notes' ||
      normalized == 'заметка' ||
      normalized == 'заметки' ||
      normalized.contains('замет');
}

bool isRealNotesField(FieldDefinition field) {
  if (field.id == spbDescriptionFieldId) return false;
  final normalizedId = field.id.trim().toLowerCase();
  return normalizedId == 'note' ||
      normalizedId == 'notes' ||
      isNotesLabel(field.label);
}

bool fieldTypeIsSecret(String type) =>
    type == 'password' || type == 'custom_secret';

bool fieldDefinitionIsSecret(FieldDefinition field) =>
    field.secret || fieldTypeIsSecret(field.type);

bool spbFieldIsSecret(int fieldTypeId, String fieldName) {
  if (fieldTypeId == 4) return true;
  final normalized = fieldName.toLowerCase();
  return normalized.contains('password') ||
      normalized.contains('pass') ||
      normalized.contains('парол') ||
      normalized.contains('pin') ||
      normalized.contains('пин') ||
      normalized.contains('cvv') ||
      normalized.contains('код');
}

String secretFieldTypeForName(String fieldName) {
  final normalized = fieldName.trim().toLowerCase();
  if (normalized.contains('парол') ||
      normalized.contains('password') ||
      normalized.contains('pass')) {
    return 'password';
  }
  return 'custom_secret';
}

String spbFieldTypeToUi(int fieldTypeId, [String fieldName = '']) {
  if (spbFieldIsSecret(fieldTypeId, fieldName)) {
    return secretFieldTypeForName(fieldName);
  }
  switch (fieldTypeId) {
    case 2:
      return 'number';
    case 6:
      return 'url';
    case 7:
      return 'email';
    case 8:
      return 'phone';
    default:
      return 'text';
  }
}

String fieldDisplayValue(
  FieldDefinition field,
  String value, {
  required bool revealed,
}) =>
    fieldDefinitionIsSecret(field) && !revealed ? '••••••••' : value;

String noteFieldIdForTemplate(CardTemplate template) {
  for (final field in template.fields) {
    if (field.id == spbDescriptionFieldId) return spbDescriptionFieldId;
  }
  for (final field in template.fields) {
    if (isRealNotesField(field)) return field.id;
  }
  return spbDescriptionFieldId;
}

Map<String, String> spbCardValuesForUi(
  CardTemplate template,
  SpbWalletCardRecord card,
) {
  final values = Map<String, String>.from(card.fieldValues);
  values.remove(spbDescriptionFieldId);
  values.removeWhere((_, value) => !cardFieldValueIsPopulated(value));
  if (card.description.trim().isNotEmpty) {
    values[spbDescriptionFieldId] = card.description;
  }
  return values;
}

bool cardFieldValueIsPopulated(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.isNotEmpty && normalized != 'http://www';
}

List<FieldDefinition> fieldsForItem(
  CardTemplate template,
  SecretItem item, {
  bool includeHidden = false,
}) {
  final byId = <String, FieldDefinition>{
    for (final field in template.fields) field.id: field,
  };
  final populatedValueIds = item.values.entries
      .where((entry) => cardFieldValueIsPopulated(entry.value))
      .map((entry) => entry.key);
  for (final id in populatedValueIds) {
    byId.putIfAbsent(
      id,
      () => FieldDefinition(
        id: id,
        label: 'Сохранённое поле ${id.length > 8 ? id.substring(0, 8) : id}',
        type: 'text',
      ),
    );
  }
  final visibleIds = projectVisibleFieldIds(
    definedIds: template.fields.map((field) => field.id),
    valueIds: populatedValueIds,
    preferredOrder: item.fieldOrder,
    hiddenIds: includeHidden ? const {} : item.hiddenFieldIds,
  );
  return [for (final id in visibleIds) byId[id]!];
}

int spbFieldTypeId(FieldDefinition field) {
  if (fieldTypeIsSecret(field.type)) {
    return 4;
  }
  switch (field.type) {
    case 'multiline_note':
      return 1;
    case 'url':
      return 6;
    case 'email':
      return 7;
    case 'date':
      return 1;
    case 'phone':
      return 8;
    case 'number':
      return 2;
    default:
      return 1;
  }
}

bool createInitialSwlVaultFile(Map<String, dynamic> payload) {
  final path = payload['path'] as String;
  final password = payload['password'] as String;
  final templates = (payload['templates'] as List<dynamic>)
      .map(
        (entry) =>
            CardTemplate.fromJson(Map<String, dynamic>.from(entry as Map)),
      )
      .toList();
  final itemEntries = (payload['items'] as List<dynamic>)
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .toList();
  final items = itemEntries.map((entry) => SecretItem.fromJson(entry)).toList();
  final categoryIcons = Map<String, String>.from(
    payload['categoryIcons'] as Map<dynamic, dynamic>,
  );
  SpbWalletDatabase? wallet;
  try {
    wallet = SpbWalletDatabase.create(path, password);
    for (final template in templates) {
      wallet.saveTemplate(
        SpbWalletTemplateDraft(
          id: template.id,
          name: template.name,
          iconId: syntheticSpbIconIdForUi(template.iconId),
          fields: template.fields
              .where((field) => field.id != spbDescriptionFieldId)
              .map(
                (field) => SpbWalletTemplateFieldRecord(
                  id: field.id,
                  name: field.label,
                  templateId: template.id,
                  fieldTypeId: spbFieldTypeId(field),
                ),
              )
              .toList(),
        ),
      );
    }
    final templateMap = {
      for (final template in templates) template.id: template,
    };
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final template = templateMap[item.templateId];
      if (template == null) continue;
      wallet.saveCard(
        SpbWalletCardDraft(
          id: item.id,
          title: item.title,
          description: '',
          categoryPath: item.category,
          templateId: template.id,
          iconId: syntheticSpbIconIdForUi(item.iconId ?? template.iconId),
          fieldValues: item.values,
          cardColor: itemEntries[i]['cardColor'] as int,
          backgroundImageBase64: item.backgroundImageBase64,
        ),
      );
    }
    for (final entry in categoryIcons.entries) {
      wallet.saveCategoryIcon(entry.key, syntheticSpbIconIdForUi(entry.value));
    }
    wallet.close();
    return true;
  } catch (_) {
    try {
      wallet?.close();
    } catch (_) {}
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
    rethrow;
  }
}

bool cloneSwlVaultWithPassword(Map<String, dynamic> payload) {
  final path = payload['path'] as String;
  final password = payload['password'] as String;
  final sourcePassword = payload['sourcePassword'] as String;
  final passwordHint = payload['passwordHint'] as String? ?? '';
  final baseBytes = Uint8List.fromList(payload['baseBytes'] as List<int>);
  final targetFile = File(path);
  SpbWalletDatabase? verification;
  try {
    if (targetFile.existsSync()) {
      throw StateError('Файл новой базы уже существует.');
    }
    targetFile.writeAsBytesSync(baseBytes, flush: true);
    WalletRekeyService.rekeyFile(
      targetFile.path,
      oldPassword: sourcePassword,
      newPassword: password,
    );
    verification = SpbWalletDatabase.open(targetFile.path, password);
    if (payload['renameNewWalletAboutFolder'] == true) {
      renameNewWalletAboutFolder(verification);
    }
    verification.savePasswordHint(passwordHint);
    verification.flushToDisk();
    verification.close(flush: false);
    verification = null;
    return true;
  } catch (_) {
    try {
      verification?.close(flush: false);
    } catch (_) {}
    try {
      if (targetFile.existsSync()) targetFile.deleteSync();
    } catch (_) {}
    rethrow;
  }
}

void renameNewWalletAboutFolder(SpbWalletDatabase wallet) {
  final categories = wallet.loadSnapshot().categories;
  final byId = {for (final category in categories) category.id: category};
  for (final category in categories) {
    if (category.name.trim().toLowerCase() != 'о программе spb wallet') {
      continue;
    }
    final names = <String>[category.name];
    var parentId = category.parentId;
    final visited = <String>{category.id};
    while (parentId.isNotEmpty && visited.add(parentId)) {
      final parent = byId[parentId];
      if (parent == null) break;
      names.insert(0, parent.name);
      parentId = parent.parentId;
    }
    wallet.renameCategory(
      names.join(' / '),
      'О программе Wallet',
      category.iconId,
      colorId: category.colorId,
    );
  }
}

bool createSwlVaultFromBaseFile(Map<String, dynamic> payload) =>
    cloneSwlVaultWithPassword({
      ...payload,
      'sourcePassword': '0000',
      'renameNewWalletAboutFolder': true,
    });

String? normalizeNewVaultDirectorySelection(
  String selectedPath,
  FileSystemEntityType entityType,
) {
  final path = selectedPath.trim();
  if (path.isEmpty || entityType == FileSystemEntityType.notFound) return null;
  if (entityType == FileSystemEntityType.file) return File(path).parent.path;
  return entityType == FileSystemEntityType.directory ? path : null;
}

int passwordStrengthScore(String password) {
  if (password.isEmpty) {
    return 0;
  }
  var score = 1;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  if (RegExp(r'[a-zа-я]').hasMatch(password) &&
      RegExp(r'[A-ZА-Я]').hasMatch(password)) {
    score++;
  }
  if (RegExp(r'\d').hasMatch(password) &&
      RegExp(r'[^A-Za-zА-Яа-я0-9]').hasMatch(password)) {
    score++;
  }
  return score.clamp(0, 5);
}

String normalizeUrlInput(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed)) {
    return trimmed;
  }
  return 'https://$trimmed';
}

String formatDateInput(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString().padLeft(4, '0');
  return '$day.$month.$year';
}

DateTime? parseDateInput(String value) {
  final trimmed = value.trim();
  final dotted = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(trimmed);
  if (dotted != null) {
    final day = int.parse(dotted.group(1)!);
    final month = int.parse(dotted.group(2)!);
    final year = int.parse(dotted.group(3)!);
    return validDate(year, month, day);
  }
  final iso = RegExp(r'^(\d{4})-(\d{2})(?:-(\d{2}))?$').firstMatch(trimmed);
  if (iso != null) {
    final year = int.parse(iso.group(1)!);
    final month = int.parse(iso.group(2)!);
    final day = int.parse(iso.group(3) ?? '1');
    return validDate(year, month, day);
  }
  return null;
}

DateTime? validDate(int year, int month, int day) {
  if (year < 1 || month < 1 || month > 12 || day < 1) return null;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

class DateTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final removedAutomaticDot = newValue.text.length < oldValue.text.length &&
        oldValue.text.endsWith('.') &&
        newValue.text == oldValue.text.substring(0, oldValue.text.length - 1);
    if (removedAutomaticDot && digits.isNotEmpty) {
      digits = digits.substring(0, digits.length - 1);
    }
    final trimmed = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buffer = StringBuffer();
    if (trimmed.isNotEmpty) {
      buffer.write(trimmed.substring(0, min(2, trimmed.length)));
    }
    if (trimmed.length >= 2) buffer.write('.');
    if (trimmed.length > 2) {
      buffer.write(trimmed.substring(2, min(4, trimmed.length)));
    }
    if (trimmed.length >= 4) buffer.write('.');
    if (trimmed.length > 4) buffer.write(trimmed.substring(4));
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class VaultShell extends StatefulWidget {
  const VaultShell({
    this.initiallyUnlocked = false,
    this.initialVaultPath,
    super.key,
  });

  final bool initiallyUnlocked;
  final String? initialVaultPath;

  @override
  State<VaultShell> createState() => _VaultShellState();
}

class _VaultShellState extends State<VaultShell> with WidgetsBindingObserver {
  final vaultNameController = TextEditingController(text: 'личная');
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();
  final searchController = TextEditingController();
  final passwordFocusNode = FocusNode(debugLabel: 'vaultPassword');

  EntryMode entryMode = EntryMode.openSwl;
  bool showPassword = false;
  bool showConfirm = false;
  bool loginHintVisible = false;
  String loginPasswordHint = '';
  bool unlocked = false;
  bool? menuOpenOverride;
  bool creatingVault = false;
  String? configuredWindowMode;
  String? configuredMainWindowTitle;
  VirtualKeyboardMode virtualKeyboardMode = VirtualKeyboardMode.numeric;
  String activeView = 'cards';
  String? message;
  String? spbWalletPath;
  String? spbWalletUri;
  String? spbWalletDisplayPath;
  bool spbWalletWritable = true;
  bool spbWritePending = false;
  bool vaultDirty = false;
  String? syncSourcePath;
  String? syncSourceUrl;
  String? syncOriginProvider;
  SpbWalletDatabase? spbWallet;
  String syncProvider = 'mounted_folder';
  String templateFilter = '';
  String templateSearchQuery = '';
  String sortMode = 'modified_desc';
  String? selectedItemId;
  final List<String> recentlyOpenedItemIds = [];
  String selectedCategoryPath = '';
  String? selectedCategoryId;
  bool mobileTemplatesOpen = false;
  String? selectedTemplateId;
  int mobilePane = 0;
  bool rootTreeExpanded = true;
  final Set<String> expandedCategoryPaths = {};
  double? spbNavigatorWidth;
  double? spbActionsPanelWidth;
  String spbSubmittedSearchQuery = '';
  bool spbExactSearch = false;
  bool spbTasksExpanded = true;
  bool spbFoundExpanded = true;
  bool spbFrequentExpanded = true;
  bool spbObjectMenuPointerActive = false;
  bool spbContextMenuOpen = false;
  final GlobalKey spbSessionUndoButtonKey = GlobalKey();
  final GlobalKey spbSessionTrashButtonKey = GlobalKey();
  final ScrollController spbFoundScrollController = ScrollController();
  final ScrollController spbFrequentScrollController = ScrollController();
  final ScrollController spbMobileActionsScrollController = ScrollController();
  Timer? inactivityTimer;
  Timer? inactivityCountdownTimer;
  int inactivitySecondsRemaining = 15;
  bool inactivityWarningVisible = false;
  Timer? lockedExitTimer;
  Timer? lockedExitCountdownTimer;
  int lockedExitSecondsRemaining = 30;
  bool lockedExitWarningVisible = false;
  Timer? passwordUnlockDebounce;
  bool automaticUnlockInProgress = false;
  bool closingForInactivity = false;
  DateTime lastUserActivityAt = DateTime.now();
  DateTime? lastSyncAt;

  List<CardTemplate> templates = builtInTemplates();
  List<SecretItem> items = [];
  Map<String, CardTemplate> templatesById = {};
  Map<String, SecretItem> itemsById = {};
  List<ConflictRecord> conflicts = [];
  List<SpbWalletCardLoadFailure> cardLoadFailures = [];
  WalletLoadReport walletLoadReport = const WalletLoadReport([]);
  List<ExistingVault> recentVaults = [];
  final Map<String, String> spbIconIdByUiIcon = {};
  Map<String, String> categoryIconsByPath = {};
  Map<String, String> categoryColorsByPath = {};
  Map<String, String> categoryIdsByPath = {};
  Map<String, String> categoryPathsById = {};
  Set<String> categoryPaths = {};
  final Set<String> revealed = {};
  final Map<String, String> syncConfig = {};
  final List<SessionTrashEntry> sessionTrash = [];
  final Set<String> sessionTrashCardIds = {};
  final Set<String> sessionTrashFolderPaths = {};
  final Set<String> sessionTrashTemplateIds = {};
  final List<SessionUndoEntry> sessionUndoHistory = [];
  bool sessionUndoInProgress = false;

  bool get createMode => entryMode == EntryMode.createSwl;

  String get normalizedVaultBaseName {
    final rawName = vaultNameController.text.trim().replaceAll(
          RegExp(r'\.swl$', caseSensitive: false),
          '',
        );
    final safeName = rawName.isEmpty ? 'personal' : rawName;
    return safeName.replaceAll(RegExp(r'[^\wа-яА-ЯёЁ.-]+', unicode: true), '_');
  }

  Future<File> swlVaultFile() async {
    final directory = await appVaultDirectory();
    return File('${directory.path}/$normalizedVaultBaseName.swl');
  }

  Future<File> recentVaultsFile() async {
    final stateDirectory = await appStateDirectory();
    final current = File('${stateDirectory.path}/wallet_aps_recent_swl.json');
    if (!current.existsSync()) {
      // One-time compatibility copy for installations created before renaming.
      final legacy = File('${stateDirectory.path}/actitpass_recent_swl.json');
      if (legacy.existsSync()) {
        await legacy.copy(current.path);
      }
    }
    return current;
  }

  Future<Directory> appStateDirectory() async {
    if (Platform.isAndroid) {
      final directory = Directory('${Directory.systemTemp.parent.path}/files');
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      return directory;
    }
    final directory = await getApplicationSupportDirectory();
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }

  Future<Directory> appVaultDirectory() async {
    final base = Platform.isAndroid
        ? await appStateDirectory()
        : await getApplicationDocumentsDirectory();
    final directory = Directory('${base.path}/Wallet APS');
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }

  bool isAndroidCacheWalletPath(String path) =>
      Platform.isAndroid && path.contains('/cache/spbwallet_');

  @override
  void initState() {
    super.initState();
    templatesById = indexEntitiesById(templates, (template) => template.id);
    WidgetsBinding.instance.addObserver(this);
    unlocked = widget.initiallyUnlocked;
    final initialVaultPath = widget.initialVaultPath;
    if (initialVaultPath != null && initialVaultPath.isNotEmpty) {
      spbWalletPath = initialVaultPath;
      spbWalletDisplayPath = initialVaultPath;
      vaultNameController.text = _vaultTitleFromPath(initialVaultPath);
    }
    searchController.addListener(() => setState(() {}));
    passwordController.addListener(scheduleAutomaticUnlock);
    loadRecentVaults();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        passwordFocusNode.requestFocus();
        initializeExternalWalletHandling();
      }
    });
  }

  Future<void> initializeExternalWalletHandling() async {
    if (!Platform.isAndroid) return;
    spbWalletChannel.setMethodCallHandler((call) async {
      if (call.method != 'openWallet' || call.arguments is! Map) return;
      await applyExternalAndroidWallet(
        Map<Object?, Object?>.from(call.arguments as Map),
      );
    });
    try {
      final launchWallet = await spbWalletChannel
          .invokeMapMethod<Object?, Object?>('getLaunchWallet');
      if (launchWallet != null) {
        await applyExternalAndroidWallet(launchWallet);
      }
    } on MissingPluginException {
      // Widget tests and non-Android targets do not provide this channel.
    }
  }

  Future<void> applyExternalAndroidWallet(Map<Object?, Object?> wallet) async {
    final path = wallet['localPath']?.toString();
    if (path == null || path.isEmpty || !mounted) return;
    if (unlocked || spbWallet != null) {
      await closeCurrentVaultForPasswordPrompt();
      if (!mounted) return;
    }
    final displayName =
        wallet['displayName']?.toString() ?? _vaultTitleFromPath(path);
    final uri = wallet['uri']?.toString();
    setState(() {
      entryMode = EntryMode.openSwl;
      spbWalletPath = path;
      spbWalletUri = uri;
      spbWalletWritable = wallet['writable'] != false;
      spbWalletDisplayPath = wallet['displayPath']?.toString() ?? uri ?? path;
      syncSourcePath = null;
      syncSourceUrl = null;
      syncOriginProvider = null;
      vaultNameController.text = displayName;
      passwordController.clear();
      message = null;
    });
    if (uri != null && uri.isNotEmpty && wallet['persisted'] != false) {
      await rememberRecentVaultEntry(
        ExistingVault(
          title: displayName,
          uri: uri,
          displayPath: spbWalletDisplayPath,
        ),
      );
    }
    passwordFocusNode.requestFocus();
  }

  void synchronizeWindowMode() {
    if (!Platform.isWindows) return;
    final desiredMode = unlocked
        ? 'main'
        : message == null && !loginHintVisible
            ? 'login'
            : 'loginExpanded';
    final mainTitle = unlocked ? selectedVaultTitle : null;
    if (configuredWindowMode == desiredMode &&
        (!unlocked || configuredMainWindowTitle == mainTitle)) {
      return;
    }
    configuredWindowMode = desiredMode;
    configuredMainWindowTitle = mainTitle;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (unlocked) {
        configureMainWindow();
      } else {
        configureLoginWindow(expanded: message != null);
      }
    });
  }

  Future<void> configureLoginWindow({bool expanded = false}) async {
    if (!Platform.isWindows) return;
    try {
      await windowChannel.invokeMethod<void>(
        expanded ? 'showLoginExpanded' : 'showLogin',
      );
    } on MissingPluginException {
      // Other Flutter targets do not provide the Win32 window channel.
    }
  }

  Future<void> configureMainWindow() async {
    if (!Platform.isWindows) return;
    try {
      await windowChannel.invokeMethod<void>('showMain', selectedVaultTitle);
    } on MissingPluginException {
      // Other Flutter targets do not provide the Win32 window channel.
    }
  }

  Future<void> startLoginWindowDrag() async {
    if (!Platform.isWindows) return;
    try {
      await windowChannel.invokeMethod<void>('startDrag');
    } on MissingPluginException {
      // Other Flutter targets do not provide the Win32 window channel.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    inactivityTimer?.cancel();
    inactivityCountdownTimer?.cancel();
    lockedExitTimer?.cancel();
    lockedExitCountdownTimer?.cancel();
    purgeSessionTrashFromDatabase();
    persistVaultState();
    clearSessionUndoHistory();
    spbWallet?.close(flush: vaultDirty);
    passwordUnlockDebounce?.cancel();
    vaultNameController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    searchController.dispose();
    spbFoundScrollController.dispose();
    spbFrequentScrollController.dispose();
    spbMobileActionsScrollController.dispose();
    passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      purgeSessionTrashFromDatabase();
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      persistVaultState();
      unawaited(writeBackSpbWallet());
    }
    if (state == AppLifecycleState.resumed) {
      final idleFor = DateTime.now().difference(lastUserActivityAt);
      if (unlocked && idleFor >= const Duration(minutes: 3)) {
        unawaited(closeAfterInactivity());
      } else if (unlocked &&
          idleFor >= const Duration(minutes: 2, seconds: 45)) {
        unawaited(showInactivityWarning());
      } else if (!unlocked && idleFor >= const Duration(minutes: 5)) {
        unawaited(exitApplication());
      }
    }
  }

  void persistVaultState() {
    final wallet = spbWallet;
    if (wallet == null || !vaultDirty) return;
    wallet.saveRecentlyOpenedCardIds(recentlyOpenedItemIds);
    wallet.flushToDisk();
  }

  void markVaultDirty() {
    vaultDirty = true;
    spbWritePending = true;
  }

  Future<SessionUndoEntry> captureSessionUndo(
    String label,
    String iconId,
  ) async {
    final wallet = spbWallet;
    if (wallet == null) {
      throw StateError('База данных не открыта.');
    }
    return SessionUndoEntry(
      label: label,
      iconId: iconId,
      databaseSnapshot: await wallet.createUndoSnapshot(),
      trash: List<SessionTrashEntry>.from(sessionTrash),
      trashCardIds: Set<String>.from(sessionTrashCardIds),
      trashFolderPaths: Set<String>.from(sessionTrashFolderPaths),
      trashTemplateIds: Set<String>.from(sessionTrashTemplateIds),
    );
  }

  void commitSessionUndo(SessionUndoEntry entry) {
    sessionUndoHistory.add(entry);
    while (sessionUndoHistory.length > 12) {
      sessionUndoHistory.removeAt(0).databaseSnapshot.dispose();
    }
    if (mounted) setState(() {});
  }

  void discardSessionUndo(SessionUndoEntry? entry) {
    entry?.databaseSnapshot.dispose();
  }

  void clearSessionUndoHistory() {
    for (final entry in sessionUndoHistory) {
      entry.databaseSnapshot.dispose();
    }
    sessionUndoHistory.clear();
  }

  Future<void> restoreSessionUndoAt(int index) async {
    final wallet = spbWallet;
    if (wallet == null ||
        sessionUndoInProgress ||
        index < 0 ||
        index >= sessionUndoHistory.length) {
      return;
    }
    sessionUndoInProgress = true;
    final entry = sessionUndoHistory[index];
    try {
      await wallet.restoreUndoSnapshot(entry.databaseSnapshot);
      sessionTrash
        ..clear()
        ..addAll(entry.trash);
      sessionTrashCardIds
        ..clear()
        ..addAll(entry.trashCardIds);
      sessionTrashFolderPaths
        ..clear()
        ..addAll(entry.trashFolderPaths);
      sessionTrashTemplateIds
        ..clear()
        ..addAll(entry.trashTemplateIds);
      for (final removed in sessionUndoHistory.sublist(
        index,
        sessionUndoHistory.length,
      )) {
        removed.databaseSnapshot.dispose();
      }
      sessionUndoHistory.removeRange(index, sessionUndoHistory.length);
      markVaultDirty();
      final written = await writeBackSpbWallet();
      final snapshot = wallet.loadSnapshot();
      if (!mounted) return;
      setState(() {
        applySpbSnapshot(snapshot);
        if (selectedItemId != null &&
            !items.any((item) => item.id == selectedItemId)) {
          selectedItemId = null;
        }
        if (selectedTemplateId != null &&
            !templates.any((template) => template.id == selectedTemplateId)) {
          selectedTemplateId = null;
        }
        if (written) message = null;
      });
      showSpbOperationMessage('Отменено: ${entry.label}');
    } catch (error) {
      showSpbOperationMessage('Не удалось отменить изменение: $error');
    } finally {
      sessionUndoInProgress = false;
    }
  }

  bool isPathInSessionTrash(String path) {
    final normalized = path.trim();
    return sessionTrashFolderPaths.any(
      (folderPath) =>
          normalized == folderPath || normalized.startsWith('$folderPath / '),
    );
  }

  void purgeSessionTrashFromDatabase() {
    final wallet = spbWallet;
    if (wallet == null || sessionTrash.isEmpty) {
      sessionTrash.clear();
      sessionTrashCardIds.clear();
      sessionTrashFolderPaths.clear();
      sessionTrashTemplateIds.clear();
      return;
    }
    markVaultDirty();
    final rootFolders = sessionTrashFolderPaths.where(
      (path) => !sessionTrashFolderPaths.any(
        (other) => other != path && path.startsWith('$other / '),
      ),
    );
    for (final path in rootFolders) {
      wallet.deleteCategory(path);
    }
    for (final cardId in sessionTrashCardIds) {
      wallet.deleteCard(cardId);
    }
    for (final templateId in sessionTrashTemplateIds) {
      wallet.deleteTemplate(templateId);
    }
    sessionTrash.clear();
    sessionTrashCardIds.clear();
    sessionTrashFolderPaths.clear();
    sessionTrashTemplateIds.clear();
    wallet.flushToDisk();
  }

  Future<bool> finalizeSessionTrash() async {
    purgeSessionTrashFromDatabase();
    return writeBackSpbWallet();
  }

  Future<void> exitToPasswordPrompt() async {
    final saved = await finalizeSessionTrash();
    if (!saved || !mounted) return;
    await closeCurrentVaultForPasswordPrompt();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) passwordFocusNode.requestFocus();
    });
  }

  void scheduleAutomaticUnlock() {
    passwordUnlockDebounce?.cancel();
    if (unlocked ||
        entryMode != EntryMode.openSwl ||
        spbWalletPath == null ||
        spbWalletPath!.isEmpty ||
        passwordController.text.isEmpty) {
      return;
    }
    passwordUnlockDebounce = Timer(
      const Duration(milliseconds: 180),
      () => unlock(automatic: true),
    );
  }

  Future<void> unlock({bool automatic = false}) async {
    if (automatic && automaticUnlockInProgress) return;
    final password = passwordController.text;
    if (entryMode == EntryMode.openSwl) {
      if (spbWalletPath == null || spbWalletPath!.isEmpty) {
        setState(() => message = 'Выберите файл базы .swl.');
        return;
      }
      try {
        if (automatic) automaticUnlockInProgress = true;
        await loadSpb64PngIconAssets();
        if (spbWallet != null) {
          await finalizeSessionTrash();
        }
        clearSessionUndoHistory();
        spbWallet?.close(flush: vaultDirty);
        final wallet = SpbWalletDatabase.open(spbWalletPath!, password);
        final snapshot = wallet.loadSnapshot();
        final integrityReport = wallet.inspectIntegrity();
        spbWallet = wallet;
        vaultDirty = false;
        spbIconIdByUiIcon.clear();
        setState(() {
          applySpbSnapshot(snapshot);
          conflicts = [];
          lastSyncAt = null;
          selectedItemId = items.isEmpty ? null : items.first.id;
          unlocked = true;
          lastUserActivityAt = DateTime.now();
          activeView = 'cards';
          message =
              integrityReport.hasProblems ? integrityReport.userMessage : null;
        });
        lastUserActivityAt = DateTime.now();
        passwordUnlockDebounce?.cancel();
        passwordController.clear();
        confirmController.clear();
        if (!Platform.isAndroid || spbWalletUri == null) {
          await rememberRecentVault(spbWalletPath!);
        }
      } catch (error) {
        if (!automatic) {
          passwordController.clear();
          setState(
            () => message =
                'Не удалось открыть базу. Проверьте правильность пароля.',
          );
          passwordFocusNode.requestFocus();
        }
      } finally {
        if (automatic) automaticUnlockInProgress = false;
      }
      return;
    }
    if (createMode && password != confirmController.text) {
      setState(() => message = 'Пароли не совпадают.');
      return;
    }
    if (createMode) {
      if (creatingVault) return;
      setState(() {
        creatingVault = true;
        message = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 16));
      try {
        await createSwlVault(password);
        passwordController.clear();
        confirmController.clear();
      } catch (error) {
        setState(() => message = 'Не удалось создать .swl базу: $error');
      } finally {
        if (mounted) {
          setState(() => creatingVault = false);
        }
      }
      return;
    }
  }

  Future<void> closeCurrentVaultForPasswordPrompt() async {
    passwordUnlockDebounce?.cancel();
    automaticUnlockInProgress = false;
    if (spbWallet != null) {
      await finalizeSessionTrash();
    }
    clearSessionUndoHistory();
    spbWallet?.close(flush: vaultDirty);
    spbWallet = null;
    vaultDirty = false;
    passwordController.clear();
    confirmController.clear();
    revealed.clear();
    loginHintVisible = false;
    loginPasswordHint = '';
    showPassword = false;
    if (!mounted) return;
    setState(() {
      unlocked = false;
      entryMode = EntryMode.openSwl;
      message = null;
    });
  }

  Future<void> pickSpbWalletFile() async {
    if (Platform.isAndroid) {
      try {
        final picked = await spbWalletChannel.invokeMapMethod<String, Object?>(
          'pickSpbWallet',
        );
        if (picked == null) return;
        final path = picked['localPath']?.toString();
        if (path == null || path.isEmpty) return;
        await closeCurrentVaultForPasswordPrompt();
        if (!mounted) return;
        setState(() {
          spbWalletPath = path;
          spbWalletUri = picked['uri']?.toString();
          spbWalletWritable = picked['writable'] != false;
          spbWalletDisplayPath =
              picked['displayPath']?.toString() ?? spbWalletUri;
          syncSourcePath = null;
          syncSourceUrl = null;
          syncOriginProvider = null;
          vaultNameController.text = picked['displayName']?.toString() ??
              File(path).uri.pathSegments.last;
          message = null;
        });
        final uri = spbWalletUri;
        if (uri != null && uri.isNotEmpty && picked['persisted'] != false) {
          await rememberRecentVaultEntry(
            ExistingVault(
              title: vaultNameController.text,
              uri: uri,
              displayPath: spbWalletDisplayPath,
            ),
          );
        } else if (picked['persisted'] == false) {
          showSpbOperationMessage(
            'Поставщик файла не разрешил постоянный доступ. После '
            'перезапуска файл потребуется выбрать снова.',
          );
        }
      } catch (error) {
        setState(() => message = 'Не удалось выбрать .swl файл: $error');
      }
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['swl', 'db', 'sqlite'],
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await closeCurrentVaultForPasswordPrompt();
    if (!mounted) return;
    setState(() {
      spbWalletPath = path;
      spbWalletUri = null;
      spbWalletDisplayPath = path;
      syncSourcePath = null;
      syncSourceUrl = null;
      syncOriginProvider = null;
      vaultNameController.text = File(path).uri.pathSegments.last;
      message = null;
    });
    await rememberRecentVault(path);
  }

  Future<void> loadRecentVaults() async {
    final found = <ExistingVault>[];
    try {
      final file = await recentVaultsFile();
      if (file.existsSync()) {
        final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
        for (final raw in decoded) {
          ExistingVault? vault;
          if (raw is String) {
            final file = File(raw);
            if (isAndroidCacheWalletPath(file.path)) continue;
            if (!file.existsSync() ||
                !file.path.toLowerCase().endsWith('.swl')) {
              continue;
            }
            vault = ExistingVault(
              title: _vaultTitleFromPath(file.path),
              path: file.path,
              displayPath: file.path,
            );
          } else if (raw is Map<String, dynamic>) {
            vault = ExistingVault.fromJson(raw);
            if (vault.uri == null) {
              final path = vault.path;
              if (path == null || isAndroidCacheWalletPath(path)) continue;
              if (!File(path).existsSync() ||
                  !path.toLowerCase().endsWith('.swl')) {
                continue;
              }
            }
          } else if (raw is Map) {
            vault = ExistingVault.fromJson(Map<String, dynamic>.from(raw));
          }
          if (vault == null) continue;
          if (found.any((entry) => entry.key == vault!.key)) {
            continue;
          }
          found.add(vault);
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => recentVaults = found);
    if (found.isNotEmpty &&
        !unlocked &&
        entryMode == EntryMode.openSwl &&
        (spbWalletPath == null || spbWalletPath!.isEmpty)) {
      await chooseExistingVault(found.first);
    }
  }

  Future<void> rememberRecentVault(String path) async {
    if (path.isEmpty) return;
    if (isAndroidCacheWalletPath(path)) return;
    await rememberRecentVaultEntry(
      ExistingVault(
        title: _vaultTitleFromPath(path),
        path: path,
        displayPath: path,
      ),
    );
  }

  Future<void> rememberRecentVaultEntry(ExistingVault vault) async {
    final entries = [
      vault,
      ...recentVaults.where((entry) => entry.key != vault.key).where(
            (entry) =>
                entry.uri != null ||
                (entry.path != null && !isAndroidCacheWalletPath(entry.path!)),
          ),
    ].take(8).toList();
    final file = await recentVaultsFile();
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(entries.map((entry) => entry.toJson()).toList()),
    );
    if (!mounted) return;
    setState(() => recentVaults = entries);
  }

  Future<void> createSwlVault(
    String password, {
    String passwordHint = '',
    File? targetFile,
    bool rememberLocalFile = true,
    bool unlockAfterCreate = true,
  }) async {
    final file = targetFile ?? await swlVaultFile();
    if (file.existsSync()) {
      throw StateError(
        'База "${file.uri.pathSegments.last}" уже есть. Выберите другое название или откройте существующую базу.',
      );
    }
    final baseData = await rootBundle.load('assets/base_wallet/MyWallet.swl');
    final payload = <String, dynamic>{
      'path': file.path,
      'password': password,
      'passwordHint': passwordHint,
      'baseBytes': baseData.buffer.asUint8List(
        baseData.offsetInBytes,
        baseData.lengthInBytes,
      ),
    };
    await compute<Map<String, dynamic>, bool>(
      createSwlVaultFromBaseFile,
      payload,
    );

    spbIconIdByUiIcon.clear();
    await loadSpb64PngIconAssets();
    final wallet = SpbWalletDatabase.open(file.path, password);
    final snapshot = wallet.loadSnapshot();
    if (spbWallet != null) {
      await finalizeSessionTrash();
    }
    clearSessionUndoHistory();
    spbWallet?.close(flush: vaultDirty);
    spbWallet = wallet;
    vaultDirty = false;
    setState(() {
      spbWalletPath = file.path;
      spbWalletUri = null;
      spbWalletDisplayPath = file.path;
      syncSourcePath = null;
      syncSourceUrl = null;
      syncOriginProvider = null;
      applySpbSnapshot(snapshot);
      conflicts = [];
      lastSyncAt = null;
      selectedItemId = items.isEmpty ? null : items.first.id;
      if (unlockAfterCreate) {
        unlocked = true;
        lastUserActivityAt = DateTime.now();
        activeView = 'cards';
      }
      message = null;
    });
    if (rememberLocalFile) {
      await rememberRecentVault(file.path);
    }
  }

  Future<void> createNewVaultFromLogin() async {
    final pathController = TextEditingController();
    if (Platform.isAndroid) {
      pathController.text = 'Android-хранилище';
    }
    final nameController = TextEditingController(text: 'Новая база');
    final newPasswordController = TextEditingController();
    final repeatPasswordController = TextEditingController();
    final hintController = TextEditingController();
    var showNewPassword = false;
    var showRepeatedPassword = false;
    var isCreating = false;
    var createdVault = false;
    Map<String, Object?>? androidDocument;
    String? dialogError;

    Future<void> pickNewVaultDirectory(StateSetter setDialogState) async {
      if (Platform.isAndroid) {
        final baseName = nameController.text.trim().replaceAll(
              RegExp(r'\.swl$', caseSensitive: false),
              '',
            );
        final document = await spbWalletChannel
            .invokeMapMethod<String, Object?>('createSpbWalletDocument', {
          'displayName': '${baseName.isEmpty ? 'Новая база' : baseName}.swl',
        });
        if (document == null) return;
        setDialogState(() {
          androidDocument = document;
          pathController.text = document['displayPath']?.toString() ??
              document['displayName']?.toString() ??
              'Android-хранилище';
          dialogError = null;
        });
        return;
      }
      var selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Назначить путь для новой базы',
        lockParentWindow: true,
      );
      if (selectedDirectory == null || selectedDirectory.trim().isEmpty) {
        return;
      }
      if (Platform.isLinux) {
        var entityType = await FileSystemEntity.type(
          selectedDirectory,
          followLinks: true,
        );
        if (entityType == FileSystemEntityType.notFound &&
            await File(selectedDirectory).parent.exists()) {
          entityType = FileSystemEntityType.file;
        }
        selectedDirectory = normalizeNewVaultDirectorySelection(
          selectedDirectory,
          entityType,
        );
        if (selectedDirectory == null) {
          setDialogState(
            () => dialogError = 'Выберите существующую папку для новой базы.',
          );
          return;
        }
      }
      setDialogState(() {
        pathController.text = selectedDirectory!;
        dialogError = null;
      });
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xffececec),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
          title: GestureDetector(
            key: const Key('newVaultDialogDragHandle'),
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              unawaited(startLoginWindowDrag());
            },
            child: const SizedBox(
              height: 38,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Создание новой базы'),
              ),
            ),
          ),
          content: Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: const InputDecorationTheme(
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            child: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 42,
                      child: TextField(
                        key: const Key('newVaultPath'),
                        controller: pathController,
                        readOnly: true,
                        autofocus: true,
                        onTap: () => pickNewVaultDirectory(setDialogState),
                        decoration: InputDecoration(
                          labelText: 'Назначить путь',
                          hintText: Platform.isAndroid
                              ? 'Выберите файл в локальном или облачном хранилище'
                              : 'Выберите папку для новой базы',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          suffixIconConstraints: const BoxConstraints.tightFor(
                            width: 40,
                            height: 40,
                          ),
                          suffixIcon: IconButton(
                            key: const Key('browseNewVaultPath'),
                            tooltip: Platform.isAndroid
                                ? 'Выбрать файл в проводнике'
                                : 'Выбрать папку в проводнике',
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.folder_open_outlined),
                            onPressed: () =>
                                pickNewVaultDirectory(setDialogState),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: TextField(
                        key: const Key('newVaultName'),
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Название базы',
                          suffixText: '.swl',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    PasswordField(
                      key: const Key('newVaultPassword'),
                      controller: newPasswordController,
                      label: 'Новый пароль',
                      visible: showNewPassword,
                      onToggle: () => setDialogState(
                        () => showNewPassword = !showNewPassword,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      compact: true,
                    ),
                    const SizedBox(height: 8),
                    PasswordStrengthBar(
                      key: const Key('newVaultPasswordStrength'),
                      password: newPasswordController.text,
                    ),
                    const SizedBox(height: 8),
                    PasswordField(
                      key: const Key('newVaultPasswordRepeat'),
                      controller: repeatPasswordController,
                      label: 'Повторите новый пароль',
                      visible: showRepeatedPassword,
                      onToggle: () => setDialogState(
                        () => showRepeatedPassword = !showRepeatedPassword,
                      ),
                      compact: true,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: TextField(
                        key: const Key('newVaultPasswordHint'),
                        controller: hintController,
                        decoration: const InputDecoration(
                          labelText: 'Подсказка',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogError!,
                        key: const Key('newVaultError'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          actions: [
            SizedBox.square(
              dimension: 48,
              child: IgnorePointer(
                ignoring: isCreating,
                child: Opacity(
                  opacity: isCreating ? 0.6 : 1,
                  child: SpbGradientActionButton(
                    key: const Key('confirmCreateVault'),
                    icon: Icons.check,
                    tooltip: 'Создать базу',
                    colors: const [Color(0xff43a047), Color(0xff1b5e20)],
                    onTap: () async {
                      final selectedDirectory = pathController.text.trim();
                      final name = nameController.text.trim().replaceAll(
                            RegExp(r'\.swl$', caseSensitive: false),
                            '',
                          );
                      final newPassword = newPasswordController.text;
                      if (!Platform.isAndroid && selectedDirectory.isEmpty) {
                        setDialogState(
                          () => dialogError =
                              'Назначьте путь для файла новой базы.',
                        );
                        return;
                      }
                      if (name.isEmpty) {
                        setDialogState(
                          () => dialogError = 'Введите название базы.',
                        );
                        return;
                      }
                      if (newPassword.isEmpty) {
                        setDialogState(
                          () => dialogError = 'Введите новый пароль.',
                        );
                        return;
                      }
                      if (newPassword != repeatPasswordController.text) {
                        setDialogState(
                          () => dialogError = 'Новые пароли не совпадают.',
                        );
                        return;
                      }

                      final previousName = vaultNameController.text;
                      setDialogState(() {
                        isCreating = true;
                        dialogError = null;
                      });
                      vaultNameController.text = name;
                      try {
                        if (Platform.isAndroid) {
                          final document = androidDocument ??
                              await spbWalletChannel
                                  .invokeMapMethod<String, Object?>(
                                'createSpbWalletDocument',
                                {
                                  'displayName': '$normalizedVaultBaseName.swl',
                                },
                              );
                          if (document == null) {
                            if (dialogContext.mounted) {
                              setDialogState(() => isCreating = false);
                            }
                            return;
                          }
                          final directory = await appVaultDirectory();
                          final targetFile = File(
                            '${directory.path}${Platform.pathSeparator}'
                            '${DateTime.now().microsecondsSinceEpoch}_'
                            '$normalizedVaultBaseName.swl',
                          );
                          await createSwlVault(
                            newPassword,
                            passwordHint: hintController.text,
                            targetFile: targetFile,
                            rememberLocalFile: false,
                            unlockAfterCreate: false,
                          );
                          spbWalletUri = document['uri']?.toString();
                          spbWalletDisplayPath =
                              document['displayPath']?.toString() ??
                                  document['displayName']?.toString();
                          spbWalletWritable = document['writable'] != false;
                          final written = await writeBackSpbWallet(force: true);
                          if (!written) {
                            throw StateError(
                              'Не удалось записать новую базу в выбранный файл.',
                            );
                          }
                          await rememberRecentVaultEntry(
                            ExistingVault(
                              title: document['displayName']?.toString() ??
                                  '$normalizedVaultBaseName.swl',
                              uri: spbWalletUri,
                              displayPath: spbWalletDisplayPath,
                            ),
                          );
                        } else {
                          final targetFile = File(
                            '${Directory(selectedDirectory).path}'
                            '${Platform.pathSeparator}'
                            '$normalizedVaultBaseName.swl',
                          );
                          await createSwlVault(
                            newPassword,
                            passwordHint: hintController.text,
                            targetFile: targetFile,
                            unlockAfterCreate: false,
                          );
                        }
                        entryMode = EntryMode.openSwl;
                        createdVault = true;
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      } catch (error) {
                        vaultNameController.text = previousName;
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            isCreating = false;
                            dialogError =
                                'Не удалось создать .swl базу: $error';
                          });
                        }
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox.square(
              dimension: 48,
              child: IgnorePointer(
                ignoring: isCreating,
                child: Opacity(
                  opacity: isCreating ? 0.6 : 1,
                  child: SpbGradientActionButton(
                    key: const Key('cancelCreateVault'),
                    icon: Icons.close,
                    tooltip: 'Отмена',
                    colors: const [Color(0xffd32b31), Color(0xff7f0609)],
                    onTap: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    pathController.dispose();
    nameController.dispose();
    newPasswordController.clear();
    repeatPasswordController.clear();
    hintController.clear();
    newPasswordController.dispose();
    repeatPasswordController.dispose();
    hintController.dispose();
    if (!mounted) return;
    if (createdVault) {
      passwordController.clear();
      confirmController.clear();
      setState(() {
        unlocked = true;
        lastUserActivityAt = DateTime.now();
        activeView = 'cards';
        message = null;
      });
    } else if (!unlocked) {
      passwordFocusNode.requestFocus();
    }
  }

  Future<void> replaceCurrentWalletPassword({
    required String oldPassword,
    required String newPassword,
    required String passwordHint,
  }) async {
    final wallet = spbWallet;
    final path = spbWalletPath;
    if (wallet == null || path == null || path.isEmpty) {
      throw StateError('Кошелек не открыт.');
    }
    wallet.saveRecentlyOpenedCardIds(recentlyOpenedItemIds);
    wallet.flushToDisk();
    final sourceFile = File(path);
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final temporaryFile = File('$path.password-change-$suffix.tmp');
    final backupFile = File('$path.password-change-$suffix.backup');
    await compute<Map<String, dynamic>, bool>(
      cloneSwlVaultWithPassword,
      <String, dynamic>{
        'path': temporaryFile.path,
        'password': newPassword,
        'sourcePassword': oldPassword,
        'passwordHint': passwordHint,
        'baseBytes': await sourceFile.readAsBytes(),
      },
    );
    final verification = SpbWalletDatabase.open(
      temporaryFile.path,
      newPassword,
    );
    verification.close(flush: false);

    clearSessionUndoHistory();
    wallet.close(flush: false);
    spbWallet = null;
    try {
      await sourceFile.rename(backupFile.path);
      await temporaryFile.rename(sourceFile.path);
      final reopened = SpbWalletDatabase.open(path, newPassword);
      final snapshot = reopened.loadSnapshot();
      spbWallet = reopened;
      vaultDirty = false;
      setState(() => applySpbSnapshot(snapshot));
      final written = await writeBackSpbWallet(force: true);
      if (!written) {
        throw StateError('Не удалось записать базу в исходное хранилище.');
      }
      if (backupFile.existsSync()) await backupFile.delete();
    } catch (_) {
      spbWallet?.close(flush: false);
      spbWallet = null;
      if (sourceFile.existsSync()) await sourceFile.delete();
      if (backupFile.existsSync()) await backupFile.rename(sourceFile.path);
      spbWallet = SpbWalletDatabase.open(path, oldPassword);
      if (temporaryFile.existsSync()) await temporaryFile.delete();
      rethrow;
    }
  }

  Future<void> openChangePasswordDialog() async {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    final repeatController = TextEditingController();
    final hintController = TextEditingController(
      text: spbWallet?.loadPasswordHint() ?? '',
    );
    var showOld = false;
    var showNew = false;
    var showRepeat = false;
    var saving = false;
    String? errorText;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final media = MediaQuery.of(context);
          final narrow = media.size.width < 600;
          return AlertDialog(
            key: const Key('changePasswordDialog'),
            scrollable: true,
            insetPadding: EdgeInsets.symmetric(
              horizontal: narrow ? 4 : 40,
              vertical: narrow ? 8 : 24,
            ),
            backgroundColor: const Color(0xffececec),
            surfaceTintColor: Colors.transparent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            title: GestureDetector(
              key: const Key('changePasswordDialogDragHandle'),
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {
                unawaited(startLoginWindowDrag());
              },
              child: const SizedBox(
                height: 38,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Изменить пароль'),
                ),
              ),
            ),
            content: SizedBox(
              width: narrow ? double.maxFinite : 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PasswordField(
                    key: const Key('changePasswordOld'),
                    controller: oldController,
                    label: 'Старый пароль',
                    visible: showOld,
                    onToggle: () => setDialogState(() => showOld = !showOld),
                    compact: true,
                  ),
                  const SizedBox(height: 8),
                  PasswordField(
                    key: const Key('changePasswordNew'),
                    controller: newController,
                    label: 'Новый пароль',
                    visible: showNew,
                    onChanged: (_) => setDialogState(() {}),
                    onToggle: () => setDialogState(() => showNew = !showNew),
                    compact: true,
                  ),
                  const SizedBox(height: 8),
                  PasswordStrengthBar(
                    key: const Key('changePasswordStrength'),
                    password: newController.text,
                  ),
                  const SizedBox(height: 8),
                  PasswordField(
                    key: const Key('changePasswordRepeat'),
                    controller: repeatController,
                    label: 'Повторите новый пароль',
                    visible: showRepeat,
                    onToggle: () =>
                        setDialogState(() => showRepeat = !showRepeat),
                    compact: true,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 42,
                    child: TextField(
                      key: const Key('changePasswordHint'),
                      controller: hintController,
                      decoration: const InputDecoration(
                        labelText: 'Подсказка',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      key: const Key('changePasswordError'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            actions: [
              IgnorePointer(
                ignoring: saving,
                child: Opacity(
                  opacity: saving ? 0.6 : 1,
                  child: SpbGradientActionButton(
                    key: const Key('cancelChangePassword'),
                    icon: Icons.close,
                    tooltip: 'Отменить',
                    colors: const [Color(0xffff5a5f), Color(0xffa90000)],
                    onTap: () => Navigator.of(dialogContext).pop(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IgnorePointer(
                ignoring: saving,
                child: Opacity(
                  opacity: saving ? 0.6 : 1,
                  child: SpbGradientActionButton(
                    key: const Key('confirmChangePassword'),
                    icon: Icons.check,
                    tooltip: saving ? 'Сохранение…' : 'Сохранить',
                    colors: const [Color(0xff5bc96d), Color(0xff08772f)],
                    onTap: () async {
                      FocusScope.of(dialogContext).unfocus();
                      await SystemChannels.textInput.invokeMethod<void>(
                        'TextInput.hide',
                      );
                      await WidgetsBinding.instance.endOfFrame;
                      final oldPassword = oldController.text;
                      final newPassword = newController.text;
                      final repeatedPassword = repeatController.text;
                      if (oldPassword.isEmpty) {
                        setDialogState(
                          () => errorText = 'Введите старый пароль.',
                        );
                        return;
                      }
                      if (newPassword.isEmpty) {
                        setDialogState(
                            () => errorText = 'Введите новый пароль.');
                        return;
                      }
                      if (newPassword != repeatedPassword) {
                        setDialogState(
                          () => errorText = 'Новые пароли не совпадают.',
                        );
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        errorText = null;
                      });
                      try {
                        await replaceCurrentWalletPassword(
                          oldPassword: oldPassword,
                          newPassword: newPassword,
                          passwordHint: hintController.text,
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                        showSpbOperationMessage('Пароль кошелька изменен.');
                      } catch (_) {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            saving = false;
                            errorText =
                                'Не удалось изменить пароль. Проверьте старый пароль.';
                          });
                        }
                      }
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    oldController.dispose();
    newController.dispose();
    repeatController.dispose();
    hintController.dispose();
  }

  Map<String, String> demoCategoryIcons() => const {
        'Примеры': 'bookmark',
        'Примеры / Доступы': 'key',
        'Примеры / Финансы': 'bank',
        'Примеры / Работа': 'briefcase',
        'Примеры / Сервисы': 'globe',
        'Примеры / Документы': 'id',
        'Примеры / О программе': 'info',
      };

  Future<void> connectSyncVault(String password) async {
    if (syncProvider == 'mounted_folder') {
      final source = resolveMountedFolderSyncFile();
      final localName = vaultNameController.text.trim().isEmpty
          ? source.uri.pathSegments.last.replaceAll(
              RegExp(r'\.swl$', caseSensitive: false),
              '',
            )
          : vaultNameController.text.trim();
      vaultNameController.text = localName;
      final local = await swlVaultFile();
      await source.copy(local.path);
      await openSyncedLocalWallet(
        localPath: local.path,
        password: password,
        sourcePath: source.path,
        sourceUrl: null,
      );
      return;
    }
    if (syncProvider == 'webdav') {
      final uri = webDavSyncUri();
      final bytes = await downloadWebDavVault(uri);
      final localName = vaultNameController.text.trim().isEmpty
          ? webDavFileName(
              uri,
            ).replaceAll(RegExp(r'\.swl$', caseSensitive: false), '')
          : vaultNameController.text.trim();
      vaultNameController.text = localName;
      final local = await swlVaultFile();
      await local.writeAsBytes(bytes, flush: true);
      await openSyncedLocalWallet(
        localPath: local.path,
        password: password,
        sourcePath: null,
        sourceUrl: uri.toString(),
      );
      return;
    }
    throw StateError(
      'Для автоматического подключения сейчас поддержаны папка/SMB/NFS и WebDAV. Для SFTP/FTP/почты сначала подключите хранилище как папку или откройте .swl файл вручную.',
    );
  }

  Future<void> openSyncedLocalWallet({
    required String localPath,
    required String password,
    required String? sourcePath,
    required String? sourceUrl,
  }) async {
    if (spbWallet != null) {
      await finalizeSessionTrash();
    }
    clearSessionUndoHistory();
    spbWallet?.close(flush: vaultDirty);
    await loadSpb64PngIconAssets();
    final wallet = SpbWalletDatabase.open(localPath, password);
    final snapshot = wallet.loadSnapshot();
    spbWallet = wallet;
    vaultDirty = false;
    spbIconIdByUiIcon.clear();
    setState(() {
      spbWalletPath = localPath;
      spbWalletUri = null;
      spbWalletDisplayPath = sourcePath ?? sourceUrl ?? localPath;
      syncSourcePath = sourcePath;
      syncSourceUrl = sourceUrl;
      syncOriginProvider = syncProvider;
      applySpbSnapshot(snapshot);
      conflicts = [];
      lastSyncAt = DateTime.now();
      selectedItemId = items.isEmpty ? null : items.first.id;
      unlocked = true;
      lastUserActivityAt = DateTime.now();
      activeView = 'cards';
      message = null;
    });
    passwordController.clear();
    confirmController.clear();
    await rememberRecentVault(localPath);
  }

  File resolveMountedFolderSyncFile() {
    final directoryPath = syncConfig['mounted_folder:directory']?.trim() ?? '';
    if (directoryPath.isEmpty) {
      throw StateError('Укажите путь к папке с .swl файлом.');
    }
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      throw StateError('Папка не найдена: $directoryPath');
    }
    final configuredName = syncConfig['mounted_folder:database']?.trim() ?? '';
    if (configuredName.isNotEmpty) {
      final file = File(
        '${directory.path}${Platform.pathSeparator}$configuredName',
      );
      if (!file.existsSync()) {
        throw StateError('В папке нет файла $configuredName.');
      }
      return file;
    }
    final swlFiles = directory
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.swl'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (swlFiles.isEmpty) throw StateError('В папке нет .swl базы.');
    if (swlFiles.length > 1) {
      throw StateError(
        'В папке несколько .swl баз. Укажите имя файла в поле “Имя .swl файла”.',
      );
    }
    return swlFiles.single;
  }

  Uri webDavSyncUri() {
    final rawUrl = syncConfig['webdav:url']?.trim() ?? '';
    if (rawUrl.isEmpty) throw StateError('Укажите WebDAV URL.');
    final base = Uri.parse(rawUrl);
    if (base.scheme.toLowerCase() != 'https') {
      throw StateError('WebDAV разрешён только через защищённый HTTPS.');
    }
    if (base.host.isEmpty || base.userInfo.isNotEmpty) {
      throw StateError(
        'Укажите корректный WebDAV HTTPS URL без пароля в адресе.',
      );
    }
    if (base.path.toLowerCase().endsWith('.swl')) return base;
    final configuredName = syncConfig['webdav:database']?.trim() ?? '';
    final fileName = configuredName.isEmpty
        ? '${vaultNameController.text.trim().isEmpty ? 'personal' : vaultNameController.text.trim()}.swl'
        : configuredName;
    final separator = rawUrl.endsWith('/') ? '' : '/';
    return Uri.parse('$rawUrl$separator${Uri.encodeComponent(fileName)}');
  }

  String webDavFileName(Uri uri) =>
      uri.pathSegments.isEmpty ? 'personal.swl' : uri.pathSegments.last;

  Future<List<int>> downloadWebDavVault(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      applyWebDavAuth(request);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('WebDAV вернул HTTP ${response.statusCode}.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> uploadWebDavVault(Uri uri, List<int> bytes) async {
    final client = HttpClient();
    try {
      final request = await client.putUrl(uri);
      applyWebDavAuth(request);
      request.headers.contentType = ContentType.binary;
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'WebDAV вернул HTTP ${response.statusCode} при записи.',
        );
      }
      await response.drain();
    } finally {
      client.close(force: true);
    }
  }

  void applyWebDavAuth(HttpClientRequest request) {
    final username = syncConfig['webdav:username']?.trim() ?? '';
    final password = syncConfig['webdav:password'] ?? '';
    if (username.isEmpty && password.isEmpty) return;
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Basic ${base64Encode(utf8.encode('$username:$password'))}',
    );
  }

  Future<void> chooseExistingVault(ExistingVault vault) async {
    try {
      if (Platform.isAndroid && vault.uri != null) {
        final copied = await spbWalletChannel.invokeMapMethod<String, Object?>(
          'copySpbWallet',
          {'uri': vault.uri, 'displayName': vault.title},
        );
        final localPath = copied?['localPath']?.toString();
        if (localPath == null || localPath.isEmpty) {
          throw StateError('Не удалось открыть выбранную .swl базу.');
        }
        await closeCurrentVaultForPasswordPrompt();
        if (!mounted) return;
        setState(() {
          entryMode = EntryMode.openSwl;
          message = null;
          spbWalletPath = localPath;
          spbWalletUri = vault.uri;
          spbWalletWritable = copied?['writable'] != false;
          spbWalletDisplayPath =
              copied?['displayPath']?.toString() ?? vault.displayPath;
          syncSourcePath = null;
          syncSourceUrl = null;
          syncOriginProvider = null;
          vaultNameController.text =
              copied?['displayName']?.toString() ?? vault.title;
        });
      } else {
        await closeCurrentVaultForPasswordPrompt();
        if (!mounted) return;
        setState(() {
          entryMode = EntryMode.openSwl;
          message = null;
          spbWalletPath = vault.path;
          spbWalletUri = null;
          spbWalletWritable = true;
          spbWalletDisplayPath = vault.displayPath ?? vault.path;
          syncSourcePath = null;
          syncSourceUrl = null;
          syncOriginProvider = null;
          vaultNameController.text = vault.title;
        });
      }
      await rememberRecentVaultEntry(
        ExistingVault(
          title: vaultNameController.text,
          path:
              Platform.isAndroid && spbWalletUri != null ? null : spbWalletPath,
          uri: spbWalletUri,
          displayPath: spbWalletDisplayPath,
        ),
      );
    } catch (error) {
      setState(
        () => message = 'Не удалось открыть последнюю .swl базу: $error',
      );
    }
  }

  Future<bool> writeBackSpbWallet({bool force = false}) async {
    if (!force && !vaultDirty) {
      spbWritePending = false;
      return true;
    }
    var ok = true;
    try {
      spbWallet?.saveRecentlyOpenedCardIds(recentlyOpenedItemIds);
      spbWallet?.flushToDisk();
      if (Platform.isAndroid && spbWalletUri != null && spbWalletPath != null) {
        if (!spbWalletWritable) {
          throw StateError(
            'Файл открыт только для чтения. Выберите доступный для записи файл.',
          );
        }
        final written = await spbWalletChannel.invokeMethod<bool>(
          'writeSpbWallet',
          {'uri': spbWalletUri, 'localPath': spbWalletPath},
        );
        if (written != true) {
          throw StateError('Android не подтвердил запись файла.');
        }
      }
      if (syncSourcePath != null &&
          spbWalletPath != null &&
          syncSourcePath != spbWalletPath) {
        await File(spbWalletPath!).copy(syncSourcePath!);
      }
      if (syncSourceUrl != null && spbWalletPath != null) {
        await uploadWebDavVault(
          Uri.parse(syncSourceUrl!),
          await File(spbWalletPath!).readAsBytes(),
        );
      }
      if (spbWalletUri != null ||
          syncSourcePath != null ||
          syncSourceUrl != null) {
        lastSyncAt = DateTime.now();
      }
      spbWritePending = false;
      vaultDirty = false;
    } catch (error) {
      ok = false;
      spbWritePending = true;
      if (mounted) {
        final failure =
            'Изменения сохранены в рабочей копии, но не записаны в исходную '
            '.swl базу: $error';
        setState(() => message = failure);
        showSpbOperationMessage(failure);
      }
    }
    return ok;
  }

  bool ensureSpbWalletWritable() {
    if (!Platform.isAndroid || spbWalletUri == null || spbWalletWritable) {
      return true;
    }
    showSpbOperationMessage(
      'Эта база открыта только для чтения. Изменения не выполнялись.',
    );
    return false;
  }

  Future<void> createDatedArchiveCopy() async {
    if (spbWallet == null || spbWalletPath == null) {
      setState(() => message = 'Сначала откройте .swl базу.');
      return;
    }
    final saved = await writeBackSpbWallet();
    if (!saved || !mounted) return;
    if (Platform.isAndroid) {
      try {
        final now = DateTime.now();
        String two(int value) => value.toString().padLeft(2, '0');
        final baseName = selectedVaultTitle.replaceAll(
          RegExp(r'[\\/:*?"<>|]'),
          '_',
        );
        final bytes = await File(spbWalletPath!).readAsBytes();
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Сохранить архивную копию',
          fileName: '${baseName}_${now.year}${two(now.month)}'
              '${two(now.day)}_${two(now.hour)}${two(now.minute)}.swl',
          type: FileType.custom,
          allowedExtensions: const ['swl'],
          bytes: bytes,
        );
        if (path != null) {
          showSpbOperationMessage('Архивная копия сохранена.');
        }
      } catch (error) {
        showSpbOperationMessage('Не удалось сохранить архивную копию: $error');
      }
      return;
    }
    final sourcePath = syncSourcePath ?? spbWalletPath!;
    final source = File(sourcePath);
    if (!source.existsSync()) {
      setState(() => message = 'Исходный файл базы не найден: $sourcePath');
      return;
    }
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final suffix = '${now.year}${two(now.month)}${two(now.day)}';
    final sourceName = source.uri.pathSegments.last;
    final baseName = sourceName.replaceFirst(
      RegExp(r'\.swl$', caseSensitive: false),
      '',
    );
    final archiveName = '${suffix}_arc_$baseName.swl';
    final archivePath =
        '${source.parent.path}${Platform.pathSeparator}$archiveName';
    try {
      await source.copy(archivePath);
      if (!mounted) return;
      setState(() => message = 'Архивная копия создана: $archivePath');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Архивная копия создана: $archiveName')),
        );
    } catch (error) {
      if (!mounted) return;
      setState(() => message = 'Не удалось создать архивную копию: $error');
    }
  }

  Future<void> repairCurrentWalletCompatibility() async {
    final wallet = spbWallet;
    final path = spbWalletPath;
    if (wallet == null || path == null || !ensureSpbWalletWritable()) return;
    final source = File(path);
    if (!source.existsSync()) {
      showSpbOperationMessage('Рабочая копия базы не найдена.');
      return;
    }
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final backup = File('$path.compatibility-$stamp.backup.swl');
    SpbWalletUndoSnapshot? undo;
    try {
      wallet.flushToDisk();
      await source.copy(backup.path);
      undo = await wallet.createUndoSnapshot();
      final report = wallet.repairLegacyCompatibility();
      markVaultDirty();
      final written = await writeBackSpbWallet(force: true);
      if (!written) {
        throw StateError('Исправленная база не записана в исходный файл.');
      }
      undo.dispose();
      undo = null;
      final snapshot = wallet.loadSnapshot();
      if (!mounted) return;
      setState(() {
        applySpbSnapshot(snapshot);
        message = '${report.userMessage} Резервная копия: ${backup.path}';
      });
      showSpbOperationMessage(report.userMessage);
    } catch (error) {
      if (undo != null) {
        await wallet.restoreUndoSnapshot(undo);
        undo.dispose();
      }
      showSpbOperationMessage(
        'Восстановление отменено, исходные данные сохранены: $error',
      );
    }
  }

  List<SecretItem> demoItems() {
    final now = DateTime.now();
    return [
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_password',
        title: 'Демо: личный кабинет',
        category: 'Примеры / Доступы',
        colorId: 'blue',
        modifiedAt: now,
        values: {
          'username': 'user@example.com',
          'password': 'Example-Password-2026!',
          'url': 'https://example.com/login',
          'notes':
              'Нажмите на любое поле в просмотре карточки, чтобы скопировать значение. Поля типа пароль и секрет скрываются по умолчанию.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_payment_card',
        title: 'Демо: банковская карта',
        category: 'Примеры / Финансы',
        colorId: 'teal',
        modifiedAt: now,
        values: {
          'holder': 'DEMO USER',
          'number': '2200 0000 0000 1234',
          'expires': '2028-11',
          'cvv': '927',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_bank_account',
        title: 'Демо: банковский счет',
        category: 'Примеры / Финансы',
        colorId: 'blue',
        modifiedAt: now,
        values: {
          'bank': 'Демо Банк',
          'account': '40817810000000000000',
          'login': 'demo-bank-login',
          'password': 'Demo-Bank-Password!',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_email_account',
        title: 'Демо: почтовый аккаунт',
        category: 'Примеры / Доступы',
        colorId: 'green',
        modifiedAt: now,
        values: {
          'email': 'mailbox@example.com',
          'password': 'Mail-Example-Secret!',
          'recovery': 'backup@example.com',
          'notes':
              'Для почты удобно хранить основной пароль, резервный адрес и подсказки по восстановлению.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_api_key',
        title: 'Демо: API ключ',
        category: 'Примеры / Работа',
        colorId: 'violet',
        modifiedAt: now,
        values: {
          'service': 'Example Cloud',
          'url': 'https://console.example.com',
          'token': 'ex_live_000000000000000000000000',
          'notes':
              'В заметках можно указать права ключа, дату выпуска и где он используется.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_crypto_wallet',
        title: 'Демо: криптокошелек',
        category: 'Примеры / Финансы',
        colorId: 'amber',
        modifiedAt: now,
        values: {
          'wallet': 'Demo Wallet',
          'address': 'bc1qexample000000000000000000000000000000',
          'seed': 'example seed phrase words are stored here as a secret',
          'pin': '000000',
          'notes':
              'Это пример структуры. Реальные seed-фразы стоит хранить особенно осторожно и иметь офлайн-резервную копию.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_subscription',
        title: 'Демо: подписка',
        category: 'Примеры / Сервисы',
        colorId: 'blue',
        modifiedAt: now,
        values: {
          'service': 'Example Plus',
          'login': 'user@example.com',
          'renewal': '2026-12-01',
          'price': '990',
          'notes':
              'Можно хранить дату продления, стоимость и условия отмены подписки.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_travel',
        title: 'Демо: поездка',
        category: 'Примеры / Документы',
        colorId: 'violet',
        modifiedAt: now,
        values: {
          'carrier': 'Example Airlines',
          'booking': 'ABC123',
          'date': '2026-08-15',
          'document': 'Demo Passport 000000000',
          'notes':
              'Для поездок можно хранить бронь, дату, номер документа и добавить вложения с билетами.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_note',
        title: 'Как устроена база',
        category: 'Примеры / О программе',
        colorId: 'neutral',
        modifiedAt: now,
        values: {
          'note':
              'База создается и открывается как обычный файл SPB Wallet .swl. При открытии существующей базы приложение старается не конвертировать формат, а записывать изменения обратно в исходную .swl базу.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_note',
        title: 'Открытие базы',
        category: 'Примеры / О программе',
        colorId: 'neutral',
        modifiedAt: now,
        values: {
          'note':
              'На стартовом экране можно выбрать .swl файл вручную или открыть один из последних выбранных файлов. На Android выбранный файл показывается как исходный файл из Downloads, хотя технически SQLite работает через временную рабочую копию.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_note',
        title: 'Заметки и вложения',
        category: 'Примеры / О программе',
        colorId: 'neutral',
        modifiedAt: now,
        values: {
          'note':
              'У карточек есть кнопка вложений. В просмотре вложения открываются без редактирования, а изменение вложений доступно через режим редактирования карточки.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_note',
        title: 'Копирование значений',
        category: 'Примеры / О программе',
        colorId: 'neutral',
        modifiedAt: now,
        values: {
          'note':
              'В просмотре карточки нажмите на поле, чтобы скопировать его значение. Для паролей копируется настоящее значение, даже если на экране показаны точки.',
        },
      ),
      SecretItem(
        id: makeId('item'),
        templateId: 'tpl_note',
        title: 'Шаблоны',
        category: 'Примеры / О программе',
        colorId: 'neutral',
        modifiedAt: now,
        values: {
          'note':
              'Встроенные шаблоны служат стартовой библиотекой. Их можно копировать и на основе копии создавать свой вариант с нужными полями и пиктограммой.',
        },
      ),
    ];
  }

  List<CardTemplate> spbTemplatesToUi(List<SpbWalletTemplateRecord> source) {
    return source.map((template) {
      final fields = template.fields.map((field) {
        final type = spbFieldTypeToUi(field.fieldTypeId, field.name);
        final secret = spbFieldIsSecret(field.fieldTypeId, field.name);
        return FieldDefinition(
          id: field.id,
          label: field.name.isEmpty ? 'Поле' : field.name,
          type: type,
          secret: secret,
        );
      }).toList();
      if (!fields.any((field) => field.id == spbDescriptionFieldId)) {
        fields.add(
          const FieldDefinition(
            id: spbDescriptionFieldId,
            label: 'Заметки',
            type: 'multiline_note',
          ),
        );
      }
      final iconId = spbTemplateIconForUi(template);
      rememberSpbIcon(iconId, template.iconId);
      return CardTemplate(
        id: template.id,
        name: template.name,
        iconId: iconId,
        colorId: spbTemplateColorToPaletteId(template.cardColor),
        spbColor: template.cardColor,
        categoryPath: template.categoryPath,
        fields: fields,
      );
    }).toList();
  }

  void applySpbSnapshot(SpbWalletSnapshot snapshot) {
    cardLoadFailures = List.of(snapshot.cardLoadFailures);
    walletLoadReport = snapshot.loadReport.hasIssues
        ? snapshot.loadReport
        : WalletLoadReport([
            for (final failure in cardLoadFailures)
              WalletLoadIssue(
                kind: WalletLoadIssueKind.card,
                entityId: failure.cardId,
                reason: failure.reason,
              ),
          ]);
    if (walletLoadReport.hasIssues) {
      message = walletLoadReport.issues.length == cardLoadFailures.length
          ? 'Не удалось отобразить ${cardLoadFailures.length} карточек'
          : 'Не удалось загрузить ${walletLoadReport.issues.length} элементов';
    }
    spbEmbeddedIconPngs = Map<String, Uint8List>.from(
      snapshot.embeddedIconPngs,
    );
    final loadedTemplates = spbTemplatesToUi(snapshot.templates);
    final knownTemplateIds =
        loadedTemplates.map((template) => template.id).toSet();
    final missingTemplateIds = snapshot.cards
        .map((card) => card.templateId)
        .where((id) => !knownTemplateIds.contains(id))
        .toSet();
    for (final templateId in missingTemplateIds) {
      final fieldIds = snapshot.cards
          .where((card) => card.templateId == templateId)
          .expand((card) => card.fieldValues.keys)
          .toSet()
          .toList()
        ..sort();
      loadedTemplates.add(
        CardTemplate(
          id: templateId,
          name: 'Неизвестный шаблон',
          iconId: 'key',
          colorId: 'neutral',
          fields: [
            for (var index = 0; index < fieldIds.length; index++)
              FieldDefinition(
                id: fieldIds[index],
                label: 'Сохранённое поле ${index + 1}',
                type: 'text',
              ),
            const FieldDefinition(
              id: spbDescriptionFieldId,
              label: 'Заметки',
              type: 'multiline_note',
            ),
          ],
        ),
      );
    }
    loadedTemplates.sort(
      (a, b) => compareNamedEntities(a.name, a.id, b.name, b.id),
    );
    templates = loadedTemplates;
    templatesById = indexEntitiesById(templates, (template) => template.id);
    items = spbCardsToUi(snapshot.cards)
        .where(
          (item) =>
              !sessionTrashCardIds.contains(item.id) &&
              !sessionTrashTemplateIds.contains(item.templateId) &&
              !isPathInSessionTrash(item.category),
        )
        .toList();
    templates = loadedTemplates
        .where((template) => !sessionTrashTemplateIds.contains(template.id))
        .toList();
    templatesById = indexEntitiesById(templates, (template) => template.id);
    itemsById = indexEntitiesById(items, (item) => item.id);
    categoryIconsByPath = spbCategoryIconsToUi(snapshot.categories)
      ..removeWhere((path, _) => isPathInSessionTrash(path));
    categoryColorsByPath = spbCategoryColorsToUi(snapshot.categories)
      ..removeWhere((path, _) => isPathInSessionTrash(path));
    categoryIdsByPath = spbCategoryIdsToUi(snapshot.categories)
      ..removeWhere((path, _) => isPathInSessionTrash(path));
    categoryPathsById = {
      for (final entry in categoryIdsByPath.entries) entry.value: entry.key,
    };
    if (selectedCategoryId != null) {
      selectedCategoryPath = categoryPathsById[selectedCategoryId] ?? '';
      if (selectedCategoryPath.isEmpty) selectedCategoryId = null;
    } else if (selectedCategoryPath.isNotEmpty) {
      selectedCategoryId = categoryIdsByPath[selectedCategoryPath];
    }
    categoryPaths = spbCategoryPathsToUi(snapshot.categories)
      ..removeWhere(isPathInSessionTrash);
    final validIds = items.map((item) => item.id).toSet();
    recentlyOpenedItemIds
      ..clear()
      ..addAll(
        (spbWallet?.loadRecentlyOpenedCardIds() ?? const <String>[])
            .where(validIds.contains)
            .take(10),
      );
  }

  List<SecretItem> spbCardsToUi(List<SpbWalletCardRecord> source) {
    return source.map((card) {
      final template = templateFor(card.templateId);
      final iconId = spbCardIconForUi(card.iconId, template.iconId);
      final values = spbCardValuesForUi(template, card);
      rememberSpbIcon(iconId, card.iconId);
      return SecretItem(
        id: card.id,
        templateId: card.templateId,
        title: card.title.isEmpty ? '.swl карточка' : card.title,
        category: card.categoryPath,
        colorId: spbColorToPaletteId(card.cardColor),
        iconId: iconId,
        values: values,
        attachments: card.attachments
            .map(
              (attachment) => SecretAttachment(
                id: attachment.id,
                fileName: attachment.fileName,
                size: attachment.size,
                decodeError: attachment.decodeError,
              ),
            )
            .toList(),
        modifiedAt: card.modifiedAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        hitCount: card.hitCount,
        backgroundImageBase64: card.backgroundImageBase64,
        spbColor: card.cardColor,
        fieldOrder: card.fieldOrder,
        hiddenFieldIds: card.hiddenFieldIds,
      );
    }).toList();
  }

  void rememberSpbIcon(String uiIconId, String spbIconId) {
    if (spbIconId.isEmpty || !isSpbHexId(spbIconId)) return;
    spbIconIdByUiIcon.putIfAbsent(uiIconId, () => spbIconId);
  }

  String? uiIconForSpbIcon(String spbIconId) {
    if (spbIconId.isEmpty) return null;
    if (spbIconCanRender(spbIconId)) {
      return spbIconId.toUpperCase();
    }
    final synthetic = uiIconIdFromSyntheticSpbIcon(spbIconId);
    if (synthetic != null) return synthetic;
    for (final entry in spbIconIdByUiIcon.entries) {
      if (entry.value == spbIconId) return entry.key;
    }
    return null;
  }

  String? spbIconIdForUi(String uiIconId, String fallbackUiIconId) {
    if (isSpbHexId(uiIconId)) return uiIconId.toUpperCase();
    final selectedAsset = spbPngIconAsset(uiIconId);
    if (selectedAsset != null) {
      final normalizedSelectedAsset = normalizeSpbPackedIconId(selectedAsset);
      for (final entry in spbOriginalIconAssets.entries) {
        if (normalizeSpbPackedIconId(entry.value) == normalizedSelectedAsset) {
          return entry.key;
        }
      }
    }
    final direct = spbIconIdByUiIcon[uiIconId];
    if (direct != null && isSpbHexId(direct)) return direct;
    if (uiIconId == fallbackUiIconId) {
      final fallback = spbIconIdByUiIcon[fallbackUiIconId];
      if (fallback != null && isSpbHexId(fallback)) return fallback;
    }
    return syntheticSpbIconIdForUi(uiIconId);
  }

  Map<String, String> spbCategoryIconsToUi(
    List<SpbWalletCategoryRecord> categories,
  ) {
    final byId = {for (final category in categories) category.id: category};
    final result = <String, String>{};
    String pathFor(SpbWalletCategoryRecord category) {
      final names = <String>[];
      var current = category;
      var guard = 0;
      while (guard++ < 64) {
        if (current.name.isNotEmpty) names.add(current.name);
        final parent = byId[current.parentId];
        if (parent == null) break;
        current = parent;
      }
      return names.reversed.join(' / ');
    }

    for (final category in categories) {
      final path = pathFor(category);
      if (path.isEmpty) continue;
      final iconId = spbFolderIconAsset(path, category.iconId);
      rememberSpbIcon(iconId, category.iconId);
      result[path] = iconId;
    }
    return result;
  }

  Map<String, String> spbCategoryColorsToUi(
    List<SpbWalletCategoryRecord> categories,
  ) {
    final byId = {for (final category in categories) category.id: category};
    final result = <String, String>{};
    for (final category in categories) {
      if (category.colorId.isEmpty) continue;
      final names = <String>[];
      var current = category;
      var guard = 0;
      while (guard++ < 64) {
        if (current.name.isNotEmpty) names.add(current.name);
        final parent = byId[current.parentId];
        if (parent == null) break;
        current = parent;
      }
      final path = names.reversed.join(' / ');
      if (path.isNotEmpty) result[path] = category.colorId;
    }
    return result;
  }

  Map<String, String> spbCategoryIdsToUi(
    List<SpbWalletCategoryRecord> categories,
  ) {
    final pathsById = buildCategoryPathsById(
      categories,
      idOf: (category) => category.id,
      parentIdOf: (category) => category.parentId,
      nameOf: (category) => category.name,
    );
    return {
      for (final entry in pathsById.entries)
        if (entry.value.isNotEmpty) entry.value: entry.key,
    };
  }

  Set<String> spbCategoryPathsToUi(List<SpbWalletCategoryRecord> categories) {
    final byId = {for (final category in categories) category.id: category};
    final result = <String>{};
    String pathFor(SpbWalletCategoryRecord category) {
      final names = <String>[];
      var current = category;
      var guard = 0;
      while (guard++ < 64) {
        if (current.name.isNotEmpty) names.add(current.name);
        final parent = byId[current.parentId];
        if (parent == null) break;
        current = parent;
      }
      return names.reversed.join(' / ');
    }

    for (final category in categories) {
      final path = pathFor(category);
      if (path.isNotEmpty) result.add(path);
    }
    return result;
  }

  String defaultIconForCategoryPath(String path) {
    final normalized = path.toLowerCase();
    if (normalized.contains('пример') || normalized.contains('demo')) {
      if (normalized.contains('финанс')) return 'bank';
      if (normalized.contains('работ')) return 'briefcase';
      if (normalized.contains('сервис')) return 'globe';
      if (normalized.contains('документ')) return 'id';
      if (normalized.contains('доступ')) return 'key';
      return 'bookmark';
    }
    if (normalized.contains('кредит') ||
        normalized.contains('карта') ||
        normalized.contains('card')) {
      return 'card';
    }
    if (normalized.contains('личн') ||
        normalized.contains('паспорт') ||
        normalized.contains('документ') ||
        normalized.contains('personal')) {
      return normalized.contains('паспорт') || normalized.contains('документ')
          ? 'id'
          : 'contact';
    }
    if (normalized.contains('путеше') ||
        normalized.contains('ави') ||
        normalized.contains('билет') ||
        normalized.contains('travel') ||
        normalized.contains('flight')) {
      return 'plane';
    }
    if (normalized.contains('программ') ||
        normalized.contains('about') ||
        normalized.contains('spb')) {
      return 'info';
    }
    if (normalized.contains('банк') ||
        normalized.contains('финанс') ||
        normalized.contains('деньг') ||
        normalized.contains('money')) {
      return 'bank';
    }
    if (normalized.contains('почт') || normalized.contains('mail')) {
      return 'mail';
    }
    if (normalized.contains('работ') ||
        normalized.contains('проект') ||
        normalized.contains('office') ||
        normalized.contains('work')) {
      return 'briefcase';
    }
    if (normalized.contains('сервис') ||
        normalized.contains('сайт') ||
        normalized.contains('web') ||
        normalized.contains('internet')) {
      return 'globe';
    }
    if (normalized.contains('дом') || normalized.contains('home')) {
      return 'home';
    }
    if (normalized.contains('здоров') || normalized.contains('мед')) {
      return 'heart';
    }
    if (normalized.contains('сем') || normalized.contains('family')) {
      return 'family';
    }
    if (normalized.contains('покуп') || normalized.contains('shop')) {
      return 'cart';
    }
    if (normalized.contains('архив') || normalized.contains('archive')) {
      return 'snowflake';
    }
    return 'folder';
  }

  @override
  Widget build(BuildContext context) {
    synchronizeWindowMode();
    if (!unlocked) {
      inactivityTimer?.cancel();
      inactivityTimer = null;
      ensureLockedExitTimer();
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => recordLockedUserActivity(),
        onPointerMove: (_) => recordLockedUserActivity(),
        onPointerSignal: (_) => recordLockedUserActivity(),
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, __) {
            recordLockedUserActivity();
            return KeyEventResult.ignored;
          },
          child: buildLocked(),
        ),
      );
    }
    lockedExitTimer?.cancel();
    lockedExitTimer = null;
    ensureInactivityTimer();
    final shell = LayoutBuilder(
      builder: (context, constraints) {
        final portraitTablet = constraints.maxHeight > constraints.maxWidth &&
            min(constraints.maxWidth, constraints.maxHeight) >= 600;
        final mobile = constraints.maxWidth < 700 ||
            constraints.maxHeight < 500 ||
            portraitTablet;
        return mobile ? buildSpbMobileShell() : buildSpbDesktopShell();
      },
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => recordUserActivity(),
      onPointerMove: (_) => recordUserActivity(),
      onPointerHover: (_) => recordUserActivity(),
      onPointerSignal: (_) => recordUserActivity(),
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (_, __) {
          recordUserActivity();
          return KeyEventResult.ignored;
        },
        child: shell,
      ),
    );
  }

  static const _spbRightPanel = Color(0xffc7d9ea);
  static const _spbBorder = Color(0xffb7b7b7);

  Widget spbWorkspaceScrollbarTheme(Widget child) {
    return ScrollbarTheme(
      data: Theme.of(context).scrollbarTheme.copyWith(
            thickness: const WidgetStatePropertyAll<double>(10.88),
          ),
      child: child,
    );
  }

  Widget spbResourceIcon(String fileName, double size) => spbPackedImage(
        'spb://apk_icons/res/drawable-hdpi/$fileName',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        fallback: Icon(Icons.image_outlined, size: size),
      );

  Widget spbSizedDataIcon(String iconId, double size, {Color? fallbackColor}) {
    final embeddedBytes = spbEmbeddedIconPngs[iconId.toUpperCase()];
    if (embeddedBytes != null) {
      return Image.memory(
        embeddedBytes,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Icon(
          Icons.vpn_key_outlined,
          size: size,
          color: fallbackColor ?? const Color(0xffd79a00),
        ),
      );
    }
    final asset = spbPngIconAsset(iconId);
    if (asset != null) {
      return spbPackedImage(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        fallback: Icon(
          templateIconGlyph(iconId),
          size: size,
          color: fallbackColor ?? const Color(0xffd79a00),
        ),
      );
    }
    return Icon(
      templateIconGlyph(iconId),
      size: size,
      color: fallbackColor ?? const Color(0xffd79a00),
    );
  }

  Widget spbSectionHeader(
    String title, {
    Widget? leading,
    Widget? trailing,
    double height = 34,
    bool bold = false,
  }) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
        ),
        border: Border(bottom: BorderSide(color: _spbBorder)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading,
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget buildSpbSearchBar({
    bool mobile = false,
    double? desktopNavigatorWidth,
    double? desktopActionsPanelWidth,
  }) {
    final searchField = OverflowBox(
      maxHeight: 68,
      alignment: Alignment.centerLeft,
      child: Transform.translate(
        offset: const Offset(0, 21),
        child: SizedBox(
          width: mobile ? double.infinity : 250.445,
          height: 68,
          child: TextField(
            key: const Key('spbSearchInput'),
            controller: searchController,
            onChanged: updateSpbSearch,
            onSubmitted: submitSpbSearch,
            textInputAction: TextInputAction.search,
            textAlignVertical: TextAlignVertical.bottom,
            style: const TextStyle(
              fontSize: 19,
              height: 1,
              fontWeight: FontWeight.normal,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xffffffff),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Colors.black87, width: 1.2),
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Colors.black87, width: 1.2),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Colors.black, width: 1.5),
              ),
              contentPadding: const EdgeInsets.fromLTRB(12, 0, 4, 12),
              suffixIcon: buildSearchClearButton(
                const Key('spbClearSearchButton'),
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 30,
                minHeight: 30,
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      height: 48,
      color: const Color(0xfff4f4f4),
      padding: EdgeInsets.fromLTRB(mobile ? 22 : 11, 7, 12, 7),
      child: mobile
          ? LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  if (constraints.maxWidth >= 316) ...[
                    Transform.translate(
                      offset: const Offset(0, 3),
                      child: const Text(
                        'Поиск',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff202020),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: searchField),
                  const SizedBox(width: 4),
                  buildSpbSearchButton(
                    key: const Key('spbSubmitSearchButton'),
                    icon: Icons.search,
                    tooltip: 'Начать поиск',
                    gradient: const [Color(0xff42bff5), Color(0xff006fc4)],
                    onTap: () => submitSpbSearch(searchController.text),
                  ),
                  const SizedBox(width: 4),
                  buildSpbSearchButton(
                    key: spbSessionUndoButtonKey,
                    icon: Icons.undo,
                    tooltip: 'Отменить изменения этой сессии',
                    gradient: const [Color(0xffffdc58), Color(0xffc58a00)],
                    onTap: showSessionUndoMenu,
                  ),
                  const SizedBox(width: 4),
                  Transform.translate(
                    offset: const Offset(-1, 0),
                    child: buildSpbSearchButton(
                      key: const Key('spbForceCloseButton'),
                      icon: Icons.power_settings_new,
                      tooltip: 'Сохранить базу и закрыть программу',
                      gradient: const [Color(0xffff5a5f), Color(0xffa90000)],
                      onTap: exitApplication,
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  children: [
                    Transform.translate(
                      offset: const Offset(0, 3),
                      child: const Text(
                        'Поиск',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff202020),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 250.445, child: searchField),
                  ],
                ),
                Positioned(
                  left: max(
                    0,
                    (desktopNavigatorWidth ?? 300) - 11 - 34.2,
                  ),
                  top: 0,
                  child: buildSpbSearchButton(
                    key: const Key('spbSubmitSearchButton'),
                    icon: Icons.search,
                    tooltip: 'Начать поиск',
                    gradient: const [Color(0xff42bff5), Color(0xff006fc4)],
                    onTap: () => submitSpbSearch(searchController.text),
                  ),
                ),
                Positioned(
                  right: (desktopActionsPanelWidth ?? 300) - 49.2,
                  top: 0,
                  child: Row(
                    children: [
                      buildSpbSearchButton(
                        key: spbSessionUndoButtonKey,
                        icon: Icons.undo,
                        tooltip: 'Отменить изменения этой сессии',
                        gradient: const [Color(0xffffdc58), Color(0xffc58a00)],
                        onTap: showSessionUndoMenu,
                      ),
                      const SizedBox(width: 4),
                      Transform.translate(
                        offset: const Offset(-1, 0),
                        child: buildSpbSearchButton(
                          key: const Key('spbForceCloseButton'),
                          icon: Icons.power_settings_new,
                          tooltip: 'Сохранить базу и закрыть программу',
                          gradient: const [
                            Color(0xffff5a5f),
                            Color(0xffa90000),
                          ],
                          onTap: exitApplication,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> showSessionUndoMenu() async {
    final buttonContext = spbSessionUndoButtonKey.currentContext;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final button = buttonContext?.findRenderObject() as RenderBox?;
    if (button == null || overlay == null) return;
    final offset = button.localToGlobal(Offset.zero, ancestor: overlay);
    final selected = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + button.size.height,
        overlay.size.width - offset.dx - button.size.width,
        0,
      ),
      items: sessionUndoHistory.isEmpty
          ? const [
              PopupMenuItem<int>(
                enabled: false,
                child: Text('Нет изменений для отмены'),
              ),
            ]
          : [
              for (var index = sessionUndoHistory.length - 1;
                  index >= 0;
                  index--)
                PopupMenuItem<int>(
                  value: index,
                  child: Row(
                    children: [
                      templateIconWidget(
                        sessionUndoHistory[index].iconId,
                        size: 28,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          sessionUndoHistory[index].label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
    );
    if (selected != null && mounted) {
      await restoreSessionUndoAt(selected);
    }
  }

  Future<void> showSessionTrashMenu() async {
    final buttonContext = spbSessionTrashButtonKey.currentContext;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final button = buttonContext?.findRenderObject() as RenderBox?;
    if (button == null || overlay == null) return;
    final offset = button.localToGlobal(Offset.zero, ancestor: overlay);
    final entries = sessionTrash.reversed.toList();
    final selected = await showMenu<SessionTrashEntry>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + button.size.height,
        overlay.size.width - offset.dx - button.size.width,
        0,
      ),
      items: entries.isEmpty
          ? const [
              PopupMenuItem<SessionTrashEntry>(
                enabled: false,
                child: Text('Корзина пуста'),
              ),
            ]
          : [
              for (final entry in entries)
                PopupMenuItem<SessionTrashEntry>(
                  value: entry,
                  child: Row(
                    children: [
                      templateIconWidget(entry.iconId, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
    );
    if (selected != null && mounted) {
      await restoreSessionTrashEntry(selected);
    }
  }

  Future<void> restoreSessionTrashEntry(SessionTrashEntry entry) async {
    final wallet = spbWallet;
    if (wallet == null) return;
    SessionUndoEntry? undoEntry;
    try {
      final kind = switch (entry.kind) {
        SessionTrashKind.card => 'карточки',
        SessionTrashKind.folder => 'папки',
        SessionTrashKind.template => 'шаблона',
      };
      undoEntry = await captureSessionUndo(
        'Восстановление $kind: ${entry.title}',
        entry.iconId,
      );
      switch (entry.kind) {
        case SessionTrashKind.card:
          sessionTrashCardIds.remove(entry.id);
          break;
        case SessionTrashKind.folder:
          sessionTrashFolderPaths.remove(entry.id);
          break;
        case SessionTrashKind.template:
          sessionTrashTemplateIds.remove(entry.id);
          break;
      }
      sessionTrash.remove(entry);
      final snapshot = wallet.loadSnapshot();
      setState(() {
        applySpbSnapshot(snapshot);
        message = null;
      });
      commitSessionUndo(undoEntry);
    } catch (error) {
      discardSessionUndo(undoEntry);
      showSpbOperationMessage('Не удалось восстановить объект: $error');
    }
  }

  Widget buildSpbSearchButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 34.2,
      height: 34,
      child: OverflowBox(
        minHeight: 34.2,
        maxHeight: 34.2,
        child: SizedBox.square(
          dimension: 34.2,
          child: Tooltip(
            message: tooltip,
            child: Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: gradient,
                  ),
                  borderRadius: BorderRadius.circular(2.7),
                  border: Border.all(color: const Color(0x99000000)),
                ),
                child: InkWell(
                  key: key,
                  borderRadius: BorderRadius.circular(2.7),
                  onTap: onTap,
                  child: Icon(icon, color: Colors.white, size: 22.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void submitSpbSearch(String value) {
    setState(() {
      spbSubmittedSearchQuery = value.trim();
      spbExactSearch = true;
    });
  }

  void updateSpbSearch(String value) {
    final query = value.trim();
    final size = MediaQuery.sizeOf(context);
    final portraitTablet =
        size.height > size.width && min(size.width, size.height) >= 600;
    final narrowLayout =
        size.width < 700 || size.height < 500 || portraitTablet;
    setState(() {
      spbSubmittedSearchQuery = query;
      spbExactSearch = false;
      if (query.isNotEmpty &&
          (defaultTargetPlatform == TargetPlatform.android || narrowLayout)) {
        mobileTemplatesOpen = false;
        mobilePane = 1;
      }
    });
  }

  void clearSearch() {
    searchController.clear();
    setState(() {
      spbSubmittedSearchQuery = '';
      spbExactSearch = false;
    });
  }

  Widget? buildSearchClearButton(Key key) {
    if (searchController.text.isEmpty) return null;
    return IconButton(
      key: key,
      tooltip: 'Очистить поиск',
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.close, size: 16),
      onPressed: clearSearch,
    );
  }

  static const _englishKeyboard = "`qwertyuiop[]asdfghjkl;'zxcvbnm,.";
  static const _russianKeyboard = 'ёйцукенгшщзхъфывапролджэячсмитьбю';

  String spbSwapKeyboardLayout(String value) {
    final buffer = StringBuffer();
    for (final rune in value.toLowerCase().runes) {
      final character = String.fromCharCode(rune);
      final englishIndex = _englishKeyboard.indexOf(character);
      if (englishIndex >= 0) {
        buffer.write(_russianKeyboard[englishIndex]);
        continue;
      }
      final russianIndex = _russianKeyboard.indexOf(character);
      buffer.write(
        russianIndex >= 0 ? _englishKeyboard[russianIndex] : character,
      );
    }
    return buffer.toString();
  }

  String spbTransliterate(String value) {
    const replacements = <String, String>{
      'а': 'a',
      'б': 'b',
      'в': 'v',
      'г': 'g',
      'д': 'd',
      'е': 'e',
      'ё': 'e',
      'ж': 'zh',
      'з': 'z',
      'и': 'i',
      'й': 'y',
      'к': 'k',
      'л': 'l',
      'м': 'm',
      'н': 'n',
      'о': 'o',
      'п': 'p',
      'р': 'r',
      'с': 's',
      'т': 't',
      'у': 'u',
      'ф': 'f',
      'х': 'h',
      'ц': 'ts',
      'ч': 'ch',
      'ш': 'sh',
      'щ': 'sch',
      'ъ': '',
      'ы': 'y',
      'ь': '',
      'э': 'e',
      'ю': 'yu',
      'я': 'ya',
    };
    final buffer = StringBuffer();
    for (final rune in value.toLowerCase().runes) {
      final character = String.fromCharCode(rune);
      buffer.write(replacements[character] ?? character);
    }
    return buffer.toString();
  }

  Set<String> spbSearchVariants(String value) {
    final normalized = value.toLowerCase().trim();
    final swapped = spbSwapKeyboardLayout(normalized);
    return {
      normalized,
      swapped,
      spbTransliterate(normalized),
      spbTransliterate(swapped),
    }..removeWhere((entry) => entry.isEmpty);
  }

  int spbEditDistance(String left, String right) {
    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var leftIndex = 0; leftIndex < left.length; leftIndex++) {
      final current = <int>[leftIndex + 1];
      for (var rightIndex = 0; rightIndex < right.length; rightIndex++) {
        final substitution = previous[rightIndex] +
            (left[leftIndex] == right[rightIndex] ? 0 : 1);
        current.add(
          min(
            min(current[rightIndex] + 1, previous[rightIndex + 1] + 1),
            substitution,
          ),
        );
      }
      previous = current;
    }
    return previous.last;
  }

  bool spbWordsHaveSimilarSpelling(String text, String query) {
    final textWords = spbTransliterate(text)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final queryWords = spbTransliterate(query)
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.length >= 4)
        .toList();
    if (queryWords.isEmpty) return false;
    return queryWords.every((queryWord) {
      final tolerance = queryWord.length >= 8 ? 2 : 1;
      return textWords.any(
        (textWord) =>
            (textWord.length - queryWord.length).abs() <= tolerance &&
            spbEditDistance(textWord, queryWord) <= tolerance,
      );
    });
  }

  bool spbSearchMatches(String text, String query) {
    final textVariants = spbSearchVariants(text);
    final queryVariants = spbSearchVariants(query);
    for (final queryVariant in queryVariants) {
      if (textVariants
          .any((textVariant) => textVariant.contains(queryVariant))) {
        return true;
      }
      if (textVariants.any(
        (textVariant) => spbWordsHaveSimilarSpelling(textVariant, queryVariant),
      )) {
        return true;
      }
    }
    return false;
  }

  bool spbExactSearchMatches(Iterable<String> values, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return false;
    return values.any(
      (value) => value.trim().toLowerCase() == normalizedQuery,
    );
  }

  List<String> spbMatchingFolderPaths(String query) {
    if (query.isEmpty) return const [];
    final allPaths = <String>{};
    for (final category in existingCategories()) {
      final parts = categoryParts(category);
      for (var index = 1; index <= parts.length; index++) {
        allPaths.add(parts.take(index).join(' / '));
      }
    }
    return allPaths.where((path) {
      if (!spbExactSearch) return spbSearchMatches(path, query);
      final parts = categoryParts(path);
      return spbExactSearchMatches(
        [path, if (parts.isNotEmpty) parts.last],
        query,
      );
    }).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<SecretItem> spbMatchingCards(String query) {
    if (query.isEmpty) return const [];
    return items.where((item) {
      final template = templateFor(item.templateId);
      final searchableValues = <String>[
        item.title,
        item.category,
        template.name,
        ...item.values.values,
      ];
      if (spbExactSearch) {
        return spbExactSearchMatches(searchableValues, query);
      }
      return spbSearchMatches(searchableValues.join(' '), query);
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  Widget buildSpbDesktopShell() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const rightDividerWidth = 1.0;
            const minimumNavigatorWidth = 416.0;
            const minimumCenterWidth = 160.0;
            const minimumRightPanelWidth = 180.0;
            const splitterHitWidth = 9.0;
            final defaultRightPanelWidth = constraints.maxWidth * 0.20;
            final maximumRightPanelWidth = max(
              minimumRightPanelWidth,
              constraints.maxWidth -
                  rightDividerWidth * 2 -
                  minimumNavigatorWidth -
                  minimumCenterWidth,
            );
            final rightPanelWidth =
                (spbActionsPanelWidth ?? defaultRightPanelWidth)
                    .clamp(minimumRightPanelWidth, maximumRightPanelWidth)
                    .toDouble();
            final maximumNavigatorWidth = max(
              minimumNavigatorWidth,
              constraints.maxWidth -
                  rightDividerWidth * 2 -
                  rightPanelWidth -
                  minimumCenterWidth,
            );
            final defaultNavigatorWidth = constraints.maxWidth * 0.30;
            final navigatorWidth = (spbNavigatorWidth ?? defaultNavigatorWidth)
                .clamp(minimumNavigatorWidth, maximumNavigatorWidth)
                .toDouble();
            return Column(
              children: [
                buildSpbSearchBar(
                  desktopNavigatorWidth: navigatorWidth,
                  desktopActionsPanelWidth: rightPanelWidth,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: navigatorWidth,
                            child:
                                spbWorkspaceScrollbarTheme(buildSpbNavigator()),
                          ),
                          const VerticalDivider(width: 1, thickness: 1),
                          Expanded(
                            child: spbWorkspaceScrollbarTheme(
                              mobileTemplatesOpen
                                  ? buildSpbTemplateWorkspace()
                                  : buildSpbFolderGrid(),
                            ),
                          ),
                          const VerticalDivider(width: 1, thickness: 1),
                          SizedBox(
                            width: rightPanelWidth,
                            child: spbWorkspaceScrollbarTheme(
                              buildSpbActionsPanel(desktop: true),
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        left: navigatorWidth - (splitterHitWidth - 1) / 2,
                        top: 0,
                        bottom: 0,
                        width: splitterHitWidth,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            key: const Key('spbNavigatorSplitter'),
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate: (details) {
                              setState(() {
                                spbNavigatorWidth =
                                    (navigatorWidth + details.delta.dx)
                                        .clamp(
                                          minimumNavigatorWidth,
                                          maximumNavigatorWidth,
                                        )
                                        .toDouble();
                              });
                            },
                          ),
                        ),
                      ),
                      Positioned(
                        left: constraints.maxWidth -
                            rightPanelWidth -
                            rightDividerWidth -
                            (splitterHitWidth - 1) / 2,
                        top: 0,
                        bottom: 0,
                        width: splitterHitWidth,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            key: const Key('spbActionsPanelSplitter'),
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragUpdate: (details) {
                              setState(() {
                                spbActionsPanelWidth =
                                    (rightPanelWidth - details.delta.dx)
                                        .clamp(
                                          minimumRightPanelWidth,
                                          maximumRightPanelWidth,
                                        )
                                        .toDouble();
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget buildSpbMobileShell() {
    final paneTitle = mobileTemplatesOpen
        ? switch (mobilePane) {
            2 => 'Задачи',
            _ => 'Шаблоны',
          }
        : switch (mobilePane) {
            1 => selectedCategoryPath.isEmpty
                ? selectedVaultTitle
                : categoryParts(selectedCategoryPath).last,
            2 => 'Задачи',
            _ => 'Мои карточки',
          };
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 54,
              color: const Color(0xff7d7d7d),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Image.asset(
                    'assets/branding/wallet_android.png',
                    key: const Key('spbMobileAppIcon'),
                    width: 40,
                    height: 40,
                    cacheWidth: 128,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      selectedVaultTitle,
                      key: const Key('spbMobileWalletTitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            buildSpbSearchBar(mobile: true),
            if (mobilePane == 0)
              GestureDetector(
                key: const Key('spbMobilePaneHeader'),
                behavior: HitTestBehavior.opaque,
                onTap: mobileTemplatesOpen
                    ? null
                    : () => setState(() {
                          selectedCategoryPath = '';
                          selectedCategoryId = null;
                          mobilePane = 1;
                        }),
                child: spbSectionHeader(paneTitle, height: 42),
              ),
            Expanded(
              child: spbWorkspaceScrollbarTheme(
                mobileTemplatesOpen
                    ? switch (mobilePane) {
                        1 => buildSpbTemplateWorkspace(showHeader: false),
                        2 => buildSpbActionsPanel(),
                        _ => buildSpbTemplateTree(),
                      }
                    : switch (mobilePane) {
                        1 => buildSpbFolderGrid(),
                        2 => buildSpbActionsPanel(),
                        _ => buildSpbTreeBody(showWalletRoot: false),
                      },
              ),
            ),
            if (mobilePane == 0) ...[
              buildSpbModeButton(
                label: 'Мои карточки',
                iconFile: 'icon_wallets.png',
                selected: !mobileTemplatesOpen,
                onTap: showSpbCardsMode,
              ),
              buildSpbModeButton(
                label: 'Шаблоны',
                iconFile: 'icon_templates.png',
                selected: mobileTemplatesOpen,
                onTap: showSpbTemplatesMode,
              ),
            ],
            buildSpbMobileArrows(
              allowBack: mobilePane > 0,
              allowForward: mobilePane < 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSpbMobileArrows({
    required bool allowBack,
    required bool allowForward,
  }) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xfff4f4f4),
        border: Border(top: BorderSide(color: _spbBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Spb3dArrowButton(
            key: const Key('mobilePaneBack'),
            icon: Icons.arrow_left,
            onPressed: allowBack ? () => setState(() => mobilePane--) : null,
          ),
          _Spb3dArrowButton(
            key: const Key('mobileFolderUp'),
            icon: Icons.arrow_drop_up,
            onPressed: !mobileTemplatesOpen &&
                    mobilePane == 1 &&
                    selectedCategoryPath.isNotEmpty
                ? openParentSpbFolder
                : null,
          ),
          _Spb3dArrowButton(
            key: const Key('mobilePaneForward'),
            icon: Icons.arrow_right,
            onPressed: allowForward ? () => setState(() => mobilePane++) : null,
          ),
        ],
      ),
    );
  }

  void openParentSpbFolder() {
    final parts = categoryParts(selectedCategoryPath);
    if (parts.isNotEmpty) parts.removeLast();
    openSpbFolder(parts.join(' / '));
  }

  void openSpbFolder(String path) {
    final size = MediaQuery.sizeOf(context);
    final mobile = defaultTargetPlatform == TargetPlatform.android
        ? size.height >= size.width
        : size.width < 700;
    setState(() {
      selectedCategoryPath = path;
      selectedCategoryId = categoryIdsByPath[path];
      if (mobile) mobilePane = 1;
    });
  }

  void showSpbCardsMode() {
    setState(() {
      mobileTemplatesOpen = false;
      mobilePane = 0;
    });
  }

  void showSpbTemplatesMode() {
    searchController.clear();
    setState(() {
      mobileTemplatesOpen = true;
      mobilePane = 0;
      spbSubmittedSearchQuery = '';
      if (templates.isNotEmpty &&
          !templates.any((template) => template.id == selectedTemplateId)) {
        selectedTemplateId = templates.first.id;
      }
    });
  }

  Widget buildSpbNavigator() {
    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const Key('spbVaultTitle'),
            onTap: () {
              searchController.clear();
              setState(() {
                spbSubmittedSearchQuery = '';
                selectedCategoryPath = '';
                selectedCategoryId = null;
              });
            },
            child: spbSectionHeader(
              selectedVaultTitle,
              leading: Image.asset(
                'assets/branding/wallet_android.png',
                key: const Key('spbDesktopAppIcon'),
                width: 28,
                height: 28,
                cacheWidth: 96,
                fit: BoxFit.contain,
              ),
              bold: true,
            ),
          ),
          Expanded(
            child: mobileTemplatesOpen
                ? buildSpbTemplateTree(compactRows: true)
                : buildSpbTreeBody(compactRows: true, showWalletRoot: false),
          ),
          buildSpbModeButton(
            label: 'Мои карточки',
            iconFile: 'icon_wallets.png',
            selected: !mobileTemplatesOpen,
            onTap: showSpbCardsMode,
          ),
          buildSpbModeButton(
            label: 'Шаблоны',
            iconFile: 'icon_templates.png',
            selected: mobileTemplatesOpen,
            onTap: showSpbTemplatesMode,
          ),
        ],
      ),
    );
  }

  Widget buildSpbModeButton({
    required String label,
    required String iconFile,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0xffdbeaf5) : const Color(0xfff5f5f5),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _spbBorder)),
          ),
          child: Row(
            children: [
              spbResourceIcon(iconFile, 40),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget spbExpansionMark(bool expanded) {
    return Container(
      width: 15,
      height: 15,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xfff5f5f5),
        border: Border.all(color: const Color(0xff8d9aa3)),
      ),
      child: expanded
          ? const Text(
              '−',
              style: TextStyle(
                color: Color(0xff526b7d),
                fontSize: 15,
                height: 0.9,
                fontWeight: FontWeight.w700,
              ),
            )
          : const Icon(
              Icons.add,
              color: Color(0xff526b7d),
              size: 13,
              weight: 700,
            ),
    );
  }

  Widget buildSpbTreeBody({
    bool compactRows = false,
    bool showWalletRoot = true,
  }) {
    final query = searchController.text.trim();
    final root = buildCategoryTree(
      filteredItems(),
      includeAllCategories: query.isEmpty,
      additionalPaths: query.isEmpty ? const [] : spbMatchingFolderPaths(query),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(5, 10, 5, 12),
      children: [
        if (showWalletRoot)
          Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              splashColor: Colors.transparent,
            ),
            child: ExpansionTile(
              initiallyExpanded: true,
              onExpansionChanged: (expanded) => setState(() {
                rootTreeExpanded = expanded;
                if (expanded) {
                  selectedCategoryPath = '';
                  selectedCategoryId = null;
                }
              }),
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              childrenPadding: EdgeInsets.zero,
              trailing: const SizedBox.shrink(),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [spbResourceIcon('icon_wallets_small.png', 40)],
              ),
              title: buildSpbCardDropTarget(
                categoryPath: '',
                child: GestureDetector(
                  key: const Key('spbWalletRoot'),
                  onTap: () => openSpbFolder(''),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 3,
                    ),
                    decoration: selectedCategoryPath.isEmpty
                        ? const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xffc9e5f8), Color(0xffeef8ff)],
                            ),
                          )
                        : null,
                    child: Text(
                      selectedVaultTitle,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
              children: buildSpbTreeChildren(root, 0),
            ),
          ),
        if (!showWalletRoot)
          ...buildSpbTreeChildren(root, 0, compactRows: compactRows),
      ],
    );
  }

  List<Widget> buildSpbTreeChildren(
    CategoryTreeNode node,
    int depth, {
    bool compactRows = false,
  }) {
    final result = <Widget>[];
    final folders = node.children.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final folder in folders) {
      result.add(
        Padding(
          padding: EdgeInsets.only(left: depth * 15.0),
          child: GestureDetector(
            onSecondaryTapDown: (details) =>
                showSpbFolderMenu(folder, details.globalPosition),
            onLongPressStart: (details) =>
                showSpbFolderMenu(folder, details.globalPosition),
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                dense: true,
                initiallyExpanded: expandedCategoryPaths.contains(folder.path),
                onExpansionChanged: (expanded) {
                  setState(() {
                    if (expanded) {
                      expandedCategoryPaths.add(folder.path);
                      selectedCategoryPath = folder.path;
                      selectedCategoryId = folder.id;
                    } else {
                      expandedCategoryPaths.remove(folder.path);
                    }
                  });
                },
                visualDensity: const VisualDensity(vertical: -3.25),
                minTileHeight: compactRows ? 16.2 : 30,
                tilePadding: const EdgeInsets.only(left: 6, right: 2),
                childrenPadding: EdgeInsets.zero,
                trailing: const SizedBox.shrink(),
                leading: SizedBox(
                  width: 60,
                  height: compactRows ? 18 : 30,
                  child: OverflowBox(
                    minWidth: 60,
                    maxWidth: 60,
                    minHeight: 40,
                    maxHeight: 40,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        spbExpansionMark(
                          expandedCategoryPaths.contains(folder.path),
                        ),
                        const SizedBox(width: 3.75),
                        spbSizedDataIcon(
                          folder.iconId ??
                              defaultIconForCategoryPath(folder.path),
                          40,
                          fallbackColor: categoryPictogramColor(folder.colorId),
                        ),
                      ],
                    ),
                  ),
                ),
                title: buildSpbCardDropTarget(
                  categoryPath: folder.path,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => openSpbFolder(folder.path),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: compactRows ? 0 : 3,
                      ),
                      decoration: selectedCategoryPath == folder.path
                          ? const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xffb9dcf5), Color(0xffedf7fe)],
                              ),
                            )
                          : null,
                      child: Text(
                        folder.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18.8,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
                children: buildSpbTreeChildren(
                  folder,
                  depth + 1,
                  compactRows: compactRows,
                ),
              ),
            ),
          ),
        ),
      );
    }
    final cards = [...node.cards]
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    for (final item in cards) {
      final template = templateFor(item.templateId);
      result.add(
        Padding(
          padding: EdgeInsets.only(left: 25.5 + depth * 15.0),
          child: GestureDetector(
            key: ValueKey('spbTreeCard-${item.id}'),
            onSecondaryTapDown: (details) =>
                showSpbCardMenu(item, details.globalPosition),
            onLongPressStart: (details) =>
                showSpbCardMenu(item, details.globalPosition),
            child: ListTile(
              selected: selectedItemId == item.id,
              selectedTileColor: const Color(0xffcfe9fb),
              dense: true,
              visualDensity: const VisualDensity(vertical: -3.25),
              minTileHeight: compactRows ? 20.25 : 30,
              contentPadding: const EdgeInsets.symmetric(horizontal: 5),
              leading: SizedBox(
                width: 40,
                height: compactRows ? 20.25 : 30,
                child: OverflowBox(
                  minWidth: 40,
                  maxWidth: 40,
                  minHeight: 40,
                  maxHeight: 40,
                  child: spbSizedDataIcon(
                    itemIconId(item, template),
                    40,
                    fallbackColor: itemPictogramColor(item, template),
                  ),
                ),
              ),
              title: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17),
              ),
              onTap: () => openCardPreviewDialog(item),
            ),
          ),
        ),
      );
    }
    return result;
  }

  Widget buildSpbTemplateTree({bool compactRows = false}) {
    final query = searchController.text.trim().toLowerCase();
    final visible = templates
        .where(
          (entry) => query.isEmpty || entry.name.toLowerCase().contains(query),
        )
        .toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final template = visible[index];
        return GestureDetector(
          key: ValueKey('spbTemplate-${template.id}'),
          onDoubleTap: () => openTemplatePreview(template),
          onSecondaryTapDown: (details) =>
              showSpbTemplateMenu(template, details.globalPosition),
          onLongPressStart: (details) =>
              showSpbTemplateMenu(template, details.globalPosition),
          child: ListTile(
            dense: true,
            minTileHeight: compactRows ? 36 : null,
            selected: selectedTemplateId == template.id,
            selectedTileColor: const Color(0xffdbeaf5),
            leading: spbSizedDataIcon(
              template.iconId,
              40,
              fallbackColor: templateDisplayPictogramColor(template),
            ),
            title: Text(
              template.name,
              style: const TextStyle(fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => setState(() => selectedTemplateId = template.id),
          ),
        );
      },
    );
  }

  Future<void> showSpbTemplateMenu(
    CardTemplate template,
    Offset globalPosition,
  ) async {
    setState(() => selectedTemplateId = template.id);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          key: Key('createTemplateFromIconContextAction'),
          value: 'create',
          child: Text('Создать'),
        ),
        PopupMenuItem(
          key: Key('viewTemplateContextAction'),
          value: 'view',
          child: Text('Просмотр'),
        ),
        PopupMenuItem(
          key: Key('editTemplateContextAction'),
          value: 'edit',
          child: Text('Редактировать'),
        ),
        PopupMenuItem(
          key: Key('copyTemplateContextAction'),
          value: 'copy',
          child: Text('Копировать'),
        ),
        PopupMenuItem(
          key: Key('exportTemplateContextAction'),
          value: 'export',
          child: Text('Экспортировать'),
        ),
        PopupMenuItem(
          key: Key('importTemplateFromIconContextAction'),
          value: 'import',
          child: Text('Импортировать'),
        ),
        PopupMenuItem(
          key: Key('deleteTemplateContextAction'),
          value: 'delete',
          child: Text('Удалить'),
        ),
      ],
    );
    if (!mounted || selected == null) return;
    if (selected == 'create') {
      await openTemplateDialog();
    } else if (selected == 'view') {
      await openTemplatePreview(template);
    } else if (selected == 'edit') {
      await openTemplateDialog(template: template);
    } else if (selected == 'copy') {
      await cloneSpbTemplate(template);
    } else if (selected == 'export') {
      await exportSelectedSpbTemplate();
    } else if (selected == 'import') {
      await importSpbTemplate();
    } else if (selected == 'delete') {
      await deleteTemplateWithConfirmation(template);
    }
  }

  Future<void> cloneSpbTemplate(CardTemplate template) async {
    final existingNames = templates.map((entry) => entry.name).toSet();
    var suffix = 1;
    var cloneName = '${template.name} ($suffix)';
    while (existingNames.contains(cloneName)) {
      suffix++;
      cloneName = '${template.name} ($suffix)';
    }
    final clone = CardTemplate(
      id: makeId('tpl'),
      name: cloneName,
      iconId: template.iconId,
      colorId: template.colorId,
      spbColor: template.spbColor,
      categoryPath: template.categoryPath,
      fields: [
        for (final field in template.fields)
          FieldDefinition(
            id: field.id,
            label: field.label,
            type: field.type,
            required: field.required,
            secret: field.secret,
          ),
      ],
    );
    final saved = await saveSpbTemplateDefinition(clone, isNew: true);
    if (saved) {
      showTemplateActionMessage('Создана копия шаблона «$cloneName».');
    }
  }

  Widget buildSpbTemplateWorkspace({bool showHeader = true}) {
    final query = searchController.text.trim().toLowerCase();
    final visible = templates
        .where(
          (template) =>
              query.isEmpty || template.name.toLowerCase().contains(query),
        )
        .toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader)
          spbSectionHeader(
            'Шаблоны',
            trailing: spbResourceIcon('icon_templates.png', 23),
          ),
        Expanded(
          child: GestureDetector(
            key: const Key('spbTemplateWorkspace'),
            behavior: HitTestBehavior.translucent,
            onSecondaryTapDown: (details) =>
                showSpbTemplateImportMenu(details.globalPosition),
            onLongPressStart: (details) =>
                showSpbTemplateImportMenu(details.globalPosition),
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 89.04,
                mainAxisExtent: 83.475,
                crossAxisSpacing: 3.975,
                mainAxisSpacing: 6.36,
              ),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final template = visible[index];
                return KeyedSubtree(
                  key: ValueKey('spbCentralTemplate-${template.id}'),
                  child: buildSpbGridEntry(
                    label: template.name,
                    icon: spbSizedDataIcon(
                      template.iconId,
                      50.25,
                      fallbackColor: templateDisplayPictogramColor(template),
                    ),
                    onTap: () =>
                        setState(() => selectedTemplateId = template.id),
                    onDoubleTap: () => openTemplatePreview(template),
                    onContextMenu: (position) =>
                        showSpbTemplateMenu(template, position),
                    selected: selectedTemplateId == template.id,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> showSpbTemplateImportMenu(Offset globalPosition) async {
    if (spbObjectMenuPointerActive) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          key: Key('createTemplateContextAction'),
          value: 'create',
          child: Text('Создать'),
        ),
        PopupMenuItem(
          key: Key('importTemplateContextAction'),
          value: 'import',
          child: Text('Импортировать'),
        ),
      ],
    );
    if (!mounted) return;
    if (selected == 'create') {
      await openTemplateDialog();
    } else if (selected == 'import') {
      await importSpbTemplate();
    }
  }

  Future<bool> deleteTemplateWithConfirmation(CardTemplate template) async {
    if (!ensureSpbWalletWritable()) return false;
    final linkedCards =
        items.where((item) => item.templateId == template.id).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xffececec),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Text('Удалить шаблон'),
        content: Text(
          linkedCards == 0
              ? 'Шаблон "${template.name}" будет перемещён во внутреннюю корзину.'
              : 'Шаблон "${template.name}" и связанные с ним карточки '
                  '($linkedCards) будут перемещены во внутреннюю корзину.',
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actions: [
          SizedBox(
            width: 124,
            child: passwordKey(
              key: const Key('cancelDeleteTemplateButton'),
              label: 'Отмена',
              height: 40,
              fontSize: 18,
              onPressed: () => Navigator.pop(dialogContext, false),
            ),
          ),
          SizedBox(
            width: 124,
            child: passwordKey(
              key: const Key('confirmDeleteTemplateButton'),
              label: 'Удалить',
              height: 40,
              fontSize: 18,
              top: const Color(0xffe04b3f),
              bottom: const Color(0xff8f1515),
              onPressed: () => Navigator.pop(dialogContext, true),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    final wallet = spbWallet;
    if (wallet == null) {
      showTemplateActionMessage(
        'Откройте или создайте .swl базу перед удалением шаблонов.',
      );
      return false;
    }
    SessionUndoEntry? undoEntry;
    try {
      undoEntry = await captureSessionUndo(
        'Удаление шаблона: ${template.name}',
        template.iconId,
      );
      sessionTrashTemplateIds.add(template.id);
      sessionTrash.add(
        SessionTrashEntry(
          kind: SessionTrashKind.template,
          id: template.id,
          title: template.name,
          iconId: template.iconId,
        ),
      );
      setState(() {
        templates = templates
            .where((entry) => entry.id != template.id)
            .toList(growable: false);
        templatesById.remove(template.id);
        final removedCardIds = items
            .where((item) => item.templateId == template.id)
            .map((item) => item.id)
            .toSet();
        items = items
            .where((item) => item.templateId != template.id)
            .toList(growable: false);
        itemsById.removeWhere((id, _) => removedCardIds.contains(id));
        if (selectedTemplateId == template.id) {
          selectedTemplateId = templates.isEmpty ? null : templates.first.id;
        }
        if (selectedItemId != null && !itemsById.containsKey(selectedItemId)) {
          selectedItemId = null;
        }
        message = null;
      });
      commitSessionUndo(undoEntry);
      return true;
    } catch (error) {
      discardSessionUndo(undoEntry);
      sessionTrashTemplateIds.remove(template.id);
      sessionTrash.removeWhere(
        (entry) =>
            entry.kind == SessionTrashKind.template && entry.id == template.id,
      );
      showTemplateActionMessage('Не удалось удалить шаблон: $error');
      return false;
    }
  }

  CategoryTreeNode categoryNodeAt(CategoryTreeNode root, String path) {
    var current = root;
    for (final part in categoryParts(path)) {
      final next = current.children[part];
      if (next == null) return root;
      current = next;
    }
    return current;
  }

  Widget buildSpbFolderGrid() {
    final searchQuery = spbSubmittedSearchQuery;
    final showingSearchResults = searchQuery.isNotEmpty;
    final root = buildCategoryTree(
      showingSearchResults ? items : filteredItems(),
    );
    final node = categoryNodeAt(root, selectedCategoryPath);
    final folders = showingSearchResults
        ? [
            for (final path in spbMatchingFolderPaths(searchQuery))
              if (categoryNodeAt(root, path).path == path)
                categoryNodeAt(root, path),
          ]
        : (node.children.values.toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ));
    final cards = showingSearchResults
        ? spbMatchingCards(searchQuery)
        : ([...node.cards]..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          ));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        showingSearchResults
            ? spbSectionHeader(
                'Результаты поиска',
                trailing: const Icon(Icons.search, size: 23),
              )
            : selectedCategoryPath.isEmpty
                ? spbSectionHeader(
                    'Мои карточки',
                    trailing: spbResourceIcon('icon_wallets_small.png', 23),
                  )
                : Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xffb9dcf5), Color(0xfff2f9fe)],
                      ),
                      border: Border(bottom: BorderSide(color: _spbBorder)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            categoryParts(selectedCategoryPath).last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xff18364d),
                              fontSize: 18,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                        spbResourceIcon('icon_wallets_small.png', 23),
                      ],
                    ),
                  ),
        Expanded(
          child: ColoredBox(
            color: selectedCategoryPath.isEmpty ||
                    categoryColorsByPath[selectedCategoryPath] == null
                ? Colors.transparent
                : colorById(categoryColorsByPath[selectedCategoryPath]!).bg,
            child: GestureDetector(
              key: const Key('spbCentralWorkspace'),
              behavior: HitTestBehavior.translucent,
              onSecondaryTapDown: (details) =>
                  showSpbCreationMenu(details.globalPosition),
              onLongPressStart: (details) =>
                  showSpbCreationMenu(details.globalPosition),
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 89.04,
                  mainAxisExtent: 83.475,
                  crossAxisSpacing: 3.975,
                  mainAxisSpacing: 6.36,
                ),
                itemCount: folders.length + cards.length,
                itemBuilder: (context, index) {
                  if (index < folders.length) {
                    final folder = folders[index];
                    return buildSpbGridEntry(
                      label: folder.name,
                      icon: spbSizedDataIcon(
                        folder.iconId ??
                            defaultIconForCategoryPath(folder.path),
                        50.25,
                        fallbackColor: categoryPictogramColor(folder.colorId),
                      ),
                      onTap: () => openSpbFolder(folder.path),
                      onContextMenu: (position) =>
                          showSpbFolderMenu(folder, position),
                    );
                  }
                  final item = cards[index - folders.length];
                  final template = templateFor(item.templateId);
                  final cardEntry = buildSpbGridEntry(
                    label: item.title,
                    labelWidth: 73.3125,
                    selected: selectedItemId == item.id,
                    icon: SizedBox(
                      width: 50.25,
                      height: 50.25,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          spbSizedDataIcon(
                            itemIconId(item, template),
                            50.25,
                            fallbackColor: itemPictogramColor(item, template),
                          ),
                          if (item.attachments.any(
                            (attachment) => !attachment.deleted,
                          ))
                            Positioned(
                              key: ValueKey('cardAttachmentArrow-${item.id}'),
                              right: 2,
                              bottom: 2,
                              width: 16.33125,
                              height: 14.586,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  for (final offset in const [
                                    Offset(-2, 0),
                                    Offset(2, 0),
                                    Offset(0, -2),
                                    Offset(0, 2),
                                    Offset(-1.414, -1.414),
                                    Offset(1.414, -1.414),
                                    Offset(-1.414, 1.414),
                                    Offset(1.414, 1.414),
                                  ])
                                    Transform.translate(
                                      offset: offset,
                                      child: Image.asset(
                                        'assets/branding/attachment_arrow.png',
                                        width: 16.33125,
                                        height: 14.586,
                                        fit: BoxFit.fill,
                                        color: Colors.white,
                                        colorBlendMode: BlendMode.srcIn,
                                      ),
                                    ),
                                  ShaderMask(
                                    blendMode: BlendMode.srcIn,
                                    shaderCallback: (bounds) =>
                                        const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xffff4fa3),
                                        Color(0xffe6007e),
                                        Color(0xffa8005b),
                                      ],
                                    ).createShader(bounds),
                                    child: Image.asset(
                                      'assets/branding/attachment_arrow.png',
                                      width: 16.33125,
                                      height: 14.586,
                                      fit: BoxFit.fill,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    onTap: () => openCardPreviewDialog(item),
                    onContextMenu: (position) =>
                        showSpbCardMenu(item, position),
                  );
                  return KeyedSubtree(
                    key: ValueKey('spbCentralCard-${item.id}'),
                    child: Draggable<SecretItem>(
                      data: item,
                      maxSimultaneousDrags: spbWallet == null ? 0 : 1,
                      dragAnchorStrategy: pointerDragAnchorStrategy,
                      feedback: Material(
                        color: Colors.transparent,
                        child: Container(
                          width: 104,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xffedf7fe),
                            border: Border.all(color: const Color(0xff367ca8)),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 6),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              spbSizedDataIcon(
                                itemIconId(item, template),
                                42,
                                fallbackColor:
                                    itemPictogramColor(item, template),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.35,
                        child: cardEntry,
                      ),
                      child: cardEntry,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> showSpbCreationMenu(Offset globalPosition) async {
    if (spbObjectMenuPointerActive) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'card',
          child: Row(
            children: [
              spbResourceIcon('icon_add_card.png', 24),
              const SizedBox(width: 9),
              const Flexible(child: Text('Создать карточку')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'folder',
          child: Row(
            children: [
              spbResourceIcon('icon_add_folder.png', 24),
              const SizedBox(width: 9),
              const Flexible(child: Text('Создать папку')),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'import',
          child: Row(
            children: [
              Icon(Icons.file_open_outlined, size: 24),
              SizedBox(width: 9),
              Flexible(child: Text('Импорт')),
            ],
          ),
        ),
      ],
    );
    if (!mounted) return;
    if (selected == 'card') {
      await openItemDialog(initialCategory: selectedCategoryPath);
    } else if (selected == 'folder') {
      await openCategoryEditorDialog(
        folder: null,
        parentPath: selectedCategoryPath,
      );
    } else if (selected == 'import') {
      await importSpbWalletCards();
    }
  }

  Future<String?> showSpbObjectMenu(
    Offset globalPosition, {
    bool allowExport = false,
    bool allowCopy = false,
    bool allowShare = false,
  }) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: 'open',
          child: Row(
            children: [
              Icon(Icons.open_in_new, size: 22),
              SizedBox(width: 9),
              Text('Открыть'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 22),
              SizedBox(width: 9),
              Text('Редактировать'),
            ],
          ),
        ),
        if (allowExport)
          const PopupMenuItem(
            key: Key('exportObjectContextAction'),
            value: 'export',
            child: Row(
              children: [
                Icon(Icons.save_alt_outlined, size: 22),
                SizedBox(width: 9),
                Text('Экспорт'),
              ],
            ),
          ),
        if (allowCopy)
          const PopupMenuItem(
            key: Key('copyCardContextAction'),
            value: 'copy',
            child: Row(
              children: [
                Icon(Icons.copy_all_outlined, size: 22),
                SizedBox(width: 9),
                Text('Копировать'),
              ],
            ),
          ),
        if (allowShare)
          const PopupMenuItem(
            key: Key('shareCardContextAction'),
            value: 'share',
            child: Row(
              children: [
                Icon(Icons.share_outlined, size: 22),
                SizedBox(width: 9),
                Text('Поделиться'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 22),
              SizedBox(width: 9),
              Text('Удалить'),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> showSpbFolderMenu(
    CategoryTreeNode folder,
    Offset globalPosition,
  ) async {
    if (spbContextMenuOpen) return;
    spbContextMenuOpen = true;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    String? selected;
    try {
      selected = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
          Offset.zero & overlay.size,
        ),
        items: const [
          PopupMenuItem(
            key: Key('viewFolderContextAction'),
            value: 'view',
            child: Text('Просмотр'),
          ),
          PopupMenuItem(
            key: Key('createInFolderContextAction'),
            value: 'create',
            child: Text('Создать'),
          ),
          PopupMenuItem(
            key: Key('editFolderContextAction'),
            value: 'edit',
            child: Text('Редактировать'),
          ),
          PopupMenuItem(
            key: Key('moveFolderContextAction'),
            value: 'move',
            child: Text('Переместить'),
          ),
          PopupMenuItem(
            key: Key('exportFolderContextAction'),
            value: 'export',
            child: Text('Экспортировать'),
          ),
          PopupMenuItem(
            key: Key('importFolderContextAction'),
            value: 'import',
            child: Text('Импортировать'),
          ),
        ],
      );
    } finally {
      spbContextMenuOpen = false;
    }
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'view':
        openSpbFolder(folder.path);
        break;
      case 'create':
        await openItemDialog(initialCategory: folder.path);
        break;
      case 'edit':
        await openCategoryEditorDialog(folder: folder);
        break;
      case 'move':
        await moveSpbFolder(folder);
        break;
      case 'export':
        await exportSpbItems(
          items
              .where(
                (item) =>
                    item.category == folder.path ||
                    item.category.startsWith('${folder.path} / '),
              )
              .toList(),
          suggestedName: folder.name,
          categoryPath: folder.path,
        );
        break;
      case 'import':
        await importSpbWalletCards();
        break;
    }
  }

  Future<void> showSpbCardMenu(SecretItem item, Offset globalPosition) async {
    if (spbContextMenuOpen) return;
    spbContextMenuOpen = true;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    String? selected;
    try {
      selected = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
          Offset.zero & overlay.size,
        ),
        items: const [
          PopupMenuItem(
            key: Key('viewCardContextAction'),
            value: 'view',
            child: Text('Просмотр'),
          ),
          PopupMenuItem(
            key: Key('createCardContextAction'),
            value: 'create',
            child: Text('Создать'),
          ),
          PopupMenuItem(
            key: Key('editCardContextAction'),
            value: 'edit',
            child: Text('Редактировать'),
          ),
          PopupMenuItem(
            key: Key('copyCardContextAction'),
            value: 'copy',
            child: Text('Копировать'),
          ),
          PopupMenuItem(
            key: Key('moveCardContextAction'),
            value: 'move',
            child: Text('Переместить'),
          ),
          PopupMenuItem(
            key: Key('exportObjectContextAction'),
            value: 'export',
            child: Text('Экспортировать'),
          ),
          PopupMenuItem(
            key: Key('importCardContextAction'),
            value: 'import',
            child: Text('Импортировать'),
          ),
          PopupMenuItem(
            key: Key('deleteCardContextAction'),
            value: 'delete',
            child: Text('Удалить'),
          ),
        ],
      );
    } finally {
      spbContextMenuOpen = false;
    }
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'view':
        await openCardPreviewDialog(item);
        break;
      case 'create':
        await openItemDialog(initialCategory: item.category);
        break;
      case 'edit':
        await openItemDialog(item: item);
        break;
      case 'export':
        await exportSpbItems([item], suggestedName: item.title);
        break;
      case 'copy':
        await cloneSpbCard(item);
        break;
      case 'move':
        await moveSpbCard(item);
        break;
      case 'import':
        await importSpbWalletCards();
        break;
      case 'delete':
        await deleteItemWithConfirmation(item);
        break;
    }
  }

  Future<String?> showMoveTargetDialog({
    required String initialPath,
    Set<String> excludedPaths = const {},
  }) {
    var selectedPath = excludedPaths.contains(initialPath) ? '' : initialPath;
    final targets = <String>[
      '',
      ...categoryPaths.where((path) => !excludedPaths.contains(path)),
    ]..sort((a, b) {
        if (a.isEmpty) return -1;
        if (b.isEmpty) return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final media = MediaQuery.sizeOf(context);
          final compact = Platform.isAndroid ||
              Theme.of(context).platform == TargetPlatform.android ||
              media.width < 700;
          return Dialog(
            insetPadding: compact ? EdgeInsets.zero : const EdgeInsets.all(24),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: Color(0xff7f8d98)),
            ),
            child: SizedBox(
              key: const Key('moveTargetSurface'),
              width: compact ? media.width : min(media.width - 48, 440),
              height: compact ? media.height : min(media.height - 48, 620),
              child: SafeArea(
                child: Column(
                  children: [
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.centerLeft,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
                        ),
                        border: Border(
                          bottom: BorderSide(color: Color(0xff7f8d98)),
                        ),
                      ),
                      child: const Text(
                        'Выберите папку',
                        style: TextStyle(fontSize: 19),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        key: const Key('moveTargetFolderList'),
                        itemCount: targets.length,
                        itemBuilder: (context, index) {
                          final path = targets[index];
                          final depth = categoryParts(path).length;
                          final selected = selectedPath == path;
                          return Padding(
                            padding: EdgeInsets.only(left: depth * 14.0),
                            child: ListTile(
                              key: ValueKey('moveTarget-$path'),
                              selected: selected,
                              selectedTileColor: const Color(0xffcfe9fb),
                              leading: path.isEmpty
                                  ? const Icon(Icons.account_balance_wallet)
                                  : categoryFolderIcon(
                                      categoryIconsByPath[path] ??
                                          defaultIconForCategoryPath(path),
                                      categoryColorsByPath[path],
                                    ),
                              title: Text(
                                path.isEmpty
                                    ? 'Мои карточки'
                                    : categoryParts(path).last,
                              ),
                              onTap: () =>
                                  setDialogState(() => selectedPath = path),
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
                      height: 64,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xffdce8f1),
                        border: Border(
                          top: BorderSide(color: Color(0xff7f8d98)),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          SpbGradientActionButton(
                            key: const Key('cancelMoveButton'),
                            icon: Icons.close,
                            tooltip: 'Отменить перемещение',
                            colors: const [
                              Color(0xffff5a5f),
                              Color(0xffa90000),
                            ],
                            onTap: () => Navigator.pop(dialogContext),
                          ),
                          const SizedBox(width: 6),
                          SpbGradientActionButton(
                            key: const Key('confirmMoveButton'),
                            icon: Icons.check,
                            tooltip: 'Подтвердить перемещение',
                            colors: const [
                              Color(0xff5bc96d),
                              Color(0xff08772f),
                            ],
                            onTap: () =>
                                Navigator.pop(dialogContext, selectedPath),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> moveSpbCard(SecretItem item) async {
    final wallet = spbWallet;
    if (wallet == null || !ensureSpbWalletWritable()) return;
    final target = await showMoveTargetDialog(initialPath: item.category);
    if (target == null || target == item.category || !mounted) return;
    await moveSpbCardTo(item, target);
  }

  Future<void> moveSpbCardTo(SecretItem item, String target) async {
    final wallet = spbWallet;
    if (wallet == null || !ensureSpbWalletWritable()) return;
    if (target == item.category || !mounted) return;
    SessionUndoEntry? undoEntry;
    try {
      undoEntry = await captureSessionUndo(
        'Перемещение карточки: ${item.title}',
        itemIconId(item, templateFor(item.templateId)),
      );
      wallet.moveCard(item.id, target);
      markVaultDirty();
      final written = await writeBackSpbWallet();
      setState(() {
        final moved = SecretItem(
          id: item.id,
          templateId: item.templateId,
          title: item.title,
          category: target,
          colorId: item.colorId,
          values: item.values,
          modifiedAt: DateTime.now().toUtc(),
          attachments: item.attachments,
          hitCount: item.hitCount,
          iconId: item.iconId,
          backgroundImageBase64: item.backgroundImageBase64,
          spbColor: item.spbColor,
          fieldOrder: item.fieldOrder,
          hiddenFieldIds: item.hiddenFieldIds,
        );
        items = [
          for (final entry in items)
            if (entry.id == item.id) moved else entry,
        ];
        itemsById[item.id] = moved;
        selectedCategoryPath = target;
        selectedItemId = item.id;
        if (written) message = null;
      });
      commitSessionUndo(undoEntry);
    } catch (error) {
      discardSessionUndo(undoEntry);
      setState(() => message = 'Не удалось переместить карточку: $error');
    }
  }

  Widget buildSpbCardDropTarget({
    required String categoryPath,
    required Widget child,
  }) {
    return DragTarget<SecretItem>(
      onWillAcceptWithDetails: (details) =>
          details.data.category != categoryPath && spbWallet != null,
      onAcceptWithDetails: (details) {
        unawaited(moveSpbCardTo(details.data, categoryPath));
      },
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: candidates.isEmpty
            ? null
            : BoxDecoration(
                color: const Color(0xffd7f4df),
                border: Border.all(color: const Color(0xff16833c), width: 2),
              ),
        child: child,
      ),
    );
  }

  Future<void> moveSpbFolder(CategoryTreeNode folder) async {
    final wallet = spbWallet;
    if (wallet == null || !ensureSpbWalletWritable()) return;
    final parentParts = categoryParts(folder.path);
    if (parentParts.isNotEmpty) parentParts.removeLast();
    final currentParent = parentParts.join(' / ');
    final excluded = categoryPaths
        .where(
          (path) => path == folder.path || path.startsWith('${folder.path} / '),
        )
        .toSet();
    final target = await showMoveTargetDialog(
      initialPath: currentParent,
      excludedPaths: excluded,
    );
    if (target == null || target == currentParent || !mounted) return;
    SessionUndoEntry? undoEntry;
    try {
      undoEntry = await captureSessionUndo(
        'Перемещение папки: ${folder.name}',
        folder.iconId ?? defaultIconForCategoryPath(folder.path),
      );
      wallet.moveCategory(folder.path, target);
      markVaultDirty();
      final written = await writeBackSpbWallet();
      final snapshot = wallet.loadSnapshot();
      final newPath = [if (target.isNotEmpty) target, folder.name].join(' / ');
      setState(() {
        applySpbSnapshot(snapshot);
        selectedCategoryPath = newPath;
        if (written) message = null;
      });
      commitSessionUndo(undoEntry);
    } catch (error) {
      discardSessionUndo(undoEntry);
      setState(() => message = 'Не удалось переместить папку: $error');
    }
  }

  Widget buildSpbGridEntry({
    required String label,
    required Widget icon,
    required VoidCallback onTap,
    VoidCallback? onDoubleTap,
    required ValueChanged<Offset> onContextMenu,
    bool selected = false,
    double labelWidth = 63.75,
  }) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          openSpbObjectContextMenu(onContextMenu, details.globalPosition),
      onLongPressStart: (details) =>
          openSpbObjectContextMenu(onContextMenu, details.globalPosition),
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Container(
          decoration: selected
              ? const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xffb9dcf5), Color(0xffedf7fe)],
                  ),
                )
              : null,
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minWidth: 112,
            maxWidth: 112,
            minHeight: 105,
            maxHeight: 105,
            child: Column(
              children: [
                SizedBox(width: 68, height: 67, child: Center(child: icon)),
                const SizedBox(height: 2),
                SizedBox(
                  width: labelWidth,
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14.3, height: 1.05),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void openSpbObjectContextMenu(
    ValueChanged<Offset> onContextMenu,
    Offset globalPosition,
  ) {
    spbObjectMenuPointerActive = true;
    scheduleMicrotask(() => spbObjectMenuPointerActive = false);
    onContextMenu(globalPosition);
  }

  Future<String?> askSpbExportPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Экспорт в SWL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Пароль (необязательно)',
            helperText: 'Оставьте поле пустым для экспорта без пароля',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(dialogContext, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Экспорт'),
          ),
        ],
      ),
    );
    controller.clear();
    controller.dispose();
    return result;
  }

  Future<String?> askSpbImportPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Введите пароль SWL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Пароль',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(dialogContext, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Открыть'),
          ),
        ],
      ),
    );
    controller.clear();
    controller.dispose();
    return result;
  }

  String safeSpbFileName(String value) {
    final safe = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return '${safe.isEmpty ? 'Экспорт' : safe}.swl';
  }

  Future<File> createSpbItemsExportFile(
    List<SecretItem> exportItems, {
    required String password,
    String? categoryPath,
    String? targetPath,
  }) async {
    final file = targetPath == null
        ? File(
            '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}'
            'wallet_aps_export_${DateTime.now().microsecondsSinceEpoch}.swl',
          )
        : File(targetPath);
    final exportWallet = SpbWalletDatabase.create(file.path, password);
    try {
      if (categoryPath != null && categoryPath.trim().isNotEmpty) {
        exportWallet.ensureCategoryPath(categoryPath);
      }
      final templateIds = <String, String>{};
      final fieldIds = <String, Map<String, String>>{};
      for (final item in exportItems) {
        if (templateIds.containsKey(item.templateId)) continue;
        final template = templateFor(item.templateId);
        final exportedTemplateId = SpbWalletDatabase.makeId();
        final exportedFieldIds = <String, String>{
          for (final field in template.fields)
            if (field.id != spbDescriptionFieldId)
              field.id: SpbWalletDatabase.makeId(),
        };
        templateIds[item.templateId] = exportedTemplateId;
        fieldIds[item.templateId] = exportedFieldIds;
        exportWallet.saveTemplate(
          SpbWalletTemplateDraft(
            id: exportedTemplateId,
            name: template.name,
            iconId: spbIconIdForUi(template.iconId, template.iconId),
            fields: [
              for (final field in template.fields)
                if (field.id != spbDescriptionFieldId)
                  SpbWalletTemplateFieldRecord(
                    id: exportedFieldIds[field.id]!,
                    name: field.label,
                    templateId: exportedTemplateId,
                    fieldTypeId: spbFieldTypeId(field),
                  ),
            ],
          ),
        );
      }
      for (final item in exportItems) {
        final template = templateFor(item.templateId);
        final exportedFieldIds = fieldIds[item.templateId]!;
        final cardId = SpbWalletDatabase.makeId();
        exportWallet.saveCard(
          SpbWalletCardDraft(
            id: cardId,
            title: item.title,
            description: item.values[spbDescriptionFieldId] ?? '',
            categoryPath: item.category,
            templateId: templateIds[item.templateId]!,
            fieldValues: {
              for (final field in template.fields)
                if (field.id != spbDescriptionFieldId &&
                    (item.values[field.id]?.isNotEmpty ?? false))
                  exportedFieldIds[field.id]!: item.values[field.id]!,
            },
            iconId: spbIconIdForUi(itemIconId(item, template), template.iconId),
            cardColor: item.spbColor ?? paletteColorToSpb(item.colorId),
            backgroundImageBase64: item.backgroundImageBase64,
          ),
        );
        for (final attachment in item.attachments) {
          if (attachment.deleted) continue;
          final bytes = attachment.pendingBytes ??
              (attachment.id.isEmpty || spbWallet == null
                  ? null
                  : spbWallet!.readAttachmentBytes(attachment.id));
          if (bytes == null) continue;
          exportWallet.saveAttachment(
            cardId: cardId,
            fileName: attachment.fileName,
            bytes: bytes,
          );
        }
      }
    } finally {
      exportWallet.close();
    }
    return file;
  }

  Future<void> exportSpbItems(
    List<SecretItem> exportItems, {
    required String suggestedName,
    String? categoryPath,
  }) async {
    final password = await askSpbExportPassword();
    if (password == null) return;
    File? temporary;
    try {
      temporary = await createSpbItemsExportFile(
        exportItems,
        password: password,
        categoryPath: categoryPath,
      );
      final data = await temporary.readAsBytes();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Экспорт в SWL',
        fileName: safeSpbFileName(suggestedName),
        type: FileType.custom,
        allowedExtensions: const ['swl'],
        bytes: data,
      );
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        final outputPath =
            path.toLowerCase().endsWith('.swl') ? path : '$path.swl';
        final output = File(outputPath);
        if (!output.existsSync() || output.lengthSync() != data.length) {
          await output.writeAsBytes(data, flush: true);
        }
      }
    } catch (error) {
      showSpbOperationMessage('Не удалось экспортировать SWL: $error');
    } finally {
      if (temporary != null && temporary.existsSync()) {
        temporary.deleteSync();
      }
    }
  }

  String spbCardClipboardText(SecretItem item) {
    final template = templateFor(item.templateId);
    final buffer = StringBuffer('Название: ${item.title}');
    final includedIds = <String>{};
    for (final field in template.fields) {
      includedIds.add(field.id);
      final value = item.values[field.id]?.trim() ?? '';
      if (value.isNotEmpty) buffer.write('\n${field.label}: $value');
    }
    for (final entry in item.values.entries) {
      final value = entry.value.trim();
      if (includedIds.contains(entry.key) || value.isEmpty) continue;
      final label =
          entry.key == spbDescriptionFieldId ? 'Примечание' : entry.key;
      buffer.write('\n$label: $value');
    }
    return buffer.toString();
  }

  Future<void> copySpbCard(SecretItem item) async {
    await copySensitiveText(spbCardClipboardText(item));
    showSpbOperationMessage('Текст карточки скопирован');
  }

  Future<void> cloneSpbCard(SecretItem item) async {
    final wallet = spbWallet;
    if (wallet == null || !ensureSpbWalletWritable()) return;
    final existingTitles = items.map((entry) => entry.title).toSet();
    var suffix = 1;
    var cloneTitle = '${item.title} ($suffix)';
    while (existingTitles.contains(cloneTitle)) {
      suffix++;
      cloneTitle = '${item.title} ($suffix)';
    }
    final clonedAttachments = <SecretAttachment>[];
    try {
      for (final attachment in item.attachments) {
        final bytes = wallet.readAttachmentBytes(attachment.id);
        clonedAttachments.add(
          SecretAttachment(
            id: '',
            fileName: attachment.fileName,
            size: bytes.length,
            pendingBytes: bytes,
          ),
        );
      }
      final clone = SecretItem(
        id: makeId('item'),
        templateId: item.templateId,
        title: cloneTitle,
        category: item.category,
        colorId: item.colorId,
        values: Map<String, String>.from(item.values),
        modifiedAt: DateTime.now().toUtc(),
        attachments: clonedAttachments,
        iconId: item.iconId,
        backgroundImageBase64: item.backgroundImageBase64,
        spbColor: item.spbColor,
        fieldOrder: item.fieldOrder,
        hiddenFieldIds: item.hiddenFieldIds,
      );
      final savedId = await persistItem(clone);
      if (savedId != null) {
        showSpbOperationMessage('Создана копия карточки «$cloneTitle».');
      }
    } catch (error) {
      showSpbOperationMessage('Не удалось скопировать карточку: $error');
    }
  }

  Future<void> shareSpbCard(SecretItem item) async {
    if (!Platform.isAndroid) return;
    final password = await askSpbExportPassword();
    if (password == null) return;
    try {
      final file = await createSpbItemsExportFile([item], password: password);
      await spbWalletChannel.invokeMethod<bool>('shareFile', {
        'path': file.path,
        'mimeType': 'application/octet-stream',
        'title': safeSpbFileName(item.title),
      });
    } catch (error) {
      showSpbOperationMessage('Не удалось поделиться карточкой: $error');
    }
  }

  Future<void> importSpbWalletCards() async {
    final destination = spbWallet;
    if (destination == null) {
      showSpbOperationMessage('Сначала откройте базу, в которую нужен импорт.');
      return;
    }
    if (!ensureSpbWalletWritable()) return;
    File? temporary;
    SpbWalletDatabase? source;
    SessionUndoEntry? undoEntry;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['swl'],
        withData: true,
      );
      final selected = picked?.files.single;
      if (selected == null) return;
      String sourcePath;
      if (selected.path != null && File(selected.path!).existsSync()) {
        sourcePath = selected.path!;
      } else {
        final bytes = selected.bytes;
        if (bytes == null) {
          throw const FormatException('Не удалось прочитать SWL.');
        }
        final directory = await getTemporaryDirectory();
        temporary = File(
          '${directory.path}${Platform.pathSeparator}'
          'wallet_aps_import_${DateTime.now().microsecondsSinceEpoch}.swl',
        );
        await temporary.writeAsBytes(bytes, flush: true);
        sourcePath = temporary.path;
      }
      try {
        source = SpbWalletDatabase.open(sourcePath, '');
      } catch (_) {
        final password = await askSpbImportPassword();
        if (password == null) return;
        source = SpbWalletDatabase.open(sourcePath, password);
      }
      final snapshot = source.loadSnapshot();
      undoEntry = await captureSessionUndo(
        'Импорт карточек: ${snapshot.cards.length}',
        'folder',
      );
      final templateIds = <String, String>{};
      final fieldIds = <String, Map<String, String>>{};
      for (final template in snapshot.templates) {
        final importedTemplateId = SpbWalletDatabase.makeId();
        final importedFieldIds = <String, String>{
          for (final field in template.fields)
            field.id: SpbWalletDatabase.makeId(),
        };
        templateIds[template.id] = importedTemplateId;
        fieldIds[template.id] = importedFieldIds;
        destination.saveTemplate(
          SpbWalletTemplateDraft(
            id: importedTemplateId,
            name: template.name,
            iconId: template.iconId,
            fields: [
              for (final field in template.fields)
                SpbWalletTemplateFieldRecord(
                  id: importedFieldIds[field.id]!,
                  name: field.name,
                  templateId: importedTemplateId,
                  fieldTypeId: field.fieldTypeId,
                ),
            ],
          ),
        );
      }
      for (final card in snapshot.cards) {
        final importedTemplateId = templateIds[card.templateId];
        final importedFieldIds = fieldIds[card.templateId];
        if (importedTemplateId == null || importedFieldIds == null) continue;
        final cardId = SpbWalletDatabase.makeId();
        destination.saveCard(
          SpbWalletCardDraft(
            id: cardId,
            title: card.title,
            description: card.description,
            categoryPath: card.categoryPath,
            templateId: importedTemplateId,
            fieldValues: {
              for (final entry in card.fieldValues.entries)
                if (importedFieldIds[entry.key] != null)
                  importedFieldIds[entry.key]!: entry.value,
            },
            iconId: card.iconId,
            cardColor: card.cardColor,
            backgroundImageBase64: card.backgroundImageBase64,
          ),
        );
        for (final attachment in card.attachments) {
          destination.saveAttachment(
            cardId: cardId,
            fileName: attachment.fileName,
            bytes: source.readAttachmentBytes(attachment.id),
          );
        }
      }
      if (snapshot.templates.isNotEmpty || snapshot.cards.isNotEmpty) {
        markVaultDirty();
      }
      final written = await writeBackSpbWallet();
      final updated = destination.loadSnapshot();
      setState(() => applySpbSnapshot(updated));
      commitSessionUndo(undoEntry);
      showSpbOperationMessage(
        written
            ? 'Импортировано карточек: ${snapshot.cards.length}'
            : 'Карточки импортированы в рабочую копию, но исходный файл '
                'записать не удалось.',
      );
    } catch (error) {
      discardSessionUndo(undoEntry);
      showSpbOperationMessage('Не удалось импортировать SWL: $error');
    } finally {
      source?.close(flush: false);
      if (temporary != null && temporary.existsSync()) {
        temporary.deleteSync();
      }
    }
  }

  void showSpbOperationMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
  }

  List<SecretItem> frequentItems() {
    final byId = {for (final item in items) item.id: item};
    final result = <SecretItem>[
      for (final id in recentlyOpenedItemIds)
        if (byId[id] != null) byId[id]!,
    ];
    final recentIds = result.map((item) => item.id).toSet();
    final previous = items
        .where((item) => item.hitCount > 0 && !recentIds.contains(item.id))
        .toList()
      ..sort((a, b) {
        final byHits = b.hitCount.compareTo(a.hitCount);
        return byHits == 0 ? a.title.compareTo(b.title) : byHits;
      });
    result.addAll(previous);
    return result;
  }

  CardTemplate? selectedSpbTemplate() {
    if (templates.isEmpty) return null;
    for (final template in templates) {
      if (template.id == selectedTemplateId) return template;
    }
    return templates.first;
  }

  List<(Widget, String, VoidCallback)> spbTasksForCurrentMode() {
    if (mobileTemplatesOpen) {
      return [
        (
          spbResourceIcon('icon_add.png', 40),
          'Создать новый шаблон',
          () => openTemplateDialog(),
        ),
        (
          spbResourceIcon('icon_edit_fun_icon.png', 40),
          'Редактировать',
          editSelectedSpbTemplate,
        ),
        (spbResourceIcon('icon_import.png', 40), 'Импорт', importSpbTemplate),
        (
          spbResourceIcon('icon_share.png', 40),
          'Экспорт',
          exportSelectedSpbTemplate,
        ),
        (
          const Icon(Icons.delete_outline, size: 36, color: Color(0xff33434f)),
          'Удалить',
          deleteSelectedSpbTemplate,
        ),
        (
          spbResourceIcon('icon_save_enable.png', 40),
          spbWritePending ? 'Повторить сохранение' : 'Сохранить базу',
          saveVaultThroughExplorer,
        ),
        (
          const Icon(Icons.logout, size: 36, color: Color(0xff33434f)),
          'Выйти',
          exitToPasswordPrompt,
        ),
      ];
    }
    return [
      if (walletLoadReport.hasIssues)
        (
          const Icon(
            Icons.warning_amber_rounded,
            size: 36,
            color: Color(0xffa65b00),
          ),
          walletLoadReport.issues.length == cardLoadFailures.length
              ? 'Не удалось отобразить ${cardLoadFailures.length} карточек'
              : 'Ошибок загрузки: ${walletLoadReport.issues.length}',
          showCardLoadFailureReport,
        ),
      (
        Image.asset(
          'assets/branding/wallet_android.png',
          key: const Key('spbCreateWalletAppIcon'),
          width: 40,
          height: 40,
          cacheWidth: 128,
          fit: BoxFit.contain,
        ),
        'Создать кошелёк',
        createNewVaultFromLogin,
      ),
      (
        spbResourceIcon('icon_import.png', 40),
        'Открыть кошелёк',
        pickSpbWalletFile,
      ),
      (
        const Icon(Icons.password_outlined, size: 36, color: Color(0xff33434f)),
        'Изменить пароль',
        openChangePasswordDialog,
      ),
      (
        spbResourceIcon('icon_add_card.png', 40),
        'Создать новую карточку',
        () => openItemDialog(initialCategory: selectedCategoryPath),
      ),
      (
        spbResourceIcon('icon_add_folder.png', 40),
        'Создать новую папку',
        () => openCategoryEditorDialog(
              folder: null,
              parentPath: selectedCategoryPath,
            ),
      ),
      (
        spbResourceIcon('icon_backup.png', 40),
        'Сделать архивную копию',
        createDatedArchiveCopy,
      ),
      (
        const Icon(
          Icons.health_and_safety_outlined,
          size: 36,
          color: Color(0xff33434f),
        ),
        'Проверить и восстановить базу',
        repairCurrentWalletCompatibility,
      ),
      (
        spbResourceIcon('icon_save_enable.png', 40),
        spbWritePending ? 'Повторить сохранение' : 'Сохранить базу',
        saveVaultThroughExplorer,
      ),
      (
        const Icon(Icons.logout, size: 36, color: Color(0xff33434f)),
        'Выйти',
        exitToPasswordPrompt,
      ),
    ];
  }

  Future<void> showCardLoadFailureReport() async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ошибок загрузки: ${walletLoadReport.issues.length}'),
        content: SizedBox(
          width: min(MediaQuery.sizeOf(context).width - 48, 620),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: walletLoadReport.issues.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final failure = walletLoadReport.issues[index];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.error_outline),
                title: Text(
                  '${walletLoadIssueLabel(failure.kind)} ${failure.entityId}',
                ),
                subtitle: Text(
                  failure.reason,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'backup'),
            child: const Text('Сохранить исходную базу'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'export'),
            child: const Text('Экспортировать исправные'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'repair'),
            child: const Text('Проверить и восстановить'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'export') {
      await exportSpbItems(items, suggestedName: 'readable-cards');
    } else if (action == 'backup') {
      await createDatedArchiveCopy();
    } else if (action == 'repair') {
      await repairCurrentWalletCompatibility();
    }
  }

  String walletLoadIssueLabel(WalletLoadIssueKind kind) => switch (kind) {
        WalletLoadIssueKind.card => 'Карточка',
        WalletLoadIssueKind.field => 'Поле',
        WalletLoadIssueKind.attachment => 'Вложение',
        WalletLoadIssueKind.category => 'Категория',
        WalletLoadIssueKind.template => 'Шаблон',
        WalletLoadIssueKind.icon => 'Иконка',
      };

  Widget buildSpbActionsPanel({bool desktop = false}) {
    final frequent = frequentItems();
    final query = spbSubmittedSearchQuery;
    final matchingFolders = spbMatchingFolderPaths(query);
    final matchingCards = spbMatchingCards(query);
    final foundCount = matchingFolders.length + matchingCards.length;
    final maximizeFound = spbFrequentExpanded == false && spbFoundExpanded;
    if (desktop) {
      return wrapSpbTemplateRightContextMenu(
        Material(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildSpbActionGroup(
                'Задачи',
                spbTasksForCurrentMode(),
                shellStyle: true,
                sectionExpanded: spbTasksExpanded,
                onExpand: () => setState(() => spbTasksExpanded = true),
                onCollapse: () => setState(() => spbTasksExpanded = false),
              ),
              buildSpbCollapsibleHeader(
                'Найдено',
                expanded: spbFoundExpanded,
                onExpand: () => setState(() => spbFoundExpanded = true),
                onCollapse: () => setState(() => spbFoundExpanded = false),
                shellStyle: true,
                trailing: Text(
                  '$foundCount',
                  key: const Key('spbFoundCount'),
                  style: const TextStyle(fontSize: 17),
                ),
              ),
              if (maximizeFound)
                Expanded(
                  child: query.isEmpty
                      ? const SizedBox.expand()
                      : buildSpbSearchResults(
                          matchingFolders,
                          matchingCards,
                          controller: spbFoundScrollController,
                        ),
                )
              else if (spbFoundExpanded && query.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: buildSpbSearchResults(
                    matchingFolders,
                    matchingCards,
                    controller: spbFoundScrollController,
                  ),
                ),
              if (spbFrequentExpanded)
                Expanded(
                  child: buildSpbActionGroup(
                    'Часто используемые',
                    [
                      for (final item in frequent.take(10))
                        (
                          spbSizedDataIcon(
                            itemIconId(item, templateFor(item.templateId)),
                            40,
                            fallbackColor: itemPictogramColor(
                              item,
                              templateFor(item.templateId),
                            ),
                          ),
                          item.title,
                          () => openFrequentCard(item),
                        ),
                    ],
                    expand: true,
                    shellStyle: true,
                    sectionExpanded: true,
                    onExpand: () => setState(() => spbFrequentExpanded = true),
                    onCollapse: () =>
                        setState(() => spbFrequentExpanded = false),
                    scrollController: spbFrequentScrollController,
                  ),
                )
              else
                buildSpbActionGroup(
                  'Часто используемые',
                  const [],
                  shellStyle: true,
                  sectionExpanded: false,
                  onExpand: () => setState(() => spbFrequentExpanded = true),
                  onCollapse: () => setState(() => spbFrequentExpanded = false),
                ),
            ],
          ),
        ),
      );
    }
    return wrapSpbTemplateRightContextMenu(
      Scrollbar(
        key: const Key('spbMobileActionsScrollbar'),
        controller: spbMobileActionsScrollController,
        thumbVisibility: true,
        trackVisibility: true,
        child: SingleChildScrollView(
          controller: spbMobileActionsScrollController,
          child: Container(
            color: _spbRightPanel,
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildSpbActionGroup(
                  'Задачи',
                  spbTasksForCurrentMode(),
                  sectionExpanded: spbTasksExpanded,
                  onExpand: () => setState(() => spbTasksExpanded = true),
                  onCollapse: () => setState(() => spbTasksExpanded = false),
                ),
                buildSpbCollapsibleHeader(
                  'Найдено',
                  expanded: spbFoundExpanded,
                  onExpand: () => setState(() => spbFoundExpanded = true),
                  onCollapse: () => setState(() => spbFoundExpanded = false),
                  trailing: Text(
                    '$foundCount',
                    key: const Key('spbFoundCount'),
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
                if (spbFoundExpanded && query.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: buildSpbSearchResults(
                      matchingFolders,
                      matchingCards,
                      controller: spbFoundScrollController,
                    ),
                  ),
                if (spbFrequentExpanded)
                  buildSpbActionGroup(
                    'Часто используемые',
                    [
                      for (final item in frequent.take(10))
                        (
                          spbSizedDataIcon(
                            itemIconId(item, templateFor(item.templateId)),
                            40,
                            fallbackColor: itemPictogramColor(
                              item,
                              templateFor(item.templateId),
                            ),
                          ),
                          item.title,
                          () => openFrequentCard(item),
                        ),
                    ],
                    sectionExpanded: true,
                    onExpand: () => setState(() => spbFrequentExpanded = true),
                    onCollapse: () =>
                        setState(() => spbFrequentExpanded = false),
                  )
                else
                  buildSpbActionGroup(
                    'Часто используемые',
                    const [],
                    sectionExpanded: false,
                    onExpand: () => setState(() => spbFrequentExpanded = true),
                    onCollapse: () =>
                        setState(() => spbFrequentExpanded = false),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget wrapSpbTemplateRightContextMenu(Widget child) {
    if (!mobileTemplatesOpen) return child;
    return GestureDetector(
      key: const Key('spbTemplateRightWorkspace'),
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) =>
          showSpbTemplateRightMenu(details.globalPosition),
      onLongPressStart: (details) =>
          showSpbTemplateRightMenu(details.globalPosition),
      child: child,
    );
  }

  Future<void> showSpbTemplateRightMenu(Offset globalPosition) async {
    if (spbObjectMenuPointerActive) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          key: Key('createTemplateRightContextAction'),
          value: 'create',
          child: Text('Создать'),
        ),
        PopupMenuItem(
          key: Key('importTemplateRightContextAction'),
          value: 'import',
          child: Text('Импортировать'),
        ),
      ],
    );
    if (!mounted) return;
    if (selected == 'create') {
      await openTemplateDialog();
    } else if (selected == 'import') {
      await importSpbTemplate();
    }
  }

  Widget buildSpbSearchResults(
    List<String> matchingFolders,
    List<SecretItem> matchingCards, {
    ScrollController? controller,
  }) {
    if (matchingFolders.isEmpty && matchingCards.isEmpty) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: Text(
            'Совпадений нет',
            key: Key('spbNoSearchResults'),
            style: TextStyle(fontSize: 15),
          ),
        ),
      );
    }
    final results = ListView(
      key: const Key('spbSearchResults'),
      controller: controller,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: [
        for (final path in matchingFolders)
          buildSpbSearchResultRow(
            icon: spbSizedDataIcon(
              categoryIconsByPath[path] ?? defaultIconForCategoryPath(path),
              36,
              fallbackColor: categoryPictogramColor(categoryColorsByPath[path]),
            ),
            title: categoryParts(path).last,
            subtitle: 'Папка',
            onTap: () => openSpbFolder(path),
          ),
        for (final item in matchingCards)
          buildSpbSearchResultRow(
            icon: spbSizedDataIcon(
              itemIconId(item, templateFor(item.templateId)),
              36,
              fallbackColor: itemPictogramColor(
                item,
                templateFor(item.templateId),
              ),
            ),
            title: item.title,
            subtitle: item.category.trim().isEmpty
                ? 'Карточка'
                : 'Карточка • ${item.category}',
            onTap: () => openCardPreviewDialog(item, preserveSearch: true),
          ),
      ],
    );
    if (controller == null) return results;
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: results,
    );
  }

  Widget buildSpbSearchResultRow({
    required Widget icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4.5, 6, 3.75),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 27,
              child: OverflowBox(
                minWidth: 36,
                maxWidth: 36,
                minHeight: 36,
                maxHeight: 36,
                child: Center(
                  child: Transform.scale(scale: 0.9, child: icon),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff5f5f5f),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSpbCollapsibleHeader(
    String title, {
    required bool expanded,
    required VoidCallback onExpand,
    required VoidCallback onCollapse,
    bool shellStyle = false,
    Widget? trailing,
  }) {
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 4, right: 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
        ),
        border: shellStyle
            ? const Border(bottom: BorderSide(color: _spbBorder))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 32,
            child: Tooltip(
              message: expanded ? 'Свернуть' : 'Развернуть',
              child: InkWell(
                key: ValueKey(
                  expanded ? 'spbCollapse$title' : 'spbExpand$title',
                ),
                onTap: expanded ? onCollapse : onExpand,
                child: Center(
                  child: Icon(
                    expanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    size: 29,
                    color: const Color(0xff168bd2),
                    shadows: const [
                      Shadow(
                        color: Color(0xb3ffffff),
                        offset: Offset(0, -1),
                        blurRadius: 0.5,
                      ),
                      Shadow(
                        color: Color(0xff075582),
                        offset: Offset(0, 1.5),
                        blurRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget buildSpbActionGroup(
    String title,
    List<(Widget, String, VoidCallback)> actions, {
    bool expand = false,
    bool shellStyle = false,
    bool? sectionExpanded,
    VoidCallback? onExpand,
    VoidCallback? onCollapse,
    ScrollController? scrollController,
  }) {
    final header = sectionExpanded == null
        ? Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
              ),
              border: shellStyle
                  ? const Border(bottom: BorderSide(color: _spbBorder))
                  : null,
            ),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17),
            ),
          )
        : buildSpbCollapsibleHeader(
            title,
            expanded: sectionExpanded,
            onExpand: onExpand!,
            onCollapse: onCollapse!,
            shellStyle: shellStyle,
          );
    if (sectionExpanded == false) return header;
    final actionTiles = [
      for (final action in actions)
        InkWell(
          onTap: action.$3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 5.25, 6, 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 40,
                  height: 30,
                  child: OverflowBox(
                    minWidth: 40,
                    maxWidth: 40,
                    minHeight: 40,
                    maxHeight: 40,
                    child: Center(
                      child: Transform.scale(scale: 0.9, child: action.$1),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    action.$2,
                    style: const TextStyle(fontSize: 16, height: 1.12),
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
    if (expand) {
      final scrollable = SingleChildScrollView(
        key: const Key('frequentCardsScroll'),
        controller: scrollController,
        child: Container(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: actionTiles,
          ),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: scrollController == null
                ? scrollable
                : Scrollbar(
                    controller: scrollController,
                    thumbVisibility: true,
                    child: scrollable,
                  ),
          ),
        ],
      );
    }
    final content = Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, ...actionTiles],
      ),
    );
    return IntrinsicHeight(child: content);
  }

  bool isMenuOpen(bool compact) => menuOpenOverride ?? false;

  void toggleMenu(bool compact) {
    final current = isMenuOpen(compact);
    setState(() => menuOpenOverride = !current);
  }

  Future<void> lockVault() async {
    await finalizeSessionTrash();
    clearSessionUndoHistory();
    spbWallet?.close(flush: vaultDirty);
    spbWallet = null;
    vaultDirty = false;
    syncSourcePath = null;
    syncSourceUrl = null;
    syncOriginProvider = null;
    passwordController.clear();
    setState(() {
      unlocked = false;
      message = null;
    });
  }

  Widget buildMenuHeader({required bool compact}) {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Меню',
              icon: const Icon(Icons.menu),
              onPressed: () => toggleMenu(compact),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                openDatabaseTitle(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildMenuHandle({required bool compact}) {
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          const SizedBox(height: 8),
          IconButton(
            tooltip: 'Меню',
            icon: const Icon(Icons.menu),
            onPressed: () => toggleMenu(compact),
          ),
        ],
      ),
    );
  }

  Widget buildCollapsedRail() {
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          const SizedBox(height: 8),
          IconButton(
            tooltip: 'Меню',
            icon: const Icon(Icons.menu),
            onPressed: () => toggleMenu(false),
          ),
          const Divider(height: 16),
          ...navEntries.map(
            (entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: IconButton(
                tooltip: entry.label,
                isSelected: activeView == entry.id,
                icon: Icon(entry.icon),
                selectedIcon: Icon(entry.icon),
                style: IconButton.styleFrom(
                  backgroundColor: activeView == entry.id
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  foregroundColor: activeView == entry.id
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : null,
                ),
                onPressed: () => setState(() => activeView = entry.id),
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Заблокировать',
            icon: const Icon(Icons.lock_outline),
            onPressed: lockVault,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget databaseStatusBar() {
    return Material(
      color: const Color(0xffedf2f6),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.storage_outlined, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  openDatabaseTitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String openDatabaseTitle() {
    if (spbWallet != null) {
      final path = spbWalletDisplayPath ?? spbWalletPath;
      if (path == null || path.isEmpty) return '.swl база';
      if (path.startsWith('content://')) {
        final name = vaultNameController.text.trim();
        return name.isEmpty ? '.swl база' : name;
      }
      return File(path).uri.pathSegments.isEmpty
          ? path
          : File(path).uri.pathSegments.last;
    }
    final name = vaultNameController.text.trim();
    return name.isEmpty ? 'personal' : name;
  }

  String? spbWalletUserPath() => spbWalletDisplayPath ?? spbWalletPath;

  String lastSyncText() {
    final value = lastSyncAt;
    if (value == null) return 'не выполнялась';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String get selectedVaultTitle {
    final path = spbWalletDisplayPath ?? spbWalletPath;
    String withoutSwlExtension(String name) =>
        name.replaceFirst(RegExp(r'\.swl$', caseSensitive: false), '');
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('content://')) {
        final name = vaultNameController.text.trim();
        return name.isEmpty ? 'база' : withoutSwlExtension(name);
      }
      return withoutSwlExtension(_vaultTitleFromPath(path));
    }
    if (recentVaults.isNotEmpty) {
      return withoutSwlExtension(recentVaults.first.title);
    }
    return 'файл не выбран';
  }

  String? get selectedVaultModifiedText {
    final path = spbWalletPath;
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final modified = file.lastModifiedSync().toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      return '${two(modified.day)}.${two(modified.month)}.'
          '${two(modified.year % 100)} ${two(modified.hour)}.'
          '${two(modified.minute)}';
    } on FileSystemException {
      return null;
    }
  }

  String get passwordPromptText {
    final modified = selectedVaultModifiedText;
    return modified == null
        ? selectedVaultTitle
        : '$selectedVaultTitle, $modified';
  }

  void insertPasswordText(String value) {
    final nextText = '${passwordController.text}$value';
    passwordController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    passwordFocusNode.requestFocus();
  }

  void backspacePassword() {
    final text = passwordController.text;
    if (text.isNotEmpty) {
      final nextText = text.substring(0, text.length - 1);
      passwordController.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
    }
    passwordFocusNode.requestFocus();
  }

  void clearPassword() {
    passwordController.clear();
    passwordFocusNode.requestFocus();
  }

  void showLoginPasswordHint() {
    if (loginHintVisible) return;
    final path = spbWalletPath;
    final hint = path == null || path.isEmpty
        ? ''
        : SpbWalletDatabase.readPasswordHint(path);
    setState(() {
      loginPasswordHint = hint.trim().isEmpty ? 'Подсказка не задана.' : hint;
      loginHintVisible = true;
    });
  }

  void hideLoginPasswordHint() {
    if (!loginHintVisible) return;
    setState(() => loginHintVisible = false);
  }

  Future<void> exitApplication() async {
    lockedExitTimer?.cancel();
    lockedExitTimer = null;
    lockedExitCountdownTimer?.cancel();
    lockedExitCountdownTimer = null;
    purgeSessionTrashFromDatabase();
    persistVaultState();
    final saved = await writeBackSpbWallet();
    if (!saved) {
      showSpbOperationMessage(
        'Программа не закрыта: не удалось сохранить изменения базы.',
      );
      return;
    }
    passwordController.clear();
    confirmController.clear();
    clearSessionUndoHistory();
    spbWallet?.close(flush: vaultDirty);
    spbWallet = null;
    vaultDirty = false;
    spbWalletPath = null;
    spbWalletUri = null;
    spbWalletDisplayPath = null;
    if (Platform.isAndroid || Platform.isIOS) {
      await SystemNavigator.pop();
    } else {
      exit(0);
    }
  }

  void ensureLockedExitTimer() {
    lockedExitTimer ??= Timer(
      const Duration(minutes: 5),
      () => unawaited(exitApplication()),
    );
  }

  void recordLockedUserActivity() {
    if (unlocked) return;
    lastUserActivityAt = DateTime.now();
    lockedExitTimer?.cancel();
    lockedExitTimer = Timer(
      const Duration(minutes: 5),
      () => unawaited(exitApplication()),
    );
  }

  Future<void> showLockedExitWarning() async {
    if (!mounted || unlocked || lockedExitWarningVisible) return;
    lockedExitTimer?.cancel();
    lockedExitTimer = null;
    lockedExitWarningVisible = true;
    lockedExitSecondsRemaining = 30;
    StateSetter? updateDialog;
    lockedExitCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      lockedExitSecondsRemaining--;
      updateDialog?.call(() {});
      if (lockedExitSecondsRemaining <= 0) {
        lockedExitCountdownTimer?.cancel();
        if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop(false);
        }
      }
    });
    final continued = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          updateDialog = setDialogState;
          return Dialog(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: Color(0xff7f8d98)),
            ),
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 48,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
                      ),
                      border: Border(
                        bottom: BorderSide(color: Color(0xff7f8d98)),
                      ),
                    ),
                    child: const Text(
                      'Предупреждение',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    color: const Color(0xfff4f4f4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 24,
                    ),
                    child: Text(
                      'Программа сохранит базу и закроется через '
                      '$lockedExitSecondsRemaining секунд',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                  Container(
                    height: 64,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xffdce8f1),
                      border: Border(top: BorderSide(color: Color(0xff7f8d98))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SpbGradientActionButton(
                          key: const Key('lockedExitContinueButton'),
                          icon: Icons.play_arrow,
                          tooltip: 'Продолжить работу',
                          colors: const [Color(0xff5bc96d), Color(0xff08772f)],
                          onTap: () => Navigator.of(dialogContext).pop(true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    lockedExitCountdownTimer?.cancel();
    lockedExitCountdownTimer = null;
    lockedExitWarningVisible = false;
    if (continued == true && mounted) {
      recordLockedUserActivity();
    } else {
      await exitApplication();
    }
  }

  void ensureInactivityTimer() {
    inactivityTimer ??= Timer(
      const Duration(minutes: 2, seconds: 45),
      showInactivityWarning,
    );
  }

  void recordUserActivity() {
    if (!unlocked || closingForInactivity || inactivityWarningVisible) return;
    lastUserActivityAt = DateTime.now();
    inactivityTimer?.cancel();
    inactivityTimer = Timer(
      const Duration(minutes: 2, seconds: 45),
      showInactivityWarning,
    );
  }

  Future<void> showInactivityWarning() async {
    if (!mounted || inactivityWarningVisible || closingForInactivity) return;
    inactivityTimer?.cancel();
    inactivityTimer = null;
    inactivityWarningVisible = true;
    final remaining = const Duration(minutes: 3) -
        DateTime.now().difference(lastUserActivityAt);
    if (remaining <= Duration.zero) {
      inactivityWarningVisible = false;
      await closeAfterInactivity();
      return;
    }
    inactivitySecondsRemaining = max(
      1,
      min(15, (remaining.inMilliseconds / 1000).ceil()),
    );
    StateSetter? updateDialog;
    inactivityCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      inactivitySecondsRemaining--;
      updateDialog?.call(() {});
      if (inactivitySecondsRemaining <= 0) {
        inactivityCountdownTimer?.cancel();
        if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop(false);
        }
      }
    });
    final continued = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          updateDialog = setDialogState;
          return Dialog(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
              side: BorderSide(color: Color(0xff7f8d98)),
            ),
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 48,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
                      ),
                      border: Border(
                        bottom: BorderSide(color: Color(0xff7f8d98)),
                      ),
                    ),
                    child: const Text(
                      'Предупреждение',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    color: const Color(0xfff4f4f4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 24,
                    ),
                    child: Text(
                      'Хранилище будет заблокировано через '
                      '$inactivitySecondsRemaining секунд',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                  Container(
                    height: 64,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xffdce8f1),
                      border: Border(top: BorderSide(color: Color(0xff7f8d98))),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SpbGradientActionButton(
                          key: const Key('inactivityContinueButton'),
                          icon: Icons.play_arrow,
                          tooltip: 'Продолжить работу',
                          colors: const [Color(0xff5bc96d), Color(0xff08772f)],
                          onTap: () => Navigator.of(dialogContext).pop(true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    inactivityCountdownTimer?.cancel();
    inactivityCountdownTimer = null;
    inactivityWarningVisible = false;
    if (continued == true && mounted) {
      setState(() {
        activeView = 'cards';
        mobilePane = 0;
      });
      recordUserActivity();
    } else {
      await closeAfterInactivity();
    }
  }

  Future<void> closeAfterInactivity() async {
    if (closingForInactivity) return;
    closingForInactivity = true;
    inactivityTimer?.cancel();
    inactivityTimer = null;
    purgeSessionTrashFromDatabase();
    persistVaultState();
    await writeBackSpbWallet();
    clearSessionUndoHistory();
    spbWallet?.close(flush: vaultDirty);
    spbWallet = null;
    vaultDirty = false;
    spbWritePending = false;
    passwordController.clear();
    confirmController.clear();
    revealed.clear();
    if (!mounted) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
    setState(() {
      unlocked = false;
      entryMode = EntryMode.openSwl;
      activeView = 'cards';
      mobilePane = 0;
      message = null;
      closingForInactivity = false;
    });
    lastUserActivityAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) passwordFocusNode.requestFocus();
    });
  }

  Widget passwordKey({
    required String label,
    required VoidCallback onPressed,
    Widget? child,
    Color top = const Color(0xff2483bc),
    Color bottom = const Color(0xff07436c),
    double fontSize = 34,
    FontWeight fontWeight = FontWeight.w500,
    double height = 62,
    double minimumHeight = 48,
    Key? key,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        height: max(height, minimumHeight),
        child: Material(
          key: key,
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [top, bottom],
              ),
              border: Border.all(color: const Color(0xff5c6870)),
              borderRadius: BorderRadius.circular(3),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  offset: Offset(0, 2),
                  blurRadius: 2,
                ),
              ],
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(3),
              child: Center(
                child: child ??
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSize,
                        height: 1,
                        fontWeight: fontWeight,
                        shadows: const [
                          Shadow(color: Colors.black45, offset: Offset(1, 1)),
                        ],
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget keypadRow(List<Widget> children) => Row(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(width: 5),
            Expanded(child: children[index]),
          ],
        ],
      );

  void selectVirtualKeyboardMode(VirtualKeyboardMode mode) {
    setState(() => virtualKeyboardMode = mode);
    passwordFocusNode.requestFocus();
  }

  Widget buildPasswordKeyboard({
    required Color redTop,
    required Color redBottom,
  }) {
    if (virtualKeyboardMode == VirtualKeyboardMode.symbols) {
      Widget symbolKey(String symbol) => passwordKey(
            key: Key('keypadSymbol$symbol'),
            label: symbol,
            height: 42,
            minimumHeight: 42,
            fontSize: 25,
            onPressed: () => insertPasswordText(symbol),
          );

      return Column(
        children: [
          keypadRow([
            for (final symbol in [
              '+',
              '×',
              '÷',
              '=',
              '/',
              '_',
              '<',
              '>',
              '[',
              ']',
            ])
              symbolKey(symbol),
          ]),
          const SizedBox(height: 2),
          keypadRow([
            for (final symbol in [
              '!',
              '@',
              '#',
              r'$',
              '%',
              '^',
              '&',
              '*',
              '(',
              ')',
            ])
              symbolKey(symbol),
          ]),
          const SizedBox(height: 2),
          keypadRow([
            passwordKey(
              key: const Key('keypadSymbolsPage'),
              label: '1/2',
              height: 42,
              minimumHeight: 42,
              fontSize: 18,
              onPressed: passwordFocusNode.requestFocus,
            ),
            for (final symbol in ['-', "'", '"', ':', ';', ',', '?'])
              symbolKey(symbol),
            passwordKey(
              key: const Key('keypadBackspace'),
              label: '<-',
              height: 42,
              minimumHeight: 42,
              fontSize: 22,
              top: redTop,
              bottom: redBottom,
              onPressed: backspacePassword,
            ),
          ]),
        ],
      );
    }

    if (virtualKeyboardMode != VirtualKeyboardMode.numeric) {
      final uppercase = virtualKeyboardMode == VirtualKeyboardMode.uppercase;
      Widget letterKey(String baseLetter) {
        final letter = uppercase ? baseLetter : baseLetter.toLowerCase();
        return passwordKey(
          key: Key('keypadLetter$letter'),
          label: letter,
          height: 42,
          minimumHeight: 42,
          fontSize: 24,
          onPressed: () => insertPasswordText(letter),
        );
      }

      return Column(
        children: [
          keypadRow([
            for (final letter in [
              'Q',
              'W',
              'E',
              'R',
              'T',
              'Y',
              'U',
              'I',
              'O',
              'P',
            ])
              letterKey(letter),
          ]),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: keypadRow([
              for (final letter in [
                'A',
                'S',
                'D',
                'F',
                'G',
                'H',
                'J',
                'K',
                'L',
              ])
                letterKey(letter),
            ]),
          ),
          const SizedBox(height: 2),
          keypadRow([
            passwordKey(
              key: const Key('keypadClear'),
              label: 'CLR',
              height: 42,
              minimumHeight: 42,
              fontSize: 17,
              top: redTop,
              bottom: redBottom,
              onPressed: clearPassword,
            ),
            for (final letter in ['Z', 'X', 'C', 'V', 'B', 'N', 'M'])
              letterKey(letter),
            passwordKey(
              key: const Key('keypadBackspace'),
              label: '<-',
              height: 42,
              minimumHeight: 42,
              fontSize: 22,
              top: redTop,
              bottom: redBottom,
              onPressed: backspacePassword,
            ),
          ]),
        ],
      );
    }

    return Column(
      children: [
        keypadRow([
          for (final digit in ['1', '2', '3'])
            passwordKey(
              key: Key('keypad$digit'),
              label: digit,
              onPressed: () => insertPasswordText(digit),
            ),
        ]),
        const SizedBox(height: 5),
        keypadRow([
          for (final digit in ['4', '5', '6'])
            passwordKey(
              key: Key('keypad$digit'),
              label: digit,
              onPressed: () => insertPasswordText(digit),
            ),
        ]),
        const SizedBox(height: 5),
        keypadRow([
          for (final digit in ['7', '8', '9'])
            passwordKey(
              key: Key('keypad$digit'),
              label: digit,
              onPressed: () => insertPasswordText(digit),
            ),
        ]),
        const SizedBox(height: 5),
        keypadRow([
          passwordKey(
            key: const Key('keypadClear'),
            label: 'CLR',
            fontSize: 29,
            top: redTop,
            bottom: redBottom,
            onPressed: clearPassword,
          ),
          passwordKey(
            key: const Key('keypad0'),
            label: '0',
            onPressed: () => insertPasswordText('0'),
          ),
          passwordKey(
            key: const Key('keypadBackspace'),
            label: '<-',
            fontSize: 31,
            top: redTop,
            bottom: redBottom,
            onPressed: backspacePassword,
          ),
        ]),
      ],
    );
  }

  Widget buildLocked() {
    const redTop = Color(0xffd32b31);
    const redBottom = Color(0xff7f0609);
    const modeTop = Color(0xffb96b25);
    const greenTop = Color(0xff43a047);
    const greenBottom = Color(0xff1b5e20);
    const modeBottom = Color(0xff6d3107);

    return Scaffold(
      backgroundColor: const Color(0xfff4f4f4),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: SizedBox(
              width: min(MediaQuery.sizeOf(context).width, 562),
              height: message == null && !loginHintVisible ? 590 : 650,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Container(
                      width: constraints.maxWidth,
                      decoration: BoxDecoration(
                        color: const Color(0xfff4f4f4),
                        border: Border.all(color: const Color(0xffc6c6c6)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (_) {
                              unawaited(startLoginWindowDrag());
                            },
                            child: Container(
                              height: 44,
                              color: const Color(0xff777777),
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: const Text(
                                'Пароль',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: selectedVaultTitle,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (selectedVaultModifiedText
                                            case final modified?)
                                          TextSpan(text: ', $modified'),
                                      ],
                                    ),
                                    key: const Key('passwordPrompt'),
                                    maxLines: 1,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Color(0xff16212a),
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 48,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: TextSelectionTheme(
                                          data: const TextSelectionThemeData(
                                            cursorColor: Colors.black,
                                            selectionColor: Colors.transparent,
                                            selectionHandleColor:
                                                Colors.transparent,
                                          ),
                                          child: TextField(
                                            key: const Key('passwordInput'),
                                            controller: passwordController,
                                            focusNode: passwordFocusNode,
                                            autofocus: true,
                                            obscureText: !showPassword,
                                            enableSuggestions: false,
                                            autocorrect: false,
                                            keyboardType:
                                                TextInputType.visiblePassword,
                                            textInputAction:
                                                TextInputAction.done,
                                            onSubmitted: (_) => unlock(),
                                            decoration: InputDecoration(
                                              isDense: true,
                                              filled: true,
                                              fillColor: Colors.white,
                                              border: const OutlineInputBorder(
                                                borderRadius: BorderRadius.zero,
                                              ),
                                              suffixIcon: IconButton(
                                                key: const Key(
                                                  'loginPasswordVisibility',
                                                ),
                                                tooltip: showPassword
                                                    ? 'Скрыть пароль'
                                                    : 'Показать пароль',
                                                icon: Icon(
                                                  showPassword
                                                      ? Icons.visibility_off
                                                      : Icons.visibility,
                                                ),
                                                onPressed: () => setState(
                                                  () => showPassword =
                                                      !showPassword,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Listener(
                                        key: const Key(
                                          'loginPasswordHintButton',
                                        ),
                                        onPointerDown: (_) =>
                                            showLoginPasswordHint(),
                                        onPointerUp: (_) =>
                                            hideLoginPasswordHint(),
                                        onPointerCancel: (_) =>
                                            hideLoginPasswordHint(),
                                        child: SizedBox.square(
                                          dimension: 48,
                                          child: passwordKey(
                                            label: 'Подсказка пароля',
                                            height: 48,
                                            top: const Color(0xffffdc58),
                                            bottom: const Color(0xffc58a00),
                                            onPressed:
                                                passwordFocusNode.requestFocus,
                                            child: const Icon(
                                              Icons.question_mark,
                                              color: Colors.white,
                                              size: 28,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (loginHintVisible) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    key: const Key('loginPasswordHint'),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xfffff4bc),
                                      border: Border.all(
                                        color: const Color(0xffb18b00),
                                      ),
                                    ),
                                    child: Text(loginPasswordHint),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                buildPasswordKeyboard(
                                  redTop: redTop,
                                  redBottom: redBottom,
                                ),
                                const SizedBox(height: 6),
                                keypadRow([
                                  passwordKey(
                                    key: const Key('keypadModeUppercase'),
                                    label: 'ABC',
                                    fontSize: 23,
                                    top: modeTop,
                                    bottom: modeBottom,
                                    onPressed: () => selectVirtualKeyboardMode(
                                      VirtualKeyboardMode.uppercase,
                                    ),
                                  ),
                                  passwordKey(
                                    key: const Key('keypadModeLowercase'),
                                    label: 'abc',
                                    fontSize: 23,
                                    top: modeTop,
                                    bottom: modeBottom,
                                    onPressed: () => selectVirtualKeyboardMode(
                                      VirtualKeyboardMode.lowercase,
                                    ),
                                  ),
                                  passwordKey(
                                    key: const Key('keypadModeNumeric'),
                                    label: '123',
                                    fontSize: 23,
                                    top: modeTop,
                                    bottom: modeBottom,
                                    onPressed: () => selectVirtualKeyboardMode(
                                      VirtualKeyboardMode.numeric,
                                    ),
                                  ),
                                  passwordKey(
                                    key: const Key('keypadModeSymbols'),
                                    label: '#!?',
                                    fontSize: 23,
                                    top: modeTop,
                                    bottom: modeBottom,
                                    onPressed: () => selectVirtualKeyboardMode(
                                      VirtualKeyboardMode.symbols,
                                    ),
                                  ),
                                ]),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 18),
                                  child: Divider(height: 1),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        width: double.infinity,
                                        height: 48,
                                        child: passwordKey(
                                          key: const Key('fileMenu'),
                                          label: 'Открыть файл',
                                          child: const Icon(
                                            Icons.folder_outlined,
                                            color: Colors.white,
                                            size: 25,
                                          ),
                                          height: 48,
                                          fontSize: 18,
                                          top: const Color(0xffffdc58),
                                          bottom: const Color(0xffc58a00),
                                          onPressed: pickSpbWalletFile,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: passwordKey(
                                        key: const Key('createVault'),
                                        label: '+',
                                        height: 40,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        top: const Color(0xffffdc58),
                                        bottom: const Color(0xffc58a00),
                                        onPressed: createNewVaultFromLogin,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: passwordKey(
                                        key: const Key('loginOk'),
                                        label: 'OK',
                                        height: 40,
                                        fontSize: 18,
                                        top: greenTop,
                                        bottom: greenBottom,
                                        onPressed: unlock,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: passwordKey(
                                        key: const Key('loginCancel'),
                                        label: '',
                                        child: const Icon(
                                          Icons.power_settings_new,
                                          color: Colors.white,
                                          size: 25,
                                        ),
                                        height: 40,
                                        fontSize: 18,
                                        top: redTop,
                                        bottom: redBottom,
                                        onPressed: () {
                                          exitApplication();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                if (message != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    message!,
                                    key: const Key('loginMessage'),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildCreatingVaultOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.18),
        child: Center(
          child: Card(
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Создаем .swl базу',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Добавляем шаблоны, папки и демо-карточки...',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildRecentVaultsPicker() {
    final visibleRows = min(recentVaults.length, 2);
    final height = 48.0 + visibleRows * 58.0 + max(0, visibleRows - 1) * 4.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        height: height.clamp(106.0, 168.0).toDouble(),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Последние файлы',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
            ),
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: ListView.separated(
                primary: false,
                padding: const EdgeInsets.all(6),
                itemCount: recentVaults.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final vault = recentVaults[index];
                  return SizedBox(
                    height: 54,
                    child: Material(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          chooseExistingVault(vault);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.history, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      vault.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      vault.displayPath ??
                                          vault.path ??
                                          vault.uri ??
                                          '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSideRail() {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const CircleAvatar(child: Text('A')),
              title: const Text('.swl база'),
              subtitle: Text(spbWalletUserPath() ?? 'открытая .swl база'),
            ),
            const SizedBox(height: 12),
            ...navButtons(),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: lockVault,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Заблокировать'),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildTopRail({required bool compact}) {
    return Material(
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            ...navButtons(compact: compact),
            Padding(
              padding: EdgeInsets.only(right: compact ? 8 : 0),
              child: OutlinedButton.icon(
                onPressed: lockVault,
                icon: const Icon(Icons.lock_outline),
                label: const Text('Заблокировать'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> navButtons({bool compact = false}) {
    return navEntries
        .map(
          (entry) => Padding(
            padding: EdgeInsets.only(
              bottom: compact ? 0 : 8,
              right: compact ? 8 : 0,
            ),
            child: NavigationButton(
              selected: activeView == entry.id,
              icon: entry.icon,
              label: entry.label,
              onTap: () => setState(() => activeView = entry.id),
            ),
          ),
        )
        .toList();
  }

  Widget buildContent() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    viewTitle(),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
              if (activeView != 'settings')
                FilledButton.icon(
                  onPressed: primaryAction,
                  icon: Icon(primaryIcon()),
                  label: Text(primaryLabel()),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: viewBody()),
        ],
      ),
    );
  }

  String viewTitle() => {
        'cards': 'Карточки',
        'frequent': 'Часто используемые',
        'templates': 'Шаблоны',
        'settings': 'Настройки',
      }[activeView]!;

  String primaryLabel() =>
      activeView == 'templates' ? 'Новый шаблон' : 'Новая карточка';

  IconData primaryIcon() =>
      activeView == 'templates' ? Icons.add_box_outlined : Icons.add;

  void primaryAction() {
    if (activeView == 'templates') {
      openTemplateDialog();
    } else {
      openItemDialog();
    }
  }

  Widget viewBody() {
    switch (activeView) {
      case 'frequent':
        return buildFrequentView();
      case 'templates':
        return buildTemplatesView();
      case 'settings':
        return buildSettingsView();
      default:
        return buildCardsView();
    }
  }

  Widget buildCardsView() {
    final filtered = filteredItems();
    final selected = selectedItem(filtered);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: buildSearchClearButton(
                    const Key('cardsClearSearchButton'),
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  labelText: 'Поиск',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Фильтры',
              child: IconButton.filledTonal(
                onPressed: openCardFilterDialog,
                icon: Badge(
                  isLabelVisible:
                      templateFilter.isNotEmpty || sortMode != 'modified_desc',
                  child: const Icon(Icons.filter_alt_outlined),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              if (compact) {
                return walletTree(filtered, openCardsInDialog: true);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 320, child: walletTree(filtered)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: selected == null
                        ? emptyCardDetail()
                        : itemDetail(selected),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(width: 230, child: spbRightPanel(filtered)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> openCardFilterDialog() async {
    var nextTemplateFilter = templateFilter;
    var nextSortMode = sortMode;
    final applied = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Фильтры карточек'),
          content: SizedBox(
            width: min(MediaQuery.of(context).size.width - 48, 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: nextTemplateFilter,
                  decoration: const InputDecoration(
                    labelText: 'Шаблон',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Все шаблоны'),
                    ),
                    ...templates.map(
                      (template) => DropdownMenuItem(
                        value: template.id,
                        child: Text(template.name),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => nextTemplateFilter = value ?? ''),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: nextSortMode,
                  decoration: const InputDecoration(
                    labelText: 'Сортировка',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'modified_desc',
                      child: Text('Сначала новые'),
                    ),
                    DropdownMenuItem(
                      value: 'title_asc',
                      child: Text('По названию'),
                    ),
                    DropdownMenuItem(
                      value: 'template_asc',
                      child: Text('По шаблону'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => nextSortMode = value ?? 'modified_desc',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                nextTemplateFilter = '';
                nextSortMode = 'modified_desc';
                Navigator.pop(context, true);
              },
              child: const Text('Сбросить'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
    if (applied != true) return;
    setState(() {
      templateFilter = nextTemplateFilter;
      sortMode = nextSortMode;
    });
  }

  List<SecretItem> filteredItems() {
    final filtered = items.where((item) {
      final template = templateFor(item.templateId);
      final text =
          '${item.title} ${item.category} ${template.name} ${item.values.values.join(' ')}'
              .toLowerCase();
      return (templateFilter.isEmpty || item.templateId == templateFilter) &&
          text.contains(searchController.text.toLowerCase());
    }).toList();
    if (sortMode == 'title_asc') {
      filtered.sort((a, b) => a.title.compareTo(b.title));
    } else if (sortMode == 'template_asc') {
      filtered.sort(
        (a, b) => templateFor(
          a.templateId,
        ).name.compareTo(templateFor(b.templateId).name),
      );
    } else {
      filtered.sort((a, b) {
        final byDate = b.modifiedAt.compareTo(a.modifiedAt);
        if (byDate != 0) return byDate;
        final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return byTitle == 0 ? a.id.compareTo(b.id) : byTitle;
      });
    }
    return filtered;
  }

  SecretItem? selectedItem(List<SecretItem> candidates) {
    if (candidates.isEmpty) return null;
    for (final item in candidates) {
      if (item.id == selectedItemId) return item;
    }
    return candidates.first;
  }

  Widget walletTree(List<SecretItem> source, {bool openCardsInDialog = false}) {
    final root = buildCategoryTree(source);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xffd8e4f0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: const Text(
              'Мои карточки',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                ExpansionTile(
                  initiallyExpanded: true,
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Row(
                    children: [
                      const Expanded(child: Text('Мой кошелёк')),
                      Tooltip(
                        message: 'Создать папку',
                        child: IconButton(
                          icon: const Icon(Icons.create_new_folder_outlined),
                          onPressed: () => openCategoryEditorDialog(
                            parentPath: '',
                            folder: null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  children: root.isEmpty
                      ? const [
                          ListTile(
                            dense: true,
                            title: Text('Карточек не найдено'),
                          ),
                        ]
                      : treeChildren(
                          root,
                          0,
                          openCardsInDialog: openCardsInDialog,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  CategoryTreeNode buildCategoryTree(
    List<SecretItem> source, {
    bool includeAllCategories = true,
    Iterable<String> additionalPaths = const [],
  }) {
    final root = CategoryTreeNode('Мой кошелёк');
    final paths = <String>{...additionalPaths};
    if (includeAllCategories) {
      paths.addAll(categoryPaths);
      paths.addAll(categoryIconsByPath.keys);
      paths.addAll(categoryColorsByPath.keys);
    }
    for (final path in paths) {
      ensureCategoryTreeNode(root, path);
    }
    for (final item in source) {
      final node = ensureCategoryTreeNode(root, item.category);
      node.cards.add(item);
    }
    return root;
  }

  CategoryTreeNode ensureCategoryTreeNode(CategoryTreeNode root, String path) {
    var node = root;
    final pathParts = <String>[];
    for (final part in categoryParts(path)) {
      pathParts.add(part);
      final currentPath = pathParts.join(' / ');
      node = node.children.putIfAbsent(
        part,
        () => CategoryTreeNode(
          part,
          path: currentPath,
          iconId: categoryIconsByPath[currentPath],
          colorId: categoryColorsByPath[currentPath],
          id: categoryIdsByPath[currentPath],
        ),
      );
    }
    return node;
  }

  List<String> categoryParts(String value) {
    return value
        .split(RegExp(r'\s*/\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && part != 'Без категории')
        .toList();
  }

  List<String> existingCategories() {
    final categories = {
      ...categoryPaths,
      ...categoryIconsByPath.keys,
      ...categoryColorsByPath.keys,
      for (final item in items)
        if (item.category.trim().isNotEmpty) item.category.trim(),
    }.toList();
    categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return categories;
  }

  List<Widget> treeChildren(
    CategoryTreeNode node,
    int depth, {
    required bool openCardsInDialog,
  }) {
    final children = <Widget>[];
    final folders = node.children.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final folder in folders) {
      children.add(
        Padding(
          padding: EdgeInsets.only(left: depth * 10.0),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: categoryFolderIcon(
              folder.iconId ?? defaultIconForCategoryPath(folder.path),
              folder.colorId,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Tooltip(
                  message: 'Изменить папку',
                  child: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => openCategoryEditorDialog(folder: folder),
                  ),
                ),
                Tooltip(
                  message: 'Создать подпапку',
                  child: IconButton(
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: () => openCategoryEditorDialog(
                      parentPath: folder.path,
                      folder: null,
                    ),
                  ),
                ),
              ],
            ),
            children: treeChildren(
              folder,
              depth + 1,
              openCardsInDialog: openCardsInDialog,
            ),
          ),
        ),
      );
    }
    final cards = [...node.cards]..sort((a, b) => a.title.compareTo(b.title));
    for (final item in cards) {
      final template = templateFor(item.templateId);
      children.add(
        Padding(
          padding: EdgeInsets.only(left: 16 + depth * 14.0),
          child: ListTile(
            dense: true,
            selected: selectedItemId == item.id,
            leading: templateIconWidget(
              itemIconId(item, template),
              color: itemPictogramColor(item, template),
            ),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              template.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => openCardsInDialog
                ? openCardPreviewDialog(item)
                : selectItem(item),
            onLongPress: () => openItemDialog(item: item),
          ),
        ),
      );
    }
    return children;
  }

  Widget categoryFolderIcon(String iconId, String? colorId) {
    return SizedBox(
      width: 38,
      height: 38,
      child: Center(
        child: templateIconWidget(
          iconId.isEmpty ? 'folder' : iconId,
          size: 30,
          color: categoryPictogramColor(colorId),
        ),
      ),
    );
  }

  Future<void> openCategoryEditorDialog({
    required CategoryTreeNode? folder,
    String parentPath = '',
  }) async {
    final wallet = spbWallet;
    if (wallet == null) {
      setState(
        () =>
            message = 'Откройте или создайте .swl базу перед изменением папок.',
      );
      return;
    }
    if (!ensureSpbWalletWritable()) return;
    final editing = folder != null;
    final saved =
        await showDialog<({String name, String iconId, String colorId})>(
      context: context,
      builder: (context) => CategoryEditorDialog(
        editing: editing,
        initialName: folder?.name ?? '',
        initialIconId: folder?.iconId ?? defaultIconForCategoryPath(parentPath),
        initialColorId: folder?.colorId ?? 'template_gray',
      ),
    );
    if (saved == null) return;
    if (editing && saved.name == '__delete__') {
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      final confirmed = await confirmDeleteCategory(folder);
      if (confirmed != true || !mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      SessionUndoEntry? undoEntry;
      try {
        undoEntry = await captureSessionUndo(
          'Удаление папки: ${folder.name}',
          folder.iconId ?? defaultIconForCategoryPath(folder.path),
        );
        sessionTrashFolderPaths.add(folder.path);
        sessionTrash.add(
          SessionTrashEntry(
            kind: SessionTrashKind.folder,
            id: folder.path,
            title: folder.name,
            iconId: folder.iconId ?? defaultIconForCategoryPath(folder.path),
          ),
        );
        final snapshot = wallet.loadSnapshot();
        setState(() {
          applySpbSnapshot(snapshot);
          if (selectedItemId != null &&
              !items.any((entry) => entry.id == selectedItemId)) {
            selectedItemId = null;
          }
          message = null;
        });
        commitSessionUndo(undoEntry);
      } catch (error) {
        discardSessionUndo(undoEntry);
        setState(() => message = 'Не удалось удалить папку: $error');
      }
      return;
    }
    final fullPath = [
      if (!editing && parentPath.trim().isNotEmpty) parentPath.trim(),
      saved.name,
    ].join(' / ');
    if (editing &&
        saved.name == folder.name &&
        saved.iconId ==
            (folder.iconId ?? defaultIconForCategoryPath(folder.path)) &&
        saved.colorId == folder.colorId) {
      return;
    }
    SessionUndoEntry? undoEntry;
    try {
      undoEntry = await captureSessionUndo(
        editing
            ? 'Изменение папки: ${folder.name}'
            : 'Создание папки: ${saved.name}',
        saved.iconId,
      );
      final spbIconId = spbIconIdForUi(saved.iconId, 'folder') ??
          syntheticSpbIconIdForUi(saved.iconId);
      final iconBytes = spbEmbeddedIconPngs[saved.iconId.toUpperCase()];
      if (editing) {
        wallet.renameCategory(
          folder.path,
          saved.name,
          spbIconId,
          iconBytes: iconBytes,
          colorId: saved.colorId,
        );
      } else {
        wallet.createCategory(
          fullPath,
          spbIconId,
          iconBytes: iconBytes,
          colorId: saved.colorId,
        );
      }
      markVaultDirty();
      final written = await writeBackSpbWallet();
      final snapshot = wallet.loadSnapshot();
      setState(() {
        applySpbSnapshot(snapshot);
        if (!editing) {
          selectedCategoryPath = fullPath;
          selectedCategoryId = categoryIdsByPath[fullPath];
          mobilePane = 1;
        }
        if (written) message = null;
      });
      commitSessionUndo(undoEntry);
    } catch (error) {
      discardSessionUndo(undoEntry);
      setState(() => message = 'Не удалось сохранить папку: $error');
    }
  }

  Future<bool?> confirmDeleteCategory(CategoryTreeNode folder) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить папку?'),
        content: Text(
          'Папка "${folder.name}", ее подпапки и все карточки внутри будут удалены.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  Future<void> deleteCategoryWithConfirmation(CategoryTreeNode folder) async {
    final wallet = spbWallet;
    if (wallet == null) return;
    if (!ensureSpbWalletWritable()) return;
    final confirmed = await confirmDeleteCategory(folder);
    if (confirmed != true || !mounted) return;
    final parentParts = categoryParts(folder.path);
    if (parentParts.isNotEmpty) parentParts.removeLast();
    final parentPath = parentParts.join(' / ');
    SessionUndoEntry? undoEntry;
    try {
      undoEntry = await captureSessionUndo(
        'Удаление папки: ${folder.name}',
        folder.iconId ?? defaultIconForCategoryPath(folder.path),
      );
      sessionTrashFolderPaths.add(folder.path);
      sessionTrash.add(
        SessionTrashEntry(
          kind: SessionTrashKind.folder,
          id: folder.path,
          title: folder.name,
          iconId: folder.iconId ?? defaultIconForCategoryPath(folder.path),
        ),
      );
      final snapshot = wallet.loadSnapshot();
      setState(() {
        applySpbSnapshot(snapshot);
        if (selectedCategoryPath == folder.path ||
            selectedCategoryPath.startsWith('${folder.path} / ')) {
          selectedCategoryPath = parentPath;
          selectedCategoryId = categoryIdsByPath[parentPath];
        }
        if (selectedItemId != null &&
            !items.any((entry) => entry.id == selectedItemId)) {
          selectedItemId = null;
        }
        message = null;
      });
      commitSessionUndo(undoEntry);
    } catch (error) {
      discardSessionUndo(undoEntry);
      setState(() => message = 'Не удалось удалить папку: $error');
    }
  }

  Widget emptyCardDetail() {
    return const Card(
      elevation: 0,
      child: Center(child: Text('Выберите карточку в дереве слева')),
    );
  }

  Widget itemDetail(SecretItem item) {
    return itemCard(item, onDelete: deleteItemWithConfirmation);
  }

  Widget spbRightPanel(List<SecretItem> visibleItems) {
    final frequent = frequentItems();
    final top = frequent.take(10).toList();
    final selected = selectedItem(visibleItems);
    return ListView(
      children: [
        SpbPanel(
          title: 'Задачи',
          children: [
            ListTile(
              dense: true,
              leading: const Icon(Icons.add_card_outlined),
              title: const Text('Создать новую карточку'),
              onTap: () => openItemDialog(),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Редактировать'),
              enabled: selected != null,
              onTap: selected == null
                  ? null
                  : () => openItemDialog(item: selected),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SpbPanel(
          title: 'Часто используемые',
          children: [
            if (top.isEmpty)
              const ListTile(dense: true, title: Text('Пока нет данных'))
            else
              ...top.map((item) {
                final template = templateFor(item.templateId);
                return ListTile(
                  dense: true,
                  leading: templateIconWidget(
                    itemIconId(item, template),
                    color: itemPictogramColor(item, template),
                  ),
                  title: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => openFrequentCard(item),
                );
              }),
          ],
        ),
        const SizedBox(height: 12),
        SpbPanel(
          title: 'Найти карточки',
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: buildSearchClearButton(
                    const Key('panelClearSearchButton'),
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> selectItem(SecretItem item) async {
    final current = itemById(item.id) ?? item;
    final background = current.backgroundImageBase64 ??
        spbWallet?.loadCardBackgroundBase64(current.id);
    final selected = SecretItem(
      id: current.id,
      templateId: current.templateId,
      title: current.title,
      category: current.category,
      colorId: current.colorId,
      values: current.values,
      modifiedAt: current.modifiedAt,
      attachments: current.attachments,
      hitCount: current.hitCount + 1,
      iconId: current.iconId,
      backgroundImageBase64: background,
      spbColor: current.spbColor,
      fieldOrder: current.fieldOrder,
      hiddenFieldIds: current.hiddenFieldIds,
    );
    setState(() {
      selectedItemId = selected.id;
      recentlyOpenedItemIds
        ..remove(selected.id)
        ..insert(0, selected.id);
      if (recentlyOpenedItemIds.length > 10) {
        recentlyOpenedItemIds.removeRange(10, recentlyOpenedItemIds.length);
      }
      items = [
        for (final entry in items)
          if (entry.id == selected.id) selected else entry,
      ];
      itemsById[selected.id] = selected;
    });
    if (spbWallet == null) {
      setState(
        () => message =
            'Откройте или создайте .swl базу перед изменением карточек.',
      );
    }
  }

  Future<void> openCardPreviewDialog(
    SecretItem item, {
    bool preserveSearch = false,
  }) async {
    await selectItem(item);
    if (!mounted) return;
    var previewItem = itemById(item.id) ?? item;
    while (true) {
      if (!mounted) return;
      final action = await showDialog<CardPreviewAction>(
        context: context,
        builder: (context) => CardPreviewDialog(
          item: previewItem,
          template: templateFor(previewItem.templateId),
          loadAttachmentBytes: spbWallet == null
              ? null
              : (attachmentId) async =>
                  spbWallet!.readAttachmentBytes(attachmentId),
          onAddAttachment: spbWallet == null ? null : addAttachmentFromPreview,
        ),
      );
      if (!mounted || !unlocked) return;
      final latestItem = itemById(previewItem.id) ?? previewItem;
      if (action == CardPreviewAction.edit) {
        await openItemDialog(item: latestItem);
        if (!mounted || !unlocked) return;
        previewItem = itemById(latestItem.id) ?? latestItem;
        continue;
      }
      if (action == CardPreviewAction.delete) {
        await deleteItemWithConfirmation(latestItem);
      }
      previewItem = itemById(latestItem.id) ?? latestItem;
      break;
    }
    if (!mounted || !unlocked) return;
    if (!preserveSearch) revealCardFolder(previewItem);
  }

  Future<void> openFrequentCard(SecretItem item) async {
    await openCardPreviewDialog(item);
  }

  void revealCardFolder(SecretItem item) {
    final latestItem = itemById(item.id);
    final categoryPath = latestItem?.category ?? item.category;
    final parts = categoryParts(categoryPath);
    final parentPaths = <String>{};
    for (var index = 1; index <= parts.length; index++) {
      parentPaths.add(parts.take(index).join(' / '));
    }

    searchController.clear();
    setState(() {
      mobileTemplatesOpen = false;
      mobilePane = 1;
      spbSubmittedSearchQuery = '';
      selectedCategoryPath = categoryPath;
      selectedCategoryId = categoryIdsByPath[categoryPath];
      expandedCategoryPaths.addAll(parentPaths);
      selectedItemId = latestItem?.id;
    });
  }

  Future<SecretItem?> addAttachmentFromPreview(SecretItem item) async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null) return null;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return null;
    final updated = SecretItem(
      id: item.id,
      templateId: item.templateId,
      title: item.title,
      category: item.category,
      colorId: item.colorId,
      values: item.values,
      attachments: [
        ...item.attachments,
        SecretAttachment(
          id: '',
          fileName: file.name,
          size: bytes.length,
          pendingBytes: bytes,
        ),
      ],
      modifiedAt: DateTime.now().toUtc(),
      hitCount: item.hitCount,
      iconId: item.iconId,
      backgroundImageBase64: item.backgroundImageBase64,
      spbColor: item.spbColor,
      fieldOrder: item.fieldOrder,
      hiddenFieldIds: item.hiddenFieldIds,
    );
    final savedId = await persistItem(updated);
    return savedId == null ? null : itemById(savedId);
  }

  void updateItemCardState(
    VoidCallback action,
    void Function(VoidCallback action)? onStateChange,
  ) {
    if (onStateChange == null) {
      setState(action);
    } else {
      onStateChange(action);
    }
  }

  Future<void> saveNoteFromDialog(
    SecretItem item,
    String fieldId,
    String saved,
  ) async {
    if (!mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await persistItem(
      SecretItem(
        id: item.id,
        templateId: item.templateId,
        title: item.title,
        category: item.category,
        colorId: item.colorId,
        values: {...item.values, fieldId: saved},
        modifiedAt: DateTime.now().toUtc(),
        attachments: item.attachments,
        hitCount: item.hitCount,
        iconId: item.iconId,
        backgroundImageBase64: item.backgroundImageBase64,
        spbColor: item.spbColor,
        fieldOrder: item.fieldOrder,
        hiddenFieldIds: item.hiddenFieldIds,
      ),
    );
  }

  Future<void> openNotesDialog(SecretItem item) async {
    final fieldId = noteFieldIdFor(item);
    final controller = TextEditingController(text: item.values[fieldId] ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Заметки: ${item.title}'),
        content: SizedBox(
          width: min(MediaQuery.of(context).size.width - 48, 620),
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: null,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Заметка',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null) return;
    await saveNoteFromDialog(item, fieldId, saved);
  }

  Widget buildFrequentView() {
    final top = frequentItems().take(10).toList();
    if (top.isEmpty) {
      return const Center(
        child: Text(
          'Часто используемые карточки появятся после открытия карточек из дерева.',
        ),
      );
    }
    return ListView.separated(
      itemCount: top.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = top[index];
        final template = templateFor(item.templateId);
        return Card(
          elevation: 0,
          child: ListTile(
            leading: templateIconWidget(
              itemIconId(item, template),
              size: 24,
              color: itemPictogramColor(item, template),
            ),
            title: Text(item.title),
            subtitle: Text('${template.name} · открытий: ${item.hitCount}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openFrequentCard(item),
          ),
        );
      },
    );
  }

  Widget itemCard(
    SecretItem item, {
    VoidCallback? onClose,
    bool showFooterActions = true,
    bool showNotesAction = true,
    bool attachmentsReadOnly = true,
    Future<void> Function(SecretItem item)? onEdit,
    Future<bool> Function(SecretItem item)? onDelete,
    void Function(VoidCallback action)? onStateChange,
  }) {
    final template = templateFor(item.templateId);
    final color = itemDisplayColor(item, template);
    final noteCount = noteText(item).trim().isEmpty ? 0 : 1;
    final attachmentCount =
        item.attachments.where((attachment) => !attachment.deleted).length;
    final backgroundImage = backgroundImageFor(item);
    return Card(
      color: backgroundImage == null ? color.bg : Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: backgroundImage == null
                ? null
                : BoxDecoration(
                    image: DecorationImage(
                      image: backgroundImage,
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        Colors.white.withValues(alpha: 0.28),
                        BlendMode.srcOver,
                      ),
                    ),
                  ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 72),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    templateIconWidget(
                      itemIconId(item, template),
                      size: 28,
                      color: itemPictogramColor(item, template),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: color.fg,
                            ),
                          ),
                          Text(
                            template.name,
                            style: TextStyle(
                              color: color.fg.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onClose != null) ...[
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Закрыть',
                        icon: const Icon(Icons.close),
                        onPressed: onClose,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: CardFieldValuesList(
                    key: ValueKey('card-fields-${item.id}'),
                    fields: fieldsForItem(template, item),
                    item: item,
                    foreground: color.fg,
                    revealed: revealed,
                    onToggle: (revealKey, isRevealed) =>
                        updateItemCardState(() {
                      isRevealed
                          ? revealed.remove(revealKey)
                          : revealed.add(revealKey);
                    }, onStateChange),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Категория: ${item.category.isEmpty ? 'Без категории' : item.category}',
                  style: TextStyle(color: color.fg.withValues(alpha: 0.72)),
                ),
                const SizedBox(height: 8),
                if (showFooterActions)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (showNotesAction)
                        CountBadgeButton(
                          key: const Key('cardNotesButton'),
                          icon: Icons.notes_outlined,
                          label: 'Заметки',
                          count: noteCount,
                          onPressed: () => openNotesDialog(item),
                        ),
                      CountBadgeButton(
                        icon: Icons.attach_file,
                        label: 'Вложения',
                        count: attachmentCount,
                        onPressed: () => attachmentsReadOnly
                            ? openAttachmentsPreviewDialog(item)
                            : openAttachmentsDialog(item),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (onDelete != null)
            Positioned(
              left: 12,
              bottom: 12,
              child: IconButton.filledTonal(
                tooltip: 'Удалить карточку',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(item),
              ),
            ),
          Positioned(
            right: 12,
            bottom: 12,
            child: IconButton.filled(
              tooltip: 'Редактировать',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                if (onEdit == null) {
                  await openItemDialog(item: item);
                } else {
                  await onEdit(item);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  ImageProvider? backgroundImageFor(SecretItem item) {
    final encoded = item.backgroundImageBase64;
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return MemoryImage(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }

  String noteFieldIdFor(SecretItem item) {
    return noteFieldIdForTemplate(templateFor(item.templateId));
  }

  String noteText(SecretItem item) => item.values[noteFieldIdFor(item)] ?? '';

  Future<void> openAttachmentsDialog(SecretItem item) async {
    await openItemDialog(item: item);
  }

  Future<bool> deleteItemWithConfirmation(SecretItem item) async {
    if (!ensureSpbWalletWritable()) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Text('Удалить карточку'),
        content: Text('Карточка "${item.title}" будет удалена из базы.'),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actions: [
          SizedBox(
            width: 124,
            child: passwordKey(
              key: const Key('cancelDeleteCardButton'),
              label: 'Отмена',
              height: 40,
              fontSize: 18,
              onPressed: () => Navigator.pop(dialogContext, false),
            ),
          ),
          SizedBox(
            width: 124,
            child: passwordKey(
              key: const Key('confirmDeleteCardButton'),
              label: 'Удалить',
              height: 40,
              fontSize: 18,
              top: const Color(0xffe04b3f),
              bottom: const Color(0xff8f1515),
              onPressed: () => Navigator.pop(dialogContext, true),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    final wallet = spbWallet;
    if (wallet == null) {
      setState(
        () => message =
            'Откройте или создайте .swl базу перед удалением карточек.',
      );
      return false;
    }
    SessionUndoEntry? undoEntry;
    try {
      undoEntry = await captureSessionUndo(
        'Удаление карточки: ${item.title}',
        itemIconId(item, templateFor(item.templateId)),
      );
      sessionTrashCardIds.add(item.id);
      sessionTrash.add(
        SessionTrashEntry(
          kind: SessionTrashKind.card,
          id: item.id,
          title: item.title,
          iconId: itemIconId(item, templateFor(item.templateId)),
        ),
      );
      setState(() {
        items = items.where((entry) => entry.id != item.id).toList();
        itemsById.remove(item.id);
        if (selectedItemId == item.id) selectedItemId = null;
        recentlyOpenedItemIds.remove(item.id);
        message = null;
      });
      commitSessionUndo(undoEntry);
      return true;
    } catch (error) {
      discardSessionUndo(undoEntry);
      setState(() => message = 'Не удалось удалить карточку: $error');
      return false;
    }
  }

  Future<void> openAttachmentsPreviewDialog(SecretItem item) async {
    final visibleAttachments =
        item.attachments.where((attachment) => !attachment.deleted).toList();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Вложения: ${item.title}'),
        content: SizedBox(
          width: min(MediaQuery.of(context).size.width - 48, 560),
          child: visibleAttachments.isEmpty
              ? const Text('Вложений нет')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: visibleAttachments.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final attachment = visibleAttachments[index];
                    final hasError = attachment.decodeError != null;
                    return ListTile(
                      leading: attachmentPreview(attachment, hasError),
                      title: Text(attachment.fileName),
                      subtitle: Text(
                        hasError
                            ? 'Ошибка чтения: ${attachment.decodeError}'
                            : attachment.size >= 0
                                ? '${attachment.size} байт'
                                : 'Размер неизвестен',
                      ),
                      onTap: hasError
                          ? null
                          : () => viewReadOnlyAttachment(attachment),
                      trailing: hasError
                          ? null
                          : IconButton(
                              tooltip: 'Сохранить вложение',
                              icon: const Icon(Icons.download_outlined),
                              onPressed: () =>
                                  exportReadOnlyAttachment(attachment),
                            ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget attachmentPreview(SecretAttachment attachment, bool hasError) {
    if (hasError) {
      return const SizedBox(
        width: 56,
        height: 56,
        child: Icon(Icons.error_outline),
      );
    }
    if (isImageAttachment(attachment.fileName) && attachment.id.isNotEmpty) {
      return FutureBuilder<Uint8List>(
        future: readAttachmentData(attachment),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              width: 56,
              height: 56,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              snapshot.data!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox(
                width: 56,
                height: 56,
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
          );
        },
      );
    }
    return SizedBox(
      width: 56,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Icon(
          isPdfAttachment(attachment.fileName)
              ? Icons.picture_as_pdf_outlined
              : Icons.insert_drive_file_outlined,
        ),
      ),
    );
  }

  Future<Uint8List> readAttachmentData(SecretAttachment attachment) async {
    final wallet = spbWallet;
    if (wallet == null || attachment.id.isEmpty) return Uint8List(0);
    return Uint8List.fromList(wallet.readAttachmentBytes(attachment.id));
  }

  bool isImageAttachment(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  bool isPdfAttachment(String fileName) =>
      fileName.toLowerCase().endsWith('.pdf');

  Future<void> viewReadOnlyAttachment(SecretAttachment attachment) async {
    try {
      final bytes = await readAttachmentData(attachment);
      if (bytes.isEmpty) return;
      if (isImageAttachment(attachment.fileName)) {
        await showImageAttachmentDialog(attachment.fileName, bytes);
      } else {
        await openAttachmentExternally(attachment.fileName, bytes);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть вложение: $error')),
      );
    }
  }

  Future<void> showImageAttachmentDialog(
    String fileName,
    Uint8List bytes,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: min(MediaQuery.of(context).size.width - 32, 900),
            maxHeight: MediaQuery.of(context).size.height - 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Закрыть',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> openAttachmentExternally(
    String fileName,
    Uint8List bytes,
  ) async {
    final directory = await getTemporaryDirectory();
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final temporaryName = Platform.isAndroid
        ? 'wallet_aps_${safeName.hashCode.toUnsigned(32)}.apsblob'
        : 'wallet_aps_$safeName';
    final file = File(
      '${directory.path}${Platform.pathSeparator}$temporaryName',
    );
    await file.writeAsBytes(bytes, flush: true);
    final mimeType = isPdfAttachment(fileName)
        ? 'application/pdf'
        : isImageAttachment(fileName)
            ? 'image/*'
            : 'application/octet-stream';
    if (Platform.isAndroid) {
      await spbWalletChannel.invokeMethod<bool>('openFile', {
        'path': file.path,
        'mimeType': mimeType,
      });
      return;
    }
    if (Platform.isWindows) {
      await Process.start(
          'cmd',
          [
            '/c',
            'start',
            '',
            file.path,
          ],
          runInShell: true);
    } else if (Platform.isMacOS) {
      await Process.start('open', [file.path]);
    } else {
      await Process.start('xdg-open', [file.path]);
    }
  }

  Future<void> exportReadOnlyAttachment(SecretAttachment attachment) async {
    final wallet = spbWallet;
    if (wallet == null || attachment.id.isEmpty) return;
    try {
      final bytes = Uint8List.fromList(
        wallet.readAttachmentBytes(attachment.id),
      );
      final export = gallerySafeAttachmentExport(attachment.fileName, bytes);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить вложение',
        fileName: export.fileName,
        bytes: export.bytes,
      );
      if (path != null && !Platform.isAndroid && !Platform.isIOS) {
        final file = File(path);
        if (!file.existsSync() || file.lengthSync() != bytes.length) {
          await file.writeAsBytes(bytes, flush: true);
        }
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить вложение: $error')),
      );
    }
  }

  Widget buildTemplatesView() {
    final query = templateSearchQuery.trim().toLowerCase();
    final visibleTemplates = templates.where((template) {
      if (query.isEmpty) return true;
      final haystack = [
        template.name,
        ...template.fields.map((field) => field.label),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
    return ListView(
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Поиск по шаблонам',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => templateSearchQuery = value),
        ),
        const SizedBox(height: 12),
        if (visibleTemplates.isEmpty)
          const Center(child: Text('Шаблоны не найдены'))
        else
          ...visibleTemplates.map((template) {
            final backgroundColor = templateDisplayBackground(template);
            final pictogramColor = templateDisplayPictogramColor(template);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                elevation: 0,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: backgroundColor,
                    foregroundColor: pictogramColor,
                    child: templateIconWidget(
                      template.iconId,
                      color: pictogramColor,
                    ),
                  ),
                  title: Text(template.name),
                  subtitle: Text(
                    template.fields
                        .map(
                          (field) =>
                              '${field.label}${fieldDefinitionIsSecret(field) ? ' (скрыто)' : ''}',
                        )
                        .join(', '),
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      if (template.builtIn)
                        const Chip(label: Text('Встроенный')),
                      IconButton(
                        tooltip: 'Скопировать в новый шаблон',
                        icon: const Icon(Icons.copy),
                        onPressed: () => copyTemplate(template),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Future<void> copyTemplate(CardTemplate template) async {
    final copy = CardTemplate(
      id: makeId('tpl'),
      name: '${template.name}(1)',
      iconId: template.iconId,
      colorId: template.colorId,
      spbColor: template.spbColor,
      categoryPath: template.categoryPath,
      builtIn: false,
      fields: [
        for (final field in template.fields)
          FieldDefinition(
            id: field.id,
            label: field.label,
            type: field.type,
            required: field.required,
            secret: fieldDefinitionIsSecret(field),
          ),
      ],
    );
    await openTemplateDialog(draft: copy);
  }

  Widget buildSettingsView() {
    return ListView(
      children: [
        Text('Открытая база', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Card(
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: Text(openDatabaseTitle()),
            subtitle: Text(spbWalletUserPath() ?? 'локальный .swl файл'),
          ),
        ),
      ],
    );
  }

  CardTemplate templateFor(String id) {
    final indexed = templatesById[id];
    if (indexed != null) return indexed;
    return templates.isEmpty ? builtInTemplates().first : templates.first;
  }

  SecretItem? itemById(String id) => itemsById[id];

  Future<SecretItem?> openItemDialog({
    SecretItem? item,
    String? initialCategory,
  }) async {
    if (templates.isEmpty) {
      if (mounted) {
        setState(
          () => message =
              'В базе нет шаблонов. Сначала создайте или импортируйте шаблон.',
        );
      }
      return null;
    }
    final saved = await showDialog<SecretItem>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ItemEditorDialog(
        templates: templates,
        categories: existingCategories(),
        initial: item,
        initialCategory: initialCategory,
        supportsAttachments: spbWallet != null,
        loadAttachmentBytes: spbWallet == null
            ? null
            : (attachmentId) async =>
                spbWallet!.readAttachmentBytes(attachmentId),
      ),
    );
    if (!mounted || !unlocked) return null;
    if (item != null) {
      setState(() => selectedItemId = item.id);
    }
    if (saved == null) return null;
    final savedId = await persistItem(saved);
    if (savedId == null) return null;
    return itemById(savedId) ?? saved;
  }

  Future<String?> persistItem(SecretItem saved) async {
    if (spbWallet != null) {
      return saveSpbItem(saved);
    }
    setState(
      () => message =
          'Откройте или создайте .swl базу перед сохранением карточек.',
    );
    return null;
  }

  bool spbItemsHaveSameStoredContent(SecretItem first, SecretItem second) {
    if (first.templateId != second.templateId ||
        first.title != second.title ||
        first.category != second.category ||
        first.colorId != second.colorId ||
        first.iconId != second.iconId ||
        first.backgroundImageBase64 != second.backgroundImageBase64 ||
        first.spbColor != second.spbColor ||
        !mapEquals(first.values, second.values) ||
        !listEquals(first.fieldOrder, second.fieldOrder) ||
        !setEquals(first.hiddenFieldIds, second.hiddenFieldIds) ||
        first.attachments.length != second.attachments.length) {
      return false;
    }
    for (var index = 0; index < first.attachments.length; index++) {
      final original = first.attachments[index];
      final edited = second.attachments[index];
      if (original.id != edited.id ||
          original.fileName != edited.fileName ||
          original.size != edited.size ||
          edited.deleted ||
          edited.pendingBytes != null) {
        return false;
      }
    }
    return true;
  }

  bool spbTemplatesHaveSameStoredContent(
    CardTemplate first,
    CardTemplate second,
  ) {
    if (first.name != second.name ||
        first.iconId != second.iconId ||
        first.colorId != second.colorId ||
        first.spbColor != second.spbColor ||
        first.categoryPath != second.categoryPath ||
        first.fields.length != second.fields.length) {
      return false;
    }
    for (var index = 0; index < first.fields.length; index++) {
      final original = first.fields[index];
      final edited = second.fields[index];
      if (original.id != edited.id ||
          original.label != edited.label ||
          original.type != edited.type ||
          original.required != edited.required ||
          original.secret != edited.secret) {
        return false;
      }
    }
    return true;
  }

  Future<String?> saveSpbItem(SecretItem saved) async {
    final wallet = spbWallet;
    if (wallet == null) return null;
    if (!ensureSpbWalletWritable()) return null;
    final cardId = isSpbHexId(saved.id) ? saved.id : SpbWalletDatabase.makeId();
    final existing = itemById(saved.id);
    if (existing != null && spbItemsHaveSameStoredContent(existing, saved)) {
      return existing.id;
    }
    final hasAttachmentChanges = saved.attachments.any(
      (attachment) => attachment.deleted || attachment.pendingBytes != null,
    );
    final needsCategoryRefresh = saved.category.trim().isNotEmpty &&
        !categoryIdsByPath.containsKey(saved.category);
    final template = templateFor(saved.templateId);
    SessionUndoEntry? undoEntry;
    try {
      undoEntry = await captureSessionUndo(
        existing == null
            ? 'Создание карточки: ${saved.title}'
            : 'Изменение карточки: ${saved.title}',
        itemIconId(saved, template),
      );
      if (!wallet.hasTemplate(saved.templateId)) {
        wallet.saveTemplate(
          SpbWalletTemplateDraft(
            id: template.id,
            name: template.name == 'Неизвестный шаблон'
                ? 'Восстановлено: ${saved.title}'
                : template.name,
            iconId: spbIconIdForUi(template.iconId, template.iconId),
            cardColor: template.spbColor ?? paletteColorToSpb(template.colorId),
            fields: template.fields
                .where((field) => field.id != spbDescriptionFieldId)
                .map(
                  (field) => SpbWalletTemplateFieldRecord(
                    id: field.id,
                    name: field.label,
                    templateId: template.id,
                    fieldTypeId: spbFieldTypeId(field),
                  ),
                )
                .toList(),
          ),
        );
      }
      wallet.saveCard(
        SpbWalletCardDraft(
          id: cardId,
          title: saved.title,
          description: saved.values[spbDescriptionFieldId] ?? '',
          categoryPath: saved.category,
          templateId: saved.templateId,
          fieldValues: {
            for (final entry in saved.values.entries)
              if (entry.key != spbDescriptionFieldId) entry.key: entry.value,
          },
          cardColor: saved.spbColor ?? paletteColorToSpb(saved.colorId),
          iconId: spbIconIdForUi(itemIconId(saved, template), template.iconId),
          iconBytes: saved.iconId == null
              ? null
              : spbEmbeddedIconPngs[saved.iconId!.toUpperCase()],
          backgroundImageBase64: saved.backgroundImageBase64,
          fieldOrder: saved.fieldOrder,
          hiddenFieldIds: saved.hiddenFieldIds,
          modifiedAt: saved.modifiedAt,
        ),
      );
      markVaultDirty();
      for (final attachment in saved.attachments) {
        if (attachment.deleted) {
          if (attachment.id.isNotEmpty) {
            wallet.deleteAttachment(attachment.id);
          }
          continue;
        }
        if (attachment.pendingBytes != null) {
          wallet.saveAttachment(
            cardId: cardId,
            attachmentId: attachment.id.isEmpty ? null : attachment.id,
            fileName: attachment.fileName,
            bytes: attachment.pendingBytes!,
          );
        }
      }
      final written = await writeBackSpbWallet();
      final persistedAttachments = hasAttachmentChanges
          ? wallet
              .loadAttachments(cardId)
              .map(
                (attachment) => SecretAttachment(
                  id: attachment.id,
                  fileName: attachment.fileName,
                  size: attachment.size,
                  decodeError: attachment.decodeError,
                ),
              )
              .toList(growable: false)
          : List<SecretAttachment>.from(saved.attachments);
      final refreshedCategories =
          needsCategoryRefresh ? wallet.loadCategories() : null;
      setState(() {
        final persisted = SecretItem(
          id: cardId,
          templateId: saved.templateId,
          title: saved.title,
          category: saved.category,
          colorId: saved.colorId,
          values: Map<String, String>.from(saved.values),
          modifiedAt: saved.modifiedAt,
          attachments: persistedAttachments,
          hitCount: existing?.hitCount ?? 0,
          iconId: saved.iconId,
          backgroundImageBase64: saved.backgroundImageBase64,
          spbColor: saved.spbColor,
          fieldOrder: List<String>.from(saved.fieldOrder),
          hiddenFieldIds: Set<String>.from(saved.hiddenFieldIds),
        );
        if (existing == null) {
          items = [...items, persisted];
        } else {
          items = [
            for (final item in items)
              if (item.id == cardId) persisted else item,
          ];
        }
        itemsById[cardId] = persisted;
        if (refreshedCategories != null) {
          categoryIconsByPath = spbCategoryIconsToUi(refreshedCategories);
          categoryColorsByPath = spbCategoryColorsToUi(refreshedCategories);
          categoryIdsByPath = spbCategoryIdsToUi(refreshedCategories);
          categoryPathsById = {
            for (final entry in categoryIdsByPath.entries)
              entry.value: entry.key,
          };
          categoryPaths = spbCategoryPathsToUi(refreshedCategories);
        }
        selectedItemId = cardId;
        if (written) message = null;
      });
      commitSessionUndo(undoEntry);
      return cardId;
    } catch (error) {
      discardSessionUndo(undoEntry);
      setState(() => message = 'Не удалось сохранить .swl базу: $error');
      return null;
    }
  }

  Future<void> editSelectedSpbTemplate() async {
    final template = selectedSpbTemplate();
    if (template == null) {
      showTemplateActionMessage('Выберите шаблон для редактирования.');
      return;
    }
    await openTemplateDialog(template: template);
  }

  Future<void> deleteSelectedSpbTemplate() async {
    final template = selectedSpbTemplate();
    if (template == null) {
      showTemplateActionMessage('Выберите шаблон для удаления.');
      return;
    }
    await deleteTemplateWithConfirmation(template);
  }

  Future<void> importSpbTemplate() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['swt'],
        withData: true,
      );
      final file = picked?.files.single;
      if (file == null) return;
      final data = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (data == null || data.isEmpty) {
        throw const FormatException('Файл шаблона пуст.');
      }
      final imported = decodeSwtTemplate(Uint8List.fromList(data));
      final saved = await saveSpbTemplateDefinition(imported, isNew: true);
      if (saved) {
        showTemplateActionMessage('Шаблон «${imported.name}» импортирован.');
      }
    } catch (error) {
      showTemplateActionMessage('Не удалось импортировать SWT: $error');
    }
  }

  Future<void> exportSelectedSpbTemplate() async {
    final template = selectedSpbTemplate();
    if (template == null) {
      showTemplateActionMessage('Выберите шаблон для экспорта.');
      return;
    }
    try {
      final payload = const JsonEncoder.withIndent('  ').convert({
        'format': 'WalletAPS.SWT',
        'version': 1,
        'template': template.toJson(),
      });
      final data = Uint8List.fromList(utf8.encode(payload));
      final safeName =
          template.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Экспорт шаблона',
        fileName: '${safeName.isEmpty ? 'Шаблон' : safeName}.swt',
        type: FileType.custom,
        allowedExtensions: const ['swt'],
        bytes: data,
      );
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        final outputPath =
            path.toLowerCase().endsWith('.swt') ? path : '$path.swt';
        final output = File(outputPath);
        if (!output.existsSync() || output.lengthSync() != data.length) {
          await output.writeAsBytes(data, flush: true);
        }
      }
      showTemplateActionMessage('Шаблон «${template.name}» экспортирован.');
    } catch (error) {
      showTemplateActionMessage('Не удалось экспортировать SWT: $error');
    }
  }

  void showTemplateActionMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
  }

  Future<void> openTemplateDialog({
    CardTemplate? template,
    CardTemplate? draft,
  }) async {
    final saved = await showDialog<CardTemplate>(
      context: context,
      builder: (context) => TemplateEditorDialog(initial: draft ?? template),
    );
    if (saved == null) return;
    await saveSpbTemplateDefinition(saved, isNew: template == null);
  }

  Future<void> openTemplatePreview(CardTemplate template) async {
    setState(() => selectedTemplateId = template.id);
    await showDialog<void>(
      context: context,
      builder: (context) => TemplatePreviewDialog(template: template),
    );
  }

  Future<bool> saveSpbTemplateDefinition(
    CardTemplate saved, {
    required bool isNew,
  }) async {
    if (spbWallet != null) {
      if (!ensureSpbWalletWritable()) return false;
      if (!isNew) {
        final existing = templatesById[saved.id];
        if (existing != null &&
            spbTemplatesHaveSameStoredContent(existing, saved)) {
          return true;
        }
      }
      final prepared = prepareSpbTemplate(saved, isNew);
      SessionUndoEntry? undoEntry;
      try {
        undoEntry = await captureSessionUndo(
          isNew
              ? 'Создание шаблона: ${saved.name}'
              : 'Изменение шаблона: ${saved.name}',
          saved.iconId,
        );
        spbWallet!.saveTemplate(
          SpbWalletTemplateDraft(
            id: prepared.id,
            name: prepared.name,
            iconId: spbIconIdForUi(prepared.iconId, prepared.iconId),
            cardColor: prepared.spbColor ?? paletteColorToSpb(prepared.colorId),
            categoryPath: prepared.categoryPath,
            iconBytes: prepared.embeddedIconBase64 == null
                ? null
                : base64Decode(prepared.embeddedIconBase64!),
            iconFileName: prepared.iconFileName,
            fields: prepared.fields
                .where((field) => field.id != spbDescriptionFieldId)
                .map(
                  (field) => SpbWalletTemplateFieldRecord(
                    id: field.id,
                    name: field.label,
                    templateId: prepared.id,
                    fieldTypeId: spbFieldTypeId(field),
                  ),
                )
                .toList(),
          ),
        );
        markVaultDirty();
        final written = await writeBackSpbWallet();
        final updated = spbWallet!.loadSnapshot();
        setState(() {
          applySpbSnapshot(updated);
          selectedTemplateId = prepared.id;
          if (written) message = null;
        });
        commitSessionUndo(undoEntry);
        return true;
      } catch (error) {
        discardSessionUndo(undoEntry);
        setState(
          () => message = 'Не удалось сохранить шаблон .swl базы: $error',
        );
        return false;
      }
    }
    setState(
      () => message =
          'Откройте или создайте .swl базу перед сохранением шаблонов.',
    );
    return false;
  }

  CardTemplate prepareSpbTemplate(CardTemplate template, bool isNew) {
    final id = isNew ? SpbWalletDatabase.makeId() : template.id;
    return CardTemplate(
      id: id,
      name: template.name,
      iconId: template.iconId,
      colorId: template.colorId,
      embeddedIconBase64: template.embeddedIconBase64,
      iconFileName: template.iconFileName,
      spbColor: template.spbColor,
      categoryPath: template.categoryPath,
      fields: template.fields
          .where((field) => field.id != spbDescriptionFieldId)
          .map(
            (field) => FieldDefinition(
              id: spbTemplateFieldId(field.id, isNew),
              label: field.label,
              type: field.type,
              required: field.required,
              secret: fieldTypeIsSecret(field.type),
            ),
          )
          .toList(),
    );
  }

  String spbTemplateFieldId(String fieldId, bool templateIsNew) {
    if (templateIsNew || !isSpbHexId(fieldId)) {
      return SpbWalletDatabase.makeId();
    }
    return fieldId;
  }

  bool isSpbHexId(String value) =>
      RegExp(r'^[0-9A-Fa-f]+$').hasMatch(value) && value.length.isEven;

  Future<void> runSync() async {
    if (spbWallet == null) {
      setState(() => message = 'Запись доступна после открытия .swl базы.');
      return;
    }
    if (!vaultDirty) {
      showSpbOperationMessage('Изменений нет. Файл базы не перезаписывался.');
      return;
    }
    final ok = await writeBackSpbWallet();
    if (!mounted) return;
    showSpbOperationMessage(
      ok
          ? 'База успешно сохранена.'
          : 'Исходный файл не записан. Можно повторить сохранение.',
    );
    setState(() {
      if (ok) {
        lastSyncAt = DateTime.now();
        message = syncSourcePath == null && syncSourceUrl == null
            ? 'База сохранена локально.'
            : 'База записана в исходное хранилище.';
      }
    });
  }

  Future<void> saveVaultThroughExplorer() async {
    final sourcePath = spbWalletPath;
    if (spbWallet == null || sourcePath == null || sourcePath.isEmpty) {
      setState(() => message = 'Запись доступна после открытия .swl базы.');
      return;
    }
    final written = await writeBackSpbWallet();
    if (!written || !mounted) return;
    final source = File(sourcePath);
    final suggestedName = spbWalletDisplayPath == null ||
            spbWalletDisplayPath!.startsWith('content://')
        ? '${selectedVaultTitle.replaceFirst(RegExp(r'\.swl$', caseSensitive: false), '')}.swl'
        : File(spbWalletDisplayPath!).uri.pathSegments.last;
    try {
      if (Platform.isAndroid) {
        final document = await spbWalletChannel
            .invokeMapMethod<String, Object?>('createSpbWalletDocument', {
          'displayName': suggestedName,
        });
        final uri = document?['uri']?.toString();
        if (uri == null || uri.isEmpty) return;
        final copied = await spbWalletChannel.invokeMethod<bool>(
          'writeSpbWallet',
          {'uri': uri, 'localPath': sourcePath},
        );
        if (copied != true) {
          throw StateError('Системный проводник не записал выбранный файл.');
        }
      } else {
        final targetPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Сохранить базу',
          fileName: suggestedName,
          initialDirectory: source.parent.path,
          type: FileType.custom,
          allowedExtensions: const ['swl'],
        );
        if (targetPath == null || targetPath.trim().isEmpty) return;
        if (File(targetPath).absolute.path.toLowerCase() !=
            source.absolute.path.toLowerCase()) {
          await source.copy(targetPath);
        }
      }
      if (!mounted) return;
      setState(() {
        lastSyncAt = DateTime.now();
        message = 'База сохранена.';
      });
      showSpbOperationMessage('База сохранена.');
    } catch (error) {
      if (!mounted) return;
      showSpbOperationMessage('Не удалось сохранить базу: $error');
    }
  }
}

class _Spb3dArrowButton extends StatelessWidget {
  const _Spb3dArrowButton({
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) {
      return const SizedBox(width: 38, height: 34);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(3),
        child: Ink(
          width: 38,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xff676767)),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xfff4f4f4), Color(0xff8d8d8d)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.white,
                offset: Offset(-1, -1),
                blurRadius: 0.5,
              ),
              BoxShadow(
                color: Color(0x66000000),
                offset: Offset(1, 1),
                blurRadius: 1,
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 30,
            color: const Color(0xff303030),
            shadows: const [
              Shadow(color: Colors.white70, offset: Offset(0, -1)),
              Shadow(color: Color(0x66000000), offset: Offset(0, 1)),
            ],
          ),
        ),
      ),
    );
  }
}

class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({required this.password, super.key});

  final String password;

  @override
  Widget build(BuildContext context) {
    final score = passwordStrengthScore(password);
    const colors = <Color>[
      Color(0xffb71c1c),
      Color(0xffd32f2f),
      Color(0xfff57c00),
      Color(0xfffbc02d),
      Color(0xff7cb342),
      Color(0xff2e7d32),
    ];
    const labels = <String>[
      'не задан',
      'очень слабый',
      'слабый',
      'средний',
      'надежный',
      'очень надежный',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 2,
          children: [
            const Text('Надежность пароля'),
            Text(labels[score]),
          ],
        ),
        const SizedBox(height: 4),
        ClipRect(
          child: LinearProgressIndicator(
            minHeight: 8,
            value: score == 0 ? 0 : score / 5,
            backgroundColor: const Color(0xffc8c8c8),
            valueColor: AlwaysStoppedAnimation<Color>(colors[score]),
          ),
        ),
      ],
    );
  }
}

class PasswordField extends StatelessWidget {
  const PasswordField({
    required this.controller,
    required this.label,
    required this.visible,
    required this.onToggle,
    this.onChanged,
    this.onSubmitted,
    this.compact = false,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool visible;
  final VoidCallback onToggle;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      obscureText: !visible,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      textCapitalization: TextCapitalization.none,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: compact,
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
            : null,
        suffixIconConstraints: compact
            ? const BoxConstraints.tightFor(width: 40, height: 40)
            : null,
        suffixIcon: IconButton(
          padding: compact ? EdgeInsets.zero : null,
          tooltip: visible ? 'Скрыть' : 'Показать',
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
          onPressed: onToggle,
        ),
      ),
    );
    return compact ? SizedBox(height: 42, child: field) : field;
  }
}

class NavigationButton extends StatelessWidget {
  const NavigationButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor:
              selected ? Theme.of(context).colorScheme.primaryContainer : null,
        ),
      ),
    );
  }
}

class CountBadgeButton extends StatelessWidget {
  const CountBadgeButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
        if (count > 0)
          Positioned(
            right: -5,
            top: -7,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onError,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class CardFieldValuesList extends StatefulWidget {
  const CardFieldValuesList({
    required this.fields,
    required this.item,
    required this.foreground,
    required this.revealed,
    required this.onToggle,
    super.key,
  });

  final List<FieldDefinition> fields;
  final SecretItem item;
  final Color foreground;
  final Set<String> revealed;
  final void Function(String revealKey, bool isRevealed) onToggle;

  @override
  State<CardFieldValuesList> createState() => _CardFieldValuesListState();
}

class _CardFieldValuesListState extends State<CardFieldValuesList> {
  final ScrollController controller = ScrollController();

  @override
  void didUpdateWidget(covariant CardFieldValuesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id == widget.item.id) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controller.hasClients) controller.jumpTo(0);
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final populatedFields = widget.fields
        .where(
          (field) =>
              field.id != spbDescriptionFieldId &&
              (widget.item.values[field.id] ?? '').isNotEmpty,
        )
        .toList();
    return Scrollbar(
      key: const Key('cardFieldsScrollbar'),
      controller: controller,
      thumbVisibility: true,
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.only(right: 10),
        children: [
          for (final field in populatedFields)
            Builder(
              key: ValueKey('${widget.item.id}:${field.id}'),
              builder: (context) {
                final revealKey = '${widget.item.id}:${field.id}';
                final isRevealed = widget.revealed.contains(revealKey);
                final value = widget.item.values[field.id]!;
                final secret = fieldDefinitionIsSecret(field);
                return FieldValueRow(
                  label: field.label,
                  value: fieldDisplayValue(field, value, revealed: isRevealed),
                  copyValue: value,
                  foreground: widget.foreground,
                  secret: secret,
                  revealed: isRevealed,
                  onToggle: secret
                      ? () => widget.onToggle(revealKey, isRevealed)
                      : null,
                );
              },
            ),
        ],
      ),
    );
  }
}

class FieldValueRow extends StatefulWidget {
  const FieldValueRow({
    required this.label,
    required this.value,
    required this.copyValue,
    required this.foreground,
    this.secret = false,
    this.revealed = false,
    this.onToggle,
    super.key,
  });

  final String label;
  final String value;
  final String copyValue;
  final Color foreground;
  final bool secret;
  final bool revealed;
  final VoidCallback? onToggle;

  @override
  State<FieldValueRow> createState() => _FieldValueRowState();
}

class _FieldValueRowState extends State<FieldValueRow> {
  Timer? copiedTimer;
  bool copied = false;

  @override
  void dispose() {
    copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> copyValue() async {
    await copyCardFieldValue(widget.copyValue);
    if (!mounted) return;
    copiedTimer?.cancel();
    setState(() => copied = true);
    copiedTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => copied = false);
    });
  }

  Future<void> showCopyMenu(LongPressStartDetails details) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          details.globalPosition.dx,
          details.globalPosition.dy,
          1,
          1,
        ),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'copy',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.copy),
            title: Text('Копировать'),
          ),
        ),
      ],
    );
    if (picked == 'copy') await copyValue();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: copyValue,
        onLongPressStart: showCopyMenu,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.44),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.foreground.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.foreground.withValues(alpha: 0.62),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: SingleChildScrollView(
                        primary: false,
                        child: Text(
                          widget.value,
                          style: TextStyle(
                            color: widget.foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: copied ? 'Скопировано' : 'Копировать',
                icon: Icon(copied ? Icons.check : Icons.copy),
                onPressed: copyValue,
              ),
              if (widget.secret && widget.onToggle != null)
                IconButton(
                  tooltip: widget.revealed ? 'Скрыть' : 'Показать',
                  icon: Icon(
                    widget.revealed ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: widget.onToggle,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SpbPanel extends StatelessWidget {
  const SpbPanel({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xffb9cee4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class IconPickerField extends StatelessWidget {
  const IconPickerField({
    required this.label,
    required this.iconId,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String iconId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final icon = iconById(iconId);
    return Row(
      children: [
        CircleAvatar(child: Icon(templateIconGlyph(icon.id), size: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await showIconPickerDialog(context, iconId);
              if (picked != null) onChanged(picked);
            },
            icon: Icon(templateIconGlyph(icon.id), size: 18),
            label: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _IconPickerScrollbar extends StatefulWidget {
  const _IconPickerScrollbar({
    required this.builder,
    required this.scrollbarKey,
  });

  final Widget Function(ScrollController controller) builder;
  final Key scrollbarKey;

  @override
  State<_IconPickerScrollbar> createState() => _IconPickerScrollbarState();
}

class _IconPickerScrollbarState extends State<_IconPickerScrollbar> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      key: widget.scrollbarKey,
      controller: _controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      child: widget.builder(_controller),
    );
  }
}

Future<String?> showIconPickerDialog(
  BuildContext context,
  String selectedIconId,
) {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Все пиктограммы'),
      content: SizedBox(
        width: min(MediaQuery.of(context).size.width - 48, 560),
        height: min(MediaQuery.of(context).size.height - 180, 420),
        child: _IconPickerScrollbar(
          scrollbarKey: const Key('pictogramPickerScrollbar'),
          builder: (controller) => GridView.builder(
            controller: controller,
            padding: const EdgeInsets.only(right: 12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 52,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: templateIcons.length,
            itemBuilder: (context, index) {
              final icon = templateIcons[index];
              final selected = icon.id == selectedIconId;
              return Tooltip(
                message: icon.label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.pop(context, icon.id),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor,
                      ),
                    ),
                    child: Center(
                      child: Icon(templateIconGlyph(icon.id), size: 24),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ],
    ),
  );
}

Future<String?> showSpbOriginalIconPickerDialog(
  BuildContext context,
  String selectedIconId,
) async {
  final iconAssets = await loadSpb64PngIconAssets();
  if (!context.mounted) return null;
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Иконки SPB Wallet'),
      content: SizedBox(
        width: min(MediaQuery.of(context).size.width - 48, 620),
        height: min(MediaQuery.of(context).size.height - 180, 460),
        child: _IconPickerScrollbar(
          scrollbarKey: const Key('spbIconPickerScrollbar'),
          builder: (controller) => GridView.builder(
            controller: controller,
            padding: const EdgeInsets.only(right: 12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 82,
              childAspectRatio: 1,
              mainAxisSpacing: 7,
              crossAxisSpacing: 7,
            ),
            itemCount: iconAssets.length,
            itemBuilder: (context, index) {
              final iconId = iconAssets[index];
              final asset = iconId;
              final selected = iconId == selectedIconId;
              final fileName =
                  iconId.startsWith('spb://') ? iconId.substring(6) : iconId;
              return Tooltip(
                message: fileName,
                child: InkWell(
                  onTap: () => Navigator.pop(context, iconId),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surface,
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor,
                      ),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: spbPackedImage(
                        asset,
                        width: 56,
                        height: 56,
                        fit: BoxFit.contain,
                        fallback: const Icon(Icons.image_outlined, size: 40),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ],
    ),
  );
}

Future<String?> showThirdPartyIconPickerDialog(BuildContext context) async {
  final iconAssets = await loadThirdPartyIconAssets();
  if (!context.mounted) return null;
  var visible = iconAssets;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Сторонние иконки'),
        content: SizedBox(
          width: min(MediaQuery.of(context).size.width - 48, 660),
          height: min(MediaQuery.of(context).size.height - 180, 520),
          child: Column(
            children: [
              TextField(
                key: const Key('thirdPartyIconSearch'),
                decoration: const InputDecoration(
                  hintText: 'Поиск по имени файла',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (query) {
                  final normalized = query.trim().toLowerCase();
                  setDialogState(() {
                    visible = normalized.isEmpty
                        ? iconAssets
                        : iconAssets
                            .where(
                              (entry) =>
                                  entry.toLowerCase().contains(normalized),
                            )
                            .toList(growable: false);
                  });
                },
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _IconPickerScrollbar(
                  scrollbarKey: const Key('thirdPartyIconPickerScrollbar'),
                  builder: (controller) => GridView.builder(
                    controller: controller,
                    padding: const EdgeInsets.only(right: 12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 82,
                      childAspectRatio: 1,
                      mainAxisSpacing: 7,
                      crossAxisSpacing: 7,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final iconId = visible[index];
                      final bytes = thirdPartyIconPngs[iconId];
                      final fileName = iconId.split('/').last;
                      return Tooltip(
                        message: fileName,
                        child: InkWell(
                          onTap: () => Navigator.pop(context, iconId),
                          borderRadius: BorderRadius.circular(7),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: Theme.of(context).dividerColor,
                              ),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: bytes == null
                                  ? const Icon(Icons.broken_image_outlined)
                                  : Image.memory(
                                      bytes,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.medium,
                                    ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    ),
  );
}

class SpbGrayPickerButton extends StatelessWidget {
  const SpbGrayPickerButton({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.48 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(5),
            child: Ink(
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xfff4f4f4), Color(0xff969696)],
                ),
                border: Border.all(color: const Color(0xff676767)),
                borderRadius: BorderRadius.circular(5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-1, -1),
                    blurRadius: 0.5,
                  ),
                  BoxShadow(
                    color: Color(0x66000000),
                    offset: Offset(1, 1),
                    blurRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: const Color(0xff303030)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xff303030),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CategoryEditorDialog extends StatefulWidget {
  const CategoryEditorDialog({
    required this.editing,
    required this.initialName,
    required this.initialIconId,
    this.initialColorId = 'template_gray',
    super.key,
  });

  final bool editing;
  final String initialName;
  final String initialIconId;
  final String initialColorId;

  @override
  State<CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<CategoryEditorDialog> {
  late final TextEditingController name;
  late String iconId;
  late String colorId;
  bool invalidName = false;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.initialName);
    iconId = widget.initialIconId;
    colorId = widget.initialColorId;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void save() {
    final value = name.text.trim();
    if (value.isEmpty || value.contains('/')) {
      setState(() => invalidName = true);
      return;
    }
    Navigator.pop(context, (name: value, iconId: iconId, colorId: colorId));
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final media = mediaQuery.size;
    // Keyboard avoidance is owned by the dialog route. Keep the editor surface
    // stable and let its scroll view reveal the focused control.
    final availableHeight = media.height;
    final fullScreen = Platform.isAndroid || media.width < 700;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.zero,
      child: Align(
        alignment: Alignment.center,
        child: Material(
          color: const Color(0xfff4f4f4),
          elevation: 24,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: Color(0xff7f8d98)),
          ),
          child: SizedBox(
            key: const Key('categoryEditorSurface'),
            width: fullScreen ? media.width : min(media.width - 24, 720),
            height: fullScreen
                ? availableHeight
                : min(max(0.0, availableHeight - 24), 620),
            child: Column(
              children: [
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
                    ),
                    border: Border(
                      bottom: BorderSide(color: Color(0xff7f8d98)),
                    ),
                  ),
                  child: TextField(
                    key: const Key('categoryNameField'),
                    controller: name,
                    autofocus: true,
                    onChanged: (_) {
                      setState(() => invalidName = false);
                    },
                    onSubmitted: (_) => save(),
                    style: const TextStyle(fontSize: 18),
                    decoration: InputDecoration(
                      hintText: widget.editing
                          ? 'Название папки'
                          : 'Введите имя папки',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                Expanded(
                  child: ColoredBox(
                    color: colorById(colorId).bg,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        14,
                        14,
                        18 + MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                key: const Key('categoryBoundIcon'),
                                width: 112,
                                height: 112,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: const Color(0xff82929d),
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x26000000),
                                      offset: Offset(1, 2),
                                      blurRadius: 5,
                                    ),
                                  ],
                                ),
                                child: templateIconWidget(
                                  iconId.isEmpty ? 'folder' : iconId,
                                  size: 88,
                                  color: templatePictogramColor(colorId),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Text(
                                      'Выбрать иконку',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final buttons = [
                                          SpbGrayPickerButton(
                                            key: const Key(
                                              'spbFolderIconPicker',
                                            ),
                                            label: 'SPB',
                                            icon: Icons.photo_library_outlined,
                                            tooltip: 'Иконки из базы SPB',
                                            onTap: pickSpbIcon,
                                          ),
                                          SpbGrayPickerButton(
                                            key: const Key(
                                              'categoryPictogramPicker',
                                            ),
                                            label: 'пиктограммы',
                                            icon: Icons.category_outlined,
                                            tooltip: 'Выбрать пиктограмму',
                                            onTap: pickPictogram,
                                          ),
                                          SpbGrayPickerButton(
                                            key: const Key(
                                              'categoryThirdPartyPicker',
                                            ),
                                            label: 'сторонние',
                                            icon: Icons.public_outlined,
                                            tooltip: 'Иконки Visual Studio',
                                            onTap: pickThirdPartyIcon,
                                          ),
                                          SpbGrayPickerButton(
                                            key: const Key(
                                              'categoryUploadIconButton',
                                            ),
                                            label: 'загрузить иконку',
                                            icon: Icons.upload_file_outlined,
                                            tooltip:
                                                'Загрузить файл PNG или ICO',
                                            onTap: pickCustomIconFile,
                                          ),
                                        ];
                                        if (constraints.maxWidth >= 420) {
                                          return Row(
                                            children: [
                                              for (var index = 0;
                                                  index < buttons.length;
                                                  index++) ...[
                                                if (index > 0)
                                                  const SizedBox(width: 7),
                                                Expanded(child: buttons[index]),
                                              ],
                                            ],
                                          );
                                        }
                                        final width =
                                            (constraints.maxWidth - 7) / 2;
                                        return Wrap(
                                          spacing: 7,
                                          runSpacing: 7,
                                          children: [
                                            for (final button in buttons)
                                              SizedBox(
                                                width: width,
                                                child: button,
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ColorPicker(
                            value: colorId,
                            label: 'Цвет папки',
                            keyPrefix: 'categoryColor',
                            onChanged: (value) =>
                                setState(() => colorId = value),
                          ),
                          if (invalidName) ...[
                            const SizedBox(height: 12),
                            const Text(
                              'Введите название папки без символа «/».',
                              style: TextStyle(color: Color(0xffa90000)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xffdce8f1),
                    border: Border(top: BorderSide(color: Color(0xff7f8d98))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.editing) ...[
                        SpbGradientActionButton(
                          key: const Key('categoryDeleteButton'),
                          icon: Icons.delete_outline,
                          tooltip: 'Удалить папку',
                          colors: const [Color(0xffffdc58), Color(0xffc58a00)],
                          onTap: () => Navigator.pop(context, (
                            name: '__delete__',
                            iconId: iconId,
                            colorId: colorId,
                          )),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (widget.editing || name.text.trim().isNotEmpty) ...[
                        SpbGradientActionButton(
                          key: const Key('categorySaveButton'),
                          icon: Icons.check,
                          tooltip: 'Сохранить папку',
                          colors: const [Color(0xff5bc96d), Color(0xff08772f)],
                          onTap: save,
                        ),
                        const SizedBox(width: 6),
                      ],
                      SpbGradientActionButton(
                        key: const Key('categoryCloseButton'),
                        icon: Icons.close,
                        tooltip: 'Закрыть без сохранения',
                        colors: const [Color(0xffff5a5f), Color(0xffa90000)],
                        onTap: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pickSpbIcon() async {
    final picked = await showSpbOriginalIconPickerDialog(context, iconId);
    if (picked != null && mounted) setState(() => iconId = picked);
  }

  Future<void> pickPictogram() async {
    final picked = await showIconPickerDialog(context, iconId);
    if (picked != null && mounted) setState(() => iconId = picked);
  }

  Future<void> pickThirdPartyIcon() async {
    final picked = await showThirdPartyIconPickerDialog(context);
    if (picked == null || !mounted) return;
    final bytes = thirdPartyIconPngs[picked];
    if (bytes == null) return;
    setState(() => iconId = registerEmbeddedIcon(bytes));
  }

  Future<void> pickCustomIconFile() async {
    final picked = await pickUserIconFile(context);
    if (picked == null || !mounted) return;
    setState(() => iconId = registerEmbeddedIcon(picked.bytes));
  }
}

enum CardPreviewAction { back, edit, delete }

class CardPreviewDialog extends StatefulWidget {
  const CardPreviewDialog({
    required this.item,
    required this.template,
    this.loadAttachmentBytes,
    this.onAddAttachment,
    super.key,
  });

  final SecretItem item;
  final CardTemplate template;
  final Future<List<int>> Function(String attachmentId)? loadAttachmentBytes;
  final Future<SecretItem?> Function(SecretItem item)? onAddAttachment;

  @override
  State<CardPreviewDialog> createState() => _CardPreviewDialogState();
}

class _CardPreviewDialogState extends State<CardPreviewDialog> {
  final Set<String> revealedFields = {};
  late SecretItem currentItem;

  ImageProvider? get backgroundImage {
    final encoded = currentItem.backgroundImageBase64;
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return MemoryImage(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    currentItem = widget.item;
  }

  String allCardText() {
    final lines = <String>[
      'Название:',
      currentItem.title,
      if (currentItem.category.trim().isNotEmpty) ...[
        'Категория:',
        currentItem.category,
      ],
    ];
    for (final field in fieldsForItem(widget.template, currentItem)) {
      final value = currentItem.values[field.id]?.trim() ?? '';
      if (value.isNotEmpty) lines.addAll(['${field.label}:', value]);
    }
    return lines.join('\n');
  }

  bool pointIsInsidePreviewTextField(Offset globalPosition) {
    var inside = false;
    void visit(Element element) {
      if (inside) return;
      if (element.widget is EditableText) {
        final renderObject = element.renderObject;
        if (renderObject is RenderBox && renderObject.hasSize) {
          final bounds =
              renderObject.localToGlobal(Offset.zero) & renderObject.size;
          inside = bounds.contains(globalPosition);
        }
      }
      if (!inside) element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return inside;
  }

  void handlePreviewPointerDown(PointerDownEvent event) {
    if (event.buttons & kSecondaryMouseButton == 0 ||
        pointIsInsidePreviewTextField(event.position)) {
      return;
    }
    showCopyAllMenu(event.position);
  }

  Future<void> showCopyAllMenu(Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          key: Key('copyAllCardFieldsAction'),
          value: 'copyAll',
          child: Text('Скопировать всё'),
        ),
      ],
    );
    if (!mounted || selected != 'copyAll') return;
    await copySensitiveText(allCardText());
  }

  List<SecretAttachment> get availableAttachments => currentItem.attachments
      .where(
        (attachment) => !attachment.deleted && attachment.decodeError == null,
      )
      .toList(growable: false);

  Future<Uint8List> attachmentBytes(SecretAttachment attachment) async {
    if (attachment.pendingBytes != null) {
      return Uint8List.fromList(attachment.pendingBytes!);
    }
    final loader = widget.loadAttachmentBytes;
    if (loader == null || attachment.id.isEmpty) return Uint8List(0);
    return Uint8List.fromList(await loader(attachment.id));
  }

  Future<void> previewAttachment(SecretAttachment attachment) async {
    try {
      final bytes = await attachmentBytes(attachment);
      if (bytes.isEmpty) return;
      await openAttachmentBytesWithSystem(attachment.fileName, bytes);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть вложение: $error')),
      );
    }
  }

  Future<void> saveAttachment(SecretAttachment attachment) async {
    try {
      final bytes = await attachmentBytes(attachment);
      if (bytes.isEmpty) return;
      final export = gallerySafeAttachmentExport(attachment.fileName, bytes);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить вложение',
        fileName: export.fileName,
        bytes: export.bytes,
      );
      if (path != null && !Platform.isAndroid && !Platform.isIOS) {
        final file = File(path);
        if (!file.existsSync() || file.lengthSync() != bytes.length) {
          await file.writeAsBytes(bytes, flush: true);
        }
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить вложение: $error')),
      );
    }
  }

  Future<void> chooseAttachmentToSave() async {
    final source = availableAttachments;
    if (source.isEmpty) return;
    if (source.length == 1) {
      await saveAttachment(source.single);
      return;
    }
    final selected = await showDialog<SecretAttachment>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Сохранить вложение'),
        children: [
          for (final attachment in source)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, attachment),
              child: Text(attachment.fileName),
            ),
        ],
      ),
    );
    if (selected != null) await saveAttachment(selected);
  }

  Widget previewAttachmentNames() {
    final files = availableAttachments.where(
      (attachment) => !isInlineImage(attachment.fileName),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final attachment in files)
          Material(
            key: ValueKey('cardPreviewAttachment-${attachment.fileName}'),
            color: Colors.transparent,
            child: InkWell(
              onTap: () => previewAttachment(attachment),
              onSecondaryTap: () => previewAttachment(attachment),
              onLongPress: () => previewAttachment(attachment),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 19),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        attachment.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool isInlineImage(String fileName) {
    final lower = fileName.toLowerCase();
    return const [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
    ].any(lower.endsWith);
  }

  Widget inlineAttachmentPreview(
    SecretAttachment attachment,
    Color background,
  ) {
    return FutureBuilder<Uint8List>(
      future: attachmentBytes(attachment),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        Widget content;
        if (bytes == null) {
          content = const SizedBox(
            height: 72,
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (isInlineImage(attachment.fileName)) {
          content = ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: Image.memory(
              bytes,
              width: double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          );
        } else {
          return const SizedBox.shrink();
        }
        return Padding(
          key: ValueKey('cardPreviewInlineAttachment-${attachment.fileName}'),
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: background.withValues(alpha: 0.9),
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xff82929d)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: InkWell(
              onTap: () => previewAttachment(attachment),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    content,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final fullScreen = Platform.isAndroid || media.width < 700;
    final color = itemDisplayColor(currentItem, widget.template);
    final visibleFields = fieldsForItem(
      widget.template,
      currentItem,
    ).where(
      (field) => cardFieldValueIsPopulated(currentItem.values[field.id] ?? ''),
    );
    final orderedVisibleFields = [
      ...visibleFields.where((field) => field.type != 'multiline_note'),
      ...visibleFields.where((field) => field.type == 'multiline_note'),
    ];
    return Align(
      alignment: Alignment.center,
      child: Material(
        color: const Color(0xfff4f4f4),
        elevation: 24,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: Color(0xff7f8d98)),
        ),
        child: SizedBox(
          key: const Key('cardPreviewSurface'),
          width: fullScreen ? media.width : min(media.width - 24, 720),
          height: fullScreen ? media.height : min(media.height - 24, 760),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: handlePreviewPointerDown,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // A parent long-press recognizer wins the gesture arena over
              // EditableText on Android, so the selection toolbar never gets
              // a chance to open. Desktop keeps this gesture for Copy all;
              // touch platforms reserve long press for their text fields.
              onLongPressStart: usesTouchTextSelection
                  ? null
                  : (details) => showCopyAllMenu(details.globalPosition),
              child: Column(
                children: [
                  Container(
                    height: 48,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
                      ),
                      border: Border(
                        bottom: BorderSide(color: Color(0xff7f8d98)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            currentItem.title,
                            key: const Key('cardPreviewTitle'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          formatCardModifiedAt(currentItem.modifiedAt),
                          key: const Key('cardPreviewModifiedAt'),
                          maxLines: 1,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: DecoratedBox(
                      decoration: cardSurfaceDecoration(
                        color: color.bg,
                        backgroundImage: backgroundImage,
                      ),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          14,
                          14,
                          14,
                          18 + MediaQuery.viewInsetsOf(context).bottom,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onLongPressStart: usesTouchTextSelection
                                    ? (details) => showCopyAllMenu(
                                          details.globalPosition,
                                        )
                                    : null,
                                child: Container(
                                  key: const Key('cardPreviewIcon'),
                                  width: 112,
                                  height: 112,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(
                                      color: const Color(0xff82929d),
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(5),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x26000000),
                                        offset: Offset(1, 2),
                                        blurRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: templateIconWidget(
                                    itemIconId(currentItem, widget.template),
                                    size: 88,
                                    color:
                                        pictogramColorForBackground(color.bg),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            for (final field in orderedVisibleFields)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: TextFormField(
                                  key: ValueKey('cardPreviewField-${field.id}'),
                                  initialValue:
                                      currentItem.values[field.id] ?? '',
                                  readOnly: true,
                                  contextMenuBuilder:
                                      desktopCardTextContextMenu,
                                  obscureText: fieldDefinitionIsSecret(field) &&
                                      !revealedFields.contains(field.id),
                                  minLines:
                                      field.type == 'multiline_note' ? 3 : 1,
                                  maxLines:
                                      field.type == 'multiline_note' ? null : 1,
                                  decoration: InputDecoration(
                                    labelText: field.label,
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: color.bg,
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    suffixIconConstraints:
                                        BoxConstraints.tightFor(
                                      width: fieldDefinitionIsSecret(field)
                                          ? 72
                                          : 36,
                                      height: 40,
                                    ),
                                    suffixIcon: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (fieldDefinitionIsSecret(field))
                                          SizedBox(
                                            width: 36,
                                            child: IconButton(
                                              padding: EdgeInsets.zero,
                                              tooltip: revealedFields
                                                      .contains(field.id)
                                                  ? 'Скрыть'
                                                  : 'Показать',
                                              icon: Icon(
                                                revealedFields
                                                        .contains(field.id)
                                                    ? Icons.visibility_off
                                                    : Icons.visibility,
                                                size: 19,
                                              ),
                                              onPressed: () => setState(() {
                                                revealedFields
                                                        .contains(field.id)
                                                    ? revealedFields
                                                        .remove(field.id)
                                                    : revealedFields
                                                        .add(field.id);
                                              }),
                                            ),
                                          ),
                                        SizedBox(
                                          width: 36,
                                          child: IconButton(
                                            key: ValueKey(
                                                'cardPreviewCopy-${field.id}'),
                                            padding: EdgeInsets.zero,
                                            tooltip: 'Копировать',
                                            icon: const Icon(
                                              Icons.copy_outlined,
                                              size: 17,
                                              color: Color(0xff777777),
                                            ),
                                            onPressed: () => copyCardFieldValue(
                                              currentItem.values[field.id] ??
                                                  '',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if (availableAttachments.any(
                              (attachment) =>
                                  !isInlineImage(attachment.fileName),
                            )) ...[
                              previewAttachmentNames(),
                              const SizedBox(height: 8),
                            ],
                            for (final attachment in availableAttachments.where(
                              (attachment) =>
                                  isInlineImage(attachment.fileName),
                            ))
                              inlineAttachmentPreview(attachment, color.bg),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                    decoration: const BoxDecoration(
                      color: Color(0xffdce8f1),
                      border: Border(top: BorderSide(color: Color(0xff7f8d98))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            if (availableAttachments.isNotEmpty)
                              SpbGradientActionButton(
                                key: const Key(
                                    'cardPreviewSaveAttachmentButton'),
                                icon: Icons.folder_outlined,
                                tooltip: 'Сохранить вложение',
                                colors: const [
                                  Color(0xff555555),
                                  Color(0xff050505),
                                ],
                                onTap: chooseAttachmentToSave,
                              ),
                            const Spacer(),
                            SpbGradientActionButton(
                              key: const Key('cardPreviewEditButton'),
                              icon: Icons.edit,
                              tooltip: 'Редактировать карточку',
                              colors: const [
                                Color(0xff5bc96d),
                                Color(0xff08772f),
                              ],
                              onTap: () => Navigator.pop(
                                  context, CardPreviewAction.edit),
                            ),
                            const SizedBox(width: 6),
                            SpbGradientActionButton(
                              key: const Key('cardPreviewDeleteButton'),
                              icon: Icons.delete_outline,
                              tooltip: 'Удалить карточку',
                              colors: const [
                                Color(0xffffdc58),
                                Color(0xffc58a00),
                              ],
                              onTap: () => Navigator.pop(
                                context,
                                CardPreviewAction.delete,
                              ),
                            ),
                            const SizedBox(width: 6),
                            SpbGradientActionButton(
                              key: const Key('cardPreviewBackButton'),
                              icon: Icons.close,
                              tooltip: 'Выйти из просмотра',
                              colors: const [
                                Color(0xffff5a5f),
                                Color(0xffa90000),
                              ],
                              onTap: () => Navigator.pop(
                                  context, CardPreviewAction.back),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SpbGradientActionButton extends StatelessWidget {
  const SpbGradientActionButton({
    required this.icon,
    required this.tooltip,
    required this.colors,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final List<Color> colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: Center(
        child: Tooltip(
          message: tooltip,
          child: Opacity(
            opacity: onTap == null ? 0.55 : 1,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Ink(
                  width: 38,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: colors,
                    ),
                    border: Border.all(color: const Color(0xff56636c)),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CardEditorSnapshot {
  const CardEditorSnapshot({
    required this.templateId,
    required this.colorId,
    required this.categorySelection,
    required this.iconId,
    required this.title,
    required this.category,
    required this.values,
    required this.fieldOrder,
    required this.hiddenFieldIds,
    required this.attachments,
    this.backgroundImageBase64,
    this.spbColor,
  });

  final String templateId;
  final String colorId;
  final String categorySelection;
  final String iconId;
  final String title;
  final String category;
  final Map<String, String> values;
  final List<String> fieldOrder;
  final Set<String> hiddenFieldIds;
  final List<SecretAttachment> attachments;
  final String? backgroundImageBase64;
  final int? spbColor;

  String get signature => [
        templateId,
        colorId,
        categorySelection,
        iconId,
        title,
        category,
        backgroundImageBase64 ?? '',
        spbColor?.toString() ?? '',
        fieldOrder.join('\u0001'),
        (hiddenFieldIds.toList()..sort()).join('\u0001'),
        for (final entry in values.entries) '${entry.key}\u0001${entry.value}',
        for (final entry in attachments)
          '${entry.id}\u0001${entry.fileName}\u0001${entry.size}\u0001${entry.deleted}',
      ].join('\u0002');
}

class ItemEditorDialog extends StatefulWidget {
  const ItemEditorDialog({
    required this.templates,
    required this.categories,
    this.initial,
    this.initialCategory,
    this.supportsAttachments = false,
    this.loadAttachmentBytes,
    super.key,
  });

  final List<CardTemplate> templates;
  final List<String> categories;
  final SecretItem? initial;
  final String? initialCategory;
  final bool supportsAttachments;
  final Future<List<int>> Function(String attachmentId)? loadAttachmentBytes;

  @override
  State<ItemEditorDialog> createState() => _ItemEditorDialogState();
}

class _ItemEditorDialogState extends State<ItemEditorDialog> {
  static const emptyCategoryValue = '__empty_category__';
  static const newCategoryValue = '__new_category__';

  late String templateId;
  late String colorId;
  late String categorySelection;
  late String iconId;
  late final DateTime editorOpenedAt;
  late final TextEditingController title;
  late final TextEditingController category;
  late final Map<String, TextEditingController> values;
  late List<String> fieldOrder;
  late Set<String> hiddenFieldIds;
  late List<SecretAttachment> attachments;
  String? backgroundImageBase64;
  int? spbColor;
  final Set<String> visibleSecrets = {};
  final List<CardEditorSnapshot> undoHistory = [];

  Color get editorBackgroundColor => spbColor == null
      ? colorById(colorId).bg
      : Color(0xff000000 | (spbColor! & 0x00ffffff));

  ImageProvider? get editorBackgroundImage {
    final encoded = backgroundImageBase64;
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return MemoryImage(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }

  CardTemplate get template =>
      widget.templates.firstWhere((entry) => entry.id == templateId);

  List<FieldDefinition> get allCardFields {
    final result = <FieldDefinition>[...template.fields];
    final known = result.map((field) => field.id).toSet();
    for (final entry in widget.initial?.values.entries ??
        const <MapEntry<String, String>>[]) {
      final id = entry.key;
      if (!cardFieldValueIsPopulated(entry.value)) continue;
      if (known.add(id)) {
        result.add(
          FieldDefinition(
            id: id,
            label:
                'Сохранённое поле ${id.length > 8 ? id.substring(0, 8) : id}',
            type: 'text',
          ),
        );
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    editorOpenedAt = DateTime.now();
    templateId = widget.initial?.templateId ?? widget.templates.first.id;
    colorId = widget.initial?.colorId ?? template.colorId;
    iconId = widget.initial?.iconId ?? template.iconId;
    title = TextEditingController(text: widget.initial?.title ?? '');
    final initialCategory =
        widget.initial?.category.trim() ?? widget.initialCategory?.trim() ?? '';
    category = TextEditingController(text: initialCategory);
    categorySelection = initialCategory.isEmpty
        ? emptyCategoryValue
        : widget.categories.contains(initialCategory)
            ? initialCategory
            : newCategoryValue;
    values = {
      for (final field in allCardFields)
        field.id: TextEditingController(
          text: widget.initial?.values[field.id] ?? '',
        ),
    };
    hiddenFieldIds = {...?widget.initial?.hiddenFieldIds};
    final availableIds = allCardFields.map((field) => field.id).toSet();
    fieldOrder = [
      for (final id in widget.initial?.fieldOrder ?? const <String>[])
        if (availableIds.contains(id) && !hiddenFieldIds.contains(id)) id,
      for (final field in allCardFields)
        if (!(widget.initial?.fieldOrder.contains(field.id) ?? false) &&
            !hiddenFieldIds.contains(field.id))
          field.id,
    ];
    attachments = [...?widget.initial?.attachments];
    backgroundImageBase64 = widget.initial?.backgroundImageBase64;
    spbColor = widget.initial?.spbColor;
  }

  @override
  void dispose() {
    title.dispose();
    category.dispose();
    for (final controller in values.values) {
      controller.dispose();
    }
    super.dispose();
  }

  CardEditorSnapshot currentSnapshot() => CardEditorSnapshot(
        templateId: templateId,
        colorId: colorId,
        categorySelection: categorySelection,
        iconId: iconId,
        title: title.text,
        category: category.text,
        values: {
          for (final entry in values.entries) entry.key: entry.value.text
        },
        fieldOrder: [...fieldOrder],
        hiddenFieldIds: {...hiddenFieldIds},
        attachments: [...attachments],
        backgroundImageBase64: backgroundImageBase64,
        spbColor: spbColor,
      );

  void rememberCurrentAction() {
    final snapshot = currentSnapshot();
    if (undoHistory.isNotEmpty &&
        undoHistory.last.signature == snapshot.signature) {
      return;
    }
    setState(() {
      undoHistory.add(snapshot);
      if (undoHistory.length > 100) undoHistory.removeAt(0);
    });
  }

  void undoLastAction() {
    if (undoHistory.isEmpty) return;
    final snapshot = undoHistory.removeLast();
    setState(() {
      templateId = snapshot.templateId;
      colorId = snapshot.colorId;
      categorySelection = snapshot.categorySelection;
      iconId = snapshot.iconId;
      title.text = snapshot.title;
      category.text = snapshot.category;
      for (final entry in values.entries) {
        entry.value.text = snapshot.values[entry.key] ?? '';
      }
      for (final entry in snapshot.values.entries) {
        values.putIfAbsent(
          entry.key,
          () => TextEditingController(text: entry.value),
        );
      }
      fieldOrder = [...snapshot.fieldOrder];
      hiddenFieldIds = {...snapshot.hiddenFieldIds};
      attachments = [...snapshot.attachments];
      backgroundImageBase64 = snapshot.backgroundImageBase64;
      spbColor = snapshot.spbColor;
    });
  }

  Widget cardIconPickers() {
    final buttons = [
      SpbGrayPickerButton(
        key: const Key('spbCardIconPicker'),
        label: 'SPB',
        icon: Icons.photo_library_outlined,
        tooltip: 'Иконки из базы SPB',
        onTap: pickSpbCardIcon,
      ),
      SpbGrayPickerButton(
        key: const Key('cardPictogramPicker'),
        label: 'пиктограммы',
        icon: Icons.category_outlined,
        tooltip: 'Выбрать пиктограмму',
        onTap: pickCardPictogram,
      ),
      SpbGrayPickerButton(
        key: const Key('cardThirdPartyPicker'),
        label: 'сторонние',
        icon: Icons.public_outlined,
        tooltip: 'Иконки Visual Studio',
        onTap: pickCardThirdPartyIcon,
      ),
      SpbGrayPickerButton(
        key: const Key('cardUploadIconButton'),
        label: 'загрузить иконку',
        icon: Icons.upload_file_outlined,
        tooltip: 'Загрузить файл PNG или ICO',
        onTap: pickCardCustomIconFile,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 420) {
          return Row(
            children: [
              for (var index = 0; index < buttons.length; index++) ...[
                if (index > 0) const SizedBox(width: 7),
                Expanded(child: buttons[index]),
              ],
            ],
          );
        }
        final width = (constraints.maxWidth - 7) / 2;
        return Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final button in buttons) SizedBox(width: width, child: button),
          ],
        );
      },
    );
  }

  Future<void> pickSpbCardIcon() async {
    final picked = await showSpbOriginalIconPickerDialog(context, iconId);
    if (picked == null || !mounted) return;
    rememberCurrentAction();
    setState(() => iconId = picked);
  }

  Future<void> pickCardPictogram() async {
    final picked = await showIconPickerDialog(context, iconId);
    if (picked == null || !mounted) return;
    rememberCurrentAction();
    setState(() => iconId = picked);
  }

  Future<void> pickCardThirdPartyIcon() async {
    final picked = await showThirdPartyIconPickerDialog(context);
    if (picked == null || !mounted) return;
    final bytes = thirdPartyIconPngs[picked];
    if (bytes == null) return;
    rememberCurrentAction();
    setState(() => iconId = registerEmbeddedIcon(bytes));
  }

  Future<void> pickCardCustomIconFile() async {
    final picked = await pickUserIconFile(context);
    if (picked == null || !mounted) return;
    rememberCurrentAction();
    setState(() => iconId = registerEmbeddedIcon(picked.bytes));
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final media = mediaQuery.size;
    // Keyboard avoidance is owned by the dialog route. Keep the editor surface
    // stable and let its scroll view reveal the focused control.
    final availableHeight = media.height;
    final fullScreen = Platform.isAndroid || media.width < 700;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.zero,
      child: Align(
        alignment: Alignment.center,
        child: Material(
          color: const Color(0xfff4f4f4),
          elevation: 24,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: Color(0xff7f8d98)),
          ),
          child: SizedBox(
            key: const Key('cardEditorSurface'),
            width: fullScreen ? media.width : min(media.width - 24, 720),
            height: fullScreen
                ? availableHeight
                : min(max(0.0, availableHeight - 24), 760),
            child: Column(
              children: [
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
                    ),
                    border: Border(
                      bottom: BorderSide(color: Color(0xff7f8d98)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title.text.trim().isEmpty
                              ? (widget.initial == null
                                  ? 'Новая карточка'
                                  : 'Редактировать карточку')
                              : title.text,
                          key: const Key('cardWindowTitle'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        formatCardModifiedAt(
                          widget.initial?.modifiedAt ?? editorOpenedAt,
                        ),
                        key: const Key('cardEditorModifiedAt'),
                        maxLines: 1,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: DecoratedBox(
                    decoration: cardSurfaceDecoration(
                      color: editorBackgroundColor,
                      backgroundImage: editorBackgroundImage,
                    ),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        14,
                        14,
                        18 + mediaQuery.viewInsets.bottom,
                      ),
                      child: buildCardEditorContent(),
                    ),
                  ),
                ),
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xffdce8f1),
                    border: Border(top: BorderSide(color: Color(0xff7f8d98))),
                  ),
                  child: Row(
                    children: [
                      if (widget.supportsAttachments) ...[
                        if (activeAttachments.isNotEmpty) ...[
                          SpbGradientActionButton(
                            key: const Key('cardEditorSaveAttachmentButton'),
                            icon: Icons.folder_outlined,
                            tooltip: 'Сохранить вложение',
                            colors: const [
                              Color(0xff555555),
                              Color(0xff050505),
                            ],
                            onTap: chooseAttachmentToExport,
                          ),
                          const SizedBox(width: 6),
                        ],
                        SpbGradientActionButton(
                          key: const Key('cardEditorAddAttachmentButton'),
                          icon: Icons.add,
                          tooltip: 'Загрузить вложение',
                          colors: const [Color(0xff5b9dff), Color(0xff0752b5)],
                          onTap: addAttachment,
                        ),
                        if (activeAttachments.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          SpbGradientActionButton(
                            key: const Key('cardEditorDeleteAttachmentButton'),
                            icon: Icons.delete,
                            tooltip: 'Удалить вложение',
                            colors: const [
                              Color(0xffff5a5f),
                              Color(0xffa90000),
                            ],
                            onTap: chooseAttachmentToDelete,
                          ),
                        ],
                      ],
                      const Spacer(),
                      SpbGradientActionButton(
                        key: const Key('cardUndoButton'),
                        icon: Icons.undo,
                        tooltip: 'Отменить последнее действие',
                        colors: const [Color(0xffffdc58), Color(0xffc58a00)],
                        onTap: undoHistory.isEmpty ? null : undoLastAction,
                      ),
                      const SizedBox(width: 6),
                      SpbGradientActionButton(
                        key: const Key('cardSaveButton'),
                        icon: Icons.check,
                        tooltip: 'Сохранить карточку',
                        colors: const [Color(0xff5bc96d), Color(0xff08772f)],
                        onTap: saveCard,
                      ),
                      const SizedBox(width: 6),
                      SpbGradientActionButton(
                        key: const Key('cardCloseButton'),
                        icon: Icons.close,
                        tooltip: 'Закрыть без сохранения',
                        colors: const [Color(0xffff5a5f), Color(0xffa90000)],
                        onTap: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildCardEditorContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              key: const Key('cardBoundIcon'),
              width: 112,
              height: 112,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xff82929d), width: 2),
                borderRadius: BorderRadius.circular(5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    offset: Offset(1, 2),
                    blurRadius: 5,
                  ),
                ],
              ),
              child: templateIconWidget(
                iconId,
                size: 88,
                color: pictogramColorForBackground(editorBackgroundColor),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: cardIconPickers()),
          ],
        ),
        const SizedBox(height: 12),
        ColorPicker(
          value: colorId,
          onChanged: (value) {
            if (value == colorId) return;
            rememberCurrentAction();
            setState(() {
              colorId = value;
              spbColor = paletteColorToSpb(value);
            });
          },
        ),
        const SizedBox(height: 10),
        EnsureVisibleWhenFocused(
          child: SizedBox(
            height: 45,
            child: TextField(
              key: const Key('cardTitleField'),
              controller: title,
              onTap: rememberCurrentAction,
              contextMenuBuilder: desktopCardTextContextMenu,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Название карточки',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 45,
          child: DropdownButtonFormField<String>(
            key: const Key('cardTemplateField'),
            isExpanded: true,
            initialValue: templateId,
            decoration: const InputDecoration(
              labelText: 'Название шаблона',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            ),
            items: widget.templates
                .map(
                  (entry) => DropdownMenuItem(
                    value: entry.id,
                    child: cardTemplateMenuLabel(entry),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null || value == templateId) return;
              rememberCurrentAction();
              setState(() {
                templateId = value;
                if (widget.initial == null || widget.initial?.iconId == null) {
                  iconId = template.iconId;
                }
                for (final field in template.fields) {
                  values.putIfAbsent(
                    field.id,
                    () => TextEditingController(
                      text: widget.initial?.values[field.id] ?? '',
                    ),
                  );
                }
                hiddenFieldIds = {};
                fieldOrder = [for (final field in template.fields) field.id];
              });
            },
          ),
        ),
        const SizedBox(height: 10),
        categoryEditor(),
        const SizedBox(height: 10),
        for (final field in orderedCardFields)
          EnsureVisibleWhenFocused(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: buildCardValueField(field),
            ),
          ),
        if (widget.supportsAttachments) buildCardAttachmentsEditor(),
      ],
    );
  }

  List<FieldDefinition> get orderedCardFields {
    final ordered = [
      for (final id in fieldOrder)
        for (final field in allCardFields)
          if (field.id == id) field,
    ];
    return [
      ...ordered.where((field) => field.type != 'multiline_note'),
      ...ordered.where((field) => field.type == 'multiline_note'),
    ];
  }

  Widget cardTemplateMenuLabel(CardTemplate entry) {
    return Row(
      children: [
        Container(
          key: ValueKey('cardTemplateIcon-${entry.id}'),
          width: 42,
          height: 42,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xff82929d)),
          ),
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Center(
                child: templateIconWidget(
                  entry.iconId,
                  size: 60,
                  color: templateDisplayPictogramColor(entry),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget buildCardValueField(FieldDefinition field) {
    final controller = values.putIfAbsent(
      field.id,
      () => TextEditingController(),
    );
    final visible = visibleSecrets.contains(field.id);
    final index = fieldOrder.indexOf(field.id);
    final multiline = field.type == 'multiline_note';
    final textField = TextField(
      key: ValueKey('cardField-${field.id}'),
      controller: controller,
      onTap: rememberCurrentAction,
      contextMenuBuilder: desktopCardTextContextMenu,
      obscureText: fieldDefinitionIsSecret(field) && !visible,
      keyboardType:
          multiline ? TextInputType.multiline : keyboardTypeForField(field),
      textInputAction:
          multiline ? TextInputAction.newline : TextInputAction.next,
      inputFormatters: inputFormattersForField(field),
      minLines: multiline ? null : 1,
      maxLines: multiline ? null : 1,
      expands: multiline,
      scrollPadding: const EdgeInsets.only(bottom: 140),
      decoration: InputDecoration(
        labelText: '${field.label}${field.required ? ' *' : ''}',
        hintText: hintTextForField(field),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: editorBackgroundColor,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        suffixIcon: fieldSuffixIcon(field, controller, visible),
      ),
    );

    if (multiline) {
      return SizedBox(
        height: 180,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: textField),
            const SizedBox(width: 5),
            SizedBox(
              width: 73,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: fieldOrderButton(
                          key: ValueKey('cardFieldUp-${field.id}'),
                          icon: Icons.keyboard_arrow_up,
                          tooltip: 'Переместить поле вверх',
                          onTap: index > 0
                              ? () => moveCardField(field.id, -1)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 5),
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: fieldOrderButton(
                          key: ValueKey('cardFieldDelete-${field.id}'),
                          icon: Icons.delete_outline,
                          tooltip: 'Удалить поле из списка',
                          onTap: () => removeCardField(field.id),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: fieldOrderButton(
                      key: ValueKey('cardFieldDown-${field.id}'),
                      icon: Icons.keyboard_arrow_down,
                      tooltip: 'Переместить поле вниз',
                      onTap: index >= 0 && index < fieldOrder.length - 1
                          ? () => moveCardField(field.id, 1)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: SizedBox(height: 45, child: textField)),
          const SizedBox(width: 5),
          SizedBox(
            width: 34,
            child: Column(
              children: [
                fieldOrderButton(
                  key: ValueKey('cardFieldUp-${field.id}'),
                  icon: Icons.keyboard_arrow_up,
                  tooltip: 'Переместить поле вверх',
                  onTap: index > 0 ? () => moveCardField(field.id, -1) : null,
                  expanded: true,
                ),
                const SizedBox(height: 3),
                fieldOrderButton(
                  key: ValueKey('cardFieldDown-${field.id}'),
                  icon: Icons.keyboard_arrow_down,
                  tooltip: 'Переместить поле вниз',
                  onTap: index >= 0 && index < fieldOrder.length - 1
                      ? () => moveCardField(field.id, 1)
                      : null,
                  expanded: true,
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: 38,
            child: fieldOrderButton(
              key: ValueKey('cardFieldDelete-${field.id}'),
              icon: Icons.delete_outline,
              tooltip: 'Удалить поле из списка',
              onTap: () => removeCardField(field.id),
            ),
          ),
        ],
      ),
    );
  }

  Widget fieldOrderButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool expanded = false,
  }) {
    final button = Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Material(
          key: key,
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xfff4f4f4), Color(0xff969696)],
                ),
                border: Border.all(color: const Color(0xff676767)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Center(
                child: Icon(icon, size: 19, color: const Color(0xff303030)),
              ),
            ),
          ),
        ),
      ),
    );
    return expanded ? Expanded(child: button) : button;
  }

  void moveCardField(String fieldId, int offset) {
    final oldIndex = fieldOrder.indexOf(fieldId);
    final newIndex = oldIndex + offset;
    if (oldIndex < 0 || newIndex < 0 || newIndex >= fieldOrder.length) return;
    rememberCurrentAction();
    setState(() {
      fieldOrder.removeAt(oldIndex);
      fieldOrder.insert(newIndex, fieldId);
    });
  }

  void removeCardField(String fieldId) {
    if (!fieldOrder.contains(fieldId)) return;
    rememberCurrentAction();
    setState(() {
      fieldOrder.remove(fieldId);
      hiddenFieldIds.add(fieldId);
    });
  }

  Widget buildCardAttachmentsEditor() {
    final active = activeAttachments;
    if (active.isEmpty) return const SizedBox.shrink();
    final files = active.where(
      (attachment) => !isEditorInlineImage(attachment.fileName),
    );
    final images = active.where(
      (attachment) => isEditorInlineImage(attachment.fileName),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final attachment in files)
          Material(
            key: ValueKey('cardEditorAttachment-${attachment.fileName}'),
            color: Colors.transparent,
            child: InkWell(
              onTap: () => previewEditorAttachment(attachment),
              onSecondaryTap: () => previewEditorAttachment(attachment),
              onLongPress: () => previewEditorAttachment(attachment),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 19),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        attachment.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        for (final attachment in images)
          editorInlineImageAttachment(attachment),
      ],
    );
  }

  bool isEditorInlineImage(String fileName) {
    final lower = fileName.toLowerCase();
    return const [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
    ].any(lower.endsWith);
  }

  Widget editorInlineImageAttachment(SecretAttachment attachment) {
    return FutureBuilder<Uint8List>(
      future: editorAttachmentBytes(attachment),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return Padding(
          key: ValueKey('cardEditorInlineAttachment-${attachment.fileName}'),
          padding: const EdgeInsets.only(top: 10),
          child: Material(
            color: editorBackgroundColor.withValues(alpha: 0.9),
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xff82929d)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: InkWell(
              onTap: () => previewEditorAttachment(attachment),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (bytes == null)
                      const SizedBox(
                        height: 72,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: Image.memory(
                          bytes,
                          width: double.infinity,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox(
                            height: 72,
                            child: Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void saveCard() {
    Navigator.pop(
      context,
      SecretItem(
        id: widget.initial?.id ?? makeId('item'),
        templateId: templateId,
        title: title.text.trim().isEmpty ? template.name : title.text.trim(),
        category: category.text.trim(),
        colorId: colorId,
        values: {
          for (final field in allCardFields)
            if (cardFieldValueIsPopulated(
              field.type == 'url'
                  ? normalizeUrlInput(values[field.id]?.text ?? '')
                  : (values[field.id]?.text.trim() ?? ''),
            ))
              field.id: field.type == 'url'
                  ? normalizeUrlInput(values[field.id]?.text ?? '')
                  : (values[field.id]?.text.trim() ?? ''),
        },
        attachments: attachments,
        modifiedAt: DateTime.now().toUtc(),
        hitCount: widget.initial?.hitCount ?? 0,
        iconId: iconId,
        backgroundImageBase64: backgroundImageBase64,
        spbColor: spbColor,
        fieldOrder: fieldOrder,
        hiddenFieldIds: hiddenFieldIds,
      ),
    );
  }

  Widget categoryEditor() {
    final dropdownValues = <String>{
      emptyCategoryValue,
      ...widget.categories,
      newCategoryValue,
    }.toList();
    final selectedValue = dropdownValues.contains(categorySelection)
        ? categorySelection
        : newCategoryValue;
    return Column(
      children: [
        SizedBox(
          height: 45,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: selectedValue,
            decoration: const InputDecoration(
              labelText: 'Папка / каталог',
              hintText: 'Место размещения карточки',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            ),
            items: [
              const DropdownMenuItem(
                value: emptyCategoryValue,
                child: Text('Без категории'),
              ),
              ...widget.categories.map(
                (entry) => DropdownMenuItem(value: entry, child: Text(entry)),
              ),
              const DropdownMenuItem(
                value: newCategoryValue,
                child: Text('Создать новую категорию'),
              ),
            ],
            onChanged: (value) {
              rememberCurrentAction();
              setState(() {
                categorySelection = value ?? emptyCategoryValue;
                if (categorySelection == emptyCategoryValue) {
                  category.clear();
                } else if (categorySelection != newCategoryValue) {
                  category.text = categorySelection;
                }
              });
            },
          ),
        ),
        if (selectedValue == newCategoryValue) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 45,
            child: TextField(
              controller: category,
              onTap: rememberCurrentAction,
              contextMenuBuilder: desktopCardTextContextMenu,
              decoration: const InputDecoration(
                labelText: 'Новая папка / каталог',
                hintText: 'Например: Финансы / Банк',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
        ],
      ],
    );
  }

  TextInputType keyboardTypeForField(FieldDefinition field) {
    if (field.type == 'url') return TextInputType.url;
    if (field.type == 'date') return TextInputType.datetime;
    return TextInputType.text;
  }

  List<TextInputFormatter>? inputFormattersForField(FieldDefinition field) {
    if (field.type == 'date') return [DateTextInputFormatter()];
    return null;
  }

  String? hintTextForField(FieldDefinition field) {
    if (field.type == 'url') return 'https://example.com';
    if (field.type == 'date') return 'дд.мм.гггг';
    return null;
  }

  Widget? fieldSuffixIcon(
    FieldDefinition field,
    TextEditingController controller,
    bool visible,
  ) {
    final buttons = <Widget>[];
    if (field.type == 'date') {
      buttons.add(
        IconButton(
          tooltip: 'Выбрать дату',
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: () => pickDateForField(controller),
        ),
      );
    }
    if (fieldDefinitionIsSecret(field)) {
      buttons.add(
        IconButton(
          tooltip: visible ? 'Скрыть' : 'Показать',
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() {
            visible
                ? visibleSecrets.remove(field.id)
                : visibleSecrets.add(field.id);
          }),
        ),
      );
    }
    if (buttons.isEmpty) return null;
    if (buttons.length == 1) return buttons.single;
    return SizedBox(
      width: 96,
      child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
    );
  }

  Future<void> pickDateForField(TextEditingController controller) async {
    final initialDate = parseDateInput(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.year < 1900 || initialDate.year > 2200
          ? DateTime.now()
          : initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (picked == null) return;
    rememberCurrentAction();
    setState(() => controller.text = formatDateInput(picked));
  }

  List<SecretAttachment> get activeAttachments => attachments
      .where(
        (attachment) => !attachment.deleted && attachment.decodeError == null,
      )
      .toList(growable: false);

  Future<Uint8List> editorAttachmentBytes(SecretAttachment attachment) async {
    if (attachment.pendingBytes != null) {
      return Uint8List.fromList(attachment.pendingBytes!);
    }
    final loader = widget.loadAttachmentBytes;
    if (loader == null || attachment.id.isEmpty) return Uint8List(0);
    return Uint8List.fromList(await loader(attachment.id));
  }

  Future<void> previewEditorAttachment(SecretAttachment attachment) async {
    try {
      final bytes = await editorAttachmentBytes(attachment);
      if (bytes.isEmpty) return;
      await openAttachmentBytesWithSystem(attachment.fileName, bytes);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть вложение: $error')),
      );
    }
  }

  Future<SecretAttachment?> chooseEditorAttachment(String titleText) async {
    final source = activeAttachments;
    if (source.isEmpty) return null;
    if (source.length == 1) return source.single;
    return showDialog<SecretAttachment>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(titleText),
        children: [
          for (final attachment in source)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, attachment),
              child: Text(attachment.fileName),
            ),
        ],
      ),
    );
  }

  Future<void> chooseAttachmentToExport() async {
    final selected = await chooseEditorAttachment('Сохранить вложение');
    if (selected != null) await exportAttachment(selected);
  }

  Future<void> chooseAttachmentToDelete() async {
    final selected = await chooseEditorAttachment('Удалить вложение');
    if (selected == null || !mounted) return;
    rememberCurrentAction();
    setState(() {
      attachments = [
        for (final attachment in attachments)
          if (identical(attachment, selected))
            attachment.copyWith(deleted: true)
          else
            attachment,
      ];
    });
  }

  Future<void> addAttachment() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return;
    rememberCurrentAction();
    setState(() {
      attachments = [
        ...attachments,
        SecretAttachment(
          id: '',
          fileName: file.name,
          size: bytes.length,
          pendingBytes: bytes,
        ),
      ];
    });
  }

  Future<void> pickBackgroundImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return;
    rememberCurrentAction();
    setState(() => backgroundImageBase64 = base64Encode(bytes));
  }

  Future<void> replaceAttachment(SecretAttachment attachment) async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final file = picked?.files.single;
    if (file == null) return;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return;
    rememberCurrentAction();
    setState(() {
      attachments = attachments
          .map(
            (entry) => entry.id == attachment.id
                ? entry.copyWith(
                    fileName: file.name,
                    size: bytes.length,
                    decodeError: null,
                    pendingBytes: bytes,
                  )
                : entry,
          )
          .toList();
    });
  }

  Future<void> exportAttachment(SecretAttachment attachment) async {
    try {
      final data = await editorAttachmentBytes(attachment);
      if (data.isEmpty) return;
      final export = gallerySafeAttachmentExport(attachment.fileName, data);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить вложение',
        fileName: export.fileName,
        bytes: export.bytes,
      );
      if (path != null && !Platform.isAndroid && !Platform.isIOS) {
        final file = File(path);
        if (!file.existsSync() || file.lengthSync() != data.length) {
          await file.writeAsBytes(data, flush: true);
        }
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить вложение: $error')),
      );
    }
  }
}

class TemplatePreviewDialog extends StatelessWidget {
  const TemplatePreviewDialog({required this.template, super.key});

  final CardTemplate template;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final fullScreen = Platform.isAndroid || media.width < 700;
    final backgroundColor = templateDisplayBackground(template);
    Uint8List? customIconBytes;
    try {
      final encoded = template.embeddedIconBase64;
      if (encoded != null) customIconBytes = base64Decode(encoded);
    } catch (_) {
      customIconBytes = null;
    }
    return Align(
      alignment: Alignment.center,
      child: Material(
        color: const Color(0xfff4f4f4),
        elevation: 24,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: Color(0xff7f8d98)),
        ),
        child: SizedBox(
          key: const Key('templatePreviewSurface'),
          width: fullScreen ? media.width : min(media.width - 24, 720),
          height: fullScreen ? media.height : min(media.height - 24, 760),
          child: Column(
            children: [
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
                  ),
                  border: Border(bottom: BorderSide(color: Color(0xff7f8d98))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        template.name,
                        key: const Key('templatePreviewTitle'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Закрыть просмотр',
                      child: Material(
                        key: const Key('templatePreviewCloseButton'),
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          child: Ink(
                            width: 38,
                            height: 34,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xffff5a5f), Color(0xffa90000)],
                              ),
                              border: Border.all(
                                color: const Color(0xff56636c),
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ColoredBox(
                  color: backgroundColor,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 112,
                            height: 112,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: const Color(0xff82929d),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(5),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x26000000),
                                  offset: Offset(1, 2),
                                  blurRadius: 5,
                                ),
                              ],
                            ),
                            child: customIconBytes == null
                                ? templateIconWidget(
                                    template.iconId,
                                    size: 88,
                                    color: pictogramColorForBackground(
                                      backgroundColor,
                                    ),
                                  )
                                : Image.memory(
                                    customIconBytes,
                                    width: 88,
                                    height: 88,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.medium,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final field in template.fields)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: TextFormField(
                              key: ValueKey('templatePreviewField-${field.id}'),
                              initialValue: '',
                              readOnly: true,
                              minLines: field.type == 'multiline_note' ? 3 : 1,
                              maxLines: field.type == 'multiline_note' ? 5 : 1,
                              decoration: InputDecoration(
                                labelText: field.label,
                                hintText: _fieldTypeLabel(field.type),
                                prefixIcon: Icon(_fieldTypeIcon(field.type)),
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: backgroundColor,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                prefixIconConstraints:
                                    const BoxConstraints.tightFor(
                                  width: 40,
                                  height: 40,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _fieldTypeIcon(String type) => switch (type) {
        'password' || 'custom_secret' => Icons.lock_outline,
        'username' => Icons.person_outline,
        'url' => Icons.link,
        'email' => Icons.email_outlined,
        'phone' => Icons.phone_outlined,
        'date' => Icons.calendar_today_outlined,
        'number' => Icons.numbers,
        'totp' => Icons.timer_outlined,
        'multiline_note' => Icons.notes,
        _ => Icons.text_fields,
      };

  static String _fieldTypeLabel(String type) => switch (type) {
        'password' => 'Пароль',
        'custom_secret' => 'Секрет',
        'username' => 'Логин',
        'url' => 'Сайт',
        'email' => 'Email',
        'phone' => 'Телефон',
        'date' => 'Дата',
        'number' => 'Число',
        'totp' => 'TOTP',
        'multiline_note' => 'Большая строка',
        _ => 'Маленькая строка',
      };
}

class TemplateEditorDialog extends StatefulWidget {
  const TemplateEditorDialog({this.initial, super.key});

  final CardTemplate? initial;

  @override
  State<TemplateEditorDialog> createState() => _TemplateEditorDialogState();
}

class TemplateFieldDraft {
  TemplateFieldDraft(FieldDefinition field)
      : id = field.id,
        type = field.type == 'totp' ? 'url' : field.type,
        label = TextEditingController(text: field.label);

  final String id;
  final TextEditingController label;
  String type;
  bool get secret => fieldTypeIsSecret(type);

  void dispose() => label.dispose();

  FieldDefinition toField() => FieldDefinition(
        id: id,
        label: label.text.trim().isEmpty ? 'Поле' : label.text.trim(),
        type: type,
        secret: secret,
      );
}

class TemplateFieldSnapshot {
  const TemplateFieldSnapshot({
    required this.id,
    required this.label,
    required this.type,
  });

  final String id;
  final String label;
  final String type;
}

class TemplateEditorSnapshot {
  const TemplateEditorSnapshot({
    required this.name,
    required this.iconId,
    required this.colorId,
    required this.categoryPath,
    this.spbColor,
    this.customIconBase64,
    this.customIconFileName,
    required this.fields,
  });

  final String name;
  final String iconId;
  final String colorId;
  final String categoryPath;
  final int? spbColor;
  final String? customIconBase64;
  final String? customIconFileName;
  final List<TemplateFieldSnapshot> fields;

  String get signature => [
        name,
        iconId,
        colorId,
        categoryPath,
        spbColor?.toString() ?? '',
        customIconBase64 ?? '',
        customIconFileName ?? '',
        for (final field in fields)
          '${field.id}\u0001${field.label}\u0001${field.type}',
      ].join('\u0002');
}

class _TemplateEditorDialogState extends State<TemplateEditorDialog> {
  late final TextEditingController name;
  late String iconId;
  late String colorId;
  late String categoryPath;
  bool invalidName = false;
  int? spbColor;
  Uint8List? customIconBytes;
  String? customIconFileName;
  late final List<TemplateFieldDraft> fields;
  final List<TemplateEditorSnapshot> undoHistory = [];
  late String observedName;
  final Map<String, String> observedFieldLabels = {};

  Color get editorBackgroundColor => spbColor == null
      ? colorById(colorId).bg
      : Color(0xff000000 | (spbColor! & 0x00ffffff));

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.initial?.name ?? '');
    final initialIconId = widget.initial?.iconId;
    iconId = initialIconId ?? spbPasswordTemplateIconAsset;
    colorId = widget.initial?.colorId ?? 'neutral';
    categoryPath = widget.initial?.categoryPath ?? '';
    spbColor = widget.initial?.spbColor;
    customIconBytes = widget.initial?.embeddedIconBase64 == null
        ? null
        : base64Decode(widget.initial!.embeddedIconBase64!);
    customIconFileName = widget.initial?.iconFileName;
    final sourceFields = widget.initial?.fields ??
        const [
          FieldDefinition(id: 'username', label: 'Логин', type: 'username'),
          FieldDefinition(
            id: 'password',
            label: 'Пароль',
            type: 'password',
            secret: true,
          ),
          FieldDefinition(
            id: 'notes',
            label: 'Заметки',
            type: 'multiline_note',
          ),
        ];
    fields = [
      for (final field in sourceFields.where(
        (field) => field.id != spbDescriptionFieldId,
      ))
        TemplateFieldDraft(field),
    ];
    observedName = name.text;
    for (final field in fields) {
      observedFieldLabels[field.id] = field.label.text;
    }
  }

  @override
  void dispose() {
    name.dispose();
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final media = mediaQuery.size;
    // Keyboard avoidance is owned by the dialog route. Keep the editor surface
    // stable and let its scroll view reveal the focused control.
    final availableHeight = media.height;
    final fullScreen = Platform.isAndroid || media.width < 700;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.zero,
      child: Align(
        alignment: Alignment.center,
        child: Material(
          color: const Color(0xfff4f4f4),
          elevation: 24,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: Color(0xff7f8d98)),
          ),
          child: SizedBox(
            key: const Key('templateEditorSurface'),
            width: fullScreen ? media.width : min(media.width - 24, 720),
            height:
                fullScreen ? availableHeight : max(0.0, availableHeight - 24),
            child: Column(
              children: [
                templateTitleBar(),
                Expanded(
                  child: ColoredBox(
                    color: editorBackgroundColor,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        14,
                        14,
                        12 + mediaQuery.viewInsets.bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          templateIconPicker(),
                          const SizedBox(height: 12),
                          templateColorPicker(),
                          const SizedBox(height: 10),
                          templateNameField(),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text(
                                'Поля',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const Spacer(),
                              TextButton.icon(
                                key: const Key('templateAddFieldButton'),
                                onPressed: addField,
                                icon: const Icon(Icons.add),
                                label: const Text('Добавить поле'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...fields.map(fieldEditor),
                        ],
                      ),
                    ),
                  ),
                ),
                templateBottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget templateTitleBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xff7f8d98))),
      ),
      child: TextField(
        key: const Key('templateTitleNameField'),
        controller: name,
        readOnly: true,
        onChanged: rememberNameChange,
        style: const TextStyle(fontSize: 18),
        decoration: const InputDecoration(
          hintText: 'Название шаблона',
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget templateNameField() {
    return EnsureVisibleWhenFocused(
      child: SizedBox(
        height: 45,
        child: TextField(
          key: const Key('templateNameField'),
          controller: name,
          onChanged: (value) {
            rememberNameChange(value);
            if (invalidName) setState(() => invalidName = false);
          },
          decoration: InputDecoration(
            labelText: 'Название шаблона',
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: editorBackgroundColor,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            errorText: invalidName ? 'Название обязательно' : null,
          ),
        ),
      ),
    );
  }

  Widget templateIconPicker() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          key: const Key('templateBoundIcon'),
          width: 112,
          height: 112,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xff82929d), width: 2),
            borderRadius: BorderRadius.circular(5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                offset: Offset(1, 2),
                blurRadius: 5,
              ),
            ],
          ),
          child: customIconBytes == null
              ? templateIconWidget(
                  iconId,
                  size: 88,
                  color: pictogramColorForBackground(editorBackgroundColor),
                )
              : Image.memory(
                  customIconBytes!,
                  width: 88,
                  height: 88,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Выбрать иконку',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 7),
              LayoutBuilder(
                builder: (context, constraints) {
                  final buttons = [
                    templatePickerButton(
                      key: const Key('templateSpbDefaultButton'),
                      label: 'SPB',
                      icon: Icons.photo_library_outlined,
                      tooltip: 'Иконки из базы SPB',
                      onPressed: pickSpbIcon,
                    ),
                    templatePickerButton(
                      key: const Key('templatePictogramsButton'),
                      label: 'пиктограммы',
                      icon: Icons.category_outlined,
                      tooltip: 'Выбрать пиктограмму',
                      onPressed: pickPictogram,
                    ),
                    templatePickerButton(
                      key: const Key('templateIconsButton'),
                      label: 'сторонние',
                      icon: Icons.public_outlined,
                      tooltip: 'Иконки Visual Studio',
                      onPressed: pickThirdPartyIcon,
                    ),
                    templatePickerButton(
                      key: const Key('templateUploadIconButton'),
                      label: 'загрузить иконку',
                      icon: Icons.upload_file_outlined,
                      tooltip: 'Загрузить файл PNG или ICO',
                      onPressed: pickCustomIconFile,
                    ),
                  ];
                  if (constraints.maxWidth >= 420) {
                    return Row(
                      children: [
                        for (var index = 0;
                            index < buttons.length;
                            index++) ...[
                          if (index > 0) const SizedBox(width: 7),
                          Expanded(child: buttons[index]),
                        ],
                      ],
                    );
                  }
                  final width = (constraints.maxWidth - 7) / 2;
                  return Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final button in buttons)
                        SizedBox(width: width, child: button),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget templatePickerButton({
    required Key key,
    required String label,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onPressed == null ? 0.48 : 1,
        child: Material(
          key: key,
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(5),
            child: Ink(
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xfff4f4f4), Color(0xff969696)],
                ),
                border: Border.all(color: const Color(0xff676767)),
                borderRadius: BorderRadius.circular(5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-1, -1),
                    blurRadius: 0.5,
                  ),
                  BoxShadow(
                    color: Color(0x66000000),
                    offset: Offset(1, 1),
                    blurRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: const Color(0xff303030)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xff303030),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget templateColorPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Цвет шаблона',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final color in templateColorPalette)
              Tooltip(
                message: color.label,
                child: InkWell(
                  key: ValueKey('templateColor-${color.id}'),
                  onTap: () {
                    if (colorId == color.id) return;
                    rememberCurrentAction();
                    setState(() {
                      colorId = color.id;
                      spbColor = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 30,
                    height: 27,
                    decoration: BoxDecoration(
                      color: color.bg,
                      border: Border.all(
                        color: colorId == color.id
                            ? const Color(0xff253d4c)
                            : const Color(0xff8b969d),
                        width: colorId == color.id ? 2.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1f000000),
                          offset: Offset(1, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    child: colorId == color.id
                        ? const Icon(Icons.check, size: 17)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget templateBottomBar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: const BoxDecoration(
        color: Color(0xffdce8f1),
        border: Border(top: BorderSide(color: Color(0xff7f8d98))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          templateActionButton(
            key: const Key('templateUndoButton'),
            icon: Icons.undo,
            tooltip: 'Отменить последнее действие',
            colors: const [Color(0xffffdc58), Color(0xffc58a00)],
            onTap: undoHistory.isEmpty ? null : undoLastAction,
          ),
          const SizedBox(width: 6),
          templateActionButton(
            key: const Key('templateSaveButton'),
            icon: Icons.check,
            tooltip: 'Сохранить шаблон',
            colors: const [Color(0xff5bc96d), Color(0xff08772f)],
            onTap: saveTemplate,
          ),
          const SizedBox(width: 6),
          templateActionButton(
            key: const Key('templateCloseButton'),
            icon: Icons.close,
            tooltip: 'Закрыть без сохранения',
            colors: const [Color(0xffff5a5f), Color(0xffa90000)],
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget templateActionButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required List<Color> colors,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.55 : 1,
        child: Material(
          key: key,
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              width: 38,
              height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: colors,
                ),
                border: Border.all(color: const Color(0xff56636c)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }

  Widget fieldEditor(TemplateFieldDraft field) {
    return EnsureVisibleWhenFocused(
      child: Card(
        key: ValueKey('templateField-${field.id}'),
        elevation: 0,
        color: editorBackgroundColor,
        surfaceTintColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        key: ValueKey('templateFieldName-${field.id}'),
                        controller: field.label,
                        onChanged: (value) =>
                            rememberFieldLabelChange(field.id, value),
                        decoration: InputDecoration(
                          labelText: 'Название поля',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: editorBackgroundColor,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  fieldMoveButtons(field),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('templateFieldType-${field.id}'),
                        initialValue: field.type,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Тип',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: editorBackgroundColor,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'text',
                            child: Text('Маленькая строка'),
                          ),
                          DropdownMenuItem(
                            value: 'username',
                            child: Text('Логин'),
                          ),
                          DropdownMenuItem(
                            value: 'multiline_note',
                            child: Text('Большая строка'),
                          ),
                          DropdownMenuItem(
                            value: 'password',
                            child: Text('Пароль'),
                          ),
                          DropdownMenuItem(
                            value: 'custom_secret',
                            child: Text('Секрет'),
                          ),
                          DropdownMenuItem(
                            value: 'number',
                            child: Text('Число'),
                          ),
                          DropdownMenuItem(
                            value: 'email',
                            child: Text('Email'),
                          ),
                          DropdownMenuItem(
                            value: 'phone',
                            child: Text('Телефон'),
                          ),
                          DropdownMenuItem(value: 'date', child: Text('Дата')),
                          DropdownMenuItem(value: 'url', child: Text('WEB')),
                        ],
                        onChanged: (value) {
                          rememberCurrentAction();
                          setState(() => field.type = value ?? 'text');
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  fieldMoveButton(
                    key: ValueKey('templateFieldDelete-${field.id}'),
                    tooltip: 'Удалить поле',
                    icon: Icons.delete_outline,
                    height: 36,
                    onTap: fields.length <= 1 ? null : () => removeField(field),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget fieldMoveButtons(TemplateFieldDraft field) {
    final index = fields.indexOf(field);
    return SizedBox(
      width: 31,
      height: 36,
      child: Column(
        children: [
          fieldMoveButton(
            key: ValueKey('templateFieldUp-${field.id}'),
            icon: Icons.keyboard_arrow_up,
            tooltip: 'Переместить поле вверх',
            onTap: index > 0 ? () => moveField(field, -1) : null,
          ),
          const SizedBox(height: 2),
          fieldMoveButton(
            key: ValueKey('templateFieldDown-${field.id}'),
            icon: Icons.keyboard_arrow_down,
            tooltip: 'Переместить поле вниз',
            onTap: index < fields.length - 1 ? () => moveField(field, 1) : null,
          ),
        ],
      ),
    );
  }

  Widget fieldMoveButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    double height = 17,
  }) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Material(
          key: key,
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(3),
            child: Ink(
              width: 31,
              height: height,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xfff4f4f4), Color(0xff8d8d8d)],
                ),
                border: Border.all(color: const Color(0xff676767)),
                borderRadius: BorderRadius.circular(3),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(-1, -1),
                    blurRadius: 0.5,
                  ),
                  BoxShadow(
                    color: Color(0x66000000),
                    offset: Offset(1, 1),
                    blurRadius: 1,
                  ),
                ],
              ),
              child: Icon(icon, size: 19, color: const Color(0xff303030)),
            ),
          ),
        ),
      ),
    );
  }

  void addField() {
    rememberCurrentAction();
    setState(() {
      final field = TemplateFieldDraft(
        FieldDefinition(id: makeId('field'), label: 'Новое поле', type: 'text'),
      );
      fields.add(field);
      observedFieldLabels[field.id] = field.label.text;
    });
  }

  void removeField(TemplateFieldDraft field) {
    rememberCurrentAction();
    setState(() {
      fields.remove(field);
      observedFieldLabels.remove(field.id);
      field.dispose();
    });
  }

  void moveField(TemplateFieldDraft field, int offset) {
    final oldIndex = fields.indexOf(field);
    final newIndex = oldIndex + offset;
    if (oldIndex < 0 || newIndex < 0 || newIndex >= fields.length) return;
    rememberCurrentAction();
    setState(() {
      fields.removeAt(oldIndex);
      fields.insert(newIndex, field);
    });
  }

  TemplateEditorSnapshot currentSnapshot({
    String? nameOverride,
    String? fieldIdOverride,
    String? fieldLabelOverride,
  }) =>
      TemplateEditorSnapshot(
        name: nameOverride ?? name.text,
        iconId: iconId,
        colorId: colorId,
        categoryPath: categoryPath,
        spbColor: spbColor,
        customIconBase64:
            customIconBytes == null ? null : base64Encode(customIconBytes!),
        customIconFileName: customIconFileName,
        fields: [
          for (final field in fields)
            TemplateFieldSnapshot(
              id: field.id,
              label: field.id == fieldIdOverride
                  ? fieldLabelOverride ?? field.label.text
                  : field.label.text,
              type: field.type,
            ),
        ],
      );

  void rememberCurrentAction() {
    rememberSnapshot(currentSnapshot());
  }

  void rememberNameChange(String value) {
    if (value == observedName) return;
    rememberSnapshot(currentSnapshot(nameOverride: observedName));
    observedName = value;
  }

  void rememberFieldLabelChange(String fieldId, String value) {
    final previous = observedFieldLabels[fieldId] ?? '';
    if (value == previous) return;
    rememberSnapshot(
      currentSnapshot(fieldIdOverride: fieldId, fieldLabelOverride: previous),
    );
    observedFieldLabels[fieldId] = value;
  }

  void rememberSnapshot(TemplateEditorSnapshot snapshot) {
    if (undoHistory.isNotEmpty &&
        undoHistory.last.signature == snapshot.signature) {
      return;
    }
    setState(() {
      undoHistory.add(snapshot);
      if (undoHistory.length > 200) undoHistory.removeAt(0);
    });
  }

  void undoLastAction() {
    if (undoHistory.isEmpty) return;
    final snapshot = undoHistory.removeLast();
    setState(() {
      name.text = snapshot.name;
      iconId = snapshot.iconId;
      colorId = snapshot.colorId;
      categoryPath = snapshot.categoryPath;
      spbColor = snapshot.spbColor;
      customIconBytes = snapshot.customIconBase64 == null
          ? null
          : base64Decode(snapshot.customIconBase64!);
      customIconFileName = snapshot.customIconFileName;
      for (final field in fields) {
        field.dispose();
      }
      fields
        ..clear()
        ..addAll(
          snapshot.fields.map(
            (field) => TemplateFieldDraft(
              FieldDefinition(
                id: field.id,
                label: field.label,
                type: field.type,
                secret: fieldTypeIsSecret(field.type),
              ),
            ),
          ),
        );
      observedName = snapshot.name;
      observedFieldLabels
        ..clear()
        ..addEntries(
          snapshot.fields.map((field) => MapEntry(field.id, field.label)),
        );
    });
  }

  void changeIcon(String selectedIconId) {
    if (selectedIconId == iconId) return;
    rememberCurrentAction();
    setState(() {
      iconId = selectedIconId;
      customIconBytes = null;
      customIconFileName = null;
    });
  }

  Future<void> pickPictogram() async {
    final picked = await showIconPickerDialog(context, iconId);
    if (picked != null && mounted) changeIcon(picked);
  }

  Future<void> pickSpbIcon() async {
    final picked = await showSpbOriginalIconPickerDialog(context, iconId);
    if (picked != null && mounted) changeIcon(picked);
  }

  Future<void> pickThirdPartyIcon() async {
    final picked = await showThirdPartyIconPickerDialog(context);
    if (picked == null || !mounted) return;
    final bytes = thirdPartyIconPngs[picked];
    if (bytes == null) return;
    applyCustomIcon(bytes, picked.split('/').last);
  }

  Future<void> pickCustomIconFile() async {
    final picked = await pickUserIconFile(context);
    if (picked == null || !mounted) return;
    applyCustomIcon(picked.bytes, picked.fileName);
  }

  void applyCustomIcon(Uint8List pngBytes, String fileName) {
    rememberCurrentAction();
    setState(() {
      iconId = SpbWalletDatabase.makeId();
      customIconBytes = pngBytes;
      customIconFileName = fileName;
    });
  }

  void saveTemplate() {
    if (name.text.trim().isEmpty) {
      setState(() => invalidName = true);
      return;
    }
    Navigator.pop(
      context,
      CardTemplate(
        id: widget.initial?.id ?? makeId('tpl'),
        name: name.text.trim().isEmpty ? 'Новый шаблон' : name.text.trim(),
        iconId: iconId,
        colorId: colorId,
        categoryPath: categoryPath,
        spbColor: spbColor,
        builtIn: widget.initial?.builtIn ?? false,
        embeddedIconBase64:
            customIconBytes == null ? null : base64Encode(customIconBytes!),
        iconFileName: customIconFileName,
        fields: fields.map((field) => field.toField()).toList(),
      ),
    );
  }
}

class ColorPicker extends StatelessWidget {
  const ColorPicker({
    required this.value,
    required this.onChanged,
    this.label = 'Цвет карточки',
    this.keyPrefix = 'cardColor',
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final color in templateColorPalette)
              Tooltip(
                message: color.label,
                child: InkWell(
                  onTap: () => onChanged(color.id),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    key: ValueKey('$keyPrefix-${color.id}'),
                    width: 30,
                    height: 27,
                    decoration: BoxDecoration(
                      color: color.bg,
                      border: Border.all(
                        color: color.id == value
                            ? const Color(0xff253d4c)
                            : const Color(0xff8b969d),
                        width: color.id == value ? 2.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1f000000),
                          offset: Offset(1, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    child: color.id == value
                        ? const Icon(Icons.check, size: 17)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
