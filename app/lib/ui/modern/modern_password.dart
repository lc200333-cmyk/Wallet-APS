part of '../../main.dart';

/// Colours of the three skin buttons, chosen by the owner: dark yellow for
/// Retro, light grey for Light and dark grey for Dark. They are identical in
/// every skin so the buttons are recognisable whichever skin is active.
const _skinButtonColors = <AppSkin, ({Color top, Color bottom, Color text})>{
  AppSkin.retro: (
    top: Color(0xffd9a521),
    bottom: Color(0xff8a6100),
    text: Color(0xffffffff),
  ),
  AppSkin.light: (
    top: Color(0xfff6f7f9),
    bottom: Color(0xffc9ced6),
    text: Color(0xff16212a),
  ),
  AppSkin.dark: (
    top: Color(0xff5d636c),
    bottom: Color(0xff24282e),
    text: Color(0xffffffff),
  ),
};

const _skinButtonLabels = <AppSkin, String>{
  AppSkin.retro: 'Ретро',
  AppSkin.light: 'Светлая',
  AppSkin.dark: 'Тёмная',
};

const _skinButtonKeys = <AppSkin, Key>{
  AppSkin.retro: Key('skinRetroButton'),
  AppSkin.light: Key('skinLightButton'),
  AppSkin.dark: Key('skinDarkButton'),
};

extension _ModernPasswordWindow on _VaultShellState {
  WalletSkinTokens get skinTokens => WalletSkinTokens.of(context);

  OutlineInputBorder modernFieldBorder(Color color, double width) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  /// Flat password-window button of the Light and Dark skins (section 6.6).
  Widget modernPasswordKey(
    WalletSkinTokens t, {
    required String label,
    required VoidCallback onPressed,
    Widget? child,
    String? tooltip,
    bool selected = false,
    double fontSize = 34,
    FontWeight fontWeight = FontWeight.w500,
    required double height,
    Key? key,
    required SkinKeyRole role,
  }) {
    final roundButton = role == SkinKeyRole.outlined ||
        role == SkinKeyRole.primary ||
        role == SkinKeyRole.danger;
    final radius = BorderRadius.circular(roundButton ? 999 : 8);
    final (Color background, Color foreground, BorderSide side) =
        switch (role) {
      SkinKeyRole.character => (t.keyCharacter, t.onSurface, BorderSide.none),
      SkinKeyRole.service => (t.keyService, t.onSurface, BorderSide.none),
      SkinKeyRole.mode => selected
          ? (
              t.primaryContainer,
              t.onPrimaryContainer,
              BorderSide(color: t.primary, width: 2),
            )
          : (t.keyCharacter, t.onSurface, BorderSide.none),
      SkinKeyRole.hint => (t.warningContainer, t.warning, BorderSide.none),
      SkinKeyRole.outlined => (
          Colors.transparent,
          t.onSurface,
          BorderSide(color: t.outline),
        ),
      SkinKeyRole.primary => (t.primary, t.onPrimary, BorderSide.none),
      SkinKeyRole.danger => (t.errorContainer, t.error, BorderSide.none),
    };
    final shadow = role == SkinKeyRole.character || role == SkinKeyRole.mode
        ? t.keyCharacterShadow
        : null;
    final button = SizedBox(
      height: height,
      child: Material(
        key: key,
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: background,
            borderRadius: radius,
            border:
                side == BorderSide.none ? null : Border.fromBorderSide(side),
            boxShadow: shadow == null
                ? null
                : [BoxShadow(color: shadow, offset: const Offset(0, 1))],
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            overlayColor: WidgetStatePropertyAll(
              t.onSurface.withValues(alpha: 0.12),
            ),
            child: Center(
              child: IconTheme(
                data: IconThemeData(color: foreground),
                child: child ??
                    Text(
                      label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: fontSize,
                        height: 1,
                        fontWeight: fontWeight,
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: role == SkinKeyRole.mode ? selected : null,
      label: tooltip ?? label,
      child: tooltip == null
          ? button
          : Tooltip(
              message: tooltip,
              excludeFromSemantics: true,
              child: button,
            ),
    );
  }

  /// The skin row at the bottom of the password window (section 9).
  Widget buildSkinSelector() {
    final t = skinTokens;
    final current = appSkin.value;
    void choose(AppSkin skin) {
      if (skin != appSkin.value) selectAppSkin(skin);
      passwordFocusNode.requestFocus();
    }

    Widget skinButton(AppSkin skin) {
      final colors = _skinButtonColors[skin]!;
      final selected = skin == current;
      final caption = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) ...[
            Icon(Icons.check, size: 16, color: colors.text),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              _skinButtonLabels[skin]!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.text,
                fontSize: 16,
                height: 1,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      );
      final Widget body;
      if (t.isRetro) {
        body = passwordKey(
          key: _skinButtonKeys[skin],
          label: _skinButtonLabels[skin]!,
          height: 40,
          minimumHeight: 40,
          fontSize: 16,
          selected: selected,
          top: colors.top,
          bottom: colors.bottom,
          onPressed: () => choose(skin),
          child: caption,
        );
      } else {
        final radius = BorderRadius.circular(8);
        body = SizedBox(
          height: 40,
          child: Material(
            key: _skinButtonKeys[skin],
            color: Color.lerp(colors.top, colors.bottom, 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: selected
                  ? BorderSide(color: t.primary, width: 2)
                  : BorderSide(color: t.outline),
            ),
            child: InkWell(
              borderRadius: radius,
              onTap: () => choose(skin),
              child: Center(child: caption),
            ),
          ),
        );
      }
      return Semantics(
        selected: selected,
        button: true,
        label: 'Тема: ${_skinButtonLabels[skin]}',
        excludeSemantics: true,
        child: body,
      );
    }

    return Padding(
      key: const Key('skinSelector'),
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Text(
              'Тема:',
              style: TextStyle(
                fontSize: t.isRetro ? 16 : 14,
                color: t.isRetro ? const Color(0xff16212a) : t.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  for (final skin in AppSkin.values) ...[
                    if (skin != AppSkin.retro) const SizedBox(width: 5),
                    Expanded(child: skinButton(skin)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
