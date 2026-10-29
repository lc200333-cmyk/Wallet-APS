import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Interface skins. Retro is the original look; Dark is the default for a
/// profile that has never chosen a skin.
enum AppSkin { retro, light, dark }

AppSkin appSkinFromName(Object? name) => switch (name) {
      'retro' => AppSkin.retro,
      'light' => AppSkin.light,
      _ => AppSkin.dark,
    };

/// Meaning of a password-window button in the Light and Dark skins. Retro
/// keeps its explicit gradient colours and ignores the role.
enum SkinKeyRole { character, service, mode, hint, outlined, primary, danger }

/// The skin currently shown. It is loaded in main() before runApp.
final appSkin = ValueNotifier<AppSkin>(AppSkin.retro);

/// Stores the selected skin in the program settings directory, never in a
/// vault. The file is `wallet_aps_ui_settings.json` with
/// `{"skin":"retro","version":2}`.
class AppSkinStore {
  AppSkinStore._();

  static const fileName = 'wallet_aps_ui_settings.json';

  /// Choices stored before the Dark default (no version) are ignored once,
  /// so the first start of this version opens in Dark (owner decision).
  static const settingsVersion = 2;

  /// Supplies the existing application state directory.
  static Future<Directory> Function()? directoryProvider;

  static Future<File?> _file() async {
    final provider = directoryProvider;
    if (provider == null) return null;
    final directory = await provider();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  /// A missing, unreadable, unknown or older value yields the default Dark
  /// skin.
  static Future<AppSkin> load() async {
    try {
      final file = await _file();
      if (file == null || !file.existsSync()) return AppSkin.dark;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['version'] != settingsVersion) {
        return AppSkin.dark;
      }
      return appSkinFromName(decoded['skin']);
    } catch (error) {
      debugPrint('Wallet APS: skin settings could not be read: $error');
      return AppSkin.dark;
    }
  }

  static Future<void> _writeQueue = Future<void>.value();

  /// Writes a temporary file and renames it over the settings file. Writes
  /// are serialised, so the most recent choice is always the one stored.
  static Future<void> save(AppSkin skin) {
    final write = _writeQueue.then((_) => _write(skin));
    _writeQueue = write.catchError((Object _) {});
    return write;
  }

  static Future<void> _write(AppSkin skin) async {
    final file = await _file();
    if (file == null) return;
    final content = jsonEncode({'skin': skin.name, 'version': settingsVersion});
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(content, flush: true);
    // Windows refuses to replace a file that another process (antivirus,
    // indexer, a reader) holds open for a moment; retry briefly.
    for (var attempt = 0;; attempt++) {
      try {
        await temporary.rename(file.path);
        return;
      } on FileSystemException {
        if (attempt >= 4) break;
        await Future<void>.delayed(Duration(milliseconds: 25 * (attempt + 1)));
      }
    }
    // A UI preference is not vault data: fall back to a direct write.
    await file.writeAsString(content, flush: true);
    try {
      await temporary.delete();
    } on FileSystemException {
      // A leftover temporary file is replaced on the next save.
    }
  }
}

/// Selects a skin immediately and persists it without blocking the interface.
/// A storage error is only logged; the skin still applies until restart.
void selectAppSkin(AppSkin skin) {
  appSkin.value = skin;
  AppSkinStore.save(skin).catchError((Object error) {
    debugPrint('Wallet APS: skin settings could not be saved: $error');
  });
}

/// Tile and glyph colours of a palette entry in a modern skin.
typedef SkinTilePair = ({Color tile, Color icon});

/// Colour roles of the Light and Dark skins. Retro keeps the original
/// literals in its own code paths; [isRetro] selects those paths.
@immutable
class WalletSkinTokens extends ThemeExtension<WalletSkinTokens> {
  const WalletSkinTokens({
    required this.skin,
    required this.bg,
    required this.surface,
    required this.s2,
    required this.outline,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.success,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.toolbar,
    required this.nav,
    required this.work,
    required this.side,
    required this.hover,
    required this.selection,
    required this.onSelection,
    required this.splitter,
    required this.thumb,
    required this.thumbHover,
    required this.tooltip,
    required this.onTooltip,
    required this.menu,
    required this.menuBorder,
    required this.scrim,
    required this.titleBar,
    required this.navigationBar,
    required this.navigationBarLine,
    required this.groupDivider,
    required this.sheetHandle,
    required this.snackBar,
    required this.onSnackBar,
    required this.snackBarAction,
    required this.keyboardBase,
    required this.keyCharacter,
    required this.keyCharacterShadow,
    required this.keyService,
    required this.strength,
    required this.strengthEmpty,
    required this.palette,
    required this.folderTile,
  });

  final AppSkin skin;
  final Color bg;
  final Color surface;
  final Color s2;
  final Color outline;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color success;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color toolbar;
  final Color nav;
  final Color work;
  final Color side;
  final Color hover;
  final Color selection;
  final Color onSelection;
  final Color splitter;
  final Color thumb;
  final Color thumbHover;
  final Color tooltip;
  final Color onTooltip;
  final Color menu;
  final Color? menuBorder;
  final Color scrim;
  final Color titleBar;
  final Color navigationBar;
  final Color navigationBarLine;
  final Color groupDivider;
  final Color sheetHandle;
  final Color snackBar;
  final Color onSnackBar;
  final Color snackBarAction;
  final Color keyboardBase;
  final Color keyCharacter;
  final Color? keyCharacterShadow;
  final Color keyService;
  final List<Color> strength;
  final Color strengthEmpty;

  /// Tile/glyph pairs by palette id (neutral, blue, green, teal, violet,
  /// red, amber).
  final Map<String, SkinTilePair> palette;

  /// A folder without its own colour.
  final SkinTilePair folderTile;

  bool get isRetro => skin == AppSkin.retro;
  bool get isDark => skin == AppSkin.dark;

  /// Shadow of a group container in the narrow skin; none in Dark.
  List<BoxShadow> get groupShadow => isDark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x1414171c),
            offset: Offset(0, 1),
            blurRadius: 3,
          ),
        ];

  /// Light and Dark resolve unknown widget trees (dialogs pushed without the
  /// application theme, tests) to Retro.
  static WalletSkinTokens of(BuildContext context) =>
      Theme.of(context).extension<WalletSkinTokens>() ?? retro;

  static WalletSkinTokens forSkin(AppSkin skin) => switch (skin) {
        AppSkin.retro => retro,
        AppSkin.light => light,
        AppSkin.dark => dark,
      };

  /// Pair for a colour stored as a palette id or a custom colour value.
  SkinTilePair tileFor(String? paletteId, {Color? custom}) {
    final pair = palette[_modernPaletteId(paletteId)];
    if (pair != null) return pair;
    if (custom != null) return customTile(custom);
    return palette['neutral']!;
  }

  /// Colour pair of a custom colour (section 6.4 of the task).
  SkinTilePair customTile(Color color) {
    final tile = isDark
        ? Color.lerp(const Color(0xff171a20), color, 0.28)!
        : Color.lerp(const Color(0xffffffff), color, 0.25)!;
    var icon = isDark
        ? Color.lerp(color, const Color(0xffffffff), 0.35)!
        : Color.lerp(color, const Color(0xff000000), 0.35)!;
    if (contrastRatio(icon, tile) < 3) icon = onSurface;
    return (tile: tile, icon: icon);
  }

  static const retro = WalletSkinTokens(
    skin: AppSkin.retro,
    bg: Color(0xffe6e6e6),
    surface: Color(0xffffffff),
    s2: Color(0xffffffff),
    outline: Color(0xffb7b7b7),
    onSurface: Color(0xff000000),
    onSurfaceVariant: Color(0xff5f5f5f),
    primary: Color(0xff2483bc),
    onPrimary: Color(0xffffffff),
    primaryContainer: Color(0xffcfe9fb),
    onPrimaryContainer: Color(0xff18364d),
    error: Color(0xffc62828),
    onError: Color(0xffffffff),
    errorContainer: Color(0xfff8d7da),
    success: Color(0xff43a047),
    warning: Color(0xffa65b00),
    warningContainer: Color(0xfffff4bc),
    onWarningContainer: Color(0xff6b4508),
    toolbar: Color(0xffe6e6e6),
    nav: Color(0xffffffff),
    work: Color(0xffffffff),
    side: Color(0xffc7d9ea),
    hover: Color(0xffe8ebf0),
    selection: Color(0xffcfe9fb),
    onSelection: Color(0xff18364d),
    splitter: Color(0xffb7b7b7),
    thumb: Color(0xffc3c8d1),
    thumbHover: Color(0xffa9afba),
    tooltip: Color(0xff616161),
    onTooltip: Color(0xffffffff),
    menu: Color(0xffffffff),
    menuBorder: null,
    scrim: Color(0x8a000000),
    titleBar: Color(0xff777777),
    navigationBar: Color(0xffe6e6e6),
    navigationBarLine: Color(0xffb7b7b7),
    groupDivider: Color(0xffb7b7b7),
    sheetHandle: Color(0xffc3c8d1),
    snackBar: Color(0xff323232),
    onSnackBar: Color(0xffffffff),
    snackBarAction: Color(0xff8eaaff),
    keyboardBase: Color(0xffe6e6e6),
    keyCharacter: Color(0xff2483bc),
    keyCharacterShadow: null,
    keyService: Color(0xffd32b31),
    strength: [
      Color(0xffc62828),
      Color(0xffc62828),
      Color(0xfff57c00),
      Color(0xfffbc02d),
      Color(0xff43a047),
      Color(0xff2e7d32),
    ],
    strengthEmpty: Color(0xffe0e0e0),
    palette: {},
    folderTile: (tile: Color(0xfffbe9c6), icon: Color(0xffa8650a)),
  );

  static const light = WalletSkinTokens(
    skin: AppSkin.light,
    bg: Color(0xfff5f6f8),
    surface: Color(0xffffffff),
    s2: Color(0xffeef0f4),
    outline: Color(0xffd6dae1),
    onSurface: Color(0xff14171c),
    onSurfaceVariant: Color(0xff5b6270),
    primary: Color(0xff2f5bea),
    onPrimary: Color(0xffffffff),
    primaryContainer: Color(0xffdde6ff),
    onPrimaryContainer: Color(0xff0f2a7a),
    error: Color(0xffc9372c),
    onError: Color(0xffffffff),
    errorContainer: Color(0xfffbe3e0),
    success: Color(0xff1e8e5a),
    warning: Color(0xffa86b0c),
    warningContainer: Color(0xfffdf1dc),
    onWarningContainer: Color(0xff6b4508),
    toolbar: Color(0xfff5f6f8),
    nav: Color(0xfff0f2f5),
    work: Color(0xffffffff),
    side: Color(0xfff5f6f8),
    hover: Color(0xffe8ebf0),
    selection: Color(0xffdde6ff),
    onSelection: Color(0xff0f2a7a),
    splitter: Color(0xffd6dae1),
    thumb: Color(0xffc3c8d1),
    thumbHover: Color(0xffa9afba),
    tooltip: Color(0xff2a2f38),
    onTooltip: Color(0xfff2f4f7),
    menu: Color(0xffffffff),
    menuBorder: null,
    scrim: Color(0x5214171c),
    titleBar: Color(0xffe9ecf1),
    navigationBar: Color(0xffffffff),
    navigationBarLine: Color(0xffd6dae1),
    groupDivider: Color(0xffe6e9ee),
    sheetHandle: Color(0xffc3c8d1),
    snackBar: Color(0xff2a2f38),
    onSnackBar: Color(0xfff2f4f7),
    snackBarAction: Color(0xff8eaaff),
    keyboardBase: Color(0xffe3e6eb),
    keyCharacter: Color(0xffffffff),
    keyCharacterShadow: Color(0xffb6bcc6),
    keyService: Color(0xffd6dae1),
    strength: [
      Color(0xffc9372c),
      Color(0xffd9542c),
      Color(0xffc77700),
      Color(0xffa88600),
      Color(0xff4a9a3c),
      Color(0xff1e8e5a),
    ],
    strengthEmpty: Color(0xffe6e9ee),
    palette: {
      'neutral': (tile: Color(0xffe6e9ee), icon: Color(0xff4a5160)),
      'blue': (tile: Color(0xffdde6ff), icon: Color(0xff2f5bea)),
      'green': (tile: Color(0xffdcefe4), icon: Color(0xff1e7a4f)),
      'teal': (tile: Color(0xffd6efee), icon: Color(0xff147a74)),
      'violet': (tile: Color(0xffe9e1f8), icon: Color(0xff6b46c1)),
      'red': (tile: Color(0xfff8dfdc), icon: Color(0xffb8322a)),
      'amber': (tile: Color(0xfff7ead2), icon: Color(0xff9a6206)),
    },
    folderTile: (tile: Color(0xfffbe9c6), icon: Color(0xffa8650a)),
  );

  static const dark = WalletSkinTokens(
    skin: AppSkin.dark,
    bg: Color(0xff0e1014),
    surface: Color(0xff171a20),
    s2: Color(0xff1f232a),
    outline: Color(0xff333944),
    onSurface: Color(0xffe8eaef),
    onSurfaceVariant: Color(0xffa0a7b4),
    primary: Color(0xff8eaaff),
    onPrimary: Color(0xff0b1a55),
    primaryContainer: Color(0xff24345f),
    onPrimaryContainer: Color(0xffdbe4ff),
    error: Color(0xffff8a80),
    onError: Color(0xff3a0b07),
    errorContainer: Color(0xff3d1f1e),
    success: Color(0xff62cf98),
    warning: Color(0xfff2c063),
    warningContainer: Color(0xff3a2d12),
    onWarningContainer: Color(0xfff2c063),
    toolbar: Color(0xff121419),
    nav: Color(0xff121419),
    work: Color(0xff171a20),
    side: Color(0xff121419),
    hover: Color(0xff232832),
    selection: Color(0xff24345f),
    onSelection: Color(0xffdbe4ff),
    splitter: Color(0xff2a2f38),
    thumb: Color(0xff3d4451),
    thumbHover: Color(0xff545c6b),
    tooltip: Color(0xffe8eaef),
    onTooltip: Color(0xff14171c),
    menu: Color(0xff232832),
    menuBorder: Color(0xff333944),
    scrim: Color(0x8c000000),
    titleBar: Color(0xff0b0d11),
    navigationBar: Color(0xff171a20),
    navigationBarLine: Color(0xff333944),
    groupDivider: Color(0xff262b33),
    sheetHandle: Color(0xff3d4451),
    snackBar: Color(0xffe8eaef),
    onSnackBar: Color(0xff14171c),
    snackBarAction: Color(0xff2f5bea),
    keyboardBase: Color(0xff1b1e24),
    keyCharacter: Color(0xff2a2f38),
    keyCharacterShadow: null,
    keyService: Color(0xff3a404b),
    strength: [
      Color(0xffff8a80),
      Color(0xffff9e6e),
      Color(0xfff2b35b),
      Color(0xffe3cf5e),
      Color(0xff9fd67a),
      Color(0xff62cf98),
    ],
    strengthEmpty: Color(0xff2a2f38),
    palette: {
      'neutral': (tile: Color(0xff2a2f38), icon: Color(0xffc2c8d3)),
      'blue': (tile: Color(0xff1f2c52), icon: Color(0xff9db5ff)),
      'green': (tile: Color(0xff16342a), icon: Color(0xff6fd3a0)),
      'teal': (tile: Color(0xff12332f), icon: Color(0xff6fd6cc)),
      'violet': (tile: Color(0xff2b2347), icon: Color(0xffc3a9ff)),
      'red': (tile: Color(0xff3d1f1e), icon: Color(0xffff9a90)),
      'amber': (tile: Color(0xff3a2d12), icon: Color(0xfff2c063)),
    },
    folderTile: (tile: Color(0xff3a2d12), icon: Color(0xfff2c063)),
  );

  @override
  WalletSkinTokens copyWith() => this;

  @override
  WalletSkinTokens lerp(WalletSkinTokens? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

/// Maps the stored palette ids of cards, folders and templates to the seven
/// modern colour roles. The stored id itself is never changed.
String _modernPaletteId(String? id) => switch (id) {
      null || '' => 'neutral',
      'neutral' ||
      'gray' ||
      'grey' ||
      'template_gray' ||
      'template_white' ||
      'white' =>
        'neutral',
      'blue' || 'sky' || 'template_sky' || 'template_blue' => 'blue',
      'green' ||
      'template_green' ||
      'template_lime' ||
      'template_mint' =>
        'green',
      'teal' || 'cyan' || 'template_cyan' => 'teal',
      'violet' ||
      'purple' ||
      'template_violet' ||
      'template_indigo' =>
        'violet',
      'red' ||
      'rose' ||
      'pink' ||
      'template_red' ||
      'template_coral' ||
      'template_pink' ||
      'template_rose' =>
        'red',
      'amber' ||
      'yellow' ||
      'orange' ||
      'template_yellow' ||
      'template_orange' =>
        'amber',
      _ => id,
    };

/// WCAG relative luminance contrast of two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Linux draws text in Wallet Sans (`assets/fonts`): Roboto with the line
/// metrics of Segoe UI, so text sizes match the Windows version.
String? get platformFontFamily =>
    defaultTargetPlatform == TargetPlatform.linux ? 'WalletSans' : null;

/// Material 3 theme of the Light and Dark skins (sections 6–8).
ThemeData buildModernTheme(Brightness brightness) {
  final t = brightness == Brightness.dark
      ? WalletSkinTokens.dark
      : WalletSkinTokens.light;
  final narrowText = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  double size(double narrow, double wide) => narrowText ? narrow : wide;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.primary,
    onPrimary: t.onPrimary,
    primaryContainer: t.primaryContainer,
    onPrimaryContainer: t.onPrimaryContainer,
    secondary: t.primary,
    onSecondary: t.onPrimary,
    secondaryContainer: t.primaryContainer,
    onSecondaryContainer: t.onPrimaryContainer,
    tertiary: t.success,
    onTertiary: t.onPrimary,
    error: t.error,
    onError: t.onError,
    errorContainer: t.errorContainer,
    onErrorContainer: t.error,
    surface: t.surface,
    onSurface: t.onSurface,
    onSurfaceVariant: t.onSurfaceVariant,
    surfaceContainerLowest: t.bg,
    surfaceContainerLow: t.bg,
    surfaceContainer: t.surface,
    surfaceContainerHigh: t.s2,
    surfaceContainerHighest: t.s2,
    outline: t.outline,
    outlineVariant: t.outline,
    shadow: const Color(0xff000000),
    scrim: t.scrim,
    inverseSurface: t.tooltip,
    onInverseSurface: t.onTooltip,
    inversePrimary: t.primary,
    surfaceTint: Colors.transparent,
  );
  final ownText = TextTheme(
    headlineSmall: TextStyle(
        fontSize: size(22, 20),
        fontWeight: FontWeight.w700,
        color: t.onSurface),
    titleLarge: TextStyle(
        fontSize: size(20, 17),
        fontWeight: FontWeight.w600,
        color: t.onSurface),
    titleMedium: TextStyle(
        fontSize: size(16, 14),
        fontWeight: FontWeight.w500,
        color: t.onSurface),
    titleSmall: TextStyle(
        fontSize: size(15, 13),
        fontWeight: FontWeight.w500,
        color: t.onSurface),
    bodyLarge: TextStyle(
        fontSize: size(16, 14),
        fontWeight: FontWeight.w400,
        color: t.onSurface),
    bodyMedium: TextStyle(
        fontSize: size(15, 13),
        fontWeight: FontWeight.w400,
        color: t.onSurface),
    bodySmall: TextStyle(
        fontSize: size(13, 12),
        fontWeight: FontWeight.w400,
        color: t.onSurfaceVariant),
    labelLarge: TextStyle(fontSize: size(15, 13), fontWeight: FontWeight.w600),
    labelMedium: TextStyle(fontSize: size(12, 11), fontWeight: FontWeight.w600),
    labelSmall: TextStyle(fontSize: size(11, 10), fontWeight: FontWeight.w600),
  );
  // Merge with the platform typography so every style carries the system
  // font family (Segoe UI, Roboto, fontconfig) and the theme colours.
  final typography = Typography.material2021(
    platform: defaultTargetPlatform,
    colorScheme: scheme,
  );
  final textTheme =
      (brightness == Brightness.dark ? typography.white : typography.black)
          .merge(ownText)
          .apply(fontFamily: platformFontFamily);
  final buttonHeight = narrowText ? 48.0 : 34.0;
  const fullRadius = StadiumBorder();
  final fieldRadius = BorderRadius.circular(narrowText ? 12 : 8);
  OutlineInputBorder fieldBorder(Color color, double width) =>
      OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: color, width: width),
      );
  return ThemeData(
    useMaterial3: true,
    fontFamily: platformFontFamily,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.surface,
    cardColor: t.surface,
    dividerColor: t.outline,
    hoverColor: t.hover,
    splashColor: t.onSurface.withValues(alpha: 0.12),
    highlightColor: t.onSurface.withValues(alpha: 0.08),
    textTheme: textTheme,
    visualDensity: VisualDensity.standard,
    extensions: [t],
    iconTheme: IconThemeData(color: t.onSurfaceVariant),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      barrierColor: t.scrim,
      elevation: t.isDark ? 0 : 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(narrowText ? 28 : 24),
        side: t.isDark ? BorderSide(color: t.outline) : BorderSide.none,
      ),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.menu,
      surfaceTintColor: Colors.transparent,
      elevation: t.isDark ? 0 : 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: t.menuBorder == null
            ? BorderSide.none
            : BorderSide(color: t.menuBorder!),
      ),
      textStyle: textTheme.bodyMedium,
      labelTextStyle: WidgetStatePropertyAll(textTheme.bodyMedium),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.menu),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.isDark ? t.s2 : t.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: t.isDark ? t.s2 : t.surface,
      showDragHandle: true,
      dragHandleColor: t.sheetHandle,
      dragHandleSize: const Size(32, 4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 76,
      backgroundColor: t.navigationBar,
      surfaceTintColor: Colors.transparent,
      indicatorColor: t.primaryContainer,
      indicatorShape: const StadiumBorder(),
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? t.onSurface
              : t.onSurfaceVariant,
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: t.tooltip,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(color: t.onTooltip, fontSize: 12),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith(
        (states) => narrowText
            ? 4
            : states.contains(WidgetState.hovered)
                ? 12
                : 8,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.dragged)
            ? t.thumbHover
            : t.thumb,
      ),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
      radius: const Radius.circular(8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      isDense: !narrowText,
      labelStyle: TextStyle(color: t.onSurfaceVariant),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.focused)
              ? t.primary
              : t.onSurfaceVariant,
        ),
      ),
      hintStyle: TextStyle(color: t.onSurfaceVariant),
      border: fieldBorder(t.outline, 1),
      enabledBorder: fieldBorder(t.outline, 1),
      focusedBorder: fieldBorder(t.primary, 2),
      errorBorder: fieldBorder(t.error, 2),
      focusedErrorBorder: fieldBorder(t.error, 2),
      errorStyle: TextStyle(color: t.error, fontSize: size(13, 12)),
      suffixIconColor: t.onSurfaceVariant,
      prefixIconColor: t.onSurfaceVariant,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.snackBar,
      contentTextStyle: TextStyle(color: t.onSnackBar),
      actionTextColor: t.snackBarAction,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.all(16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.primary,
        foregroundColor: t.onPrimary,
        disabledBackgroundColor: t.onSurface.withValues(alpha: 0.12),
        disabledForegroundColor: t.onSurface.withValues(alpha: 0.38),
        minimumSize: Size(64, buttonHeight),
        padding: EdgeInsets.symmetric(horizontal: narrowText ? 24 : 16),
        shape: fullRadius,
        textStyle: textTheme.labelLarge,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: t.primaryContainer,
        foregroundColor: t.onPrimaryContainer,
        elevation: 0,
        minimumSize: Size(64, buttonHeight),
        shape: fullRadius,
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.onSurface,
        side: BorderSide(color: t.outline),
        minimumSize: Size(64, buttonHeight),
        padding: EdgeInsets.symmetric(horizontal: narrowText ? 24 : 16),
        shape: fullRadius,
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.primary,
        minimumSize: Size(48, buttonHeight),
        shape: fullRadius,
        textStyle: textTheme.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: t.onSurfaceVariant),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.surface,
      selectedColor: t.primaryContainer,
      side: BorderSide(color: t.outline),
      shape: const StadiumBorder(),
      labelStyle: textTheme.labelMedium?.copyWith(color: t.onSurface),
      secondaryLabelStyle:
          textTheme.labelMedium?.copyWith(color: t.onPrimaryContainer),
      checkmarkColor: t.onPrimaryContainer,
    ),
    dividerTheme: DividerThemeData(color: t.outline, thickness: 1, space: 1),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? t.primary
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(t.onPrimary),
      side: BorderSide(color: t.onSurfaceVariant, width: 2),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? t.onPrimary
            : t.onSurfaceVariant,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? t.primary : t.s2,
      ),
      trackOutlineColor: WidgetStatePropertyAll(t.outline),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        foregroundColor: t.onSurface,
        selectedForegroundColor: t.onPrimaryContainer,
        selectedBackgroundColor: t.primaryContainer,
        side: BorderSide(color: t.outline),
        shape: const StadiumBorder(),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.onSurfaceVariant,
      textColor: t.onSurface,
      selectedColor: t.onSelection,
      selectedTileColor: t.selection,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: t.onSurfaceVariant,
      collapsedIconColor: t.onSurfaceVariant,
      textColor: t.onSurface,
      collapsedTextColor: t.onSurface,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.primary,
      selectionColor: t.primary.withValues(alpha: 0.3),
      selectionHandleColor: t.primary,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.primary),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.primary,
      foregroundColor: t.onPrimary,
      // The tinted shadow of section 6.3 is drawn by the shell around the FAB.
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: t.surface),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
  );
}
