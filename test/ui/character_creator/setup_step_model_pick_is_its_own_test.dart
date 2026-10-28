// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The model picked on the creator's Setup step (oMLX, Remote API) is that
// step's own choice. It used to be written as chat's model: that switch made
// chat test the new model at once, which on oMLX or LM Studio loads it, and
// a verdict from a test run mid-load locked World from Wiki's Next. The pick
// was also replaced by chat's model whenever the model list failed to load,
// which during a load it does.
//
// The real step over the Settings harness's store, on oMLX, with a provider
// whose model list cannot be fetched.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/open_router/omlx_samplers.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/steps/setup_step.dart';

import '../../golden/support/fakes.dart';
import '../../helpers/settings_page_harness.dart';

/// oMLX with 'chat-model' in use, whose server refuses every connection
/// (the shape of a server busy loading a model).
class _OmlxLlm extends FakeLLMProvider {
  _OmlxLlm() : super(activeBackend: BackendType.omlx);

  final OpenRouterService remote = OpenRouterService(
    apiUrl: kOmlxApiUrl,
    modelName: 'chat-model',
  )..httpClientFactory = _RefusingClient.new;

  @override
  OpenRouterService get openRouterService => remote;
}

class _RefusingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw const SocketException('Connection refused');
  }
}

const _models = [
  RemoteModelInfo(id: 'chat-model', name: 'Chat model'),
  RemoteModelInfo(id: 'other-model', name: 'Other model'),
];

void main() {
  Future<({SettingsPageRig rig, CreatorState creator})> mountStep(
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rig = await buildRig(tester, lastUsedIsB: false);
    await rig.store.backendSettings.setBackendType('omlx');
    await rig.store.backendSettings.setRemoteModelName('chat-model');
    final llm = _OmlxLlm();
    addTearDown(llm.dispose);
    final creator = CreatorState();
    addTearDown(creator.dispose);
    creator.availableModels = List.of(_models);
    await tester.pumpWidget(
      withRigProviders(
        rig,
        child: ChangeNotifierProvider<LLMProvider>.value(
          value: llm,
          child: MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: creator,
                builder: (_, _) => SetupStep(state: creator),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return (rig: rig, creator: creator);
  }

  testWidgets('picking a model keeps it on the step and leaves chat\'s '
      'model as it was', (tester) async {
    final m = await mountStep(tester);

    await tester.tap(find.text('Tap to select a model...'));
    await settle(tester);
    expect(find.text('Select Model'), findsOneWidget);
    await tester.tap(find.text('Other model'));
    await settle(tester);

    expect(m.creator.selectedModelId, 'other-model');
    expect(find.text('other-model'), findsWidgets, reason: 'shown at once');
    expect(
      m.rig.store.backendSettings.remoteModelName,
      'chat-model',
      reason:
          'the pick is the step\'s own; chat\'s model does not change, '
          'so chat does not test (and on oMLX load) the picked model',
    );
  });

  test('a model list that will not load keeps the pick', () async {
    final llm = _OmlxLlm();
    addTearDown(llm.dispose);
    final creator = CreatorState();
    addTearDown(creator.dispose);
    creator.selectedModelId = 'other-model';

    await creator.loadAvailableModels(llm);

    expect(creator.isLoadingModels, isFalse);
    expect(
      creator.selectedModelId,
      'other-model',
      reason: 'a failed fetch is not a reason to show another model',
    );

    creator.selectedModelId = '';
    await creator.loadAvailableModels(llm);
    expect(
      creator.selectedModelId,
      'chat-model',
      reason: 'an empty step still falls back to chat\'s model',
    );
  });
}
