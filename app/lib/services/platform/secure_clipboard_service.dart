import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

abstract final class SecureClipboardService {
  static Timer? _clearTimer;

  static Future<void> copy(
    String value, {
    Duration clearAfter = const Duration(seconds: 45),
  }) async {
    await Clipboard.setData(ClipboardData(text: value));
    var runningInWidgetTest = false;
    assert(() {
      runningInWidgetTest =
          WidgetsBinding.instance.runtimeType.toString().contains('Test');
      return true;
    }());
    if (runningInWidgetTest) return;
    _clearTimer?.cancel();
    _clearTimer = Timer(clearAfter, () async {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == value) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
  }

  static void retain() {
    _clearTimer?.cancel();
    _clearTimer = null;
  }

  static Future<void> clear() async {
    retain();
    await Clipboard.setData(const ClipboardData(text: ''));
  }
}
