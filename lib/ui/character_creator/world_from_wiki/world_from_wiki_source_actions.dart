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

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage/settings/web_search_settings.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_wizard_source.dart';

/// The wizard state's view of its source: which engine a run gets, and
/// the words the title bar and Next use for it. Lives beside the state
/// (file-size rule); the state stays the one owner of the fields.
extension WorldFromWikiSourceActions on WorldFromWikiState {
  /// One engine for scout and for write, on the source this run reads.
  /// A character source is built once per pick, so the chat is skimmed
  /// once; Deep runs as Full there and the mode is the Book step's.
  Future<WorldFromWikiEngine> engineFor(
    LLMService svc, {
    required int contextTokens,
    required WorldWikiDepth depth,
  }) async {
    final character = wizardSource.isCharacter;
    return WorldFromWikiEngine(
      source: character
          ? await characterPick.buildSource()
          : WikiWorldSource(wikiService()),
      llm: svc,
      contextTokens: contextTokens,
      depth: character ? worldCharacterDepth(depth) : depth,
      moment: momentController.text,
      mode: character ? characterPick.mode : null,
      onProgress: noteProgress,
    );
  }

  /// Plain words when the source is not picked yet, else null.
  String? get sourcePickError => wizardSource.isCharacter
      ? characterPick.pickError
      : (wikiUrl.trim().isEmpty ? 'Pick a wiki first.' : null);

  /// The title bar's word for the source: the wiki's host, or the
  /// character and chat.
  String get sourceLabel => wizardSource.isCharacter
      ? characterPick.label
      : (wikiUrl.isEmpty ? '' : wikiHostLabel(wikiUrl));

  /// The Book step's Next: what the first pass is called.
  String get scoutLabel => !wizardSource.isCharacter
      ? 'Scout wiki'
      : characterPick.hasChat
      ? 'Skim chat'
      : 'Scout card';

  /// The wiki client for the picked address (the test seam first).
  WikiSearchService wikiService() {
    final factory = wikiFactory;
    if (factory != null) return factory(wikiUrl);
    return WikiSearchService(
      getBaseUrl: () => wikiUrl,
      sendRequest: sendRequest,
    );
  }
}
