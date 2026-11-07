import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as image;

/// Run from app/: dart run tool/generate_apple_icons.dart.
/// Uses the original desktop artwork, preserving its aspect ratio.
void main() {
  final sourceFile = File('windows/runner/resources/app_icon.source.png');
  final source = image.decodePng(sourceFile.readAsBytesSync());
  if (source == null) throw StateError('Invalid icon: ${sourceFile.path}');

  for (final platform in ['ios', 'macos']) {
    final directory = Directory(
      '$platform/Runner/Assets.xcassets/AppIcon.appiconset',
    );
    final catalog = jsonDecode(
      File('${directory.path}/Contents.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final generated = <String>{};
    for (final entry in catalog['images'] as List<dynamic>) {
      final definition = entry as Map<String, dynamic>;
      final filename = definition['filename'] as String;
      if (!generated.add(filename)) continue;
      final points = double.parse(
        (definition['size'] as String).split('x').first,
      );
      final scale = double.parse(
        (definition['scale'] as String).replaceAll('x', ''),
      );
      final size = (points * scale).round();
      final ratio = min(size / source.width, size / source.height);
      final resized = image.copyResize(
        source,
        width: max(1, (source.width * ratio).round()),
        height: max(1, (source.height * ratio).round()),
        interpolation: image.Interpolation.cubic,
      );
      // App Store iOS icons must be opaque. macOS keeps the original outline.
      final canvas = image.Image(
        width: size,
        height: size,
        numChannels: platform == 'ios' ? 3 : 4,
      );
      image.fill(
        canvas,
        color: platform == 'ios'
            ? image.ColorRgb8(255, 255, 255)
            : image.ColorRgba8(0, 0, 0, 0),
      );
      image.compositeImage(
        canvas,
        resized,
        dstX: (size - resized.width) ~/ 2,
        dstY: (size - resized.height) ~/ 2,
      );
      File('${directory.path}/$filename')
          .writeAsBytesSync(image.encodePng(canvas));
    }
    stdout.writeln('$platform: ${generated.length} original Wallet APS icons');
  }
}
