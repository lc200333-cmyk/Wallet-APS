import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/features/templates/template_folders.dart';
import 'package:wallet_aps/features/templates/template_layout.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';

// New bases take the template folders saved from an open base.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('wallet-layout-'));
  tearDown(() => dir.deleteSync(recursive: true));

  SpbWalletDatabase copyOfStandardBase(String name) {
    final path = '${dir.path}${Platform.pathSeparator}$name.swl';
    File('assets/base_wallet/MyWallet.swl').copySync(path);
    return SpbWalletDatabase.open(path, '0000');
  }

  String folderOf(SpbWalletDatabase wallet, String label) {
    final template = wallet.loadSnapshot().templates.singleWhere((t) =>
        templateLabelInFolder(
            t.name, templateFolderFor(t.name, t.categoryPath)) ==
        label);
    return templateFolderFor(template.name, template.categoryPath);
  }

  test('the shipped layout sorts every standard template, no card folders', () {
    final layout = TemplateLayout.fromJson(jsonDecode(
        File('assets/base_wallet/template_layout.json').readAsStringSync()))!;
    final wallet = copyOfStandardBase('shipped');
    try {
      final cardFolders = wallet.loadSnapshot().categories.length;
      wallet.applyTemplateLayout(layout);
      final snapshot = wallet.loadSnapshot();
      final want = {for (final entry in layout.templates) entry.id: entry};
      final standard = snapshot.templates
          .where((template) => want.containsKey(template.id.toUpperCase()))
          .toList();
      expect(standard, hasLength(want.length));
      for (final template in standard) {
        final entry = want[template.id.toUpperCase()]!;
        final folder = templateFolderFor(template.name, template.categoryPath);
        expect(folder, entry.folder, reason: template.name);
        expect(templateLabelInFolder(template.name, folder), entry.label);
      }
      expect(snapshot.categories, hasLength(cardFolders));
      expect(folderOf(wallet, 'Банковский счёт'), 'Банковские счета');
      expect(folderOf(wallet, 'Кредитная карта'), 'Карточки');
    } finally {
      wallet.close();
    }
  });

  test('a new base gets the cards, templates and icons of the shipped base',
      () {
    final path = '${dir.path}${Platform.pathSeparator}new.swl';
    expect(
      cloneSwlVaultWithPassword({
        'path': path,
        'password': 'new-password',
        'sourcePassword': '0000',
        'baseBytes': File('assets/base_wallet/MyWallet.swl').readAsBytesSync(),
        'renameNewWalletAboutFolder': true,
      }),
      isTrue,
    );
    final wallet = SpbWalletDatabase.open(path, 'new-password');
    try {
      final snapshot = wallet.loadSnapshot();
      expect(snapshot.cards, hasLength(16));
      expect(snapshot.templates, hasLength(60));
      expect(snapshot.categories, hasLength(12));
      expect(snapshot.embeddedIconPngs, isNotEmpty);
      expect(snapshot.loadReport.hasIssues, isFalse);
      final start =
          snapshot.cards.singleWhere((card) => card.title == 'С чего начать');
      expect(start.attachments.single.fileName, endsWith('.pdf'));
      expect(snapshot.cards.map((card) => card.title),
          containsAll(['My Passport', 'My Money', 'My Credit Card']));
      expect(snapshot.categories.map((category) => category.name),
          contains('О программе Wallet'));
    } finally {
      wallet.close();
    }
    expect(() => SpbWalletDatabase.open(path, '0000'), throwsA(anything));
  });

  test('a saved layout moves the templates of a new base', () {
    final source = copyOfStandardBase('source');
    final passport = source
        .loadSnapshot()
        .templates
        .singleWhere((t) => t.name == 'Личные: Паспорт');
    source.editTemplateFolder('Финансы', 'Банк',
        iconId: 'folder', colorId: 'template_blue');
    final captured = source.captureTemplateLayout();
    source.close();

    // A copy of the layout through JSON, with the passport found by name.
    final layout = TemplateLayout.fromJson(captured.toJson())!;
    final byName = TemplateLayout(
      templates: [
        for (final entry in layout.templates)
          entry.id == passport.id
              ? const TemplateLayoutEntry(
                  id: 'OTHER', name: 'Документы: Паспорт')
              : entry,
      ],
      folders: layout.folders,
    );

    final target = copyOfStandardBase('target');
    try {
      expect(target.applyTemplateLayout(byName), greaterThanOrEqualTo(3));
      expect(folderOf(target, 'Акции, облигации'), 'Банк');
      expect(folderOf(target, 'Заём, ипотека'), 'Банк');
      expect(folderOf(target, 'Паспорт'), 'Документы');
      expect(folderOf(target, 'Контакт'), 'Личные');
      expect(
        target.loadTemplateFolders().map((f) => (f.name, f.hidden)),
        containsAll([('Банк', false), ('Финансы', true)]),
      );
      // Applying again changes nothing.
      expect(target.applyTemplateLayout(byName), 0);
    } finally {
      target.close();
    }
  });
}
