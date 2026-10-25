import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// V1 geometry in Flutter logical pixels on every platform. The reference's
/// presumed 200% scale is applied by the framework, never multiplied here.
abstract final class WorkspaceGeometry {
  // Right-panel typography grows together with its measured row height.
  static TextStyle enlargeActionText(TextStyle style, {double increase = 2}) =>
      style.copyWith(fontSize: style.fontSize! + increase);

  static StrutStyle enlargeActionStrut(StrutStyle style,
          {double increase = 2}) =>
      StrutStyle(
        fontSize: style.fontSize! + increase,
        height: style.height,
        leading: style.leading,
        fontWeight: style.fontWeight,
        fontStyle: style.fontStyle,
        forceStrutHeight: style.forceStrutHeight,
      );

  static const windowWidth = 1280.0;
  static const windowHeight = 769.5;
  static const navigatorWidth = 247.0;
  static const actionsContentWidth = 225.0;
  static const actionsScrollbar = 19.0;
  // Overlay thumb: section backgrounds extend to the window's right edge.
  static const actionsOverlayScrollbar = 4.0;
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
  static const framedIconScale = 0.90;
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
  static const searchHeight = 27.0;
  static const searchToolbarHeight = 32.0;
  static const searchFontSize = fontSize + 3;
  static const searchTextStyle = TextStyle(
    fontSize: searchFontSize,
    height: (lineHeight + 3) / searchFontSize,
    fontWeight: FontWeight.normal,
  );
  static const searchWidth = 179.0;

  // Android panels use separate scales: folders/templates are 25% roomier,
  // while action rows and the narrow card grid retain their 15% increase.
  // Font increases are expressed in logical pixels (Flutter points).
  static const narrowAndroidScale = 1.15;
  static const androidListScale = 1.25;
  static const desktopFolderScale = 1.20;
  static const desktopTreeIconScale = 1.10;
  static const desktopCenterIconScale = 1.10;
  static const desktopCenterHorizontalScale = 1.20;
  static const narrowSideFontIncrease = 3.0;
  static const androidFolderFontIncrease = 3.0;
  static const desktopFolderFontIncrease = 2.0;
  static const androidTemplateFontIncrease = 3.0;
  static const androidActionFontIncrease = 1.0;
  static const narrowCenterFontIncrease = 2.0;
  static const wideAndroidGridScale = 1.20;
  static const wideAndroidCenterFontIncrease = 3.0;
  static const narrowRowHeight = rowHeight * narrowAndroidScale;
  static const narrowLineHeight = lineHeight * narrowAndroidScale;
  static const narrowSmallIcon = smallIcon * narrowAndroidScale;
  static const narrowActionIcon = actionIcon * narrowAndroidScale;
  static const narrowCollapseSize = collapseSize * narrowAndroidScale;
  static const narrowExpansionSize = expansionSize * narrowAndroidScale;
  static const androidListRowHeight = rowHeight * androidListScale;
  static const androidListLineHeight = lineHeight * androidListScale;
  static const androidListSmallIcon = smallIcon * androidListScale;
  static const androidListExpansionSize = expansionSize * androidListScale;
  static const desktopFolderRowHeight = rowHeight * desktopFolderScale;
  static const desktopFolderLineHeight = lineHeight * desktopFolderScale;
  static const desktopFolderIcon = smallIcon * desktopFolderScale;
  static const desktopTreeIcon = desktopFolderIcon * desktopTreeIconScale;
  static const desktopFolderExpansionSize = expansionSize * desktopFolderScale;
  static const desktopCenterIcon = largeIcon * desktopCenterIconScale;
  static const desktopCenterCellWidth = gridCell * desktopCenterHorizontalScale;
  static const narrowGridIcon = largeIcon * narrowAndroidScale;
  static const narrowGridCell = gridCell * narrowAndroidScale;
  static const narrowLabelHeight = labelHeight * narrowAndroidScale;
  static const wideAndroidGridIcon = largeIcon * wideAndroidGridScale;
  static const wideAndroidGridCell = gridCell * wideAndroidGridScale;
  static const wideAndroidLabelWidth = labelWidth * wideAndroidGridScale;
  static const wideAndroidLabelHeight = labelHeight * wideAndroidGridScale;

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
  static const desktopCardNameStyle = TextStyle(
    fontSize: itemNameFontSize + 1,
    height: lineHeight / (itemNameFontSize + 1),
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
  static const desktopCardNameStrut = StrutStyle(
    fontSize: itemNameFontSize + 1,
    height: lineHeight / (itemNameFontSize + 1),
    forceStrutHeight: true,
  );
  static const narrowSideBodyStyle = TextStyle(
    fontSize: fontSize + narrowSideFontIncrease,
    height: narrowLineHeight / (fontSize + narrowSideFontIncrease),
    fontWeight: FontWeight.normal,
  );
  static const narrowSideFolderStyle = TextStyle(
    fontSize: itemNameFontSize + 1 + narrowSideFontIncrease,
    height: narrowLineHeight / (itemNameFontSize + 1 + narrowSideFontIncrease),
    fontWeight: FontWeight.normal,
  );
  static const narrowSideItemNameStyle = TextStyle(
    fontSize: itemNameFontSize + narrowSideFontIncrease,
    height: narrowLineHeight / (itemNameFontSize + narrowSideFontIncrease),
    fontWeight: FontWeight.normal,
  );
  static const narrowSideHeadingStyle = TextStyle(
    fontSize: headingFontSize + narrowSideFontIncrease,
    fontWeight: FontWeight.bold,
  );
  static const narrowSideBodyStrut = StrutStyle(
    fontSize: fontSize + narrowSideFontIncrease,
    height: narrowLineHeight / (fontSize + narrowSideFontIncrease),
    forceStrutHeight: true,
  );
  static const narrowSideItemNameStrut = StrutStyle(
    fontSize: itemNameFontSize + narrowSideFontIncrease,
    height: narrowLineHeight / (itemNameFontSize + narrowSideFontIncrease),
    forceStrutHeight: true,
  );
  static const androidFolderStyle = TextStyle(
    fontSize: itemNameFontSize + 1 + androidFolderFontIncrease,
    height: androidListLineHeight /
        (itemNameFontSize + 1 + androidFolderFontIncrease),
    fontWeight: FontWeight.normal,
  );
  static const androidFolderStrut = StrutStyle(
    fontSize: itemNameFontSize + 1 + androidFolderFontIncrease,
    height: androidListLineHeight /
        (itemNameFontSize + 1 + androidFolderFontIncrease),
    forceStrutHeight: true,
  );
  // Only the left tree grows; center-pane folder and card labels keep their size.
  static final androidTreeFolderStyle = androidFolderStyle.copyWith(
    fontSize: androidFolderStyle.fontSize! * 1.15,
  );
  static final androidTreeFolderStrut = StrutStyle(
    fontSize: androidFolderStrut.fontSize! * 1.15,
    height: androidFolderStrut.height,
    forceStrutHeight: true,
  );
  static const desktopFolderStyle = TextStyle(
    fontSize: itemNameFontSize + 1 + desktopFolderFontIncrease,
    height: desktopFolderLineHeight /
        (itemNameFontSize + 1 + desktopFolderFontIncrease),
    fontWeight: FontWeight.normal,
  );
  static const desktopFolderStrut = StrutStyle(
    fontSize: itemNameFontSize + 1 + desktopFolderFontIncrease,
    height: desktopFolderLineHeight /
        (itemNameFontSize + 1 + desktopFolderFontIncrease),
    forceStrutHeight: true,
  );
  static const androidTemplateStyle = TextStyle(
    fontSize: itemNameFontSize + androidTemplateFontIncrease,
    height: androidListLineHeight /
        (itemNameFontSize + androidTemplateFontIncrease),
    fontWeight: FontWeight.normal,
  );
  static const androidTemplateStrut = StrutStyle(
    fontSize: itemNameFontSize + androidTemplateFontIncrease,
    height: androidListLineHeight /
        (itemNameFontSize + androidTemplateFontIncrease),
    forceStrutHeight: true,
  );
  static const androidActionBodyStyle = TextStyle(
    fontSize: fontSize + androidActionFontIncrease,
    height: narrowLineHeight / (fontSize + androidActionFontIncrease),
    fontWeight: FontWeight.normal,
  );
  static const androidActionItemNameStyle = TextStyle(
    fontSize: itemNameFontSize + androidActionFontIncrease,
    height: narrowLineHeight / (itemNameFontSize + androidActionFontIncrease),
    fontWeight: FontWeight.normal,
  );
  static const androidActionHeadingStyle = TextStyle(
    fontSize: headingFontSize + androidActionFontIncrease,
    fontWeight: FontWeight.bold,
  );
  static const androidActionBodyStrut = StrutStyle(
    fontSize: fontSize + androidActionFontIncrease,
    height: narrowLineHeight / (fontSize + androidActionFontIncrease),
    forceStrutHeight: true,
  );
  static const androidActionItemNameStrut = StrutStyle(
    fontSize: itemNameFontSize + androidActionFontIncrease,
    height: narrowLineHeight / (itemNameFontSize + androidActionFontIncrease),
    forceStrutHeight: true,
  );
  static const wideAndroidSideBodyStyle = TextStyle(
    fontSize: fontSize,
    height: narrowLineHeight / fontSize,
    fontWeight: FontWeight.normal,
  );
  static const wideAndroidSideFolderStyle = TextStyle(
    fontSize: itemNameFontSize + 1,
    height: narrowLineHeight / (itemNameFontSize + 1),
    fontWeight: FontWeight.normal,
  );
  static const wideAndroidSideItemNameStyle = TextStyle(
    fontSize: itemNameFontSize,
    height: narrowLineHeight / itemNameFontSize,
    fontWeight: FontWeight.normal,
  );
  static const wideAndroidSideBodyStrut = StrutStyle(
    fontSize: fontSize,
    height: narrowLineHeight / fontSize,
    forceStrutHeight: true,
  );
  static const wideAndroidSideItemNameStrut = StrutStyle(
    fontSize: itemNameFontSize,
    height: narrowLineHeight / itemNameFontSize,
    forceStrutHeight: true,
  );
  static const narrowCenterItemNameStyle = TextStyle(
    fontSize: itemNameFontSize + narrowCenterFontIncrease,
    height: narrowLineHeight / (itemNameFontSize + narrowCenterFontIncrease),
    fontWeight: FontWeight.normal,
  );
  static const narrowCenterFolderStyle = TextStyle(
    fontSize: itemNameFontSize + 2 + narrowCenterFontIncrease,
    height:
        narrowLineHeight / (itemNameFontSize + 2 + narrowCenterFontIncrease),
    fontWeight: FontWeight.normal,
  );
  static const narrowCenterItemNameStrut = StrutStyle(
    fontSize: itemNameFontSize + narrowCenterFontIncrease,
    height: narrowLineHeight / (itemNameFontSize + narrowCenterFontIncrease),
    forceStrutHeight: true,
  );
  static const wideAndroidCenterItemNameStyle = TextStyle(
    fontSize: itemNameFontSize + wideAndroidCenterFontIncrease,
    height: (lineHeight * wideAndroidGridScale) /
        (itemNameFontSize + wideAndroidCenterFontIncrease),
    fontWeight: FontWeight.normal,
  );
  static const wideAndroidCenterFolderStyle = TextStyle(
    fontSize: itemNameFontSize + 2 + wideAndroidCenterFontIncrease,
    height: (lineHeight * wideAndroidGridScale) /
        (itemNameFontSize + 2 + wideAndroidCenterFontIncrease),
    fontWeight: FontWeight.normal,
  );
  static const wideAndroidCenterItemNameStrut = StrutStyle(
    fontSize: itemNameFontSize + wideAndroidCenterFontIncrease,
    height: (lineHeight * wideAndroidGridScale) /
        (itemNameFontSize + wideAndroidCenterFontIncrease),
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

/// Adds horizontal room between desktop card columns without changing their
/// vertical rhythm.
class DesktopCardGridDelegate extends SliverGridDelegate {
  const DesktopCardGridDelegate();

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    const cellWidth = WorkspaceGeometry.desktopCenterCellWidth;
    const cellHeight = WorkspaceGeometry.gridCell;
    return SliverGridRegularTileLayout(
      crossAxisCount:
          math.max(1, (constraints.crossAxisExtent / cellWidth).floor()),
      mainAxisStride: cellHeight,
      crossAxisStride: cellWidth,
      childMainAxisExtent: cellHeight,
      childCrossAxisExtent: cellWidth,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(covariant DesktopCardGridDelegate oldDelegate) => false;
}

/// Uses the full phone width for exactly three columns. Wider cells place the
/// icon centres farther apart and give two-line card captions more room.
class NarrowAndroidGridDelegate extends SliverGridDelegate {
  const NarrowAndroidGridDelegate();

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    const crossAxisCount = 3;
    final cellWidth = constraints.crossAxisExtent / crossAxisCount;
    return SliverGridRegularTileLayout(
      crossAxisCount: crossAxisCount,
      mainAxisStride: WorkspaceGeometry.narrowGridCell,
      crossAxisStride: cellWidth,
      childMainAxisExtent: WorkspaceGeometry.narrowGridCell,
      childCrossAxisExtent: cellWidth,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(covariant NarrowAndroidGridDelegate oldDelegate) => false;
}

/// Retains the fixed desktop-style grid while increasing both grid strides by
/// 20% on wide Android screens.
class WideAndroidGridDelegate extends SliverGridDelegate {
  const WideAndroidGridDelegate();

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    const cell = WorkspaceGeometry.wideAndroidGridCell;
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
  bool shouldRelayout(covariant WideAndroidGridDelegate oldDelegate) => false;
}
