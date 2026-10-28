// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The wizard's tools gate: reads chat's verdict for the model the wizard
// runs on and asks that model only from Next or Check now. Split from
// world_from_wiki_state.dart to keep it under the size law.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';

mixin WorldWizardGate on ChangeNotifier {
  WorldToolsGate get toolsGate;
  set toolsGate(WorldToolsGate value);
  String? get error;
  set error(String? value);
  LLMService? get llmOverride;
  bool get toolsReady;
  void notify();

  /// Read chat's tool check for the model this wizard runs on (the running
  /// local engine, or the remote model picked on Setup). Reads only: the
  /// check asks the model from [ensureToolsChecked] (Next) or
  /// [retestTools] (Check now), never on its own — on oMLX or LM Studio a
  /// ping is a model load, and picking a model is not asking for one.
  void refreshToolsGate({
    required ChatService chat,
    required LLMProvider llm,
    required CreatorState creator,
  }) {
    final next = worldFromWikiToolsGate(
      chat.toolCheckFor(
        via: _wizardLlm(llm, creator),
        remoteModel: _wizardRemoteModel(llm, creator),
        autoAsk: false,
      ),
    );
    if (next == toolsGate) return;
    toolsGate = next;
    notify();
  }

  /// Setup's Next: ask the model now if nothing has, then say whether the
  /// wizard may go on. The one place the wizard itself loads a model. A
  /// "no" is asked again too, the way a tap on the pill asks: a verdict may
  /// be kept from another run, or filed by a server still loading the
  /// model, and the user's press is the ask that settles it.
  Future<bool> ensureToolsChecked({
    required ChatService chat,
    required LLMProvider llm,
    required CreatorState creator,
  }) async {
    refreshToolsGate(chat: chat, llm: llm, creator: creator);
    if (toolsGate == WorldToolsGate.notChecked ||
        toolsGate == WorldToolsGate.failed) {
      toolsGate = WorldToolsGate.checking;
      error = null;
      notify();
      await retestTools(chat: chat, llm: llm, creator: creator);
      toolsGate = WorldToolsGate.notChecked;
      refreshToolsGate(chat: chat, llm: llm, creator: creator);
    }
    if (!toolsReady) {
      error = worldFromWikiToolsCopy(toolsGate);
      notify();
    }
    return toolsReady;
  }

  /// "Check now": ask the wizard's model again.
  Future<void> retestTools({
    required ChatService chat,
    required LLMProvider llm,
    required CreatorState creator,
  }) => chat.retestToolsFor(
    via: _wizardLlm(llm, creator),
    remoteModel: _wizardRemoteModel(llm, creator),
  );

  /// The Setup step's own remote pick; empty when it is chat's model.
  String _wizardRemoteModel(LLMProvider llm, CreatorState creator) {
    if (llm.hasManagedProcess) return '';
    final pick = creator.selectedModelId;
    return pick == llm.openRouterService.modelName ? '' : pick;
  }

  /// The service scout and write use for that pick (see [llmFor]); null for
  /// chat's own model.
  LLMService? _wizardLlm(LLMProvider llm, CreatorState creator) =>
      _wizardRemoteModel(llm, creator).isEmpty ? null : llmFor(llm, creator);

  /// The service scout and write use: the test seam, else the pick's.
  LLMService? llmFor(LLMProvider llm, CreatorState creator) {
    return llmOverride ?? llm.serviceForModel(creator.selectedModelId);
  }
}
