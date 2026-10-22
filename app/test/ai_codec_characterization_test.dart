import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/data/legacy_swl/legacy_swl_codec.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_attachment_codec.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_crypto.dart';

void main() {
  final crypto = SpbWalletCrypto('synthetic-test-password');
  final codec = SpbWalletAttachmentCodec(crypto);

  test('legacy IDs reject incomplete hex and colors discard alpha', () {
    expect(LegacySwlCodec.idBytes('0041ff'), [0, 65, 255]);
    expect(() => LegacySwlCodec.idBytes('abc'), throwsFormatException);
    expect(() => LegacySwlCodec.idBytes('zz'), throwsFormatException);
    expect(LegacySwlCodec.cardColor(0xff123456), 0x123456);
  });

  test('raw encryption preserves block boundary payloads', () {
    for (final size in [0, 1, 15, 16, 17, 31, 32, 255]) {
      final bytes = Uint8List.fromList(List.generate(size, (i) => i % 256));
      final encrypted = crypto.encryptRawWithOuterPrefix(bytes);
      expect((encrypted.length - 4) % 16, 0);
      expect(crypto.decryptRawWithOuterPrefix(encrypted), bytes);
      expect(codec.decode(codec.encode(bytes)).bytes, bytes);
    }
  });

  test('malformed crypto framing is rejected', () {
    for (final bytes in [
      Uint8List(3),
      Uint8List(5),
      Uint8List.fromList([255, 255, 255, 255])
    ]) {
      expect(() => crypto.decryptRawWithOuterPrefix(bytes),
          throwsA(isA<SpbWalletCryptoException>()));
    }
  });

  test('attachment validates declared uncompressed length', () {
    final compressed = zlib.encode([1, 2, 3]);
    final payload = Uint8List(4 + compressed.length)..setAll(4, compressed);
    ByteData.sublistView(payload).setUint32(0, 99, Endian.little);
    expect(() => codec.decode(crypto.encryptRawWithOuterPrefix(payload)),
        throwsA(isA<SpbWalletAttachmentException>()));
  });
}
