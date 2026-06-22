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

// Widget pixel goldens for leaf widgets that own AnimationControllers.
//
// All cases use settle: false (2×50ms bounded pump) to avoid hanging on
// AnimationController.repeat(). The captured frame is the initial render
// before any animation step fires — deterministic by construction.
//
// AnimatedEvalPill   — pass AlwaysStoppedAnimation(0.5) so the pulse
//                      animation is frozen at mid-value (no ticker needed).
// LogView            — static log lines only; _updateBlinking() stops the
//                      controller when last line is not a progress indicator.
// DownloadQueuePanel — one active download task, panel expanded (default).
// HFModelCard        — collapsed state (default _isExpanded = false).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/download_task.dart';
import 'package:front_porch_ai/models/hf_model.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart'
    show EvalPill, AnimatedEvalPill;
import 'package:front_porch_ai/ui/widgets/download_queue_panel.dart';
import 'package:front_porch_ai/ui/widgets/hf_model_card.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart' show LogView;

import '../support/creator_test_support.dart';
import '../support/golden_app.dart';

DownloadTask _activeTask() {
  final t = DownloadTask(
    url: 'https://huggingface.co/bartowski/Meta-Llama-3-8B-Instruct-GGUF/'
        'resolve/main/Meta-Llama-3-8B-Instruct-Q4_K_M.gguf',
    filename: 'Meta-Llama-3-8B-Instruct-Q4_K_M.gguf',
    targetDir: '/models',
    repoId: 'bartowski/Meta-Llama-3-8B-Instruct-GGUF',
  );
  t.state = DownloadTaskState.downloading;
  t.progress = 0.45;
  t.bytesDownloaded = 2_214_592_716;
  t.totalBytes = 4_920_000_000;
  t.speedBytesPerSec = 4_718_592;
  return t;
}

HFModel _hfModel() => HFModel(
  id: 'bartowski/Meta-Llama-3-8B-Instruct-GGUF',
  author: 'bartowski',
  likes: 1250,
  downloads: 42000,
  files: [
    HFModelFile(
      filename: 'Meta-Llama-3-8B-Instruct-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/Meta-Llama-3-8B-Instruct-GGUF/'
          'resolve/main/Meta-Llama-3-8B-Instruct-Q4_K_M.gguf',
      sizeBytes: 4_920_000_000,
      repoId: 'bartowski/Meta-Llama-3-8B-Instruct-GGUF',
      paramCountB: 8.0,
      architecture: 'llama',
    ),
    HFModelFile(
      filename: 'Meta-Llama-3-8B-Instruct-Q8_0.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/Meta-Llama-3-8B-Instruct-GGUF/'
          'resolve/main/Meta-Llama-3-8B-Instruct-Q8_0.gguf',
      sizeBytes: 8_540_000_000,
      repoId: 'bartowski/Meta-Llama-3-8B-Instruct-GGUF',
      paramCountB: 8.0,
      architecture: 'llama',
    ),
  ],
);

void main() {
  setupPathProviderMock();

  testWidgets('AnimatedEvalPill — frozen at pulse value 0.5', (tester) async {
    const pill = EvalPill(
      label: 'Relationship',
      icon: Icons.favorite,
      color: Colors.pinkAccent,
    );
    await expectThemedGoldens(
      tester,
      child: AnimatedEvalPill(
        pill: pill,
        // AlwaysStoppedAnimation provides a constant value without a ticker.
        pulseAnimation: const AlwaysStoppedAnimation(0.5),
      ),
      group: 'leaf_animated',
      name: 'animated_eval_pill',
      surface: const Size(240, 70),
      settle: false,
    );
  });

  testWidgets('LogView — static log lines (no blinking)', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 600,
        height: 180,
        child: LogView(
          logs: const [
            '[12:01:42] KoboldCpp v1.72 loaded',
            '[12:01:43] Model: llama-3-8B-Q4_K_M.gguf',
            '[12:01:44] Context: 8192 tokens — ready',
          ],
        ),
      ),
      group: 'leaf_animated',
      name: 'log_view',
      surface: const Size(660, 240),
      settle: false,
    );
  });

  testWidgets('DownloadQueuePanel — one active download', (tester) async {
    final task = _activeTask();
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 540,
        child: DownloadQueuePanel(
          activeDownloads: [task],
          pendingDownloads: const [],
          overallProgress: task.progress,
          overallSpeed: task.speedBytesPerSec,
          onPause: (_) {},
          onResume: (_) {},
          onCancel: (_) {},
          onPauseAll: () {},
          onResumeAll: () {},
        ),
      ),
      group: 'leaf_animated',
      name: 'download_queue_panel',
      surface: const Size(600, 260),
      settle: false,
    );
  });

  testWidgets('HFModelCard — collapsed (default state)', (tester) async {
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 580,
        child: HFModelCard(
          model: _hfModel(),
          availableVramMb: 8192,
          onDownload: (_) {},
        ),
      ),
      group: 'leaf_animated',
      name: 'hf_model_card',
      surface: const Size(640, 160),
      settle: false,
    );
  });
}
