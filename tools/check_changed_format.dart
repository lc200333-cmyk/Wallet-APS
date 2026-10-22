// Run from repository root. Does not rewrite source files.
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart tools/check_changed_format.dart <base-commit>');
    exitCode = 2;
    return;
  }
  Future<String> git(List<String> command) async {
    final result = await Process.run('git', command);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
    return result.stdout as String;
  }

  final changed = await git([
    'diff',
    '--name-only',
    '-z',
    '--diff-filter=ACMR',
    args.single,
    '--',
  ]);
  final untracked = await git([
    'ls-files',
    '--others',
    '--exclude-standard',
    '-z',
  ]);
  final paths =
      '$changed\x00$untracked'
          .split('\x00')
          .where((p) => p.endsWith('.dart') && File(p).existsSync())
          .toSet()
          .toList()
        ..sort();
  for (final path in paths) {
    final result = await Process.run(Platform.resolvedExecutable, [
      'format',
      '--output=none',
      '--set-exit-if-changed',
      path,
    ]);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) exitCode = 1;
  }
  stdout.writeln('Checked ${paths.length} changed/new Dart files.');
}
