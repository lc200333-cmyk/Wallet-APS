import 'package:flutter/material.dart';
import 'appearance.dart';
import 'appearance_controller.dart';

class AppearanceSelector extends StatelessWidget {
  const AppearanceSelector({super.key});
  static const labels = ['Ретро', 'Светлая тема', 'Тёмная тема'];
  static const backgrounds = [
    Color(0xffb8860b),
    Color(0xffe5e7eb),
    Color(0xff374151)
  ];

  @override
  Widget build(BuildContext context) {
    final controller = AppearanceScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return TextFieldTapRegion(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Тема оформления'),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns = constraints.maxWidth >= 300 * scale ? 3 : 1;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final mode in AppAppearance.values)
                SizedBox(
                  width: (constraints.maxWidth - (columns - 1) * 8) / columns,
                  child: Semantics(
                    key: ValueKey('appearanceChoice-${mode.name}'),
                    selected: controller.mode == mode,
                    child: Tooltip(
                      message: 'Тема: ${labels[mode.index]}',
                      child: TextButton(
                        key: ValueKey('appearance-${mode.name}'),
                        onPressed: () => controller.choose(mode),
                        style: TextButton.styleFrom(
                          textStyle: theme.textTheme.labelLarge!
                              .copyWith(fontSize: 14),
                          backgroundColor: backgrounds[mode.index],
                          foregroundColor: mode == AppAppearance.dark
                              ? Colors.white
                              : const Color(0xff14171c),
                          // The existing AndroidScreenScale maps 320 dp onto
                          // a 360 dp canvas: 54 local dp still gives 48 dp taps.
                          minimumSize: const Size(0, 54),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          side: BorderSide(
                              color: controller.mode == mode
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                              width: controller.mode == mode ? 3 : 1),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (controller.mode == mode) ...[
                                const Icon(Icons.check, size: 16),
                                const SizedBox(width: 6)
                              ],
                              Flexible(
                                  child: Text(labels[mode.index],
                                      textAlign: TextAlign.center)),
                            ]),
                      ),
                    ),
                  ),
                ),
            ]);
          }),
          if (controller.error case final error?)
            Text(error, style: TextStyle(color: theme.colorScheme.error)),
        ]),
      ),
    );
  }
}
