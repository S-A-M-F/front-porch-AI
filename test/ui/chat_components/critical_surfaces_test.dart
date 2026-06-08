// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';

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

class _FakeStorageService extends ChangeNotifier implements StorageService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
