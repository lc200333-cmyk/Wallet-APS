import 'package:flutter/material.dart';

/// Shared monochrome pictogram and spacing for popup and selection menus.
class ContextMenuLabel extends StatelessWidget {
  const ContextMenuLabel(this.label,
      {required this.icon, this.trailing, this.maxLines, super.key});

  final String label;
  final IconData icon;
  final IconData? trailing;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 24, color: DefaultTextStyle.of(context).style.color),
          const SizedBox(width: 9),
          Expanded(
              child: Text(label,
                  maxLines: maxLines,
                  overflow: maxLines == null ? null : TextOverflow.ellipsis)),
          if (trailing != null)
            Icon(trailing,
                size: 24, color: DefaultTextStyle.of(context).style.color),
        ],
      );
}
