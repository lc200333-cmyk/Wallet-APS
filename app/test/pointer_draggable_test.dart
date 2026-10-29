import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/widgets/pointer_draggable.dart';

// A finger on a touch screen must scroll folder, card and icon grids; the
// mouse (and a pen) still drags items as before.

Future<ScrollController> _pumpList(
  WidgetTester tester, {
  required bool pointerOnly,
  List<int>? started,
}) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  Widget item(int index) {
    final child = SizedBox(height: 60, child: Text('Item $index'));
    return pointerOnly
        ? PointerDraggable<int>(
            data: index,
            feedback: child,
            onDragStarted: () => started?.add(index),
            child: child,
          )
        : Draggable<int>(data: index, feedback: child, child: child);
  }

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              children: [for (var index = 0; index < 40; index++) item(index)],
            ),
          ),
        ],
      ),
    ),
  ));
  return controller;
}

Future<void> _fingerScroll(WidgetTester tester) async {
  final finger =
      await tester.startGesture(tester.getCenter(find.text('Item 2')));
  for (var step = 0; step < 10; step++) {
    await finger.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await finger.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a plain Draggable takes the finger instead of the list',
      (tester) async {
    final controller = await _pumpList(tester, pointerOnly: false);
    await _fingerScroll(tester);
    expect(controller.offset, 0);
  });

  testWidgets('PointerDraggable lets a finger scroll the list', (tester) async {
    final controller = await _pumpList(tester, pointerOnly: true);
    await _fingerScroll(tester);
    expect(controller.offset, greaterThan(200));
  });

  testWidgets('PointerDraggable picks up nothing under a finger',
      (tester) async {
    final started = <int>[];
    await _pumpList(tester, pointerOnly: true, started: started);
    await _fingerScroll(tester);
    expect(started, isEmpty);
  });

  testWidgets('PointerDraggable still drags with the mouse', (tester) async {
    final started = <int>[];
    final controller =
        await _pumpList(tester, pointerOnly: true, started: started);
    final mouse = await tester.startGesture(
      tester.getCenter(find.text('Item 2')),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(started, [2]);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });
}
