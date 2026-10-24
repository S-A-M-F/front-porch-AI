// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/pages/model_manager_page.dart';
import 'package:front_porch_ai/ui/widgets/hf_model_card.dart';
import 'package:front_porch_ai/ui/widgets/hf_quant_row.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

/// Seeds the HuggingFace search with a page of results so the Search tab
/// has a list to scroll.
class _SearchableModelManager extends FakeModelManager {
  _SearchableModelManager({super.localModels});

  static final results = [
    for (var i = 0; i < 12; i++)
      HFModel(
        id: 'porch/Model-$i-GGUF',
        author: 'porch',
        likes: 10 * i,
        downloads: 100 * i,
        files: [
          HFModelFile(
            filename: 'Model-$i-Q4_K_M.gguf',
            downloadUrl: 'https://huggingface.co/porch/Model-$i-GGUF',
            sizeBytes: 4_920_000_000,
            repoId: 'porch/Model-$i-GGUF',
            paramCountB: 8.0,
            architecture: 'llama',
          ),
        ],
      ),
  ];

  @override
  Future<List<HFModel>> searchHFModels(String query, {int limit = 20}) async =>
      results;

  @override
  Future<Map<String, HFModel>> fetchFilesForModels(
    List<HFModel> models,
  ) async => {for (final m in models) m.id: m};
}

void main() {
  setupPathProviderMock();

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final modelManager = _SearchableModelManager(
      localModels: [
        for (var i = 0; i < 12; i++)
          LocalModelInfo(
            path: '/models/model-$i-Q4_K_M.gguf',
            filename: 'model-$i-Q4_K_M.gguf',
            sizeBytes: 4_831_838_208,
            modified: DateTime(2026, 1, 1),
            paramCountB: 8.0,
          ),
      ],
    );
    final hardware = FakeHardwareService();
    final storage = FakeStorageService();
    addTearDown(() {
      modelManager.dispose();
      hardware.dispose();
      storage.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ModelManager>.value(value: modelManager),
          ChangeNotifierProvider<HardwareService>.value(value: hardware),
          ChangeNotifierProvider<StorageService>.value(value: storage),
        ],
        child: const MaterialApp(home: ModelManagerPage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('collapsed result cards build no quant rows', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Search / Download'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'llama');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await tester.pumpAndSettle();

    // Hidden rows were mounted and laid out for every card on each scroll
    // and window resize: 7-15 fps on Windows with a page of results.
    expect(find.byType(HFModelCard), findsWidgets);
    expect(find.byType(HFQuantRow), findsNothing);

    await tester.tap(find.text('Model-0-GGUF'));
    await tester.pumpAndSettle();
    expect(find.byType(HFQuantRow), findsOneWidget);

    await tester.tap(find.text('Model-0-GGUF'));
    await tester.pump(const Duration(milliseconds: 100));
    // Still animating shut: the row stays until the card is fully closed.
    expect(find.byType(HFQuantRow), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(HFQuantRow), findsNothing);
  });
}
