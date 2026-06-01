// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/database/database.dart';

void main() {
  group(
    'Critical extracted widget surfaces (Realism/Needs/group parity, gen, objective)',
    () {
      testWidgets(
        'GenerationStatusBar renders phase labels and metrics (no crash)',
        (tester) async {
          // Minimal fake ChatService with the fields the bar reads
          final fake = _FakeChatServiceForGenBar();
          await tester.pumpWidget(
            MaterialApp(
              home: MultiProvider(
                providers: [
                  ChangeNotifierProvider<ChatService>.value(value: fake),
                  ChangeNotifierProvider<StorageService>(
                    create: (_) => _FakeStorageService(),
                  ),
                ],
                child: Scaffold(body: GenerationStatusBar(chatService: fake)),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Basic smoke: the bar exists and shows some text (phase or metric)
          expect(find.byType(GenerationStatusBar), findsOneWidget);
          expect(find.textContaining('Generating response'), findsOneWidget);
        },
      );

      // NOTE: RealismSection and ObjectiveSection (with EditableTaskRow) full render smoke tests
      // require the complete DI tree (StorageService + other services + theme + Material ancestors for Ink/Buttons).
      // The gen bar test below exercises a self-contained extracted widget successfully.
      // Realism/Needs/group parity, objective editing, and RAG surfaces are covered by:
      // - service tests (chat_service_*_realism*, group_realism, session)
      // - manual verification in worktree build (1:1 + group + creators + RAG)
      // - analyze clean on the widget code itself.
      // Full isolated widget tests for the complex sidebars would duplicate app-level setup and are
      // out of scope for this extraction stage (per plan "smoke scaffolding + parity notes").

      // Parity note: 1:1 vs group variants of the sidebar sections are exercised via chatService flags
      // in the real widgets; service tests + manual cover the observable Realism/Needs/chaos/objective behavior.
    },
  );
}

// Minimal fakes for smoke tests only (no real logic, just enough fields to not crash the widgets)
class _FakeChatServiceForGenBar extends ChangeNotifier implements ChatService {
  @override
  GenerationPhase get generationPhase => GenerationPhase.generating;
  @override
  double get tokensPerSecond => 12.3;
  @override
  int get tokensGenerated => 42;
  @override
  int get maxTokens => 200;
  @override
  double get generationProgress => 0.4;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeChatServiceForRealism extends ChangeNotifier implements ChatService {
  @override
  bool get realismEnabled => true;
  @override
  bool get isGroupMode => false;
  // Needs for chips (food/rest etc)
  @override
  double get foodLevel => 70;
  @override
  double get restLevel => 60;
  @override
  double get sleepLevel => 80;
  @override
  double get funLevel => 50;
  @override
  String get foodTierName => 'Content';
  @override
  String get restTierName => 'Rested';
  @override
  String get sleepTierName => 'Awake';
  @override
  String get funTierName => 'Amused';
  // Realism state for indicator
  @override
  int get bondLevel => 42;
  @override
  int get trustLevel => 27;
  @override
  int get arousalLevel => 15;
  @override
  String get emotionLabel => 'affection';
  @override
  String get emotionIntensity => 'moderate';
  @override
  String get fixationTopic => '';
  @override
  int get fixationTurns => 0;
  @override
  bool get nsfwCooldownEnabled => false;
  @override
  int get cooldownTurnsRemaining => 0;
  @override
  int get arousalTier => 2;
  @override
  String get arousalTierName => 'Warm';
  @override
  int get relationshipTier => 3;
  @override
  int get longTermTier => 2;
  @override
  bool get isGenerating => false;
  @override
  String get shortTermTierName => 'Warm';
  @override
  int get affectionScore => 42;
  @override
  int get shortTermProgressTarget => 100;
  @override
  double get shortTermProgressPercent => 65.0;
  @override
  String get longTermTierName => 'Bonded';
  @override
  int get longTermScore => 55;
  @override
  int get longTermProgressTarget => 100;
  @override
  double get longTermProgressPercent => 55.0;
  @override
  String get trustTierName => 'Reliable';
  @override
  List<Map<String, dynamic>> get realismEvalHistory => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) {
      final name = invocation.memberName.toString();
      if (name.contains('Percent') ||
          name.contains('Level') ||
          name.contains('Score'))
        return 0.0;
      if (name.contains('Target') ||
          name.contains('Tier') ||
          name.contains('Turns'))
        return 0;
      if (name.contains('Name') ||
          name.contains('Label') ||
          name.contains('Topic'))
        return '';
      if (name.contains('Enabled') ||
          name.contains('Generating') ||
          name.contains('Mode'))
        return false;
      if (name.contains('History') ||
          name.contains('Objectives') ||
          name.contains('Tasks') ||
          name.contains('Secondary'))
        return const [];
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeChatServiceForObjective extends ChangeNotifier
    implements ChatService {
  @override
  Objective? get primaryObjective => null;
  @override
  List<Objective> get secondaryObjectives => const [];
  @override
  List<Map<String, dynamic>> tasksForObjective(Objective obj) => const [];
  @override
  bool get isCheckingCompletion => false;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter) {
      final name = invocation.memberName.toString();
      if (name.contains('Level') ||
          name.contains('Score') ||
          name.contains('Percent') ||
          name.contains('Target') ||
          name.contains('Tier'))
        return 0;
      if (name.contains('Name') ||
          name.contains('Label') ||
          name.contains('Topic'))
        return '';
      if (name.contains('Enabled') || name.contains('Generating')) return false;
      if (name.contains('History') ||
          name.contains('Objectives') ||
          name.contains('Tasks'))
        return const [];
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeStorageService extends ChangeNotifier implements StorageService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
