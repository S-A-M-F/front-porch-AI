// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Opening the Memory (RAG) panel with RAG on and no model kicked
// EmbeddingService.ensureReady() from didChangeDependencies. ensureReady →
// runSetup notifies synchronously, so the provider was marked dirty mid-build
// ("setState() or markNeedsBuild() called during build" on
// _InheritedProviderScope<EmbeddingService?>). This pumps the real panel and
// the real ensureReady; only the two engine entry points are replaced (no
// 550 MB download in a widget test), keeping runSetup's synchronous notify.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/memory_panel.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

class _NoDownloadEmb extends EmbeddingService {
  _NoDownloadEmb(super.storage);

  int starts = 0;

  @override
  Future<bool> runSetup() async {
    starts++;
    // The real runSetup flips isSettingUp and notifies before its first
    // await — that synchronous notify is what tripped the build.
    notifyListeners();
    return false;
  }

  @override
  Future<void> checkAvailability() async {
    starts++;
    notifyListeners();
  }
}

void main() {
  setupPathProviderMock();

  testWidgets('opening MemoryPanel with RAG on starts setup after the build', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    addTearDown(storage.dispose);
    await storage.memorySettings.setRagEnabled(true);
    final chat = FakeChatService();
    addTearDown(chat.dispose);
    final emb = _NoDownloadEmb(storage);
    addTearDown(emb.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<EmbeddingService>.value(value: emb),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: MemoryPanel(chatService: chat)),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.pump();
    expect(tester.takeException(), isNull);
    // Deferred, not dropped: opening the panel still starts the engine once.
    expect(emb.starts, 1);
  });
}
