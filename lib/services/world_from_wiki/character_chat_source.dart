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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/llm_service.dart';

import 'chat_skim.dart';
import 'world_chat_record.dart';
import 'world_chat_sources.dart';
import 'world_from_wiki_budget.dart';
import 'world_from_wiki_depth.dart';
import 'world_from_wiki_ops.dart';
import 'world_progress_copy.dart';
import 'world_source.dart';

/// The virtual title under which the chat's weather words are read.
const String kWorldChatWeatherTitle = 'Weather in the chat';

/// Characters of chat lines one card may read.
const int kWorldChatArticleChars = 6000;

/// One section of a character card as an index title.
typedef WorldCardSection = ({String title, String text, String tag});

/// The sections of [card] that are titles: each non-empty field, and the
/// card's own lorebook entries by name (design §3.2).
List<WorldCardSection> worldCardSections(CharacterCard card) {
  String fill(String s) => s.replaceAll('{{char}}', card.name).trim();
  final out = <WorldCardSection>[];
  void add(String title, String text, [String tag = 'card']) {
    final t = fill(text);
    if (t.isNotEmpty) out.add((title: title, text: t, tag: tag));
  }

  add('Description', card.description);
  add('Personality', card.personality);
  add('Scenario', card.scenario);
  add('First greeting', card.firstMessage);
  for (var i = 0; i < card.alternateGreetings.length; i++) {
    add('Greeting ${i + 2}', card.alternateGreetings[i]);
  }
  add('Example dialogue', card.mesExample);
  add('Creator notes', card.creatorNotes);
  final seen = {for (final s in out) s.title.toLowerCase()};
  for (final e in card.lorebook?.entries ?? const <LorebookEntry>[]) {
    if (!e.enabled) continue;
    final name = e.name.trim().isEmpty
        ? (e.keys.isEmpty ? '' : e.keys.first)
        : e.name.trim();
    if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
    add(name, e.content, 'card-lore');
  }
  return out;
}

/// A character and, optionally, one of their chats as a [WorldSource]
/// (docs/design/world-from-character.md §3.2). The card's sections are
/// titles as they are; the chat is skimmed into an index of named things
/// on the first [catalog] call, and each name's article is the lines that
/// name it plus what the Journal, the rings and the Objectives say of it.
class CharacterChatWorldSource extends WorldSource {
  CharacterChatWorldSource({required this.card, required this.record})
    : sections = worldCardSections(card);

  final CharacterCard card;
  final WorldChatRecord record;
  final List<WorldCardSection> sections;

  WorldSkimResult? skim;

  LLMService? _llm;
  WorldWikiBudget? _budget;
  void Function(String message)? _onProgress;
  Duration _callTimeout = kWorldToolCallTimeout;
  Duration _retryPause = const Duration(seconds: 2);
  bool Function()? _isAborted;

  @override
  String get kind => 'character';

  @override
  String get label =>
      record.hasChat ? "${card.name}'s chat" : "${card.name}'s card";

  @override
  bool get offersDeep => false;

  @override
  int cardTarget(WorldWikiDepth depth) => worldCharacterCardTarget(depth);

  @override
  (int, int) scoutRange(WorldWikiDepth depth) =>
      worldCharacterScoutRange(depth);

  @override
  void bind({
    required LLMService llm,
    required WorldWikiBudget budget,
    void Function(String message)? onProgress,
    Duration callTimeout = kWorldToolCallTimeout,
    Duration retryPause = const Duration(seconds: 2),
    bool Function()? isAborted,
  }) {
    _llm = llm;
    _budget = budget;
    _onProgress = onProgress;
    _callTimeout = callTimeout;
    _retryPause = retryPause;
    _isAborted = isAborted;
  }

  /// Runs the Skim once; a second scout or a write reuses it.
  Future<WorldSkimResult?> ensureSkim() async {
    if (skim != null || !record.hasChat) return skim;
    final llm = _llm;
    final budget = _budget;
    if (llm == null || budget == null) {
      throw StateError('the chat source was not bound to a run');
    }
    return skim = await runWorldSkim(
      record,
      llm: llm,
      budget: budget,
      userName: record.userName,
      onProgress: _onProgress,
      callTimeout: _callTimeout,
      retryPause: _retryPause,
      isAborted: _isAborted,
    );
  }

  WorldSkimName? _named(String title) {
    final key = title.trim().toLowerCase();
    for (final n in skim?.names ?? const <WorldSkimName>[]) {
      if (n.key == key) return n;
      if (n.aliases.any((a) => a.trim().toLowerCase() == key)) return n;
    }
    return null;
  }

  WorldCardSection? _section(String title) {
    final key = title.trim().toLowerCase();
    for (final s in sections) {
      if (s.title.toLowerCase() == key) return s;
    }
    return null;
  }

  @override
  Future<WikiStudioCatalog> catalog({String? seedQuery}) async {
    _onProgress?.call(
      worldProgressCardRead(
        sections.where((s) => s.tag == 'card').length,
        sections.where((s) => s.tag == 'card-lore').length,
      ),
    );
    final result = await ensureSkim();
    final titles = <String>[];
    final tags = <String, List<String>>{};
    final seen = <String>{};
    for (final n in result?.names ?? const <WorldSkimName>[]) {
      if (!seen.add(n.key)) continue;
      titles.add(n.name);
      tags[n.name] = [
        // The scout's tag words: a person reads as a character page, the
        // rest by their kind; the parent place names the place around it.
        n.kind == 'person' ? 'character' : n.kind,
        if (n.parent.isNotEmpty) n.parent,
        'chat',
      ];
    }
    for (final s in sections) {
      if (!seen.add(s.title.toLowerCase())) continue;
      titles.add(s.title);
      tags[s.title] = [s.tag];
    }
    return WikiStudioCatalog(
      backend: WikiBackend.unknown,
      titles: titles,
      parsed: titles.length,
      articleCount: titles.length,
      tagsByTitle: tags,
      ranked: true,
    );
  }

  @override
  Future<String> article(String title) async {
    final t = title.trim();
    if (t.isEmpty) return '';
    if (t.toLowerCase() == kWorldChatWeatherTitle.toLowerCase()) {
      final words = [
        for (final w in skim?.weather ?? const <String>[])
          if (w.trim().isNotEmpty) w.trim(),
      ];
      return words.isEmpty
          ? ''
          : 'Weather and seasons the chat showed, in order:\n- '
                '${words.join('\n- ')}';
    }
    final section = _section(t);
    if (section != null) return section.text;
    final named = _named(t);
    if (named == null) return '';
    final b = StringBuffer();
    if (named.note.isNotEmpty) b.writeln('${named.name}: ${named.note}');
    if (named.parent.isNotEmpty) b.writeln('Lies inside ${named.parent}.');
    final lines = record.linesNaming(named.name, named.aliases);
    if (lines.isNotEmpty) {
      b.writeln('LINES FROM THE CHAT THAT NAME IT (oldest first):');
      var used = 0;
      for (final l in lines) {
        final line = '${l.sender}: ${l.text}';
        if (used + line.length > kWorldChatArticleChars) break;
        b.writeln(line);
        used += line.length;
      }
    }
    final notes = record.notesNaming(named.name, named.aliases);
    if (notes.isNotEmpty) {
      b.writeln("CONFIRMED BY THE CHAT'S JOURNAL:");
      for (final n in notes) {
        b.writeln('- $n');
      }
    }
    return b.toString().trim();
  }

  @override
  Future<List<String>> climateTitles({bool allowGuess = false}) async {
    if (skim?.hasWeather ?? false) return [kWorldChatWeatherTitle];
    if (!allowGuess) return const [];
    return [
      for (final s in sections)
        if (s.title == 'Scenario' || s.title == 'Description') s.title,
    ];
  }

  @override
  String missingPageCopy(String name) =>
      'Nothing in ${card.name}\'s card or chat is called "$name", so '
      'nothing was written. Use a name the chat uses.';
}
