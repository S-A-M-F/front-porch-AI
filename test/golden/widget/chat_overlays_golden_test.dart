// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

@Tags(['golden'])
@TestOn('linux')
library;

// Widget pixel goldens for chat overlay surfaces.
//
// All three overlay widgets own perpetual animation controllers (Timer.periodic
// or AnimationController.repeat), so every case uses settle: false — a bounded
// 2×50ms pump captures the first rendered frame without hanging pumpAndSettle.
//
// GenerationStatusBar: phase-aware inline bar. Tested in both idle phase
// (no metrics) and generating phase (progress + t/s + token counter).
//
// ObjectiveCheckOverlay and RealismProcessingOverlay: fullscreen Positioned.fill
// overlays — must be wrapped in a SizedBox>Stack so the Positioned.fill widget
// has a valid Stack ancestor (pumpGolden's Scaffold body is not a Stack).
//
// Provider tree: none — all three widgets receive chatService as a constructor
// param and read AppColors only via ThemeData (no extra providers needed).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart' show GenerationPhase;
import 'package:front_porch_ai/ui/chat_components/chat_components.dart'
    show
        GenerationStatusBar,
        ObjectiveCheckOverlay,
        RealismProcessingOverlay;

import '../support/creator_test_support.dart';
import '../support/fakes.dart';
import '../support/golden_app.dart';

// ── GenerationStatusBar ──────────────────────────────────────────────────────

void main() {
  setupPathProviderMock();

  testWidgets('GenerationStatusBar — idle', (tester) async {
    final chat = FakeChatService();
    addTearDown(chat.dispose);

    await expectThemedGoldens(
      tester,
      child: GenerationStatusBar(chatService: chat),
      group: 'overlays',
      name: 'status_bar_idle',
      surface: const Size(800, 90),
      settle: false,
    );
  });

  testWidgets('GenerationStatusBar — generating (50 % progress, 32 t/s)',
      (tester) async {
    final chat = FakeChatService(
      generationPhase: GenerationPhase.generating,
      generationProgress: 0.50,
      tokensGenerated: 128,
      maxTokens: 256,
      tokensPerSecond: 32.4,
    );
    addTearDown(chat.dispose);

    await expectThemedGoldens(
      tester,
      child: GenerationStatusBar(chatService: chat),
      group: 'overlays',
      name: 'status_bar_generating',
      surface: const Size(800, 90),
      settle: false,
    );
  });

  testWidgets('GenerationStatusBar — prefilling (large prompt)',
      (tester) async {
    final chat = FakeChatService(
      generationPhase: GenerationPhase.prefilling,
      prefillElapsedSeconds: 3.0,
      prefillPromptTokens: 4200,
    );
    addTearDown(chat.dispose);

    await expectThemedGoldens(
      tester,
      child: GenerationStatusBar(chatService: chat),
      group: 'overlays',
      name: 'status_bar_prefilling',
      surface: const Size(800, 90),
      settle: false,
    );
  });

  // ── ObjectiveCheckOverlay ──────────────────────────────────────────────────

  testWidgets('ObjectiveCheckOverlay — checking completion', (tester) async {
    final chat = FakeChatService();
    addTearDown(chat.dispose);

    await expectThemedGoldens(
      tester,
      // Positioned.fill must be a direct child of Stack.
      child: SizedBox(
        width: 680,
        height: 560,
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: const Color(0xFF0A0A1A))),
            ObjectiveCheckOverlay(chatService: chat),
          ],
        ),
      ),
      group: 'overlays',
      name: 'objective_check',
      surface: const Size(720, 620),
      settle: false,
    );
  });

  // ── RealismProcessingOverlay ───────────────────────────────────────────────

  testWidgets('RealismProcessingOverlay — realism eval (initializing)',
      (tester) async {
    final chat = FakeChatService(isEvaluatingRealism: true);
    addTearDown(chat.dispose);

    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 680,
        height: 560,
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: const Color(0xFF0A0A1A))),
            RealismProcessingOverlay(chatService: chat, isGreeting: false),
          ],
        ),
      ),
      group: 'overlays',
      name: 'realism_eval',
      surface: const Size(720, 620),
      settle: false,
    );
  });

  testWidgets('RealismProcessingOverlay — greeting baseline capture',
      (tester) async {
    final chat = FakeChatService(isProcessingGreeting: true);
    addTearDown(chat.dispose);

    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 680,
        height: 560,
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: const Color(0xFF0A0A1A))),
            RealismProcessingOverlay(chatService: chat, isGreeting: true),
          ],
        ),
      ),
      group: 'overlays',
      name: 'realism_greeting',
      surface: const Size(720, 620),
      settle: false,
    );
  });

  testWidgets('RealismProcessingOverlay — verifying (pass 1/2)', (tester) async {
    final chat = FakeChatService(
      isVerifyingRealism: true,
      verificationPass: 1,
      verificationMaxPasses: 2,
    );
    addTearDown(chat.dispose);

    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 680,
        height: 560,
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: const Color(0xFF0A0A1A))),
            RealismProcessingOverlay(chatService: chat, isGreeting: false),
          ],
        ),
      ),
      group: 'overlays',
      name: 'realism_verifying',
      surface: const Size(720, 620),
      settle: false,
    );
  });
}
