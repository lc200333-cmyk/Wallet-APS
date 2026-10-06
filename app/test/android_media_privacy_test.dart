import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';

void main() {
  test('Android image attachment export is wrapped in a non-media archive', () {
    final source = Uint8List.fromList(<int>[137, 80, 78, 71, 1, 2, 3, 4]);

    final exported = gallerySafeAttachmentExport(
      'photo.png',
      source,
      isAndroid: true,
    );

    expect(exported.fileName, 'photo.apsattachment.zip');
    final archive = ZipDecoder().decodeBytes(exported.bytes, verify: true);
    expect(archive.files, hasLength(1));
    expect(archive.files.single.name, 'photo.png');
    expect(archive.files.single.content, source);
  });

  test('Android non-image attachment export remains unchanged', () {
    final source = Uint8List.fromList(<int>[1, 2, 3]);

    final exported = gallerySafeAttachmentExport(
      'document.pdf',
      source,
      isAndroid: true,
    );

    expect(exported.fileName, 'document.pdf');
    expect(exported.bytes, same(source));
  });
  test('non-Android attachment export remains unchanged', () {
    final source = Uint8List.fromList(<int>[1, 2, 3]);

    final exported = gallerySafeAttachmentExport(
      'photo.png',
      source,
      isAndroid: false,
    );

    expect(exported.fileName, 'photo.png');
    expect(exported.bytes, same(source));
  });

  test('Android storage configuration exposes no public media directory', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final paths =
        File('android/app/src/main/res/xml/file_paths.xml').readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/lc200333cmyk/walletaps/MainActivity.kt',
    ).readAsStringSync();
    final appSource = File('lib/main.dart').readAsStringSync();

    for (final permission in <String>[
      'READ_MEDIA_IMAGES',
      'READ_EXTERNAL_STORAGE',
      'WRITE_EXTERNAL_STORAGE',
      'MANAGE_EXTERNAL_STORAGE',
    ]) {
      expect(manifest, isNot(contains(permission)));
    }
    expect(paths, isNot(contains('<external-path')));
    expect(paths, isNot(contains('<external-files-path')));
    expect(activity, contains('File(directory, ".nomedia")'));
    expect(activity, contains('externalCacheDir'));
    expect(activity, contains('getExternalFilesDirs(null)'));
    expect(activity, isNot(contains('MediaStore')));
    expect(activity, isNot(contains('FLAG_SECURE')));
    expect(appSource, contains('.apsblob'));
    expect(appSource, isNot(contains('getExternalStorageDirectory')));
    expect(appSource, isNot(contains('getExternalStorageDirectories')));
  });

  test('Android wallet writes protect the original file from zero-byte saves',
      () {
    final activity = File(
      'android/app/src/main/kotlin/com/lc200333cmyk/walletaps/MainActivity.kt',
    ).readAsStringSync();
    final appSource = File('lib/main.dart').readAsStringSync();

    expect(activity, contains('Executors.newSingleThreadExecutor()'));
    expect(activity, contains('isValidWalletFile(source)'));
    expect(activity, contains('createRecoveryWallet(source'));
    expect(activity, contains('openFileDescriptor(uri, "rw")'));
    expect(activity, contains('force(true)'));
    expect(activity, contains('actual.sha256.contentEquals(expected.sha256)'));
    expect(activity, contains('originalSize == 0L'));
    expect(
      activity.indexOf('isValidWalletFile(source)'),
      lessThan(activity.indexOf('openFileDescriptor(uri, "rw")')),
    );
    expect(appSource, contains('_spbWriteInFlight'));
    expect(appSource, contains('_vaultChangeGeneration'));
    expect(appSource, contains('spbwallet_write_'));
    expect(appSource, contains('backupTo(androidWriteSnapshot.path)'));
    expect(appSource, contains('if (!saved) {'));
  });

  test('desktop shutdown and exports use guarded save paths', () {
    final linuxRunner =
        File('linux/runner/my_application.cc').readAsStringSync();
    final appSource = File('lib/main.dart').readAsStringSync();

    expect(linuxRunner, contains('window_delete_event_cb'));
    expect(linuxRunner, contains('"delete-event"'));
    expect(linuxRunner, contains('"requestClose"'));
    expect(appSource, contains('Platform.isWindows && !Platform.isLinux'));
    expect(appSource, contains('backupWalletAtomically'));
    expect(appSource, contains('ensureTargetIsNotActiveVault'));
    expect(appSource, contains('writeBytesAtomically'));
  });

  test('Synology-synchronized project and build tree are hidden from Gallery',
      () {
    expect(File('../.nomedia').existsSync(), isTrue);
    expect(File('.nomedia').existsSync(), isTrue);
  });
}
