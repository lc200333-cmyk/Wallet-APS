part of '../../main.dart';

/// Colour pair of a stored palette colour in a modern skin.
SkinTilePair skinTileForPalette(WalletSkinTokens t, PaletteColor color) =>
    color.id == 'custom'
        ? t.customTile(color.bg)
        : t.tileFor(color.id, custom: color.bg);

/// A square slot holding an icon of any kind. The icon stands directly on
/// the window background, so a transparent icon shows the light or dark
/// surface behind it rather than a coloured tile.
Widget skinIconTile({
  required Widget icon,
  required double size,
  Key? key,
}) =>
    Container(
      key: key,
      width: size,
      height: size,
      alignment: Alignment.center,
      child: SizedBox.square(
        dimension: size * 0.9,
        child: FittedBox(fit: BoxFit.contain, child: icon),
      ),
    );

/// "Не сохранено" chip, the only new indicator of the Light and Dark skins.
class UnsavedChip extends StatelessWidget {
  const UnsavedChip({super.key});

  @override
  Widget build(BuildContext context) {
    final t = WalletSkinTokens.of(context);
    return Semantics(
      label: 'Есть несохранённые изменения',
      excludeSemantics: true,
      child: Container(
        key: const Key('unsavedChip'),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: t.warningContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit, size: 12, color: t.warning),
            const SizedBox(width: 4),
            Text(
              'Не сохранено',
              style: TextStyle(
                color: t.warning,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _ModernWideShell on _VaultShellState {
  bool get modernTouch => defaultTargetPlatform == TargetPlatform.android;

  SkinTilePair skinTileForItem(SecretItem item) => skinTileForPalette(
      skinTokens, itemDisplayColor(item, templateFor(item.templateId)));

  SkinTilePair skinTileForFolder(String? colorId) {
    final t = skinTokens;
    if (colorId == null || colorId.isEmpty) return t.folderTile;
    return skinTileForPalette(t, colorById(colorId));
  }

  SkinTilePair skinTileForTemplate(CardTemplate template) {
    final t = skinTokens;
    if (template.spbColor != null) {
      return t.customTile(templateDisplayBackground(template));
    }
    return skinTileForPalette(t, colorById(template.colorId));
  }

  /// Toolbar of the wide Light and Dark shells (section 10.1).
  Widget buildModernToolbar() {
    final t = skinTokens;
    final height = modernTouch ? 56.0 : 50.0;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: t.toolbar,
        border: Border(bottom: BorderSide(color: t.outline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: buildModernSearchField(
                  height: modernTouch ? 40 : 34,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ...buildModernHeaderButtons(dimension: modernTouch ? 48 : 34),
        ],
      ),
    );
  }

  /// Undo and exit buttons shared by the wide toolbar and narrow headers.
  List<Widget> buildModernHeaderButtons({required double dimension}) {
    final t = skinTokens;
    final iconSize = dimension >= 48 ? 24.0 : 20.0;
    return [
      SizedBox(
        key: spbSessionUndoButtonKey,
        width: dimension,
        height: dimension,
        child: IconButton(
          tooltip: 'Отменить изменения этой сессии',
          padding: EdgeInsets.zero,
          icon: Icon(Icons.undo, size: iconSize, color: t.onSurfaceVariant),
          onPressed: showSessionUndoMenu,
        ),
      ),
      const SizedBox(width: 4),
      SizedBox(
        width: dimension,
        height: dimension,
        child: IconButton(
          key: const Key('spbForceCloseButton'),
          tooltip: 'Сохранить базу и закрыть программу',
          padding: EdgeInsets.zero,
          icon: Icon(Icons.power_settings_new, size: iconSize, color: t.error),
          onPressed: exitApplication,
        ),
      ),
    ];
  }

  /// Search field with the clear button and the exact-search chip.
  Widget buildModernSearchField({required double height}) {
    final t = skinTokens;
    final radius = BorderRadius.circular(height / 2);
    final exact = spbExactSearch;
    final chip = Tooltip(
      message: 'Точное совпадение',
      child: Material(
        key: const Key('spbSubmitSearchButton'),
        color: exact ? t.primaryContainer : Colors.transparent,
        shape: StadiumBorder(
          side: exact ? BorderSide.none : BorderSide(color: t.outline),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => submitExactSpbSearch(searchController.text),
          child: SizedBox(
            height: 24,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                child: Text(
                  'Точно',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: exact ? t.onPrimaryContainer : t.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return SizedBox(
      height: height,
      child: TextField(
        key: const Key('spbSearchInput'),
        controller: searchController,
        onChanged: updateSpbSearch,
        onSubmitted: submitSpbSearch,
        textInputAction: TextInputAction.search,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(fontSize: height >= 48 ? 16 : 14, color: t.onSurface),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: t.s2,
          hintText: 'Поиск',
          hintStyle: TextStyle(color: t.onSurfaceVariant),
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: t.primary, width: 2),
          ),
          prefixIcon: Icon(Icons.search, size: 18, color: t.onSurfaceVariant),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: searchController.text.isEmpty ? 0 : 28,
                  height: 28,
                  child: buildSearchClearButton(
                    const Key('spbClearSearchButton'),
                  ),
                ),
                chip,
              ],
            ),
          ),
          suffixIconConstraints: BoxConstraints(maxHeight: height),
        ),
      ),
    );
  }

  /// Header of the wide navigator (section 10.2).
  Widget buildModernNavigatorHeader() {
    final t = skinTokens;
    final modified = selectedVaultModifiedText;
    return Container(
      height: modernTouch ? 44 : 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.outline)),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/branding/wallet_android.png',
            key: const Key('spbDesktopAppIcon'),
            width: 16,
            height: 16,
            cacheWidth: 96,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              selectedVaultTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.onSurface,
              ),
            ),
          ),
          if (spbWritePending)
            const UnsavedChip()
          else if (modified != null)
            Text(
              modified,
              key: const Key('spbDesktopVaultModified'),
              maxLines: 1,
              style: TextStyle(
                fontSize: WorkspaceGeometry.fontSize,
                fontWeight: FontWeight.normal,
                color: t.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  /// A mode row (Мои записи / Шаблоны / Иконки) in the wide navigator.
  Widget buildModernModeRow({
    required String label,
    required Widget leading,
    required bool selected,
  }) {
    final t = skinTokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Container(
        height: modernTouch ? 44 : 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? t.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 20,
              child: FittedBox(fit: BoxFit.contain, child: leading),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? t.onPrimaryContainer : t.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Path row of the central workspace (section 10.3).
  Widget buildModernWorkspaceHeader({
    required int objectCount,
    String? title,
  }) {
    final t = skinTokens;
    final parts = categoryParts(selectedCategoryPath);
    final crumbs = <Widget>[];
    void crumb(String label, String path, {required bool current}) {
      if (crumbs.isNotEmpty) {
        crumbs.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(Icons.chevron_right, size: 14, color: t.onSurfaceVariant),
        ));
      }
      final text = Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: current ? t.onSurface : t.onSurfaceVariant,
          fontWeight: current ? FontWeight.w600 : FontWeight.w400,
        ),
      );
      crumbs.add(Flexible(
        child: current
            ? text
            : InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => openSpbFolder(path),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: text,
                ),
              ),
      ));
    }

    if (title != null) {
      crumb(title, '', current: true);
    } else {
      crumb('Мои записи', '', current: parts.isEmpty);
      for (var index = 0; index < parts.length; index++) {
        crumb(
          parts[index],
          parts.take(index + 1).join(' / '),
          current: index == parts.length - 1,
        );
      }
    }
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: t.work,
        border: Border(bottom: BorderSide(color: t.outline)),
      ),
      child: Row(
        children: [
          Expanded(child: Row(children: crumbs)),
          Text(
            '$objectCount ${russianPlural(objectCount, 'объект', 'объекта', 'объектов')}',
            style: TextStyle(fontSize: 12, color: t.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// Group container of the right panel (section 10.4).
  Widget buildModernPanelGroup(List<Widget> children, {Key? key}) {
    final t = skinTokens;
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: t.isDark ? null : Border.all(color: t.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  /// Collapsible group heading with the original keys and tooltips.
  Widget buildModernGroupHeader(
    String title, {
    required bool expanded,
    required VoidCallback onExpand,
    required VoidCallback onCollapse,
    Widget? trailing,
  }) {
    final t = skinTokens;
    return SizedBox(
      key: ValueKey('spbActionHeader-$title'),
      height: modernTouch ? 44 : 34,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: t.onSurfaceVariant,
                ),
              ),
            ),
            if (trailing != null)
              DefaultTextStyle.merge(
                style: TextStyle(
                  color: t.onSurface,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
                child: trailing,
              ),
            SizedBox.square(
              dimension: modernTouch ? 40 : 24,
              child: Tooltip(
                message: expanded ? 'Свернуть' : 'Развернуть',
                child: InkWell(
                  key: ValueKey(
                    expanded ? 'spbCollapse$title' : 'spbExpand$title',
                  ),
                  borderRadius: BorderRadius.circular(12),
                  onTap: expanded ? onCollapse : onExpand,
                  child: Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: t.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One task or frequently used card row of the right panel.
  Widget buildModernPanelRow({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
    bool frequentRow = false,
    String? subtitle,
  }) {
    final t = skinTokens;
    final danger = label == 'Удалить';
    final tileSize = frequentRow ? 30.0 : 24.0;
    // Icons stand on the panel without a tile; task icons are 20 % larger.
    final iconSize = tileSize * 0.8 * (frequentRow ? 1.0 : 1.2);
    final rowHeight = modernTouch
        ? 44.0
        : subtitle == null
            ? (frequentRow ? 38.0 : 32.0)
            : 44.0;
    return InkWell(
      onTap: onTap,
      hoverColor: t.hover,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: rowHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: Row(
            children: [
              Container(
                key: ValueKey('spbActionIcon-$label'),
                width: tileSize,
                height: tileSize,
                alignment: Alignment.center,
                child: SizedBox.square(
                  dimension: iconSize,
                  child: FittedBox(fit: BoxFit.contain, child: icon),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: modernTouch ? 15 : 13,
                        fontWeight: FontWeight.w500,
                        color: danger ? t.error : t.onSurface,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: t.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Central window with a create button in the bottom right corner: the
  /// narrow Light/Dark button in the modern skins, a blue Retro button that
  /// opens the creation menu in Retro.
  Widget withCreateButton(Widget workspace) {
    final fab = skinTokens.isRetro
        ? buildRetroCreateButton()
        : buildModernCreateFab(
            iconLibraryOpen
                ? 2
                : mobileTemplatesOpen
                    ? 1
                    : 0,
          );
    if (fab == null) return workspace;
    return Stack(
      fit: StackFit.expand,
      children: [
        workspace,
        // The icons workspace keeps its own button row at the bottom.
        Positioned(right: 28, bottom: iconLibraryOpen ? 64 : 20, child: fab),
      ],
    );
  }

  /// Retro "+" button of the central window. Cards and templates open their
  /// existing creation menus at the button; icons open the upload directly,
  /// as the modern button does.
  Widget buildRetroCreateButton() {
    const size = 56.0;
    final radius = BorderRadius.circular(8);
    return Builder(
      builder: (context) {
        Offset anchor() {
          final box = context.findRenderObject() as RenderBox?;
          return box == null || !box.hasSize
              ? MediaQuery.sizeOf(context).bottomRight(Offset.zero)
              : box.localToGlobal(Offset.zero);
        }

        void open() {
          if (iconLibraryOpen) {
            unawaited(uploadManagedIcon());
          } else if (mobileTemplatesOpen) {
            unawaited(showSpbTemplateImportMenu(anchor()));
          } else {
            unawaited(showSpbCreationMenu(
              anchor(),
              destinationCategoryPath: selectedCategoryPath,
            ));
          }
        }

        return Tooltip(
          message: iconLibraryOpen ? 'Загрузить иконку' : 'Создать',
          child: SizedBox.square(
            key: const Key('retroCreateButton'),
            dimension: size,
            child: Material(
              color: Colors.transparent,
              elevation: 4,
              shadowColor: Colors.black54,
              borderRadius: radius,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xff42bff5), Color(0xff006fc4)],
                  ),
                  borderRadius: radius,
                  border: Border.all(color: const Color(0x99000000)),
                ),
                child: InkWell(
                  borderRadius: radius,
                  onTap: open,
                  child: const Icon(Icons.add, color: Colors.white, size: 36),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Right panel of the wide Light and Dark shells (section 10.4). The
  /// contents, order, keys and callbacks are the same as in Retro.
  Widget buildModernActionsPanel() {
    final t = skinTokens;
    final frequent = frequentItems();
    final query = spbSubmittedSearchQuery;
    final matchingFolders = spbMatchingFolderPaths(query);
    final matchingCards = spbMatchingCards(query);
    final foundCount = matchingFolders.length + matchingCards.length;
    Widget group(
      String title,
      List<(Widget, String, VoidCallback)> actions, {
      required bool expanded,
      required VoidCallback onExpand,
      required VoidCallback onCollapse,
      bool frequentRows = false,
    }) =>
        buildModernPanelGroup([
          buildModernGroupHeader(
            title,
            expanded: expanded,
            onExpand: onExpand,
            onCollapse: onCollapse,
          ),
          if (expanded)
            for (final action in actions)
              buildModernPanelRow(
                icon: action.$1,
                label: action.$2,
                onTap: action.$3,
                frequentRow: frequentRows,
              ),
          if (expanded && actions.isNotEmpty) const SizedBox(height: 6),
        ]);

    final body = Scrollbar(
      key: const Key('spbActionsPanelScrollbar'),
      controller: spbActionsPanelScrollController,
      thumbVisibility: true,
      interactive: true,
      child: SingleChildScrollView(
        controller: spbActionsPanelScrollController,
        padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            group(
              'Действие',
              spbTasksForCurrentMode(),
              expanded: spbTasksExpanded,
              onExpand: () => modernSetState(() => spbTasksExpanded = true),
              onCollapse: () => modernSetState(() => spbTasksExpanded = false),
            ),
            buildModernPanelGroup([
              buildModernGroupHeader(
                'Найденные',
                expanded: spbFoundExpanded,
                onExpand: () => modernSetState(() => spbFoundExpanded = true),
                onCollapse: () =>
                    modernSetState(() => spbFoundExpanded = false),
                trailing: Text(
                  '$foundCount',
                  key: const Key('spbFoundCount'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (spbFoundExpanded && query.isNotEmpty)
                buildModernSearchResults(matchingFolders, matchingCards),
            ]),
            group(
              'Последние',
              [
                for (final item in frequent.take(10))
                  (
                    spbSizedDataIcon(
                      itemIconId(item, templateFor(item.templateId)),
                      40,
                      fallbackColor: skinTileForItem(item).icon,
                    ),
                    item.title,
                    () => openFrequentCard(item),
                  ),
              ],
              expanded: spbFrequentExpanded,
              frequentRows: true,
              onExpand: () => modernSetState(() => spbFrequentExpanded = true),
              onCollapse: () =>
                  modernSetState(() => spbFrequentExpanded = false),
            ),
          ],
        ),
      ),
    );
    return wrapSpbTemplateRightContextMenu(
      Material(
        color: t.side,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KeyedSubtree(
              key: const Key('spbManagementHeader'),
              child: Container(
                height: modernTouch ? 44 : 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.outline)),
                ),
                child: Text(
                  'Управление',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.onSurface,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior:
                    ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Found folders and cards in the modern skins (right panel, narrow tab).
  Widget buildModernSearchResults(
    List<String> matchingFolders,
    List<SecretItem> matchingCards, {
    bool narrow = false,
  }) {
    final t = skinTokens;
    if (matchingFolders.isEmpty && matchingCards.isEmpty) {
      return SizedBox(
        height: 48,
        child: Center(
          child: Text(
            'Совпадений нет',
            key: const Key('spbNoSearchResults'),
            style: TextStyle(
              fontSize: narrow ? 15 : 13,
              color: t.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    Widget row({
      required Widget icon,
      required SkinTilePair pair,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) =>
        narrow
            ? buildModernListRow(
                leading: skinIconTile(icon: icon, size: 40),
                title: title,
                subtitle: subtitle,
                onTap: onTap,
                iconKey: ValueKey('spbFoundIcon-$title'),
              )
            : InkWell(
                onTap: onTap,
                hoverColor: t.hover,
                child: SizedBox(
                  height: modernTouch ? 48 : 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        skinIconTile(
                          key: ValueKey('spbFoundIcon-$title'),
                          icon: icon,
                          size: 30,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: t.onSurface,
                                ),
                              ),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: t.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );

    return Column(
      key: const Key('spbSearchResults'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final path in matchingFolders)
          row(
            icon: spbSizedDataIcon(
              categoryIconsByPath[path] ?? defaultIconForCategoryPath(path),
              36,
              fallbackColor: skinTileForFolder(categoryColorsByPath[path]).icon,
            ),
            pair: skinTileForFolder(categoryColorsByPath[path]),
            title: categoryParts(path).last,
            subtitle: 'Папка',
            onTap: () => openSpbFolder(path),
          ),
        for (final item in matchingCards)
          row(
            icon: spbSizedDataIcon(
              itemIconId(item, templateFor(item.templateId)),
              36,
              fallbackColor: skinTileForItem(item).icon,
            ),
            pair: skinTileForItem(item),
            title: item.title,
            subtitle: item.category.trim().isEmpty
                ? 'Карточка'
                : 'Карточка • ${item.category}',
            onTap: () => openCardPreviewDialog(item, preserveSearch: true),
          ),
      ],
    );
  }

  /// Two-line list row of the narrow skins (section 8.4).
  Widget buildModernListRow({
    required Widget leading,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    GestureLongPressStartCallback? onLongPressStart,
    bool selected = false,
    bool chevron = false,
    Widget? trailing,
    Key? key,
    Key? iconKey,
  }) {
    final t = skinTokens;
    return Material(
      key: key,
      color: selected ? t.selection : Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: onLongPressStart,
        onSecondaryTapDown: onLongPressStart == null
            ? null
            : (details) => onLongPressStart(LongPressStartDetails(
                  globalPosition: details.globalPosition,
                  localPosition: details.localPosition,
                )),
        child: InkWell(
          onTap: onTap,
          overlayColor: WidgetStatePropertyAll(
            t.onSurface.withValues(alpha: 0.08),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: subtitle == null ? 56 : 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  KeyedSubtree(key: iconKey, child: leading),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected ? t.onSelection : t.onSurface,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: t.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing,
                  if (chevron)
                    Icon(Icons.chevron_right,
                        size: 20, color: t.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Russian plural form: 1 запись, 2 записи, 5 записей.
String russianPlural(int count, String one, String few, String many) {
  final mod100 = count % 100;
  final mod10 = count % 10;
  if (mod100 >= 11 && mod100 <= 14) return many;
  if (mod10 == 1) return one;
  if (mod10 >= 2 && mod10 <= 4) return few;
  return many;
}
