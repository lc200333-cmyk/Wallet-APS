import 'template_folders.dart';

/// Where the templates of a base sit: the folder of every template and the
/// template folders' own settings. A new base takes this layout from the
/// base it was saved from. Only names and folders are kept, no card data.
class TemplateLayout {
  const TemplateLayout({required this.templates, required this.folders});

  final List<TemplateLayoutEntry> templates;
  final List<TemplateLayoutFolder> folders;

  Map<String, Object?> toJson() => {
        'version': 1,
        'templates': [for (final entry in templates) entry.toJson()],
        'folders': [for (final folder in folders) folder.toJson()],
      };

  static TemplateLayout? fromJson(Object? json) {
    if (json is! Map || json['version'] != 1) return null;
    final templates = json['templates'];
    final folders = json['folders'];
    if (templates is! List || folders is! List) return null;
    return TemplateLayout(
      templates: [
        for (final entry in templates)
          if (TemplateLayoutEntry.fromJson(entry) case final parsed?) parsed,
      ],
      folders: [
        for (final folder in folders)
          if (TemplateLayoutFolder.fromJson(folder) case final parsed?) parsed,
      ],
    );
  }

  /// Number of template folders the templates are spread over.
  int get folderCount => {for (final entry in templates) entry.folder}.length;
}

class TemplateLayoutEntry {
  const TemplateLayoutEntry({
    required this.id,
    required this.name,
    this.categoryPath = '',
  });

  /// Template ID; templates of a new base share it with the standard set.
  final String id;

  /// Stored name, "Папка: название" or a plain name.
  final String name;
  final String categoryPath;

  String get folder => templateFolderFor(name, categoryPath);

  /// The name without its folder, used when the IDs differ.
  String get label => templateLabelInFolder(name, folder);

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        if (categoryPath.isNotEmpty) 'categoryPath': categoryPath,
      };

  static TemplateLayoutEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final categoryPath = json['categoryPath'] ?? '';
    if (id is! String || name is! String || categoryPath is! String) {
      return null;
    }
    if (id.isEmpty || name.trim().isEmpty) return null;
    return TemplateLayoutEntry(
        id: id.toUpperCase(), name: name, categoryPath: categoryPath);
  }
}

class TemplateLayoutFolder {
  const TemplateLayoutFolder({
    required this.name,
    required this.iconId,
    required this.colorId,
    this.hidden = false,
  });

  final String name;
  final String iconId;
  final String colorId;
  final bool hidden;

  Map<String, Object?> toJson() => {
        'name': name,
        'iconId': iconId,
        'colorId': colorId,
        if (hidden) 'hidden': true,
      };

  static TemplateLayoutFolder? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final iconId = json['iconId'];
    final colorId = json['colorId'];
    if (name is! String || iconId is! String || colorId is! String) {
      return null;
    }
    if (name.trim().isEmpty) return null;
    return TemplateLayoutFolder(
      name: name,
      iconId: iconId,
      colorId: colorId,
      hidden: json['hidden'] == true,
    );
  }
}
