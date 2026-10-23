// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_craft_mechanics.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_tools.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_budget.dart';

const int kWorldFromWikiScanDepth = 10;
const int kWorldFromWikiTokenBudget = 2800;

/// The scout's index lines: a title, and its tags when the wiki has them
/// (Neokosmos keeps its nations ONLY in tags — titles alone read
/// "Ceolwynn, Bealdric…" with nothing saying where they belong, design §9).
List<String> worldScoutIndexLines(
  List<String> titles,
  Map<String, List<String>> tags,
) {
  return [
    for (final t in titles)
      () {
        final shown = [
          for (final tag in tags[t] ?? const <String>[])
            if (!tag.startsWith(r'$:/')) tag,
        ].take(4).join(', ');
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

/// Client write payload. Empty, unsigned, or ToC-sized lists are rejected.
List<WorldProposedCard> parseSignedWorldWriteCards(dynamic raw) {
  if (raw is! List) return const [];
  final out = <WorldProposedCard>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final map = Map<String, dynamic>.from(e);
    if (!_signedFlag(map['signed'])) continue;
    final card = WorldProposedCard.tryParse(map);
    if (card == null) continue;
    out.add(card);
    if (out.length > kWorldScoutCardMax) return const [];
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
