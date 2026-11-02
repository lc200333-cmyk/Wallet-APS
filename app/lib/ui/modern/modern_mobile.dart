part of '../../main.dart';

/// Same rule as the shell: narrow when width < 700, height < 500 or a
/// tablet is held upright.
bool skinNarrowLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final portraitTablet =
      size.height > size.width && min(size.width, size.height) >= 600;
  return size.width < 700 || size.height < 500 || portraitTablet;
}

/// Shows a context menu. Retro and every wide layout use [showMenu] exactly
/// as before. The narrow Light and Dark layouts show the same entries, keys,
/// order and return values in a bottom sheet: an entry's tap pops the sheet
/// with its value just as it pops a popup menu.
Future<T?> showSkinMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  WidgetBuilder? sheetHeader,
}) {
  final t = WalletSkinTokens.of(context);
  if (t.isRetro) {
    return showMenu<T>(context: context, position: position, items: items);
  }
  final styled = _skinMenuEntries(context, t, items);
  if (!skinNarrowLayout(context)) {
    return showMenu<T>(context: context, position: position, items: styled);
  }
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 8),
          // Menu items announce themselves as items of a menu.
          child: Semantics(
            role: ui.SemanticsRole.menu,
            explicitChildNodes: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sheetHeader != null) ...[
                  sheetHeader(sheetContext),
                  const PopupMenuDivider(),
                ],
                for (final entry in styled)
                  entry is PopupMenuItem<T>
                      ? ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: entry,
                          ),
                        )
                      : entry,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Destructive entries ("Удалить…") are separated and drawn in the error
/// colour in the Light and Dark skins. Keys and values are kept.
List<PopupMenuEntry<T>> _skinMenuEntries<T>(
  BuildContext context,
  WalletSkinTokens t,
  List<PopupMenuEntry<T>> items,
) {
  final result = <PopupMenuEntry<T>>[];
  final baseStyle = Theme.of(context).popupMenuTheme.textStyle ??
      Theme.of(context).textTheme.bodyMedium ??
      const TextStyle();
  for (final entry in items) {
    final child = entry is PopupMenuItem<T> ? entry.child : null;
    final destructive = entry is PopupMenuItem<T> &&
        entry is! CheckedPopupMenuItem<T> &&
        child is ContextMenuLabel &&
        child.label.startsWith('Удалить');
    if (!destructive) {
      result.add(entry);
      continue;
    }
    final item = entry;
    if (result.isNotEmpty && result.last is! PopupMenuDivider) {
      result.add(const PopupMenuDivider());
    }
    result.add(PopupMenuItem<T>(
      key: item.key,
      value: item.value,
      onTap: item.onTap,
      enabled: item.enabled,
      height: item.height,
      padding: item.padding,
      mouseCursor: item.mouseCursor,
      labelTextStyle: WidgetStatePropertyAll(
        baseStyle.copyWith(color: t.error),
      ),
      child: item.child,
    ));
  }
  return result;
}

extension _ModernMobileShell on _VaultShellState {
  /// Header of a narrow bottom-sheet menu: object icon, name and subtitle.
  Widget buildModernMenuHeader({
    required Widget icon,
    required String title,
    required String subtitle,
  }) {
    final t = skinTokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          skinIconTile(icon: icon, size: 40),
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
                    fontWeight: FontWeight.w600,
                    color: t.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: t.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildModernCardMenuHeader(SecretItem item) {
    final template = templateFor(item.templateId);
    final pair = skinTileForItem(item);
    return buildModernMenuHeader(
      icon: spbSizedDataIcon(
        itemIconId(item, template),
        40,
        fallbackColor: pair.icon,
      ),
      title: item.title,
      subtitle: [
        template.displayName,
        if (item.category.trim().isNotEmpty) item.category,
      ].join(' · '),
    );
  }

  Widget buildModernFolderMenuHeader(CategoryTreeNode folder) {
    final pair = skinTileForFolder(folder.colorId);
    final parent = categoryParts(folder.path)..removeLast();
    return buildModernMenuHeader(
      icon: spbSizedDataIcon(
        folder.iconId ?? defaultIconForCategoryPath(folder.path),
        40,
        fallbackColor: pair.icon,
      ),
      title: folder.name,
      subtitle: parent.isEmpty ? 'Папка' : 'Папка · ${parent.join(' / ')}',
    );
  }

  Widget buildModernTemplateMenuHeader(CardTemplate template) {
    final pair = skinTileForTemplate(template);
    return buildModernMenuHeader(
      icon: spbSizedDataIcon(
        template.iconId,
        40,
        fallbackColor: pair.icon,
      ),
      title: template.displayName,
      subtitle: 'Шаблон',
    );
  }

  int get modernTabIndex => modernVaultTabOpen
      ? 3
      : iconLibraryOpen
          ? 2
          : mobileTemplatesOpen
              ? 1
              : 0;

  void selectModernTab(int index) {
    switch (index) {
      case 0:
        modernSetState(() => modernVaultTabOpen = false);
        showSpbCardsMode();
      case 1:
        modernSetState(() => modernVaultTabOpen = false);
        showSpbTemplatesMode();
      case 2:
        modernSetState(() => modernVaultTabOpen = false);
        showSpbIconsMode();
      default:
        modernSetState(() => modernVaultTabOpen = true);
    }
  }

  /// Android Back (section 11.8). Sheets, dialogs and full-screen card pages
  /// are routes and close themselves before this is reached.
  bool get modernBackLeavesApp =>
      modernTabIndex == 0 &&
      searchController.text.isEmpty &&
      selectedCategoryPath.isEmpty;

  void handleModernBack() {
    if (searchController.text.isNotEmpty ||
        spbSubmittedSearchQuery.isNotEmpty) {
      clearSearch();
    } else if (modernTabIndex == 0 && selectedCategoryPath.isNotEmpty) {
      openParentSpbFolder();
    } else if (modernTabIndex != 0) {
      selectModernTab(0);
    }
  }

  /// Create button of the Light and Dark skins for a tab (0 cards,
  /// 1 templates, 2 icons). The narrow shell and the wide centre use the same
  /// button, keys and callbacks; the creation menu opens at the button.
  Widget? buildModernCreateFab(int tab) {
    final t = skinTokens;
    Offset anchor(BuildContext context) {
      final box = context.findRenderObject() as RenderBox?;
      return box == null || !box.hasSize
          ? MediaQuery.sizeOf(context).bottomRight(Offset.zero)
          : box.localToGlobal(Offset.zero);
    }

    final Widget? fab = switch (tab) {
      0 => Builder(
          builder: (context) => FloatingActionButton.extended(
            key: const Key('modernCreateFab'),
            onPressed: () => showSpbCreationMenu(
              anchor(context),
              destinationCategoryPath: selectedCategoryPath,
            ),
            icon: const Icon(Icons.add),
            label: const Text('Создать'),
          ),
        ),
      1 => FloatingActionButton.extended(
          key: const Key('modernCreateTemplateFab'),
          onPressed: () => openTemplateDialog(),
          icon: const Icon(Icons.add),
          label: const Text('Создать шаблон'),
        ),
      2 => FloatingActionButton.extended(
          key: const Key('modernUploadIconFab'),
          onPressed: uploadManagedIcon,
          icon: const Icon(Icons.add),
          label: const Text('Загрузить иконку'),
        ),
      _ => null,
    };
    if (fab == null) return null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: t.isDark
            ? const []
            : [
                BoxShadow(
                  color: t.primary.withValues(alpha: 0.30),
                  offset: const Offset(0, 4),
                  blurRadius: 12,
                ),
              ],
      ),
      child: fab,
    );
  }

  /// Narrow shell of the Light and Dark skins (section 11).
  Widget buildModernMobileShell() {
    final t = skinTokens;
    final tab = modernTabIndex;
    final Widget body = switch (tab) {
      1 => buildModernTemplatesTab(),
      2 => buildModernIconsTab(),
      3 => buildModernVaultTab(),
      _ => buildModernCardsTab(),
    };
    final fab = buildModernCreateFab(tab);
    Widget destinationIcon(Widget icon) =>
        SizedBox.square(dimension: 24, child: FittedBox(child: icon));
    return PopScope(
      canPop: modernBackLeavesApp,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) handleModernBack();
      },
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(bottom: false, child: body),
        floatingActionButton: fab,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: t.navigationBarLine, width: 0.5),
            ),
          ),
          child: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: selectModernTab,
            destinations: [
              NavigationDestination(
                key: const Key('modernTabCards'),
                icon: destinationIcon(spbResourceIcon('icon_wallets.png', 24)),
                label: 'Мои записи',
              ),
              NavigationDestination(
                key: const Key('modernTabTemplates'),
                icon:
                    destinationIcon(spbResourceIcon('icon_templates.png', 24)),
                label: 'Шаблоны',
              ),
              NavigationDestination(
                key: const Key('modernTabIcons'),
                icon: destinationIcon(buildIconsModeImage()),
                label: 'Иконки',
              ),
              NavigationDestination(
                key: const Key('modernTabVault'),
                icon: destinationIcon(
                  Image.asset(
                    'assets/branding/wallet_android.png',
                    key: const Key('spbMobileAppIcon'),
                    width: 24,
                    height: 24,
                    cacheWidth: 96,
                    fit: BoxFit.contain,
                  ),
                ),
                label: 'Управление',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildModernSectionTitle(String title, {Widget? trailing}) {
    final t = skinTokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: t.onSurfaceVariant,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  /// White (or dark) rounded group holding list rows.
  Widget buildModernGroup(List<Widget> rows) {
    final t = skinTokens;
    final children = <Widget>[];
    for (var index = 0; index < rows.length; index++) {
      if (index > 0) {
        children.add(Divider(
          height: 1,
          thickness: 1,
          indent: 72,
          color: t.groupDivider,
        ));
      }
      children.add(rows[index]);
    }
    return buildModernMaterialGroup(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: t.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// Rounded group painted by a Material so rows keep their ink effects.
  Widget buildModernMaterialGroup({
    required EdgeInsets margin,
    required Color color,
    required Widget child,
  }) {
    final t = skinTokens;
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: t.groupShadow,
        ),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }

  /// Screen header: back arrow on nested screens, title and actions.
  Widget buildModernScreenHeader({
    required Widget title,
    Widget? subtitle,
    bool showBack = false,
    List<Widget> actions = const [],
    double height = 64,
  }) {
    final t = skinTokens;
    return Container(
      constraints: BoxConstraints(minHeight: height),
      padding: EdgeInsets.only(left: showBack ? 4 : 16, right: 8, top: 4),
      color: t.bg,
      child: Row(
        children: [
          if (showBack)
            IconButton(
              key: const Key('mobileFolderUp'),
              tooltip: 'Назад',
              icon: Icon(Icons.arrow_back, color: t.onSurface),
              onPressed: openParentSpbFolder,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [title, if (subtitle != null) subtitle],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }

  Widget buildModernVaultStatus({required bool small}) {
    final t = skinTokens;
    final modified = selectedVaultModifiedText;
    if (spbWritePending) return const UnsavedChip();
    if (modified == null) return const SizedBox.shrink();
    return Text(
      modified,
      key: const Key('spbMobileVaultModified'),
      maxLines: 1,
      style: TextStyle(
        fontSize: small ? 12 : 13,
        fontWeight: FontWeight.normal,
        color: t.onSurfaceVariant,
      ),
    );
  }

  // ---- Мои записи -------------------------------------------------------

  Widget buildModernCardsTab() {
    final t = skinTokens;
    final query = spbSubmittedSearchQuery;
    final atRoot = selectedCategoryPath.isEmpty;
    final root = buildCategoryTree(filteredItems(), includeAllCategories: true);
    final node = categoryNodeAt(root, selectedCategoryPath);
    final parts = categoryParts(selectedCategoryPath);
    final header = atRoot
        ? buildModernScreenHeader(
            title: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  showSpbRootCreationMenu(details.globalPosition),
              child: Text(
                selectedVaultTitle,
                key: const Key('spbMobileWalletTitle'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: t.onSurface,
                ),
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: buildModernVaultStatus(small: true),
            ),
            actions: buildModernHeaderButtons(dimension: 48),
          )
        : buildModernScreenHeader(
            height: 56,
            showBack: true,
            title: Text(
              parts.last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: t.onSurface,
              ),
            ),
            actions: buildModernHeaderButtons(dimension: 48),
          );
    final children = <Widget>[];
    if (query.isNotEmpty) {
      final folders = spbMatchingFolderPaths(query);
      final cards = spbMatchingCards(query);
      children
        ..add(buildModernSectionTitle(
          'Найденные',
          trailing: Text(
            '${folders.length + cards.length}',
            key: const Key('spbFoundCount'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: t.onSurfaceVariant,
            ),
          ),
        ))
        ..add(buildModernGroup([
          buildModernSearchResults(folders, cards, narrow: true),
        ]));
    } else {
      if (atRoot) children.addAll(buildModernFrequentSection());
      final folders = node.children.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final cards = [
        ...node.cards
      ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      if (folders.isNotEmpty) {
        children
          ..add(buildModernSectionTitle(
            'Папки',
            trailing: Text(
              '${folders.length} ${russianPlural(folders.length, 'папка', 'папки', 'папок')}',
              style: TextStyle(fontSize: 12, color: t.onSurfaceVariant),
            ),
          ))
          ..add(buildModernGroup([
            for (final folder in folders) buildModernFolderRow(folder),
          ]));
      }
      if (cards.isNotEmpty) {
        children
          ..add(buildModernSectionTitle(
            'Карточки',
            trailing: Text(
              '${cards.length}',
              style: TextStyle(fontSize: 12, color: t.onSurfaceVariant),
            ),
          ))
          ..add(buildModernGroup([
            for (final item in cards) buildModernCardRow(item),
          ]));
      }
      if (folders.isEmpty && cards.isEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'Совпадений нет',
              style: TextStyle(color: t.onSurfaceVariant),
            ),
          ),
        ));
      }
    }
    children.add(const SizedBox(height: 96));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        // The path and the search field stay above the scrolling list.
        if (!atRoot) buildModernPathRow(parts),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: buildModernSearchField(height: 48),
        ),
        Expanded(
          child: Scrollbar(
            controller: spbMobileActionsScrollController,
            child: ListView(
              key: const Key('modernCardsList'),
              controller: spbMobileActionsScrollController,
              padding: EdgeInsets.zero,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  Widget buildModernPathRow(List<String> parts) {
    final t = skinTokens;
    final crumbs = <Widget>[];
    void add(String label, String path, bool current) {
      if (crumbs.isNotEmpty) {
        crumbs.add(
            Icon(Icons.chevron_right, size: 14, color: t.onSurfaceVariant));
      }
      final text = Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: current ? t.onSurface : t.onSurfaceVariant,
          fontWeight: current ? FontWeight.w600 : FontWeight.w400,
        ),
      );
      crumbs.add(Flexible(
        child: current
            ? text
            : InkWell(
                onTap: () => openSpbFolder(path),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: text,
                ),
              ),
      ));
    }

    add('Мои записи', '', false);
    for (var index = 0; index < parts.length; index++) {
      add(parts[index], parts.take(index + 1).join(' / '),
          index == parts.length - 1);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 16, 4),
      child: SizedBox(height: 32, child: Row(children: crumbs)),
    );
  }

  List<Widget> buildModernFrequentSection() {
    final t = skinTokens;
    final frequent = frequentItems().take(10).toList();
    if (frequent.isEmpty) return const [];
    return [
      buildModernSectionTitle(
        'Последние',
        trailing: SizedBox.square(
          dimension: 40,
          child: Tooltip(
            message: spbFrequentExpanded ? 'Свернуть' : 'Развернуть',
            child: InkWell(
              key: ValueKey(
                spbFrequentExpanded
                    ? 'spbCollapseПоследние'
                    : 'spbExpandПоследние',
              ),
              borderRadius: BorderRadius.circular(20),
              onTap: () => modernSetState(
                  () => spbFrequentExpanded = !spbFrequentExpanded),
              child: Icon(
                spbFrequentExpanded ? Icons.expand_less : Icons.expand_more,
                color: t.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
      if (spbFrequentExpanded)
        SizedBox(
          height: 92,
          child: SingleChildScrollView(
            key: const Key('frequentCardsScroll'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final item in frequent) ...[
                  buildModernFrequentCard(item),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
    ];
  }

  Widget buildModernFrequentCard(SecretItem item) {
    final t = skinTokens;
    final pair = skinTileForItem(item);
    return DecoratedBox(
      key: ValueKey('modernFrequentCard-${item.id}'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: t.groupShadow,
      ),
      child: Material(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => openFrequentCard(item),
          child: Container(
            width: 104,
            height: 92,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                skinIconTile(
                  icon: spbSizedDataIcon(
                    itemIconId(item, templateFor(item.templateId)),
                    32,
                    fallbackColor: pair.icon,
                  ),
                  size: 32,
                ),
                const Spacer(),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: t.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildModernFolderRow(CategoryTreeNode folder) {
    final pair = skinTileForFolder(folder.colorId);
    final folderCount = folder.children.length;
    final cardCount = folder.cards.length;
    final parts = [
      if (folderCount > 0)
        '$folderCount ${russianPlural(folderCount, 'папка', 'папки', 'папок')}',
      if (cardCount > 0 || folderCount == 0)
        '$cardCount ${russianPlural(cardCount, 'карточка', 'карточки', 'карточек')}',
    ];
    return buildModernListRow(
      key: ValueKey('spbCentralFolder-${folder.path}'),
      leading: skinIconTile(
        icon: spbSizedDataIcon(
          folder.iconId ?? defaultIconForCategoryPath(folder.path),
          40,
          fallbackColor: pair.icon,
        ),
        size: 40,
      ),
      title: folder.name,
      subtitle: parts.join(' · '),
      chevron: true,
      onTap: () => openSpbFolder(folder.path),
      onLongPressStart: (details) =>
          showSpbFolderMenu(folder, details.globalPosition),
    );
  }

  Widget buildModernCardRow(SecretItem item) {
    final template = templateFor(item.templateId);
    return buildModernListRow(
      key: ValueKey('spbCentralCard-${item.id}'),
      leading: Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(2),
        child: spbCardIconWithAttachmentMark(
          item: item,
          template: template,
          dimension: 30,
          attachmentMarkKey: ValueKey('cardAttachmentArrow-${item.id}'),
        ),
      ),
      title: item.title,
      subtitle: template.displayName,
      selected: selectedItemIds.contains(item.id) || selectedItemId == item.id,
      onTap: () => selectSpbCardFromPrimaryClick(item, controlPressed: false),
      onLongPressStart: (details) =>
          showSpbCardMenu(item, details.globalPosition),
    );
  }

  // ---- Шаблоны и Иконки -------------------------------------------------

  Future<void> showModernTaskSheet() async {
    final tasks = spbTasksForCurrentMode();
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < tasks.length; index++)
                buildModernTaskRow(
                  tasks[index],
                  onTap: () => Navigator.pop(sheetContext, index),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    tasks[picked].$3();
  }

  Widget buildModernTaskRow(
    (Widget, String, VoidCallback) task, {
    VoidCallback? onTap,
  }) {
    final t = skinTokens;
    final danger = task.$2 == 'Удалить';
    return InkWell(
      onTap: onTap ?? task.$3,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // No tile behind the icon; task icons are 20 % larger.
              Container(
                key: ValueKey('spbActionIcon-${task.$2}'),
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(5.6),
                child: FittedBox(fit: BoxFit.contain, child: task.$1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  task.$2,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: danger ? t.error : t.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildModernTabHeader(String title, {required Key menuKey}) {
    final t = skinTokens;
    return buildModernScreenHeader(
      title: Text(
        title,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: t.onSurface,
        ),
      ),
      actions: [
        IconButton(
          key: menuKey,
          tooltip: 'Действие',
          icon: Icon(Icons.more_vert, color: t.onSurfaceVariant),
          onPressed: showModernTaskSheet,
        ),
      ],
    );
  }

  Widget buildModernSplitTab({
    required Widget header,
    required Widget top,
    required Widget bottom,
  }) {
    final t = skinTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          flex: 2,
          child: buildModernMaterialGroup(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            color: t.surface,
            child: spbWorkspaceScrollbarTheme(top),
          ),
        ),
        Expanded(
          flex: 3,
          child: buildModernMaterialGroup(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
            color: t.work,
            child: spbWorkspaceScrollbarTheme(bottom),
          ),
        ),
      ],
    );
  }

  Widget buildModernTemplatesTab() => buildModernSplitTab(
        header: buildModernTabHeader(
          'Шаблоны',
          menuKey: const Key('modernTemplateTasksMenu'),
        ),
        top: buildSpbTemplateTree(),
        bottom: buildSpbTemplateWorkspace(showPersistentScrollbar: true),
      );

  Widget buildModernIconsTab() => buildModernSplitTab(
        header: buildModernTabHeader(
          'Иконки',
          menuKey: const Key('modernIconTasksMenu'),
        ),
        top: buildSpbIconCatalogTree(),
        bottom: buildSpbIconWorkspace(showPersistentScrollbar: true),
      );

  // ---- База ---------------------------------------------------------------

  Widget buildModernVaultTab() {
    final t = skinTokens;
    final history = sessionUndoHistory;
    return ListView(
      key: const Key('modernVaultTab'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        buildModernScreenHeader(
          title: Text(
            'Управление',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: t.onSurface,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: t.groupShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(4),
                child: Image.asset(
                  'assets/branding/wallet_android.png',
                  cacheWidth: 128,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedVaultTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: t.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    buildModernVaultStatus(small: false),
                  ],
                ),
              ),
            ],
          ),
        ),
        buildModernSectionTitle('Действие'),
        buildModernGroup([
          for (final task in spbCardModeTasks()) buildModernTaskRow(task),
        ]),
        buildModernSectionTitle('История изменений сеанса'),
        buildModernGroup([
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Нет изменений для отмены',
                style: TextStyle(color: t.onSurfaceVariant),
              ),
            )
          else
            for (var index = history.length - 1; index >= 0; index--)
              buildModernListRow(
                key: ValueKey('modernUndoEntry-$index'),
                leading: Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(6),
                  child: spbSizedDataIcon(
                    history[index].iconId,
                    28,
                    fallbackColor: t.onSurfaceVariant,
                  ),
                ),
                title: history[index].label,
                trailing: TextButton(
                  key: ValueKey('modernUndoRestore-$index'),
                  onPressed: () => restoreSessionUndoAt(index),
                  child: const Text('Вернуть'),
                ),
              ),
        ]),
      ],
    );
  }
}
