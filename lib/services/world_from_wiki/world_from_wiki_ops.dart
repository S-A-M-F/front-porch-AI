// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_craft_mechanics.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_tools.dart';

const int kWorldFromWikiScanDepth = 10;
const int kWorldFromWikiTokenBudget = 2800;

/// Reply budget for the scout's one tool call. The full shelf — 40 cards
/// (name, keys, role, up to 3 sources, group, place; ~70 tokens each) plus
/// 8 places and the envelope — is ~3,500 tokens of JSON before a thinking
/// model spends a word on reasoning, which shares this same budget. The
/// old 3,072 cut Qwen3.6 off mid card list once places joined the reply
/// (oMLX: finish_reason=length, incomplete_tool_call). 8K leaves a 16K
/// local context its prompt room: KoboldCpp trims the prompt from the
/// front to make room for max_length, and the 500-title tagged index is
/// ~7K tokens.
const int kWorldScoutMaxTokens = 8192;

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

/// Why the shelf is empty when that is not the model's judgement, in the
/// words the wizard shows. Null when the model answered with a card list
/// (even one the catalog check emptied) — the caller keeps its own
/// "try a clearer premise" line for that. Everything else used to read
/// as that same line, blaming the premise for a cut-off reply or a 502.
String? worldScoutEmptyReason(LlmToolResponse? resp, {required int budget}) {
  if (resp == null) {
    return 'The model did not answer with a card list, so there is nothing '
        'to review yet. Press Scout again; if it keeps happening, pick a '
        'different model.';
  }
  if (resp.finishReason == 'length') {
    return 'The model ran out of room before it finished the card list — '
        'its reply hit the $budget-token limit. Press Scout again, or pick '
        'a different model.';
  }
  if (resp.calls.isEmpty) {
    return 'The model answered in plain text instead of a card list. Press '
        'Scout again, or pick a model that handles tools better.';
  }
  final hasList = resp.calls.any(
    (c) =>
        c.name == kWorldScoutToolName &&
        (c.arguments['cards'] is List || c.arguments['card'] is List),
  );
  if (!hasList) {
    return "The model's card list could not be read (its reply was not "
        'valid JSON). Press Scout again.';
  }
  return null;
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
