import 'package:flutter/material.dart';

/// Object choices retain their own image; command menus use pictograms.
class ObjectSelectionMenuLabel extends StatelessWidget {
  const ObjectSelectionMenuLabel(this.label, {required this.image, super.key});

  final String label;
  final Widget image;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox.square(dimension: 24, child: image),
          const SizedBox(width: 9),
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      );
}
