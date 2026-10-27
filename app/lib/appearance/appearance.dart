import 'package:flutter/material.dart';

enum AppAppearance { retro, light, dark }

/// Explicit UI roles; no role is inferred from a legacy RGB value.
enum AppearanceRole {
  canvas,
  surface,
  raisedSurface,
  header,
  selected,
  text,
  secondaryText,
  divider,
  outline,
  focus,
  primary,
  onPrimary,
  error,
  errorSurface,
  success,
  warning,
  warningSurface,
  shadow,
}

@immutable
class AppearanceTheme extends ThemeExtension<AppearanceTheme> {
  const AppearanceTheme(this.mode, this.scheme);
  final AppAppearance mode;
  final ColorScheme scheme;
  bool get isRetro => mode == AppAppearance.retro;
  bool get isDark => mode == AppAppearance.dark;

  static AppearanceTheme of(BuildContext context) =>
      Theme.of(context).extension<AppearanceTheme>() ??
      AppearanceTheme(AppAppearance.retro, Theme.of(context).colorScheme);

  Color resolve(AppearanceRole role, Color legacy) {
    if (isRetro || legacy.a == 0) return legacy;
    return switch (role) {
      AppearanceRole.canvas => Color(isDark ? 0xff0e1014 : 0xfff5f6f8),
      AppearanceRole.surface => scheme.surface,
      AppearanceRole.header ||
      AppearanceRole.raisedSurface =>
        Color(isDark ? 0xff1f232a : 0xffeef0f4),
      AppearanceRole.selected =>
        scheme.primaryContainer.withValues(alpha: legacy.a),
      AppearanceRole.text => scheme.onSurface,
      AppearanceRole.secondaryText => scheme.onSurfaceVariant,
      AppearanceRole.divider => scheme.outlineVariant,
      AppearanceRole.outline => scheme.outline,
      AppearanceRole.focus || AppearanceRole.primary => scheme.primary,
      AppearanceRole.onPrimary => scheme.onPrimary,
      AppearanceRole.error => scheme.error,
      AppearanceRole.errorSurface => scheme.errorContainer,
      // Text shades are slightly stronger than the concept's success/warning
      // swatches, so normal-sized text also meets 4.5:1 on the light surface.
      AppearanceRole.success => Color(isDark ? 0xff62cf98 : 0xff187847),
      AppearanceRole.warning => Color(isDark ? 0xfff2c063 : 0xff945b00),
      AppearanceRole.warningSurface => Color(isDark ? 0xff3b2e16 : 0xfffff1d3),
      AppearanceRole.shadow => Colors.transparent,
    };
  }

  /// Display-only adaptation; never assign the result to a model/storage field.
  Color objectSurface(Color stored) {
    if (isRetro) return stored;
    final hsl = HSLColor.fromColor(stored);
    if (isDark) {
      return hsl
          .withLightness(.14)
          .withSaturation(hsl.saturation * .5)
          .toColor();
    }
    return stored.computeLuminance() > .6
        ? stored
        : hsl.withLightness(.95).withSaturation(hsl.saturation * .5).toColor();
  }

  @override
  AppearanceTheme copyWith({AppAppearance? mode, ColorScheme? scheme}) =>
      AppearanceTheme(mode ?? this.mode, scheme ?? this.scheme);

  @override
  AppearanceTheme lerp(covariant AppearanceTheme? other, double t) =>
      other == null
          ? this
          : AppearanceTheme(t < .5 ? mode : other.mode,
              ColorScheme.lerp(scheme, other.scheme, t));
}

Color appearanceColor(
        BuildContext context, AppearanceRole role, Color legacy) =>
    AppearanceTheme.of(context).resolve(role, legacy);

List<Color> appearanceGradient(
    BuildContext context, AppearanceRole role, List<Color> legacy) {
  final theme = AppearanceTheme.of(context);
  if (theme.isRetro) return legacy;
  final colour = theme.resolve(role, legacy.first);
  return [colour, colour];
}

Color appearanceObjectSurface(BuildContext context, Color stored) =>
    AppearanceTheme.of(context).objectSurface(stored);

BorderRadius appearanceRadius(BuildContext context, BorderRadius legacy) =>
    AppearanceTheme.of(context).isRetro ? legacy : BorderRadius.circular(8);

/// Roles assigned by command meaning, not by the old button gradient.
(Color, Color) appearanceAction(BuildContext context, IconData icon) {
  final s = Theme.of(context).colorScheme;
  if ([
    Icons.delete,
    Icons.delete_outline,
    Icons.delete_forever,
    Icons.delete_forever_outlined
  ].contains(icon)) {
    return (s.errorContainer, s.onErrorContainer);
  }
  if ([Icons.close, Icons.cancel, Icons.logout, Icons.power_settings_new]
      .contains(icon)) {
    return (
      AppearanceTheme.of(context)
          .resolve(AppearanceRole.raisedSurface, s.surface),
      s.onSurface
    );
  }
  if (icon == Icons.undo || icon == Icons.history) {
    return (s.primaryContainer, s.onPrimaryContainer);
  }
  return (s.primary, s.onPrimary);
}

List<Color> appearanceActionGradient(
        BuildContext context, List<Color> legacy, IconData icon) =>
    AppearanceTheme.of(context).isRetro
        ? legacy
        : [
            appearanceAction(context, icon).$1,
            appearanceAction(context, icon).$1
          ];

Color appearanceActionText(BuildContext context, IconData icon) =>
    AppearanceTheme.of(context).isRetro
        ? Colors.white
        : appearanceAction(context, icon).$2;

/// The Retro factory retains the original values and enlarged text exactly.
ThemeData appearanceThemeData(AppAppearance mode) {
  final retro = mode == AppAppearance.retro;
  final dark = mode == AppAppearance.dark;
  var scheme = ColorScheme.fromSeed(
    seedColor: retro ? const Color(0xff2d6f73) : const Color(0xff2f5bea),
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  if (!retro) {
    scheme = scheme.copyWith(
      primary: Color(dark ? 0xff8eaaff : 0xff2f5bea),
      onPrimary: Color(dark ? 0xff0b1a55 : 0xffffffff),
      primaryContainer: Color(dark ? 0xff24345f : 0xffdde6ff),
      onPrimaryContainer: Color(dark ? 0xffe8eaef : 0xff14171c),
      surface: Color(dark ? 0xff171a20 : 0xffffffff),
      onSurface: Color(dark ? 0xffe8eaef : 0xff14171c),
      onSurfaceVariant: Color(dark ? 0xffa0a7b4 : 0xff5b6270),
      outline: Color(dark ? 0xff647084 : 0xff727b8a),
      outlineVariant: Color(dark ? 0xff333944 : 0xffd6dae1),
      error: Color(dark ? 0xffff8a80 : 0xffc9372c),
      errorContainer: Color(dark ? 0xff512d30 : 0xffffe7e4),
      onErrorContainer: Color(dark ? 0xffffdad6 : 0xff7b1712),
    );
  }
  final tokens = AppearanceTheme(mode, scheme);
  final background =
      tokens.resolve(AppearanceRole.canvas, const Color(0xffe6e6e6));
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    dialogTheme: DialogThemeData(
        backgroundColor: background, surfaceTintColor: Colors.transparent),
    visualDensity: VisualDensity.standard,
    scrollbarTheme: const ScrollbarThemeData(
        thickness: WidgetStatePropertyAll<double>(13.6)),
    extensions: [tokens],
  );
  TextStyle enlarged(TextStyle? style, double size) =>
      (style ?? const TextStyle()).copyWith(
        fontSize: (style?.fontSize ?? size) + 2,
        fontWeight: FontWeight.normal,
      );
  final t = base.textTheme;
  final text = TextTheme(
    displayLarge: enlarged(t.displayLarge, 57),
    displayMedium: enlarged(t.displayMedium, 45),
    displaySmall: enlarged(t.displaySmall, 36),
    headlineLarge: enlarged(t.headlineLarge, 32),
    headlineMedium: enlarged(t.headlineMedium, 28),
    headlineSmall: enlarged(t.headlineSmall, 24),
    titleLarge: enlarged(t.titleLarge, 22),
    titleMedium: enlarged(t.titleMedium, 16),
    titleSmall: enlarged(t.titleSmall, 14),
    bodyLarge: enlarged(t.bodyLarge, 16),
    bodyMedium: enlarged(t.bodyMedium, 14),
    bodySmall: enlarged(t.bodySmall, 12),
    labelLarge: enlarged(t.labelLarge, 14),
    labelMedium: enlarged(t.labelMedium, 12),
    labelSmall: enlarged(t.labelSmall, 11),
  );
  return base.copyWith(
    textTheme: text,
    popupMenuTheme: PopupMenuThemeData(
        textStyle:
            text.labelLarge!.copyWith(fontSize: text.labelLarge!.fontSize! + 1),
        color: retro ? null : scheme.surface,
        shape: retro
            ? null
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: scheme.outlineVariant))),
    inputDecorationTheme: retro
        ? null
        : InputDecorationTheme(
            filled: true,
            fillColor: scheme.surface,
            labelStyle: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
  );
}
