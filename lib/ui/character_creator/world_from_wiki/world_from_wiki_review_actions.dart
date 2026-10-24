// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Review step's actions on the wizard state: edit, drop and pin by
// hand; rewrite one entry with a note, send the whole world back around
// with a direction, add a card under a place. Each model-backed action
// runs the engine that wrote the world, so its shelf, its reviewers and
// its notes carry over. Nothing here saves; Mint does.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';

extension WorldFromWikiReviewActions on WorldFromWikiState {
  /// What the entry loop did to [name], or null for a hand-written one.
  WorldEntryNote? noteFor(String name) =>
      engine?.entryNotes[name.trim().toLowerCase()];

  bool isPinned(String name) => pinned.contains(name.trim().toLowerCase());

  void togglePin(String name) {
    final key = name.trim().toLowerCase();
    if (!pinned.remove(key)) pinned.add(key);
    notify();
  }

  /// The tree the step shows; a flat write is a root with no places.
  WorldWriteTree get reviewTree =>
      tree ??
      WorldWriteTree(
        root: WorldPlaceWrite(
          name: nameController.text.trim(),
          parentName: '',
          description: descController.text.trim(),
          entries: List.of(entries),
        ),
        places: const [],
      );

  void _setTree(WorldWriteTree next) {
    tree = next;
    entries = worldTreeEntries(next);
  }

  void dropEntry(String name) {
    final key = name.trim().toLowerCase();
    _setTree(worldTreeRemove(reviewTree, {key}));
    pinned.remove(key);
    notify();
  }

  /// A hand edit of one entry's text or keys; mechanics stay.
  void editEntry(String name, {String? content, List<String>? keys}) {
    final key = name.trim().toLowerCase();
    LorebookEntry? old;
    for (final e in worldTreeEntries(reviewTree)) {
      if (e.name.trim().toLowerCase() == key) old = e;
    }
    if (old == null) return;
    final next = LorebookEntry.fromJson(old.toJson());
    if (content != null) next.content = content.trim();
    if (keys != null) {
      next.keys = [for (final k in keys) k.trim()]
        ..removeWhere((k) => k.isEmpty);
    }
    _setTree(worldTreeReplace(reviewTree, {key: next}));
    notify();
  }

  /// One entry rewritten with [note] as the finding, reviewed, replaced.
  Future<void> rewriteEntry(String name, String note) async {
    final key = name.trim().toLowerCase();
    final target = [
      for (final e in worldTreeEntries(reviewTree))
        if (e.name.trim().toLowerCase() == key) e,
    ];
    if (target.isEmpty) return;
    await _run('Rewriting ${target.first.name}…', () async {
      final drafts = await engine!.rewriteWithNote(
        entries: target,
        note: note,
        worldName: nameController.text,
        premise: premiseController.text,
        extraLore: extraLore,
      );
      _applyDrafts(drafts);
    });
  }

  /// The direction note, sorted against the shelf and acted on: rewrites
  /// (never a pinned entry), adds, drops. [wholeWorld] rewrites every
  /// unpinned entry with the note instead of sorting.
  Future<void> sendBackAround(String note, {required bool wholeWorld}) async {
    final text = note.trim();
    if (text.isEmpty) return;
    await _run('Reading your note…', () async {
      final e = engine!;
      final all = worldTreeEntries(reviewTree);
      final unpinned = [
        for (final x in all)
          if (!isPinned(x.name)) x,
      ];
      WorldDirection direction;
      if (wholeWorld) {
        direction = WorldDirection(rewrite: [for (final x in unpinned) x.name]);
      } else {
        direction = await e.triageDirection(
          note: text,
          entryNames: [for (final x in all) x.name],
          placeNames: [for (final p in reviewTree.places) p.name],
          worldName: nameController.text,
          premise: premiseController.text,
        );
      }
      final dropKeys = {
        for (final n in direction.drop)
          if (!isPinned(n)) n.trim().toLowerCase(),
      };
      if (dropKeys.isNotEmpty) _setTree(worldTreeRemove(reviewTree, dropKeys));
      final rewriteKeys = {
        for (final n in direction.rewrite)
          if (!isPinned(n)) n.trim().toLowerCase(),
      }..removeAll(dropKeys);
      final targets = [
        for (final x in worldTreeEntries(reviewTree))
          if (rewriteKeys.contains(x.name.trim().toLowerCase())) x,
      ];
      if (targets.isNotEmpty) {
        final drafts = await e.rewriteWithNote(
          entries: targets,
          note: text,
          worldName: nameController.text,
          premise: premiseController.text,
          extraLore: extraLore,
        );
        _applyDrafts(drafts);
      }
      for (final add in direction.add) {
        if (e.aborted) break;
        final made = await e.writeOneCard(
          name: add.name,
          place: add.place,
          worldName: nameController.text,
          premise: premiseController.text,
          extraLore: extraLore,
        );
        if (made != null) _setTree(worldTreeAdd(reviewTree, add.place, made));
      }
      status = worldDirectionSummary(direction, targets.length);
      progress.note(status);
    });
  }

  /// A card the author added by hand under [place].
  Future<void> addCard({
    required String place,
    required String name,
    String page = '',
  }) async {
    if (name.trim().isEmpty) return;
    await _run('Writing ${name.trim()}…', () async {
      final made = await engine!.writeOneCard(
        name: name,
        place: place,
        sourceTitle: page,
        worldName: nameController.text,
        premise: premiseController.text,
        extraLore: extraLore,
      );
      if (made == null) {
        error =
            'The wiki has no page called "${name.trim()}", so nothing was written. Give the page\'s title.';
        return;
      }
      _setTree(worldTreeAdd(reviewTree, place, made));
    });
  }

  void _applyDrafts(Map<String, WorldCraftDraft> drafts) {
    if (drafts.isEmpty) return;
    final updates = <String, LorebookEntry>{};
    for (final e in worldTreeEntries(reviewTree)) {
      final d = drafts[e.name.trim().toLowerCase()];
      if (d != null) {
        updates[e.name.trim().toLowerCase()] = worldEntryWithDraft(e, d);
      }
    }
    _setTree(worldTreeReplace(reviewTree, updates));
  }

  Future<void> _run(String first, Future<void> Function() body) async {
    if (reviewing) return;
    if (engine == null) {
      error = 'Write the world first.';
      notify();
      return;
    }
    reviewing = true;
    error = null;
    beginRun(first);
    notify();
    try {
      await body();
    } catch (e) {
      error = 'That did not go through: $e';
      debugPrint('[World] review action fail reason=$e');
    } finally {
      finishRun();
      reviewing = false;
      notify();
    }
  }
}

/// "Rewrote 3 entries, added Kurosaki Clinic, dropped 1" for the status
/// line once a send-back lands.
String worldDirectionSummary(WorldDirection d, int rewritten) {
  final parts = <String>[
    if (rewritten > 0)
      'rewrote $rewritten ${rewritten == 1 ? 'entry' : 'entries'}',
    if (d.add.isNotEmpty) 'added ${d.add.map((a) => a.name).join(', ')}',
    if (d.drop.isNotEmpty) 'dropped ${d.drop.length}',
  ];
  if (parts.isEmpty) {
    return 'Your note named nothing on the shelf, so nothing changed. Name a card, or apply it to the whole world.';
  }
  final line = parts.join(', ');
  return '${line[0].toUpperCase()}${line.substring(1)}.';
}
