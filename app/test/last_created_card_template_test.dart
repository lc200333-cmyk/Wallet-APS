import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_aps/main.dart';
import 'package:wallet_aps/spb_wallet/spb_wallet_database.dart';

void main() {
  test('preferred card template falls back when the session template is gone',
      () {
    final templates = builtInTemplates();

    expect(
      preferredNewCardTemplateId(templates, templates[1].id),
      templates[1].id,
    );
    expect(
      preferredNewCardTemplateId(templates, 'deleted-template'),
      templates.first.id,
    );
    expect(preferredNewCardTemplateId(const [], 'missing'), isNull);
  });

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.iOS,
  ]) {
    testWidgets('${platform.name} editor proposes the remembered template',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final templates = builtInTemplates();

      await tester.pumpWidget(
        MaterialApp(
          home: ItemEditorDialog(
            templates: templates,
            categories: const [],
            initialTemplateId: templates[1].id,
          ),
        ),
      );
      await tester.pump();

      final dynamic editor = tester.state(find.byType(ItemEditorDialog));
      expect(editor.templateId, templates[1].id);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('cardTemplateField')),
            )
            .initialValue,
        templates[1].id,
      );
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('successful creation becomes the next session default',
      (tester) async {
    final directory =
        Directory.systemTemp.createTempSync('wallet-last-card-template-');
    final database = SpbWalletDatabase.create(
      '${directory.path}${Platform.pathSeparator}session.swl',
      '',
    );
    for (final name in ['First template', 'Remembered template']) {
      database.saveTemplate(
        SpbWalletTemplateDraft(
          id: SpbWalletDatabase.makeId(),
          name: name,
          fields: const [],
        ),
      );
    }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      try {
        database.close();
      } catch (_) {}
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      const MaterialApp(home: VaultShell(initiallyUnlocked: true)),
    );
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(VaultShell));
    state.spbWallet = database;
    state.applySpbSnapshot(database.loadSnapshot());
    state.setState(() {});
    await tester.pump();
    final List<CardTemplate> templates =
        (state.templates as List).cast<CardTemplate>();
    final selectedTemplate = templates[1];

    final Future<SecretItem?> firstCreation = state.openItemDialog();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cardTemplateField')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('cardTemplateIcon-${selectedTemplate.id}')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cardTitleField')),
      'Session template card',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('cardSaveButton')));
    await tester.pumpAndSettle();

    final created = await firstCreation;
    expect(created?.templateId, selectedTemplate.id);
    expect(state.lastCreatedCardTemplateId, selectedTemplate.id);

    final Future<SecretItem?> secondCreation = state.openItemDialog();
    await tester.pumpAndSettle();
    final dynamic secondEditor = tester.state(find.byType(ItemEditorDialog));
    expect(secondEditor.templateId, selectedTemplate.id);

    await tester.tap(find.byKey(const Key('cardCloseButton')));
    await tester.pumpAndSettle();
    expect(await secondCreation, isNull);
    expect(state.lastCreatedCardTemplateId, selectedTemplate.id);

    expect(await state.closeCurrentVaultForPasswordPrompt(), isTrue);
    expect(state.lastCreatedCardTemplateId, isNull);
  });
}
