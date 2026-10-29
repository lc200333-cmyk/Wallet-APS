import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A [Draggable] that starts immediately for a mouse or a pen but ignores
/// touch, so a finger on a touch screen scrolls the surrounding list or grid
/// instead of picking up the item. Touch users move items through the
/// existing context menu (long press).
class PointerDraggable<T extends Object> extends Draggable<T> {
  const PointerDraggable({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.maxSimultaneousDrags,
    super.onDragStarted,
    super.onDragEnd,
    super.onDraggableCanceled,
    super.onDragCompleted,
  });

  static const devices = <PointerDeviceKind>{
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) =>
      ImmediateMultiDragGestureRecognizer(
        supportedDevices: devices,
        allowedButtonsFilter: allowedButtonsFilter,
      )..onStart = onStart;
}
