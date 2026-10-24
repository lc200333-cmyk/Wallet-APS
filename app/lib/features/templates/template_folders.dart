const defaultTemplateFolders = [
  'Банковские счета',
  'Другие',
  'Заметки',
  'Интернет',
  'Карточки',
  'Компьютеры',
  'Кредитная карта',
  'Личные',
  'Путешествия',
  'Семейные',
  'Финансы',
];

String canonicalTemplateFolder(String value) {
  final trimmed = value.trim();
  for (final folder in defaultTemplateFolders) {
    if (folder.toLowerCase() == trimmed.toLowerCase()) return folder;
  }
  return trimmed;
}

/// Legacy names keep their stored text until an explicit editor save.
String templateCategoryPathFor(String name, String categoryPath) {
  final colon = name.indexOf(':');
  if (colon > 0 &&
      name.substring(0, colon).trim().isNotEmpty &&
      name.substring(colon + 1).trim().isNotEmpty) {
    return canonicalTemplateFolder(name.substring(0, colon));
  }
  return categoryPath;
}

String templateFolderFor(String name, String categoryPath) {
  final colon = name.indexOf(':');
  if (colon > 0 && name.substring(0, colon).trim().isNotEmpty) {
    return canonicalTemplateFolder(name.substring(0, colon));
  }
  final parts = categoryPath.split('/').map((part) => part.trim());
  final category = parts.where((part) => part.isNotEmpty).firstOrNull;
  if (category != null) return canonicalTemplateFolder(category);
  return 'Другие';
}

String templateLabelInFolder(String name, String folder) {
  final colon = name.indexOf(':');
  if (colon > 0 &&
      canonicalTemplateFolder(name.substring(0, colon)) == folder) {
    final label = name.substring(colon + 1).trim();
    if (label.isNotEmpty) return label;
  }
  return name;
}
