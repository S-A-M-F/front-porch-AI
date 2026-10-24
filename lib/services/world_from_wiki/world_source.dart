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

import 'world_from_wiki_budget.dart';
import 'world_from_wiki_depth.dart';
import 'world_from_wiki_ops.dart';
import 'world_from_wiki_tools.dart';

/// What the World from Wiki engine reads: an index for the scout, and one
/// article per title for the writer, the entry reviewer and the climate
/// call. The wiki is one source; a character and one of their chats is
/// another (docs/design/world-from-character.md §3.1). Everything after
/// the index — shelf, write, review, mint — never asks which.
abstract class WorldSource {
  /// 'wiki' or 'character'; the relay and the progress copy read it.
  String get kind;

  /// Where this world comes from, in the user's words: the wiki's host,
  /// or "Ines Calder's chat".
  String get label;

  /// Hooks the source onto the run it serves. A source that needs the
  /// model (the chat Skim) keeps these; the wiki ignores them. Called
  /// before every scout, write and climate pass; must be idempotent.
  void bind({
    required LLMService llm,
    required WorldWikiBudget budget,
    void Function(String message)? onProgress,
    Duration callTimeout = kWorldToolCallTimeout,
    Duration retryPause = const Duration(seconds: 2),
    bool Function()? isAborted,
  }) {}

  /// The index: titles, their tags, whether the order means anything.
  Future<WikiStudioCatalog> catalog({String? seedQuery});

  /// One title's text, or '' when the source has nothing under it.
  Future<String> article(String title);

  /// Titles that speak to the weather, most useful first. With
  /// [allowGuess] a source may offer what a climate could be guessed from
  /// when the record shows no weather; without it, only real evidence.
  Future<List<String>> climateTitles({bool allowGuess = false});

  /// Plain words for the Review step's Add when [name] has no page.
  String missingPageCopy(String name) =>
      'The source has nothing called "$name", so nothing was written.';

  /// The most cards a shelf holds at [depth]; a chat yields fewer than a
  /// wiki (docs/design/world-from-character.md §3.3).
  int cardTarget(WorldWikiDepth depth) => depth.cardTarget;

  /// What the first scout call asks for at [depth].
  (int, int) scoutRange(WorldWikiDepth depth) => depth.scoutRange;

  /// Whether Deep is offered for this source.
  bool get offersDeep => true;
}

/// The wiki as a [WorldSource]: the studio index and full articles, as the
/// engine has always read them.
class WikiWorldSource extends WorldSource {
  WikiWorldSource(this.wiki);

  final WikiSearchService wiki;

  @override
  String get kind => 'wiki';

  @override
  String get label => wikiHostLabel(wiki.getBaseUrl());

  @override
  Future<WikiStudioCatalog> catalog({String? seedQuery}) =>
      wiki.listStudioTitles(seedQuery: seedQuery);

  @override
  Future<String> article(String title) async {
    final t = title.trim();
    if (t.isEmpty || skipWikiStudioTitle(t)) return '';
    final page = await wiki.getArticleFull(t);
    return page.ok ? page.snippet : '';
  }

  @override
  Future<List<String>> climateTitles({bool allowGuess = false}) async {
    final index = await wiki.listStudioTitles();
    return [
      for (final t in index.titles)
        if (wikiTitleLooksClimate(t)) t,
    ].take(4).toList();
  }

  @override
  String missingPageCopy(String name) =>
      'The wiki has no page called "$name", so nothing was written. '
      'Give the page\'s title.';
}
