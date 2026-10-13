import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// V1 geometry in Flutter logical pixels on every platform. The reference's
/// presumed 200% scale is applied by the framework, never multiplied here.
abstract final class WorkspaceGeometry {
  static const windowWidth = 1280.0;
  static const windowHeight = 769.5;
  static const navigatorWidth = 247.0;
  static const actionsContentWidth = 225.0;
  static const actionsScrollbar = 19.0;
  static const actionsWidth = actionsContentWidth + actionsScrollbar;
  static const divider = 4.0;
  static const headerHeight = 25.0;
  static const toolbarHeight = 26.0;
  static const toolbarButtonWidth = 22.0;
  static const toolbarButtonHeight = 24.0;
  static const fontSize = 12.0;
  static const itemNameFontSize = 13.0;
  static const headingFontSize = 13.0;
  static const menuFontSize = 14.0;
  static const navigatorHeadingFontSize = 16.0;
  static const lineHeight = 15.0;
  static const rowHeight = 20.0;
  static const smallIcon = 16.0;
  static const largeIcon = 32.0;
  static const treeTop = 19.0;
  static const treeIndent = 19.0;
  static const expansionSize = 9.0;
  static const treeScrollbar = 16.0;
  static const treeHorizontalScrollbar = 17.0;
  static const sectionHeight = 32.0;
  static const sectionIcon = 24.0;
  static const sectionDivider = 6.0;
  static const gridCell = 75.0;
  static const iconFrameContent = 64.0;
  static const labelWidth = 72.0;
  static const labelHeight = 30.0;
  static const iconTop = 3.0;
  static const labelGap = 3.0;
  static const blockMargin = 12.0;
  static const blockTop = 14.0;
  static const blockGap = 15.0;
  static const actionIconLeft = 14.0;
  static const actionIcon = smallIcon + 6.0;
  static const actionIconGap = 6.0;
  static const actionTextStart = actionIconLeft + actionIcon + actionIconGap;
  static const collapseSize = 18.0;
  static const frequentTop = 9.0;
  static const searchHeight = 21.0;
  static const searchWidth = 179.0;

  static const bodyStyle = TextStyle(
    fontSize: fontSize,
    height: lineHeight / fontSize,
    fontWeight: FontWeight.normal,
  );
  static const folderStyle = TextStyle(
    fontSize: itemNameFontSize + 1,
    height: lineHeight / (itemNameFontSize + 1),
    fontWeight: FontWeight.normal,
  );
  static const itemNameStyle = TextStyle(
    fontSize: itemNameFontSize,
    height: lineHeight / itemNameFontSize,
    fontWeight: FontWeight.normal,
  );
  static const headingStyle = TextStyle(
    fontSize: headingFontSize,
    fontWeight: FontWeight.bold,
  );
  static const bodyStrut = StrutStyle(
    fontSize: fontSize,
    height: lineHeight / fontSize,
    forceStrutHeight: true,
  );
  static const itemNameStrut = StrutStyle(
    fontSize: itemNameFontSize,
    height: lineHeight / itemNameFontSize,
    forceStrutHeight: true,
  );
}

/// Keeps both dimensions and strides fixed; surplus width stays at the right.
/// A MaxCrossAxisExtent delegate would stretch cells or add an extra column.
class WorkspaceGridDelegate extends SliverGridDelegate {
  const WorkspaceGridDelegate();

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    const cell = WorkspaceGeometry.gridCell;
    return SliverGridRegularTileLayout(
      crossAxisCount: math.max(1, (constraints.crossAxisExtent / cell).floor()),
      mainAxisStride: cell,
      crossAxisStride: cell,
      childMainAxisExtent: cell,
      childCrossAxisExtent: cell,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(covariant WorkspaceGridDelegate oldDelegate) => false;
}
