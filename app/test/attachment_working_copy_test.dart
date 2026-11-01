import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';

// An attachment opens again while a viewer still holds its previous copy.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('wallet-open-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the working copy is rewritten in place when it is free', () async {
    final first = await writeAttachmentWorkingCopy(
        dir, 'wallet_aps_a.pdf', Uint8List.fromList([1, 2]));
    final second = await writeAttachmentWorkingCopy(
        dir, 'wallet_aps_a.pdf', Uint8List.fromList([3]));
    expect(second.path, first.path);
    expect(second.readAsBytesSync(), [3]);
  });

  test('a blocked working copy is written into a fresh folder', () async {
    Directory('${dir.path}${Platform.pathSeparator}wallet_aps_a.pdf')
        .createSync();
    final copy = await writeAttachmentWorkingCopy(
        dir, 'wallet_aps_a.pdf', Uint8List.fromList([7, 8]));
    expect(copy.uri.pathSegments.last, 'wallet_aps_a.pdf');
    expect(copy.parent.path, isNot(dir.path));
    expect(copy.readAsBytesSync(), [7, 8]);
  });
}
