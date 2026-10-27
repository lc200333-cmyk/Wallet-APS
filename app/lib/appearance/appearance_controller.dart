import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../design_distribution.dart';
import 'appearance.dart';

Future<Directory> designStateDirectory() async {
  final directory = Platform.isAndroid
      ? Directory('${Directory.systemTemp.parent.path}/files')
      : designSupportDirectory(await getApplicationSupportDirectory());
  if (!await directory.exists()) await directory.create(recursive: true);
  return directory;
}

class AppearancePreferences {
  AppearancePreferences(this.directory);
  final Future<Directory> Function() directory;
  Future<File> get file async =>
      File('${(await directory()).path}/wallet_aps_appearance.json');

  Future<AppAppearance> read() async {
    try {
      final decoded = jsonDecode(await (await file).readAsString());
      if (decoded is Map && decoded['version'] == 1) {
        return AppAppearance.values.firstWhere(
            (m) => m.name == decoded['appearance'],
            orElse: () => AppAppearance.retro);
      }
    } catch (_) {
      // A preference failure must not prevent access to a vault.
    }
    return AppAppearance.retro;
  }

  Future<void> write(AppAppearance value) async {
    final target = await file;
    final temporary = File('${target.path}.tmp');
    try {
      await temporary.writeAsString(
          jsonEncode({'version': 1, 'appearance': value.name}),
          flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

class AppearanceController extends ChangeNotifier {
  AppearanceController(
      {this.preferences, AppAppearance initial = AppAppearance.retro})
      : _mode = initial;
  final AppearancePreferences? preferences;
  AppAppearance _mode;
  AppAppearance get mode => _mode;
  String? _error;
  String? get error => _error;
  bool _disposed = false;
  Future<void> _pending = Future.value();
  Future<void> get saved => _pending;

  Future<void> load() async {
    _mode = await preferences?.read() ?? AppAppearance.retro;
    if (!_disposed) notifyListeners();
  }

  void choose(AppAppearance value) {
    if (_mode == value) return;
    _mode = value;
    _error = null;
    notifyListeners();
    // Serialize replacement so the last user selection also wins on disk.
    _pending = _pending.then((_) async {
      try {
        await preferences?.write(value);
        if (_mode == value) _error = null;
      } catch (_) {
        _error = 'Тема применена, но выбор не удалось сохранить';
      }
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppearanceScope extends InheritedNotifier<AppearanceController> {
  const AppearanceScope(
      {required AppearanceController controller,
      required super.child,
      super.key})
      : super(notifier: controller);
  static AppearanceController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.notifier;
}
