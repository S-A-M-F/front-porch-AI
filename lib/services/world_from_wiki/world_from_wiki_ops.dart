// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_craft_mechanics.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_tools.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_budget.dart';

const int kWorldFromWikiScanDepth = 10;
const int kWorldFromWikiTokenBudget = 2800;

/// Tag words that say what a page IS; a line keeps these first.
const List<String> kWorldTagTypeWords = [
  'location',
  'place',
  'city',
  'town',
  'realm',
  'world',
  'region',
  'nation',
  'organization',
  'organisation',
  'faction',
  'group',
  'character',
  'people',
  'race',
  'species',
  'event',
  'battle',
  'war',
  'arc',
  'term',
  'concept',
  'power',
  'abilit',
  'item',
  'weapon',
];

/// Tags that are wiki housekeeping, never world facts.
const List<String> kWorldTagNoiseWords = [
  'pages',
  'articles',
  'stub',
  'needing',
  'unofficial',
  'image',
  'gallery',
  'with ',
  'without',
  'missing',
  'cleanup',
  'spoiler',
  'template',
];

/// The tags a title shows the scout, best four first: tags that name
/// another catalog title (a place or faction the page sits in), then tags
/// that say what the page is, then the rest; housekeeping tags are dropped.
List<String> worldScoutTagsFor(
  List<String> tags, {
  required Set<String> titlesLower,
  int max = 4,
}) {
  int rank(String tag) {
    final lower = tag.toLowerCase();
    if (titlesLower.contains(lower)) return 0;
    if (kWorldTagTypeWords.any(lower.contains)) return 1;
    return 2;
  }

  final kept = [
    for (final tag in tags)
      if (!tag.startsWith(r'$:/') &&
          !kWorldTagNoiseWords.any(tag.toLowerCase().contains))
        tag,
  ];
  final ranked = [
    for (var i = 0; i < kept.length; i++) (rank(kept[i]), i),
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [for (final r in ranked.take(max)) kept[r.$2]];
}

/// The scout's index lines: a title, and its tags when the wiki has them
/// (Neokosmos keeps its nations ONLY in tags — titles alone read
/// "Ceolwynn, Bealdric…" with nothing saying where they belong, design §9).
List<String> worldScoutIndexLines(
  List<String> titles,
  Map<String, List<String>> tags,
) {
  final titlesLower = {for (final t in titles) t.toLowerCase()};
  return [
    for (final t in titles)
      () {
        final shown = worldScoutTagsFor(
          tags[t] ?? const <String>[],
          titlesLower: titlesLower,
        ).join(', ');
        return shown.isEmpty ? '- $t' : '- $t [$shown]';
      }(),
  ];
}

/// Build the library World. Climate off → no biome json, no place traits.
/// Climate-on without a custom biome fails closed (no stock Temperate).
/// Book recursion on, scan depth 10, token budget 2800.
World worldFromWikiDraft({
  required String name,
  required String description,
  required List<LorebookEntry> entries,
  bool climateEnabled = false,
  Map<String, dynamic>? biome,
  String parentWorldId = '',
}) {
  final trimmed = name.trim();
  final custom = climateEnabled && biome != null && biome.isNotEmpty;
  return World(
    name: trimmed.isEmpty ? 'Untitled world' : trimmed,
    description: description.trim(),
    lorebook: Lorebook(
      entries: List<LorebookEntry>.from(entries),
      recursiveScanning: true,
      scanDepth: kWorldFromWikiScanDepth,
      tokenBudget: kWorldFromWikiTokenBudget,
    ),
    climateEnabled: custom,
    biomeId: custom ? 'custom' : null,
    biomeJson: custom ? jsonEncode(biome) : null,
    // Slice 8: places hang off the root; '' keeps a flat world a root.
    parentWorldId: parentWorldId.isEmpty ? null : parentWorldId,
  );
}

/// Preview/Save gate. Abort or an empty signed shelf must not persist.
bool worldFromWikiCanSave({
  required bool aborted,
  required bool lorebooksOn,
  required List<LorebookEntry> entries,
}) {
  if (aborted) return false;
  if (!lorebooksOn) return true;
  return entries.isNotEmpty;
}

/// Client write payload. Empty, unsigned, or ToC-sized lists are rejected;
/// [max] is the deepest shelf the wizard can produce.
List<WorldProposedCard> parseSignedWorldWriteCards(
  dynamic raw, {
  int max = kWorldScoutCardMax,
}) {
  if (raw is! List) return const [];
  final out = <WorldProposedCard>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final map = Map<String, dynamic>.from(e);
    if (!_signedFlag(map['signed'])) continue;
    final card = WorldProposedCard.tryParse(map);
    if (card == null) continue;
    out.add(card);
    if (out.length > max) return const [];
  }
  return out;
}

/// Pair generated prose to signed cards by name. No leftover force-pick.
List<WorldCraftDraft> matchWorldWriteBatch(
  List<WorldProposedCard> cards,
  List<WorldLoreWrite> generated,
) {
  final leftover = [...generated];
  final out = <WorldCraftDraft>[];
  for (final card in cards) {
    final want = card.name.toLowerCase();
    var hit = -1;
    for (var j = 0; j < leftover.length; j++) {
      if (leftover[j].name.toLowerCase() == want) {
        hit = j;
        break;
      }
    }
    if (hit < 0) continue;
    final g = leftover.removeAt(hit);
    out.add(
      WorldCraftDraft(
        name: g.name == 'Untitled' ? card.name : g.name,
        keys: g.keys.isEmpty ? card.keys : g.keys,
        content: g.content,
        role: card.role,
        group: card.group,
      ),
    );
  }
  return out;
}

bool _signedFlag(dynamic raw) {
  if (raw == true || raw == 1) return true;
  if (raw is String) {
    final s = raw.trim().toLowerCase();
    return s == 'true' || s == '1';
  }
  return false;
}

/// Whether [resp] carries the scout's card list at all.
bool _worldScoutHasList(LlmToolResponse resp) => resp.calls.any(
  (c) =>
      c.name == kWorldScoutToolName &&
      (c.arguments['cards'] is List || c.arguments['card'] is List),
);

/// A reply the model did not get to finish: cut at max_tokens, a tool call
/// the server dropped as incomplete, or a call whose list is not there to
/// read (a JSON cut mid-way parses to nothing). The scout asks again on a
/// smaller part for any of these.
bool worldScoutReplyWasCut(LlmToolResponse? resp) {
  if (resp == null) return false;
  if (resp.finishReason == 'length') return true;
  if (resp.isUnusableNativeToolCall) return true;
  return resp.calls.isNotEmpty && !_worldScoutHasList(resp);
}

/// Why the shelf is empty when that is not the model's judgement, in the
/// words the wizard shows. Null when the model answered with a card list
/// (even one the catalog check emptied) — the caller keeps its own
/// "try a clearer premise" line for that. Everything else used to read
/// as that same line, blaming the premise for a cut-off reply or a 502.
String? worldScoutEmptyReason(
  LlmToolResponse? resp, {
  required int budget,
  int? contextTokens,
}) {
  if (resp == null) {
    return 'The model did not answer with a card list, so there is nothing '
        'to review yet. Press Scout again; if it keeps happening, pick a '
        'different model.';
  }
  if (resp.finishReason == 'length') {
    final window = contextTokens == null
        ? ''
        : ' the wizard\'s ${worldWikiContextLabel(contextTokens)} context '
              'leaves after the index';
    return 'The model ran out of room before it finished the card list — '
        'its reply hit the $budget-token limit$window. Give this wizard a '
        'bigger context in the Book step, or pick a different model.';
  }
  if (resp.calls.isEmpty) {
    return 'The model answered in plain text instead of a card list. Press '
        'Scout again, or pick a model that handles tools better.';
  }
  if (!_worldScoutHasList(resp)) {
    return "The model's card list could not be read (its reply was not "
        'valid JSON). Press Scout again.';
  }
  return null;
}

/// The words for a shelf left empty because even the smallest index part
/// did not fit the window.
String worldScoutCutCopy({required int contextTokens, required int parts}) {
  final tries = parts == 1 ? 'once' : 'in $parts parts';
  return 'The model ran out of room before it finished the card list, even '
      'with the index asked $tries. Give this wizard a bigger context in '
      'the Book step (it has ${worldWikiContextLabel(contextTokens)} now), '
      'or pick a model that answers with less thinking.';
}

/// The scout's words for a request that never got an answer.
String worldScoutTransportCopy(Object error) {
  if (error is LlmToolTransportException) {
    return "The model's server could not take the request (${error.message}). "
        'The wiki is fine — wait a moment and press Scout again.';
  }
  if (looksLikeBackendUnreachable(error)) {
    return "The scout could not reach the model's server. Check that the "
        'backend is running, then press Scout again.';
  }
  return 'The scout could not finish ($error). Press Scout again.';
}

/// ", asked in 3 parts, 1 cut off" for the status line; '' when the index
/// fit the wizard's context whole.
String worldScoutPartsNote({required int parts, required int partsCut}) {
  final bits = <String>[];
  if (parts > 1) bits.add('asked in $parts parts');
  if (partsCut > 0) bits.add('$partsCut cut off');
  return bits.isEmpty ? '' : ', ${bits.join(', ')}';
}

/// ", shelf revised: 11 of 30 cards were people" or ", review: …" when
/// the revise did not take; '' when the shelf read as a world.
String worldScoutShelfNote({
  required bool revised,
  required List<String> auditNotes,
}) {
  if (auditNotes.isEmpty) return '';
  final first = auditNotes.first;
  final short = first.contains(';') ? first.split(';').first : first;
  return revised ? ', shelf revised: $short' : ', review: $short';
}

/// A tool call the server never answers must not hang the wizard: past
/// this the request is abandoned (its client closed) and asked again.
/// The third Kimi run sat 30 minutes inside one profile call.
const Duration kWorldToolCallTimeout = Duration(minutes: 6);

/// One tool call, asked again once when the server stumbled (a thrown
/// transport failure, a timeout) or the model never finished (no usable
/// call). The first live run on nano-gpt lost a whole write batch to one
/// 502 — "Upstream returned no tool call despite required tool_choice" —
/// and three cards vanished without a word. A prose answer is first read
/// for a JSON object carrying [floorKey] (the text floor every eval also
/// keeps); the second ask has thinking off, which is what settles a local
/// model that narrates instead of calling. Null when both tries failed.
Future<LlmToolResponse?> askToolsTwice(
  LLMService llm, {
  required GenerationParams params,
  required List<Map<String, dynamic>> tools,
  required String label,
  String? toolName,
  String? floorKey,
  Duration pause = const Duration(seconds: 2),
  Duration timeout = kWorldToolCallTimeout,
}) async {
  for (var attempt = 1; attempt <= 2; attempt++) {
    final sent = attempt == 1
        ? params
        : GenerationParams(
            prompt: params.prompt,
            maxLength: params.maxLength,
            minLength: params.minLength,
            temperature: params.temperature,
            reasoningEnabled: false,
            reasoningMaxTokens: 0,
            toolChoice: params.toolChoice,
          );
    try {
      final resp = await llm.generateWithTools(sent, tools).timeout(timeout);
      if (resp != null &&
          !resp.isUnusableNativeToolCall &&
          resp.calls.isNotEmpty) {
        return resp;
      }
      final prose =
          resp != null && resp.calls.isEmpty && resp.finishReason != 'length';
      if (prose && floorKey != null && toolName != null) {
        final floor = worldToolArgsFromText(resp.text, key: floorKey);
        if (floor != null) {
          debugPrint('[World] $label try $attempt: read from the prose');
          return LlmToolResponse(
            calls: [LlmToolCall(name: toolName, arguments: floor)],
            text: '',
            finishReason: resp.finishReason,
          );
        }
      }
      debugPrint(
        '[World] $label try $attempt: no usable call '
        '(finish=${resp?.finishReason})',
      );
    } on TimeoutException {
      debugPrint('[World] $label try $attempt: no answer in $timeout');
      llm.abortGeneration();
    } catch (e) {
      debugPrint('[World] $label try $attempt miss ($e)');
    }
    if (attempt == 1 && pause > Duration.zero) {
      await Future<void>.delayed(pause);
    }
  }
  return null;
}

/// The scout's arguments dug out of a prose answer (see
/// [worldToolArgsFromText]).
Map<String, dynamic>? worldScoutArgsFromText(String text) =>
    worldToolArgsFromText(text, key: 'cards');

/// A tool call's arguments dug out of a prose answer: the first balanced
/// JSON object in [text] that carries [key], fences and all. The text
/// floor under the native call (the same order every eval keeps): gemma-4
/// on oMLX wrote the shelf, and then whole write batches, as JSON blocks
/// in plain text. Null when the prose holds no such object.
Map<String, dynamic>? worldToolArgsFromText(
  String text, {
  required String key,
}) {
  var start = text.indexOf('{');
  while (start >= 0) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          try {
            final decoded = jsonDecode(text.substring(start, i + 1));
            if (decoded is Map && decoded[key] != null) {
              return Map<String, dynamic>.from(decoded);
            }
          } catch (_) {}
          break;
        }
      }
    }
    start = text.indexOf('{', start + 1);
  }
  return null;
}

/// The prompt line that pins when the scene stands; '' with no moment.
String worldMomentLine(String moment) =>
    moment.trim().isEmpty ? '' : 'Moment: ${moment.trim()}\n';

/// The rule every writer and reviewer applies to time.
String worldMomentRule(String moment) => moment.trim().isEmpty
    ? 'Write every person and faction as they stand in the premise\'s time '
          '— their role and fate then (alive, fallen, defected, imprisoned), '
          'not their whole history.'
    : 'Write everything as it stands at the Moment ("${moment.trim()}"): '
          'each person\'s role, whereabouts and fate then. What happens after '
          'the Moment is unknown to everyone — never state it, not even as '
          'foreshadowing.';
