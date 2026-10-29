import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

abstract final class LegacySwlCodec {
  static final Random _random = Random.secure();
  static const String _idAlphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  static Uint8List idBytes(String hex) {
    if (hex.isEmpty) return Uint8List(0);
    if (hex.length.isOdd) {
      throw const FormatException('SPB Wallet ID must contain full bytes.');
    }
    final bytes = Uint8List(hex.length ~/ 2);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] =
          int.parse(hex.substring(index * 2, index * 2 + 2), radix: 16);
    }
    return bytes;
  }

  static String makeHexId() {
    final text = List.generate(
      8,
      (_) => _idAlphabet[_random.nextInt(_idAlphabet.length)],
    ).join();
    return text.codeUnits
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  static String makeWalletId() => List.generate(
        22,
        (_) => _idAlphabet[_random.nextInt(_idAlphabet.length)],
      ).join();

  static int cardColor(int value) => value & 0xffffff;

  static bool isIco(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0 &&
      bytes[1] == 0 &&
      bytes[2] == 1 &&
      bytes[3] == 0;

  /// Largest side of an icon stored in a wallet.
  static const int maxEmbeddedIconSide = 128;

  /// Whether [bytes] hold an image wider or taller than 128 px. An ICO is
  /// judged by its directory (a size byte of 0 means 256), so no frame is
  /// decoded; other formats are decoded.
  static bool iconExceedsLimit(List<int> bytes) {
    if (!isIco(bytes)) {
      final decoded = image.decodeImage(Uint8List.fromList(bytes));
      return decoded != null &&
          (decoded.width > maxEmbeddedIconSide ||
              decoded.height > maxEmbeddedIconSide);
    }
    if (bytes.length < 6) return false;
    final count = bytes[4] | (bytes[5] << 8);
    for (var index = 0; index < count; index++) {
      final entry = 6 + index * 16;
      if (entry + 2 > bytes.length) break;
      for (final side in [bytes[entry], bytes[entry + 1]]) {
        if (side == 0 || side > maxEmbeddedIconSide) return true;
      }
    }
    return false;
  }

  /// Returns a 128×128 ICO when the largest image of [bytes] (ICO or any
  /// supported format) is wider or taller than 128 px, or null when it
  /// already fits or cannot be decoded. Proportions are kept: a non-square
  /// image is centred on a transparent square.
  static Uint8List? shrinkOversizedIcon(List<int> bytes) {
    final data = Uint8List.fromList(bytes);
    final decoded =
        isIco(data) ? largestIcoFrame(data) : image.decodeImage(data);
    if (decoded == null) return null;
    const side = maxEmbeddedIconSide;
    if (decoded.width <= side && decoded.height <= side) return null;
    final scale = side / max(decoded.width, decoded.height);
    final resized = image.copyResize(
      decoded.convert(numChannels: 4),
      width: max(1, (decoded.width * scale).round()),
      height: max(1, (decoded.height * scale).round()),
      interpolation: image.Interpolation.cubic,
    );
    final square = image.Image(width: side, height: side, numChannels: 4);
    image.compositeImage(
      square,
      resized,
      dstX: (side - resized.width) ~/ 2,
      dstY: (side - resized.height) ~/ 2,
    );
    return image.encodeIco(square);
  }

  /// The largest frame of an ICO by its decoded size. The image package's
  /// decodeImageLargest reads a 256 px directory entry (stored as 0) as 0 and
  /// returns a smaller frame.
  static image.Image? largestIcoFrame(Uint8List data) {
    image.Image? largest;
    try {
      final decoder = image.IcoDecoder();
      final info = decoder.startDecode(data);
      for (var frame = 0; frame < (info?.numFrames ?? 0); frame++) {
        image.Image? candidate;
        try {
          candidate = decoder.decodeFrame(frame);
        } catch (_) {
          continue;
        }
        if (candidate != null &&
            (largest == null ||
                candidate.width * candidate.height >
                    largest.width * largest.height)) {
          largest = candidate;
        }
      }
    } catch (_) {
      // Not a readable ICO; the caller falls back to other formats.
    }
    return largest ?? image.decodeImage(data);
  }

  static Uint8List embeddedIconIco(List<int> bytes) {
    if (isIco(bytes)) {
      return shrinkOversizedIcon(bytes) ?? Uint8List.fromList(bytes);
    }
    final decoded = image.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) {
      throw const FormatException('The custom icon is not a supported image.');
    }
    final square = image.copyResize(
      decoded,
      width: 64,
      height: 64,
      interpolation: image.Interpolation.cubic,
    );
    return image.encodeIco(square);
  }

  static Uint8List windowsMultiResolutionIco(List<int> bytes) {
    final decoded = image.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) {
      throw const FormatException('The Windows app icon cannot be decoded.');
    }
    final side = max(decoded.width, decoded.height);
    final square = image.Image(width: side, height: side, numChannels: 4);
    image.compositeImage(
      square,
      decoded,
      dstX: (side - decoded.width) ~/ 2,
      dstY: (side - decoded.height) ~/ 2,
    );
    const sizes = [16, 24, 32, 48, 64, 128, 256];
    final frames = [
      for (final size in sizes)
        Uint8List.fromList(
          image.encodePng(
            image.copyResize(
              square,
              width: size,
              height: size,
              interpolation: image.Interpolation.cubic,
            ),
          ),
        ),
    ];
    final directorySize = 6 + sizes.length * 16;
    final output = BytesBuilder(copy: false);
    final header = ByteData(directorySize)
      ..setUint16(0, 0, Endian.little)
      ..setUint16(2, 1, Endian.little)
      ..setUint16(4, sizes.length, Endian.little);
    var dataOffset = directorySize;
    for (var index = 0; index < sizes.length; index++) {
      final entryOffset = 6 + index * 16;
      final size = sizes[index];
      header
        ..setUint8(entryOffset, size == 256 ? 0 : size)
        ..setUint8(entryOffset + 1, size == 256 ? 0 : size)
        ..setUint8(entryOffset + 2, 0)
        ..setUint8(entryOffset + 3, 0)
        ..setUint16(entryOffset + 4, 1, Endian.little)
        ..setUint16(entryOffset + 6, 32, Endian.little)
        ..setUint32(entryOffset + 8, frames[index].length, Endian.little)
        ..setUint32(entryOffset + 12, dataOffset, Endian.little);
      dataOffset += frames[index].length;
    }
    output.add(header.buffer.asUint8List());
    for (final frame in frames) {
      output.add(frame);
    }
    return output.takeBytes();
  }
}
