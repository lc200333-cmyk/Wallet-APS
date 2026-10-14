import 'dart:ui' show DisplayFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Keeps phone UI proportions consistent across Android display densities.
/// 360 is the project's reference phone width in logical pixels, not a
/// hardware-model lookup. Tablets retain their separate responsive layout.
class AndroidScreenScale extends StatelessWidget {
  const AndroidScreenScale({required this.child, super.key});

  final Widget child;
  static const referenceWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final shortSide = media.size.shortestSide;
    if (defaultTargetPlatform != TargetPlatform.android ||
        shortSide <= 0 ||
        shortSide >= 600) {
      return child;
    }
    final scale = shortSide / referenceWidth;
    if (scale == 1) return child;

    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest / scale;
      return FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: MediaQuery(
            data: media.copyWith(
              size: size,
              devicePixelRatio: media.devicePixelRatio * scale,
              padding: media.padding / scale,
              viewPadding: media.viewPadding / scale,
              viewInsets: media.viewInsets / scale,
              systemGestureInsets: media.systemGestureInsets / scale,
              displayFeatures: [
                for (final feature in media.displayFeatures)
                  DisplayFeature(
                    bounds: Rect.fromLTWH(
                      feature.bounds.left / scale,
                      feature.bounds.top / scale,
                      feature.bounds.width / scale,
                      feature.bounds.height / scale,
                    ),
                    type: feature.type,
                    state: feature.state,
                  ),
              ],
            ),
            child: child,
          ),
        ),
      );
    });
  }
}
