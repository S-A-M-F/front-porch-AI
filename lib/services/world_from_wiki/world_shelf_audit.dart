// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The shelf review: does the scout's shelf read as a WORLD (era, places,
// factions, events, powers, then a few people) or as a cast list? Plain
// rules the runner checks before it asks the model to revise once.

import 'dart:math';

import 'world_craft_mechanics.dart';
import 'world_places.dart';

/// People may take at most this share of the shelf (one third).
const int kWorldShelfPeopleShare = 3;

/// Fewer people than this are always fine, whatever the share says.
const int kWorldShelfPeopleFloor = 6;

/// A shelf of twelve or more cards needs at least this many places or
/// factions — the settings and the powers that be.
const int kWorldShelfBackboneMin = 4;

/// Shelves under this size are too small to judge by share.
const int kWorldShelfJudgeFrom = 12;

class WorldShelfAudit {
  const WorldShelfAudit(this.problems);

  final List<String> problems;

  bool get ok => problems.isEmpty;
}

/// The problems a shelf has as a world, in the words the revise call and
/// the status line use. Empty when it passes.
WorldShelfAudit auditWorldShelf(
  List<WorldProposedCard> cards, {
  required List<WorldProposedPlace> places,
  required bool tagged,
}) {
  final problems = <String>[];
  // A shelf under twelve cards is not a world yet, and not worth a second
  // model call; the author signs what is there.
  if (cards.length < kWorldShelfJudgeFrom) return WorldShelfAudit(problems);
  final eras = cards.where((c) => c.role == WorldCraftRole.era).length;
  if (eras == 0) problems.add("no era card for the premise's time");
  if (eras > 1) problems.add('$eras era cards; a world has one');
  final kinded = cards.where((c) => c.kind.isNotEmpty).length;
  if (kinded * 2 >= cards.length) {
    final people = cards.where((c) => c.kind == 'person').length;
    final allowed = max(
      kWorldShelfPeopleFloor,
      cards.length ~/ kWorldShelfPeopleShare,
    );
    if (people > allowed) {
      problems.add(
        '$people of ${cards.length} cards are people; keep at most $allowed '
        'and spend the rest on places, factions, events and powers',
      );
    }
    final backbone = cards
        .where((c) => c.kind == 'place' || c.kind == 'faction')
        .length;
    if (backbone < kWorldShelfBackboneMin) {
      problems.add(
        'only $backbone place or faction cards; a world needs its settings '
        'and the powers that be',
      );
    }
    if (tagged && places.isEmpty && cards.any((c) => c.kind == 'place')) {
      problems.add(
        'the index carries tags and the shelf has place cards, but no '
        'places were named in the places list',
      );
    }
  } else {
    problems.add('cards carry no kind; set kind on every card');
  }
  return WorldShelfAudit(problems);
}
