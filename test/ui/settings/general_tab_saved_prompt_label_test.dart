// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → General → Model Instructions: after picking a saved prompt and
// then pressing the "Group Chat" preset button, the box held the group
// prompt but the saved-prompt dropdown still named the old pick. The
// dropdown now names the saved prompt whose text is in the box, or none.
// The presets became Reset to built-in on each prompt slot (Option B of the
// named-prompt picker), so the same guard runs through that menu.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/settings/tabs/general_tab.dart';

import '../../helpers/double_tap.dart';

const _saved = 'Immersive Roleplay';
const _savedText = 'You are {{char}}. Stay in character.';

class _FakeStorage extends ChangeNotifier implements StorageService {
  _FakeStorage() {
    generationSettings.initializeBase(null, notifyListeners);
    uiSettings.initializeBase(null, notifyListeners);
    presetSettings.initializeBase(null, notifyListeners);
    realismSettings.initializeBase(null, notifyListeners);
    generationSettings.setSystemPrompt('MY OWN PROMPT');
    presetSettings.savePrompt(_saved, _savedText);
    realismSettings.setAdultThemesEnabled(false);
  }

  @override
  final GenerationSettings generationSettings = GenerationSettings();
  @override
  final UiSettings uiSettings = UiSettings();
  @override
  final PresetSettings presetSettings = PresetSettings();
  @override
  final RealismSettings realismSettings = RealismSettings();

  @override
  String get spellCheckLanguage => kSpellCheckOff;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The value the one-to-one slot's saved-prompt dropdown shows (the first
/// of the two slots on the page).
String? _shown(WidgetTester tester) => tester
    .state<FormFieldState<String>>(
      find.byWidgetPredicate((w) => w is DropdownButtonFormField<String>).first,
    )
    .value;

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  // NOT pumpAndSettle: the spell-check row's spinner never settles.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(f.last);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('a preset button clears the stale saved-prompt name', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _FakeStorage();
    addTearDown(storage.dispose);
    final controller = TextEditingController(
      text: storage.generationSettings.systemPrompt,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(body: GeneralTab(systemPromptController: controller)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(_shown(tester), isNull);

    await _tapVisible(tester, find.text('Load a saved prompt...').first);
    await _tapVisible(tester, find.text(_saved));
    expect(controller.text, _savedText);
    expect(_shown(tester), _saved);

    await _tapVisible(tester, find.text('Reset to built-in').first);
    await _tapVisible(tester, find.text('API default'));
    // A menu item runs its action as the menu closes: one more frame.
    await tester.pump();
    expect(controller.text, defaultApiSystemPrompt);
    expect(_shown(tester), isNull, reason: 'the old pick\'s name stayed');
    expect(find.text('Built-in: API default'), findsOneWidget);
  });

  testWidgets('the save-prompt dialog\'s Save button shows its label and '
      'saves the prompt once', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _FakeStorage();
    addTearDown(storage.dispose);
    final controller = TextEditingController(
      text: storage.generationSettings.systemPrompt,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(body: GeneralTab(systemPromptController: controller)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await _tapVisible(tester, find.text('Save as new...').first);
    final save = find.widgetWithText(ElevatedButton, 'Save');
    expect(save, findsOneWidget);
    final button = tester.widget<ElevatedButton>(save);
    final states = <WidgetState>{};
    final fill = button.style!.backgroundColor!.resolve(states);
    final ink = button.style!.foregroundColor?.resolve(states);
    expect(
      ink,
      isNotNull,
      reason:
          'no label colour: the theme default '
          'vanished into the accent fill',
    );
    expect(ink, isNot(fill));

    await tester.enterText(find.byType(TextField).last, 'Mine');
    await doubleTapNoFrame(tester, save);
    await tester.pump(const Duration(milliseconds: 400));
    final mine = storage.presetSettings.savedPrompts.where(
      (p) => p['name'] == 'Mine',
    );
    expect(mine.single['content'], 'MY OWN PROMPT');
  });

  Future<_FakeStorage> pumpTab(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _FakeStorage();
    addTearDown(storage.dispose);
    final controller = TextEditingController(
      text: storage.generationSettings.systemPrompt,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(body: GeneralTab(systemPromptController: controller)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return storage;
  }

  testWidgets('each prompt slot keeps its own pick from one shared pool, '
      'and the untouched built-in seed is not in it', (tester) async {
    final storage = await pumpTab(tester);
    // The first-run seed, untouched, plus one prompt of the user's own.
    await storage.presetSettings.savePrompt(
      kSeededPromptName,
      GenerationSettings.defaultSystemPrompt,
    );
    await storage.presetSettings.savePrompt('Slow burn', 'Take it slow.');
    await tester.pump();

    // Load the one-to-one slot from the pool.
    await _tapVisible(tester, find.text('Load a saved prompt...').first);
    expect(
      find.text(kSeededPromptName),
      findsNothing,
      reason: 'the untouched seed is a built-in by another name',
    );
    await _tapVisible(tester, find.text('Slow burn'));
    expect(storage.presetSettings.oneToOneSlotName, 'Slow burn');

    // The group slot saves its own text as a new prompt, which then sits in
    // both slots' lists while each keeps its own pick.
    final groupField = find.widgetWithText(TextField, 'Group system prompt');
    await tester.ensureVisible(groupField);
    await tester.enterText(groupField, 'Novel style for groups.');
    await tester.pump();
    await _tapVisible(tester, find.text('Save as new...').last);
    await tester.enterText(find.byType(TextField).last, 'Group novel');
    await doubleTapNoFrame(tester, find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      storage.presetSettings.savedPrompts
          .where((p) => p['name'] == 'Group novel')
          .single['content'],
      'Novel style for groups.',
    );
    expect(storage.presetSettings.groupSlotName, 'Group novel');
    expect(storage.presetSettings.oneToOneSlotName, 'Slow burn');
    expect(storage.generationSettings.systemPrompt, 'Take it slow.');
    // Each name shows twice: its slot's dropdown and its slot's badge.
    expect(find.text('Group novel'), findsNWidgets(2));
    expect(find.text('Slow burn'), findsNWidgets(2));

    // The hidden seed's name is free to take: no "already have" for a
    // prompt the user cannot see.
    await _tapVisible(tester, find.text('Save as new...').first);
    await tester.enterText(find.byType(TextField).last, kSeededPromptName);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('already have a prompt called'), findsNothing);
    expect(
      storage.presetSettings.savedPrompts
          .where((p) => p['name'] == kSeededPromptName)
          .single['content'],
      'Take it slow.',
    );
  });

  testWidgets('Save as new refuses a taken name, Save updates the loaded '
      'prompt, and Reset to built-in can be undone', (tester) async {
    final storage = await pumpTab(tester);
    await _tapVisible(tester, find.text('Load a saved prompt...').first);
    await _tapVisible(tester, find.text(_saved));

    final field = find.widgetWithText(TextField, 'Fallback system prompt');
    await tester.enterText(field, '$_savedText Be brief.');
    await tester.pump();
    expect(find.text('$_saved (edited)'), findsOneWidget);

    await _tapVisible(tester, find.text('Save as new...').first);
    await tester.enterText(find.byType(TextField).last, _saved);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('already have a prompt called'), findsOneWidget);
    expect(
      storage.presetSettings.savedPrompts
          .where((p) => p['name'] == _saved)
          .single['content'],
      _savedText,
      reason: 'Save as new must never overwrite',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));

    await _tapVisible(tester, find.text('Save to "$_saved"'));
    expect(
      storage.presetSettings.savedPrompts
          .where((p) => p['name'] == _saved)
          .single['content'],
      '$_savedText Be brief.',
    );
    expect(find.text(_saved), findsWidgets);

    await _tapVisible(tester, find.text('Reset to built-in').first);
    await _tapVisible(tester, find.text('KoboldCpp default'));
    // A menu item runs its action as the menu closes: one more frame.
    await tester.pump();
    expect(storage.generationSettings.systemPrompt, defaultKoboldSystemPrompt);
    expect(storage.presetSettings.oneToOneSlotName, isNull);
    expect(find.text('Built-in: KoboldCpp default'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    // The snack bar lays out past this tall test surface, so press its
    // action directly.
    final undo = find.widgetWithText(SnackBarAction, 'Undo');
    expect(undo, findsOneWidget);
    tester.widget<SnackBarAction>(undo).onPressed();
    await tester.pump(const Duration(milliseconds: 400));
    expect(storage.generationSettings.systemPrompt, '$_savedText Be brief.');
    expect(storage.presetSettings.oneToOneSlotName, _saved);
  });
}
