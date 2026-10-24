// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Review step's loop: the author reads the written world and gives
// direction in their own words, and that direction becomes one more
// finding in the same reviewer loop that wrote the entries. Nothing here
// saves anything; the step mints at the end.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';

import 'world_build_mode.dart';
import 'world_craft_mechanics.dart';
import 'world_entry_polish.dart';
import 'world_entry_review.dart';
import 'world_from_wiki_budget.dart';
import 'world_from_wiki_engine.dart';
import 'world_from_wiki_ops.dart';
import 'world_places.dart';
import 'world_progress_copy.dart';

const String kWorldDirectionToolName = 'direct_world_review';

/// A card the author asked for by name, under a place (or '' for the
/// world itself).
typedef WorldDirectionAdd = ({String name, String place});

/// What an author's note asks for, sorted: entries to rewrite, cards to
/// add, entries to drop. Names are the shelf's own spelling.
class WorldDirection {
  const WorldDirection({
    this.rewrite = const [],
    this.add = const [],
    this.drop = const [],
  });

  final List<String> rewrite;
  final List<WorldDirectionAdd> add;
  final List<String> drop;

  bool get isEmpty => rewrite.isEmpty && add.isEmpty && drop.isEmpty;
}

List<Map<String, dynamic>> worldDirectionToolSchema() => [
  {
    'type': 'function',
    'function': {
      'name': kWorldDirectionToolName,
      'description':
          'Sort the author\'s direction into entries to rewrite, cards to '
          'add, and entries to drop. Only what the note asks; names '
          'exactly as listed.',
      'parameters': {
        'type': 'object',
        'properties': {
          'rewrite': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'ENTRIES the note changes, by listed name.',
          },
          'add': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'place': {
                  'type': 'string',
                  'description': 'One of PLACES, or empty for the world.',
                },
              },
              'required': ['name'],
            },
            'description': 'Cards the note asks for that are not on the shelf.',
          },
          'drop': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'ENTRIES the note says to remove.',
          },
        },
        'required': ['rewrite'],
      },
    },
  },
];

/// The model's sort, held to the shelf: a name not on it is dropped from
/// rewrite and drop; an add keeps the listed spelling of its place.
WorldDirection parseWorldDirection(
  List<LlmToolCall> calls, {
  required Iterable<String> known,
  Iterable<String> places = const [],
}) {
  final byKey = {for (final n in known) n.trim().toLowerCase(): n.trim()};
  final placeByKey = {for (final p in places) p.trim().toLowerCase(): p.trim()};
  for (final call in calls) {
    if (call.name != kWorldDirectionToolName) continue;
    List<String> names(Object? raw) => [
      for (final v in (raw is List ? raw : const []))
        ?byKey[v.toString().trim().toLowerCase()],
    ];
    final adds = <WorldDirectionAdd>[];
    final rawAdd = call.arguments['add'];
    if (rawAdd is List) {
      for (final item in rawAdd.whereType<Map>()) {
        final name = item['name']?.toString().trim() ?? '';
        if (name.isEmpty || byKey.containsKey(name.toLowerCase())) continue;
        final place = item['place']?.toString().trim().toLowerCase() ?? '';
        adds.add((name: name, place: placeByKey[place] ?? ''));
      }
    }
    return WorldDirection(
      rewrite: names(call.arguments['rewrite']).toSet().toList(),
      add: adds,
      drop: names(call.arguments['drop']).toSet().toList(),
    );
  }
  return const WorldDirection();
}

/// Without a model's sort: every shelf name the note mentions is rewritten.
WorldDirection matchDirectionNames(String note, Iterable<String> names) {
  final low = note.toLowerCase();
  return WorldDirection(
    rewrite: [
      for (final n in names)
        if (n.trim().length >= 3 && low.contains(n.trim().toLowerCase()))
          n.trim(),
    ],
  );
}

/// [old] with a rewritten draft's text and keys; every trigger setting the
/// mechanics gave it stays.
LorebookEntry worldEntryWithDraft(LorebookEntry old, WorldCraftDraft d) {
  final copy = LorebookEntry.fromJson(old.toJson())
    ..content = d.content
    ..keys = List.of(d.keys);
  return copy;
}

/// Every entry of the tree, root first then places in build order.
List<LorebookEntry> worldTreeEntries(WorldWriteTree t) => [
  ...t.root.entries,
  for (final p in t.places) ...p.entries,
];

/// The tree with entries replaced by name (lowercase keys).
WorldWriteTree worldTreeReplace(
  WorldWriteTree t,
  Map<String, LorebookEntry> updates,
) {
  List<LorebookEntry> swap(List<LorebookEntry> es) => [
    for (final e in es) updates[e.name.trim().toLowerCase()] ?? e,
  ];
  return WorldWriteTree(
    root: t.root.copyWith(entries: swap(t.root.entries)),
    places: [for (final p in t.places) p.copyWith(entries: swap(p.entries))],
  );
}

/// The tree without the named entries (lowercase names).
WorldWriteTree worldTreeRemove(WorldWriteTree t, Set<String> names) {
  List<LorebookEntry> keep(List<LorebookEntry> es) => [
    for (final e in es)
      if (!names.contains(e.name.trim().toLowerCase())) e,
  ];
  return WorldWriteTree(
    root: t.root.copyWith(entries: keep(t.root.entries)),
    places: [for (final p in t.places) p.copyWith(entries: keep(p.entries))],
  );
}

/// The tree with [entry] added to [place] ('' or unknown = the root).
WorldWriteTree worldTreeAdd(WorldWriteTree t, String place, LorebookEntry e) {
  final key = place.trim().toLowerCase();
  var placed = false;
  final places = [
    for (final p in t.places)
      if (!placed && key.isNotEmpty && p.name.trim().toLowerCase() == key)
        (() {
          placed = true;
          return p.copyWith(entries: [...p.entries, e]);
        })()
      else
        p,
  ];
  return WorldWriteTree(
    root: placed ? t.root : t.root.copyWith(entries: [...t.root.entries, e]),
    places: places,
  );
}

extension WorldReviewActions on WorldFromWikiEngine {
  /// The author's note, sorted against the shelf by the model; when the
  /// model gives nothing usable, every shelf name the note mentions is
  /// rewritten.
  Future<WorldDirection> triageDirection({
    required String note,
    required Iterable<String> entryNames,
    required Iterable<String> placeNames,
    required String worldName,
    required String premise,
  }) async {
    onProgress?.call(worldProgressTriage());
    final prompt =
        'World: ${worldName.trim().isEmpty ? 'Untitled' : worldName.trim()}\n'
        'Premise: ${premise.trim()}\n'
        '${worldMomentLine(moment)}'
        'ENTRIES: ${entryNames.join(', ')}\n'
        'PLACES: ${placeNames.join(', ')}\n'
        'THE AUTHOR SAYS: "$note"\n\n'
        'Sort the author\'s direction: which ENTRIES it changes (rewrite), '
        'which cards it asks for that are not on the shelf (add, each with '
        'its place from PLACES or empty for the world itself), and which '
        'ENTRIES it says to remove (drop). Only what the note asks; use the '
        'listed names exactly. Call $kWorldDirectionToolName once.';
    final resp = await askToolsTwice(
      llm,
      params: GenerationParams(
        prompt: prompt,
        maxLength: budget.replyFor(prompt, floor: kWorldClimateReplyWant),
        minLength: 8,
        temperature: 0.2,
        reasoningEnabled: true,
        toolChoice: kWorldDirectionToolName,
      ),
      tools: worldDirectionToolSchema(),
      label: 'direction',
      note: onProgress,
      toolName: kWorldDirectionToolName,
      floorKey: 'rewrite',
      pause: retryPause,
      timeout: callTimeout,
    );
    final sorted = resp == null
        ? const WorldDirection()
        : parseWorldDirection(
            resp.calls,
            known: entryNames,
            places: placeNames,
          );
    return sorted.isEmpty ? matchDirectionNames(note, entryNames) : sorted;
  }

  /// [entries] rewritten with the author's note as the finding, then read
  /// by the entry reviewer like any other revise. Returns the drafts that
  /// came back, by lowercase name; an entry the model skipped is absent.
  Future<Map<String, WorldCraftDraft>> rewriteWithNote({
    required List<LorebookEntry> entries,
    required String note,
    required String worldName,
    required String premise,
    String extraLore = '',
  }) async {
    if (entries.isEmpty) return const {};
    final cards = <WorldProposedCard>[];
    final articles = <String>[];
    final current = <String, WorldCraftDraft>{};
    final problems = <String, List<String>>{};
    for (final e in entries) {
      final key = e.name.trim().toLowerCase();
      final card =
          shelfCards[key] ??
          WorldProposedCard(
            name: e.name,
            keys: e.keys,
            role: _roleOf(e),
            sourceTitles: [e.name],
          );
      cards.add(card);
      articles.add(_clip(await joinSources(card.sourceTitles)));
      current[key] = WorldCraftDraft(
        name: e.name,
        keys: e.keys,
        content: e.content,
        role: card.role,
        group: card.group,
      );
      problems[key] = ['The author says: ${note.trim()}'];
    }
    onProgress?.call(worldProgressDirected(cards.length));
    final revised = await reviseEntries(
      cards,
      articles,
      problems: problems,
      current: current,
      worldName: worldName,
      premise: premise,
      extraLore: extraLore,
    );
    final reviewed = await reviewBatch(
      cards: cards,
      articles: articles,
      drafts: revised,
      worldName: worldName,
      premise: premise,
      extraLore: extraLore,
    );
    final polished = polishWorldDrafts(reviewed, allNames: shelfNames);
    return {for (final d in polished) d.name.trim().toLowerCase(): d};
  }

  /// One card the author added by hand: its page (the name when none is
  /// given), written and reviewed like the rest, with a leaf's mechanics.
  /// Null when the wiki has no such page or the model gave nothing.
  Future<LorebookEntry?> writeOneCard({
    required String name,
    required String place,
    String sourceTitle = '',
    required String worldName,
    required String premise,
    String extraLore = '',
  }) async {
    final title = sourceTitle.trim().isEmpty ? name.trim() : sourceTitle.trim();
    final card = WorldProposedCard(
      name: name.trim(),
      keys: [name.trim()],
      role: WorldCraftRole.leaf,
      sourceTitles: [title],
      place: place.trim(),
      // Creative keeps a hand-added card the record does not know and
      // writes it from the premise; every other run needs its page.
      invented: mode?.allowsUnsourced ?? false,
    );
    onProgress?.call(worldProgressAdding(card.name));
    final article = _clip(await articleForCard(card));
    if (article.trim().isEmpty) return null;
    final written = await writeBatch(
      cards: [card],
      articles: [article],
      worldName: worldName,
      premise: premise,
      extraLore: extraLore,
    );
    final reviewed = await reviewBatch(
      cards: [card],
      articles: [article],
      drafts: matchWorldWriteBatch([card], written),
      worldName: worldName,
      premise: premise,
      extraLore: extraLore,
    );
    if (reviewed.isEmpty) return null;
    rememberShelf([...shelfCards.values, card]);
    final made = applyWorldCraftMechanics(
      polishWorldDrafts(reviewed, allNames: shelfNames),
    );
    return made.isEmpty ? null : made.first;
  }

  String _clip(String article) {
    final cap = worldWriteArticleCharsFor(budget.contextTokens);
    return article.length > cap ? article.substring(0, cap) : article;
  }

  WorldCraftRole _roleOf(LorebookEntry e) => e.constant
      ? WorldCraftRole.era
      : e.preventRecursion
      ? WorldCraftRole.leaf
      : WorldCraftRole.hub;
}
