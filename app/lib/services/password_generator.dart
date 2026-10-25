import 'dart:math';

/// A local password with all four character groups, using the OS random source.
String generateVaultPassword() {
  const groups = [
    'abcdefghijklmnopqrstuvwxyz',
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    '0123456789',
    '!@#\$%&*+-=?_',
  ];
  final random = Random.secure();
  final alphabet = groups.join();
  final characters = [
    for (final group in groups) group[random.nextInt(group.length)],
    for (var i = groups.length; i < 20; i++)
      alphabet[random.nextInt(alphabet.length)],
  ]..shuffle(random);
  return characters.join();
}
