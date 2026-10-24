// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's Review step, over the relay: rewrite one entry with a note,
// send a direction back around, add a card by hand. Each runs in the
// background on the engine that wrote the world and lands as one
// `world_wiki_review_done` event carrying only what changed, so the
// phone's own edits, drops and pins stay its own. Twin of the desktop's
// WorldFromWikiReviewActions.

import 'dart:async';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/services/web/facade/world_from_wiki_facade.dart';
import 'package:front_porch_ai/services/web/util/lorebook_json.dart';

extension WorldFromWikiReviewFacade on WorldFromWikiFacade {
  /// One entry rewritten with the note as the finding. Body: `name`,
  /// `note`, and the phone's `content` / `keys` for it as they stand.
  Map<String, dynamic> startRewrite(Map<String, dynamic> body) {
    final gate = _gate(body);
    if (gate != null) return gate;
    final name = body['name']?.toString().trim() ?? '';
    final note = body['note']?.toString().trim() ?? '';
    if (name.isEmpty || note.isEmpty) {
      return {'ok': false, 'error': 'name and note are required'};
    }
    unawaited(
      _run(() async {
        _takeEdits(body);
        final target = _entryNamed(name);
        if (target == null) {
          throw StateError('no entry called "$name" on this shelf');
        }
        final drafts = await reviewEngine!.rewriteWithNote(
          entries: [target],
          note: note,
          worldName: _worldName,
          premise: _premise,
        );
        final updated = _applyDrafts(drafts);
        return {
          'updated': updated,
          'added': const [],
          'dropped': const [],
          'status': updated.isEmpty
              ? 'The model gave nothing back for $name; it stands as it was.'
              : 'Rewrote $name.',
        };
      }),
    );
    return {'ok': true};
  }

  /// The direction note: sorted against the shelf (or every unpinned
  /// entry when `wholeWorld`), then rewrites, adds and drops. Body:
  /// `note`, `wholeWorld`, `pinned` (names), `entries` (name, content,
  /// keys as the phone has them).
  Map<String, dynamic> startDirection(Map<String, dynamic> body) {
    final gate = _gate(body);
    if (gate != null) return gate;
    final note = body['note']?.toString().trim() ?? '';
    if (note.isEmpty) return {'ok': false, 'error': 'note is required'};
    final wholeWorld = body['wholeWorld'] == true;
    final pinned = {
      for (final p in (body['pinned'] is List ? body['pinned'] as List : []))
        p.toString().trim().toLowerCase(),
    };
    unawaited(
      _run(() async {
        _takeEdits(body);
        final engine = reviewEngine!;
        final all = worldTreeEntries(reviewTree!);
        final unpinned = [
          for (final e in all)
            if (!pinned.contains(e.name.trim().toLowerCase())) e,
        ];
        final direction = wholeWorld
            ? WorldDirection(rewrite: [for (final e in unpinned) e.name])
            : await engine.triageDirection(
                note: note,
                entryNames: [for (final e in all) e.name],
                placeNames: [for (final p in reviewTree!.places) p.name],
                worldName: _worldName,
                premise: _premise,
              );
        final dropKeys = {
          for (final n in direction.drop)
            if (!pinned.contains(n.trim().toLowerCase()))
              n.trim().toLowerCase(),
        };
        if (dropKeys.isNotEmpty) {
          reviewTree = worldTreeRemove(reviewTree!, dropKeys);
        }
        final rewriteKeys = {
          for (final n in direction.rewrite)
            if (!pinned.contains(n.trim().toLowerCase()))
              n.trim().toLowerCase(),
        }..removeAll(dropKeys);
        final targets = [
          for (final e in worldTreeEntries(reviewTree!))
            if (rewriteKeys.contains(e.name.trim().toLowerCase())) e,
        ];
        var updated = const <Map<String, dynamic>>[];
        if (targets.isNotEmpty) {
          final drafts = await engine.rewriteWithNote(
            entries: targets,
            note: note,
            worldName: _worldName,
            premise: _premise,
          );
          updated = _applyDrafts(drafts);
        }
        final added = <Map<String, dynamic>>[];
        for (final add in direction.add) {
          if (engine.aborted) break;
          final made = await engine.writeOneCard(
            name: add.name,
            place: add.place,
            worldName: _worldName,
            premise: _premise,
          );
          if (made == null) continue;
          reviewTree = worldTreeAdd(reviewTree!, add.place, made);
          added.add(_entryJson(made, add.place));
        }
        return {
          'updated': updated,
          'added': added,
          'dropped': [for (final k in dropKeys) k],
          'status': worldDirectionSummaryFor(direction, updated.length),
        };
      }),
    );
    return {'ok': true};
  }

  /// A card the author added by hand. Body: `name`, `place`, `page`.
  Map<String, dynamic> startAdd(Map<String, dynamic> body) {
    final gate = _gate(body);
    if (gate != null) return gate;
    final name = body['name']?.toString().trim() ?? '';
    if (name.isEmpty) return {'ok': false, 'error': 'name is required'};
    final place = body['place']?.toString().trim() ?? '';
    final page = body['page']?.toString().trim() ?? '';
    unawaited(
      _run(() async {
        final made = await reviewEngine!.writeOneCard(
          name: name,
          place: place,
          sourceTitle: page,
          worldName: _worldName,
          premise: _premise,
        );
        if (made == null) {
          throw StateError(reviewEngine!.source.missingPageCopy(name));
        }
        reviewTree = worldTreeAdd(reviewTree!, place, made);
        return {
          'updated': const [],
          'added': [_entryJson(made, place)],
          'dropped': const [],
          'status': 'Wrote $name.',
        };
      }),
    );
    return {'ok': true};
  }

  Map<String, dynamic>? _gate(Map<String, dynamic> body) {
    if (reviewEngine == null || reviewTree == null) {
      return {'ok': false, 'error': 'Write the world first.'};
    }
    if (reviewing) return {'ok': false, 'error': 'a review action is running'};
    return null;
  }

  String get _worldName => reviewBody['name']?.toString() ?? '';
  String get _premise => reviewBody['premise']?.toString() ?? '';

  Future<void> _run(Future<Map<String, dynamic>> Function() body) async {
    reviewing = true;
    try {
      final result = await body();
      if (reviewEngine?.aborted ?? false) {
        broadcast({'event': 'world_wiki_abort', 'data': 'Stopped.'});
        return;
      }
      broadcast({'event': 'world_wiki_review_done', ...result});
    } catch (e) {
      broadcast({'event': 'world_wiki_error', 'error': e.toString()});
    } finally {
      reviewing = false;
    }
  }

  /// The phone's own edits for the named entries, applied to the relay's
  /// tree first so a rewrite starts from the text the author sees.
  void _takeEdits(Map<String, dynamic> body) {
    final raw = body['entries'];
    if (raw is! List) return;
    final updates = <String, LorebookEntry>{};
    final byKey = {
      for (final e in worldTreeEntries(reviewTree!))
        e.name.trim().toLowerCase(): e,
    };
    for (final item in raw.whereType<Map>()) {
      final key = item['name']?.toString().trim().toLowerCase() ?? '';
      final old = byKey[key];
      if (old == null) continue;
      final next = LorebookEntry.fromJson(old.toJson());
      if (item['content'] is String) next.content = item['content'] as String;
      final keys = item['keys'];
      if (keys is List) {
        next.keys = [for (final k in keys) k.toString().trim()]
          ..removeWhere((k) => k.isEmpty);
      } else if (keys is String) {
        next.keys = [for (final k in keys.split(',')) k.trim()]
          ..removeWhere((k) => k.isEmpty);
      }
      updates[key] = next;
    }
    if (updates.isNotEmpty) reviewTree = worldTreeReplace(reviewTree!, updates);
  }

  LorebookEntry? _entryNamed(String name) {
    final key = name.trim().toLowerCase();
    for (final e in worldTreeEntries(reviewTree!)) {
      if (e.name.trim().toLowerCase() == key) return e;
    }
    return null;
  }

  List<Map<String, dynamic>> _applyDrafts(Map<String, WorldCraftDraft> drafts) {
    if (drafts.isEmpty) return const [];
    final updates = <String, LorebookEntry>{};
    for (final e in worldTreeEntries(reviewTree!)) {
      final d = drafts[e.name.trim().toLowerCase()];
      if (d != null) {
        updates[e.name.trim().toLowerCase()] = worldEntryWithDraft(e, d);
      }
    }
    reviewTree = worldTreeReplace(reviewTree!, updates);
    return [for (final e in updates.values) _entryJson(e, _placeOf(e.name))];
  }

  String _placeOf(String name) {
    final key = name.trim().toLowerCase();
    for (final p in reviewTree!.places) {
      if (p.entries.any((e) => e.name.trim().toLowerCase() == key)) {
        return p.name;
      }
    }
    return '';
  }

  Map<String, dynamic> _entryJson(LorebookEntry e, String place) {
    final note = reviewEngine?.entryNotes[e.name.trim().toLowerCase()];
    return {
      'name': e.name,
      'place': place,
      'entry': lorebookEntriesToJson(
        Lorebook(
          entries: [e],
          recursiveScanning: true,
          scanDepth: kWorldFromWikiScanDepth,
          tokenBudget: kWorldFromWikiTokenBudget,
        ),
      ).first,
      if (note != null) 'note': note.toJson(),
    };
  }
}

/// "Rewrote 3 entries, added Kurosaki Clinic, dropped 1." Shared words
/// with the desktop's status line.
String worldDirectionSummaryFor(WorldDirection d, int rewritten) {
  final parts = <String>[
    if (rewritten > 0)
      'rewrote $rewritten ${rewritten == 1 ? 'entry' : 'entries'}',
    if (d.add.isNotEmpty) 'added ${d.add.map((a) => a.name).join(', ')}',
    if (d.drop.isNotEmpty) 'dropped ${d.drop.length}',
  ];
  if (parts.isEmpty) {
    return 'Your note named nothing on the shelf, so nothing changed. Name '
        'a card, or apply it to the whole world.';
  }
  final line = parts.join(', ');
  return '${line[0].toUpperCase()}${line.substring(1)}.';
}
