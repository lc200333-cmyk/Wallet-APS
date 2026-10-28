part of '../../main.dart';

// Shared dialog styling. Every function returns the original Retro value
// unchanged; Light and Dark get flat surfaces, outlines and rounded shapes
// (section 12 of the skin task).

Color skinDialogBackground(BuildContext context) {
  final t = WalletSkinTokens.of(context);
  return t.isRetro ? appWindowBackgroundColor : t.surface;
}

BoxDecoration skinDialogHeaderDecoration(BuildContext context) {
  final t = WalletSkinTokens.of(context);
  if (t.isRetro) {
    return const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xffa9c9e3), Color(0xffe9f1f8)],
      ),
      border: Border(bottom: BorderSide(color: Color(0xff7f8d98))),
    );
  }
  return BoxDecoration(
    color: t.surface,
    border: Border(bottom: BorderSide(color: t.outline)),
  );
}

BoxDecoration skinDialogFooterDecoration(BuildContext context) {
  final t = WalletSkinTokens.of(context);
  if (t.isRetro) {
    return const BoxDecoration(
      color: Color(0xffdce8f1),
      border: Border(top: BorderSide(color: Color(0xff7f8d98))),
    );
  }
  return BoxDecoration(
    color: t.surface,
    border: Border(top: BorderSide(color: t.outline)),
  );
}

/// Window frame of the large dialogs. Narrow modern dialogs fill the screen
/// and therefore have no rounded corners.
ShapeBorder skinDialogShape(BuildContext context) {
  final t = WalletSkinTokens.of(context);
  if (t.isRetro) {
    return const RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
      side: BorderSide(color: Color(0xff7f8d98)),
    );
  }
  if (skinNarrowLayout(context)) {
    return const RoundedRectangleBorder(borderRadius: BorderRadius.zero);
  }
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(24),
    side: t.isDark ? BorderSide(color: t.outline) : BorderSide.none,
  );
}

Gradient skinGrayGradient(BuildContext context, Color retroBottom) {
  final t = WalletSkinTokens.of(context);
  if (t.isRetro) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [const Color(0xfff4f4f4), retroBottom],
    );
  }
  return LinearGradient(colors: [t.s2, t.s2]);
}

Color skinGrayBorder(BuildContext context) {
  final t = WalletSkinTokens.of(context);
  return t.isRetro ? const Color(0xff676767) : t.outline;
}

List<BoxShadow> skinGrayShadow(BuildContext context) {
  final t = WalletSkinTokens.of(context);
  if (!t.isRetro) return const [];
  return const [
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
  ];
}

Color skinGrayForeground(BuildContext context) {
  final t = WalletSkinTokens.of(context);
  return t.isRetro ? const Color(0xff303030) : t.onSurfaceVariant;
}

/// White framed icon well of cards, folders and templates.
Color skinFrameFill(BuildContext context) {
  final t = WalletSkinTokens.of(context);
  return t.isRetro ? Colors.white : t.s2;
}

Border skinFrameBorder(BuildContext context, {double width = 2}) {
  final t = WalletSkinTokens.of(context);
  if (t.isRetro) {
    return Border.all(color: const Color(0xff82929d), width: width);
  }
  return Border.all(color: t.outline, width: 1);
}

double skinFrameRadius(BuildContext context, double retro) =>
    WalletSkinTokens.of(context).isRetro ? retro : 16;

List<BoxShadow> skinFrameShadow(BuildContext context) {
  final t = WalletSkinTokens.of(context);
  if (!t.isRetro) return const [];
  return const [
    BoxShadow(
      color: Color(0x26000000),
      offset: Offset(1, 2),
      blurRadius: 5,
    ),
  ];
}

/// Colour of a card's own surface in the preview and the editor.
Color skinCardSurface(BuildContext context, PaletteColor color) {
  final t = WalletSkinTokens.of(context);
  if (t.isRetro) return color.bg;
  return skinTileForPalette(t, color).tile;
}

/// Field background placed on a card surface.
Color skinCardFieldFill(BuildContext context, PaletteColor color) {
  final t = WalletSkinTokens.of(context);
  if (t.isRetro) return color.bg;
  return t.surface.withValues(alpha: 0.92);
}

/// Footer and toolbar buttons of the large dialogs. Retro draws its 3D
/// gradient; Light and Dark derive the role from the original colour and
/// tooltip so that no new labels are introduced.
Widget skinModernActionButton({
  required BuildContext context,
  Key? key,
  required IconData icon,
  required String tooltip,
  required List<Color> colors,
  required VoidCallback? onTap,
  required bool tooltipPreferBelow,
}) {
  final t = WalletSkinTokens.of(context);
  final first = colors.isEmpty ? const Color(0xff000000) : colors.first;
  final destructive = tooltip.startsWith('Удалить');
  final (Color background, Color foreground, BorderSide side) = destructive
      ? (t.errorContainer, t.error, BorderSide.none)
      : switch (first.toARGB32()) {
          0xff5bc96d || 0xff43a047 => (t.primary, t.onPrimary, BorderSide.none),
          0xffff5a5f || 0xffd32b31 => (
              Colors.transparent,
              t.onSurfaceVariant,
              BorderSide(color: t.outline),
            ),
          0xff555555 => (t.s2, t.onSurface, BorderSide.none),
          _ => (t.primaryContainer, t.onPrimaryContainer, BorderSide.none),
        };
  final radius = BorderRadius.circular(12);
  return SizedBox.square(
    dimension: 48,
    child: Center(
      child: Tooltip(
        message: tooltip,
        preferBelow: tooltipPreferBelow,
        child: Opacity(
          opacity: onTap == null ? 0.38 : 1,
          child: Material(
            key: key,
            color: background,
            shape: RoundedRectangleBorder(borderRadius: radius, side: side),
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: SizedBox(
                width: 44,
                height: 40,
                child: Icon(icon, color: foreground, size: 22),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Colour swatch fill: the stored colour in Retro, its modern tile otherwise.
Color swatchColor(BuildContext context, PaletteColor color) {
  final t = WalletSkinTokens.of(context);
  return t.isRetro ? color.bg : skinTileForPalette(t, color).tile;
}

Color swatchBorder(BuildContext context, bool selected) {
  final t = WalletSkinTokens.of(context);
  if (t.isRetro) {
    return selected ? const Color(0xff253d4c) : const Color(0xff8b969d);
  }
  return selected ? t.primary : t.outline;
}

Color skinFrameEdge(BuildContext context) {
  final t = WalletSkinTokens.of(context);
  return t.isRetro ? const Color(0xff82929d) : t.outline;
}

/// Shape of AlertDialogs that set their own Retro corner radius.
ShapeBorder skinAlertShape(BuildContext context, double retroRadius) {
  final t = WalletSkinTokens.of(context);
  if (t.isRetro) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(retroRadius),
    );
  }
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(skinNarrowLayout(context) ? 28 : 24),
    side: t.isDark ? BorderSide(color: t.outline) : BorderSide.none,
  );
}

Color skinSelectionColor(BuildContext context) {
  final t = WalletSkinTokens.of(context);
  return t.isRetro ? const Color(0xffcfe9fb) : t.selection;
}

/// Text on a selected row; Retro keeps the ListTile default.
Color? skinOnSelectionColor(BuildContext context) {
  final t = WalletSkinTokens.of(context);
  return t.isRetro ? null : t.onSelection;
}

extension _ModernInactivityDialog on _VaultShellState {
  /// Autolock warning of the Light and Dark skins (section 12.4): the same
  /// countdown, text and continue action, drawn around a progress ring.
  Widget buildModernInactivityDialog(
    BuildContext context,
    BuildContext dialogContext,
  ) {
    final t = WalletSkinTokens.of(context);
    final seconds = inactivitySecondsRemaining;
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: t.isDark ? BorderSide(color: t.outline) : BorderSide.none,
      ),
      backgroundColor: t.surface,
      child: SizedBox(
        width: 360,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 96,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: (seconds / 15).clamp(0.0, 1.0),
                      strokeWidth: 6,
                      color: t.primary,
                      backgroundColor: t.outline,
                    ),
                    Center(
                      child: Text(
                        '$seconds',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          color: t.onSurface,
                          fontFeatures: const [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Предупреждение',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: t.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Хранилище будет заблокировано через '
                '$seconds секунд',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: t.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('inactivityContinueButton'),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Продолжить работу'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
