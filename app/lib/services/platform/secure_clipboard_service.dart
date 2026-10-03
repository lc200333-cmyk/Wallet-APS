import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

abstract final class SecureClipboardService {
  static Timer? _clearTimer;
  static String? _copiedValue;

  static Future<void> copy(
    String value, {
    Duration clearAfter = const Duration(seconds: 45),
  }) async {
    await Clipboard.setData(ClipboardData(text: value));
    _copiedValue = value;
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
      if (_copiedValue == value) _copiedValue = null;
    });
  }

  static Future<void> clear() async {
    _clearTimer?.cancel();
    _clearTimer = null;
    final copiedValue = _copiedValue;
    _copiedValue = null;
    if (copiedValue == null) return;
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current?.text == copiedValue) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }
}
