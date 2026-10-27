import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'workspace_geometry.dart';
import '../appearance/appearance.dart';

/// Matching section strips in the navigator and the actions panel.
class WorkspaceSectionBar extends StatelessWidget {
  const WorkspaceSectionBar(
      {required this.label,
      required this.leading,
      required this.selected,
      this.trailing,
      this.showBottomBorder = false,
      this.alwaysHighlighted = false,
      super.key});

  final String label;
  final Widget leading;
  final bool selected;
  final Widget? trailing;
  final bool showBottomBorder;
  final bool alwaysHighlighted;

  @override
  Widget build(BuildContext context) {
    final scale = defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.windows
        ? 1.1
        : 1.0;
    return Container(
      height: WorkspaceGeometry.sectionHeight * scale,
      padding: const EdgeInsets.symmetric(horizontal: 7.5),
      decoration: BoxDecoration(
        color: selected || alwaysHighlighted
            ? appearanceColor(
                context, AppearanceRole.selected, const Color(0xffdbeaf5))
            : appearanceColor(
                context, AppearanceRole.header, const Color(0xfff5f5f5)),
        border: Border(
          top: BorderSide(
              color: appearanceColor(
                  context, AppearanceRole.divider, const Color(0xffb7b7b7))),
          bottom: showBottomBorder
              ? BorderSide(
                  color: appearanceColor(
                      context, AppearanceRole.divider, const Color(0xffb7b7b7)))
              : BorderSide.none,
        ),
      ),
      child: Row(children: [
        leading,
        const SizedBox(width: 5),
        Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: WorkspaceGeometry.menuFontSize * scale,
                    fontWeight: FontWeight.bold))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}
