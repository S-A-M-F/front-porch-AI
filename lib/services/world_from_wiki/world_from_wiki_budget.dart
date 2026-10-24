// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The wizard's own context window and everything sized from it: how much
// reply room a prompt leaves, how the title index splits into parts that
// each leave the scout room to answer, and how signed cards pack into
// write batches the window can hold. Plain Dart; no Flutter.

import 'dart:math';

import 'world_craft_mechanics.dart';
import 'world_from_wiki_tools.dart';

/// The smallest context the wizard runs at: the app's own floor, never
/// suggested below (the chat's context setting keeps the same floor).
const int kWorldWikiContextFloor = 16384;

/// The Book step's choices besides "Same as chat".
const List<int> kWorldWikiContextChoices = [
  16384,
  32768,
  65536,
  131072,
  262144,
];

/// Tokens a prompt costs beyond its text: the tool schema, the chat
/// template, and slack for the chars/4 estimate running short.
const int kWorldWikiPromptOverheadTokens = 1536;

/// Room the scout's reply wants before the index is asked in parts: the
/// whole shelf is ~3.5K tokens of JSON (40 cards + 8 places) and a thinking
/// model spends its reasoning from the same room.
const int kWorldScoutReplyWant = 8192;

/// The smallest index part worth asking about. A reply that does not fit
/// for 24 titles will not fit for 12 either, so the wizard stops there.
const int kWorldScoutMinPart = 24;

/// The scout never asks for less than this, whatever the window leaves: a
/// window too small for even that is the server's to refuse, not ours to
/// second-guess with a trimmed prompt.
const int kWorldScoutReplyFloor = 2048;

/// Room a write batch's reply wants: eight 330-character entries are ~1.2K
/// tokens of JSON, the rest is thinking.
const int kWorldWriteReplyWant = 4096;

/// Room the climate call's reply wants: one biome plus up to three short
/// lore cards.
const int kWorldClimateReplyWant = 2048;

/// Characters of article a single card brings to a write batch. Two
/// sentences of lore do not need a 20K-token page, and a batch packed to
/// a 64K window prefilled for minutes on a local model (gemma-4-26B:
/// 60K-token prompts at 8 tok/s, 37 minutes for 30 cards). ~1.5K tokens
/// per card keeps an eight-card batch near 12K.
const int kWorldWriteArticleChars = 6000;

/// chars/4, the estimate the Context Viewer uses everywhere.
int worldWikiEstimateTokens(String text) =>
    text.isEmpty ? 0 : (text.length / 4).ceil();

/// The wizard's context in tokens: its own setting, or the chat's when the
/// setting is 0 ("Same as chat"); never under the floor.
int worldWikiContextTokens({required int setting, required int chatContext}) {
  final chosen = setting > 0 ? setting : chatContext;
  return max(kWorldWikiContextFloor, chosen);
}

/// "64K" for 65536; a number that is not whole K stays as digits.
String worldWikiContextLabel(int tokens) =>
    tokens > 0 && tokens % 1024 == 0 ? '${tokens ~/ 1024}K' : '$tokens';

/// A valid Book step pick: 0 (same as chat) or a size at or over the floor.
bool worldWikiContextSettingValid(int value) =>
    value == 0 || value >= kWorldWikiContextFloor;

/// One context window, and what it leaves for a reply.
class WorldWikiBudget {
  const WorldWikiBudget(this.contextTokens);

  final int contextTokens;

  /// Tokens left for the reply once [prompt] and its overhead are in. May
  /// be negative: the prompt alone outgrows the window.
  int roomAfter(String prompt) =>
      contextTokens -
      worldWikiEstimateTokens(prompt) -
      kWorldWikiPromptOverheadTokens;

  /// The reply budget to ask for: what the window leaves, never under
  /// [floor].
  int replyFor(String prompt, {int floor = 1024}) =>
      max(floor, roomAfter(prompt));

  /// Whether [prompt] leaves at least [want] tokens for the reply.
  bool leaves(String prompt, int want) => roomAfter(prompt) >= want;

  /// [text] cut so that, beside [fixedTokens] of other prompt, the reply
  /// still gets [want] tokens. Empty when nothing of it fits.
  String clipForReply(String text, {required int want, int fixedTokens = 0}) {
    final chars =
        (contextTokens - kWorldWikiPromptOverheadTokens - want - fixedTokens) *
        4;
    if (chars <= 0) return '';
    return text.length <= chars ? text : text.substring(0, chars);
  }
}

/// Index lines → parts whose prompts each leave [want] tokens of reply
/// room. [promptFor] builds the prompt around a part (header, rules). A
/// part never has fewer than [minPart] lines unless the index itself does,
/// so a window too small for even that is still asked, once per part.
List<List<String>> splitWorldScoutIndex(
  List<String> lines, {
  required WorldWikiBudget budget,
  required String Function(List<String> part) promptFor,
  int want = kWorldScoutReplyWant,
  int minPart = kWorldScoutMinPart,
  int minParts = 1,
}) {
  if (lines.isEmpty) return const [];
  final header = worldWikiEstimateTokens(promptFor(const []));
  final capacity =
      budget.contextTokens - kWorldWikiPromptOverheadTokens - want - header;
  final parts = <List<String>>[];
  var part = <String>[];
  var used = 0;
  for (final line in lines) {
    final cost = worldWikiEstimateTokens('$line\n');
    if (part.length >= minPart && used + cost > capacity) {
      parts.add(part);
      part = [];
      used = 0;
    }
    part.add(line);
    used += cost;
  }
  if (part.isNotEmpty) parts.add(part);
  // Parts by cards: a big ask is split so each answer stays short. Each
  // part takes every n-th line, so all of them see the top of the ranking.
  final byCards = min(minParts, lines.length ~/ minPart);
  if (byCards > parts.length) {
    final spread = List.generate(byCards, (_) => <String>[]);
    for (var i = 0; i < lines.length; i++) {
      spread[i % byCards].add(lines[i]);
    }
    return spread;
  }
  return parts;
}

/// Characters of article one card gets, whatever the window: a 24K clip
/// at 256K made each write call four times the prompt for no visible gain
/// and the root book took most of an hour on a remote provider. The lead
/// and first sections carry what a two-sentence card needs.
int worldWriteArticleCharsFor(int contextTokens) => kWorldWriteArticleChars;

/// Two halves of a part the model could not finish; the first keeps the
/// odd line.
(List<String>, List<String>) halveWorldScoutPart(List<String> part) {
  final mid = (part.length + 1) ~/ 2;
  return (part.sublist(0, mid), part.sublist(mid));
}

/// Cards that go to the model in one write call, with their articles.
class WorldWriteBatch {
  const WorldWriteBatch({required this.cards, required this.articles});

  final List<WorldProposedCard> cards;
  final List<String> articles;
}

/// Tokens a card costs in the batch prompt besides its articles (the CARD
/// header, name, role and keys lines).
const int kWorldWriteCardOverheadTokens = 80;

/// Signed cards → write batches the window holds: up to [maxCards] per
/// batch, each batch's articles kept under what leaves [want] reply room,
/// and a single card's articles clipped so one card always fits. Yields as
/// it goes so a slow wiki still shows progress and [stop] ends the fetching.
Stream<WorldWriteBatch> planWorldWriteBatches(
  List<WorldProposedCard> cards, {
  required WorldWikiBudget budget,
  required int headerTokens,
  required Future<String> Function(WorldProposedCard card) articleFor,
  void Function(WorldProposedCard card)? onMiss,
  bool Function()? stop,
  int maxCards = kWorldWriteBatchSize,
  int want = kWorldWriteReplyWant,
}) async* {
  final capacity =
      budget.contextTokens -
      kWorldWikiPromptOverheadTokens -
      want -
      headerTokens;
  // Characters one card's articles may take: the per-card cap, or less
  // when the window would not leave the reply room even for that.
  final articleCharCap = min(
    worldWriteArticleCharsFor(budget.contextTokens),
    max(800, (capacity - kWorldWriteCardOverheadTokens) * 4),
  );
  var batchCards = <WorldProposedCard>[];
  var batchArticles = <String>[];
  var used = 0;
  for (final card in cards) {
    if (stop?.call() ?? false) return;
    var article = await articleFor(card);
    if (article.isEmpty) {
      onMiss?.call(card);
      continue;
    }
    if (article.length > articleCharCap) {
      article = article.substring(0, articleCharCap);
    }
    final cost =
        kWorldWriteCardOverheadTokens + worldWikiEstimateTokens(article);
    if (batchCards.isNotEmpty &&
        (batchCards.length >= maxCards || used + cost > capacity)) {
      yield WorldWriteBatch(cards: batchCards, articles: batchArticles);
      batchCards = [];
      batchArticles = [];
      used = 0;
    }
    batchCards.add(card);
    batchArticles.add(article);
    used += cost;
  }
  if (batchCards.isNotEmpty) {
    yield WorldWriteBatch(cards: batchCards, articles: batchArticles);
  }
}

/// Write batches in flight at once on a remote provider; a local server
/// has one generation slot and stays serial.
const int kWorldWriteConcurrencyRemote = 3;

/// Runs [work] over [items] with at most [limit] in flight, keeping the
/// results in item order.
Future<List<T>> forEachLimited<S, T>(
  List<S> items,
  int limit,
  Future<T> Function(int index, S item) work,
) async {
  final results = List<T?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final i = next++;
      results[i] = await work(i, items[i]);
    }
  }

  final lanes = limit < 1 ? 1 : limit;
  await Future.wait([for (var i = 0; i < lanes; i++) worker()]);
  return [for (final r in results) r as T];
}
