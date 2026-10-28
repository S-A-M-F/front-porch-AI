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

import 'world_craft_mechanics.dart';
import 'world_places.dart';

/// Scout result: index size plus proposed cards (default unsigned).
class WorldScoutResult {
  const WorldScoutResult({
    required this.catalog,
    required this.proposed,
    this.places = const [],
    this.failure,
    this.parts = 0,
    this.partsCut = 0,
    this.revised = false,
    this.auditNotes = const [],
    this.notes = const [],
  });

  /// The run log: one line per loop try.
  final List<String> notes;

  final WikiStudioCatalog catalog;
  final List<WorldProposedCard> proposed;

  /// The shelf review's verdict: [revised] when the model's second shelf
  /// replaced the first, [auditNotes] what the review found (empty when
  /// the first shelf already read as a world).
  final bool revised;
  final List<String> auditNotes;

  /// How many requests the index took: 1 when it fit the wizard's context
  /// whole, more when it was asked in parts and merged.
  final int parts;

  /// Parts the model could not finish even at the smallest size; their
  /// titles are missing from [proposed].
  final int partsCut;

  /// Plain words for why [proposed] is empty when the model never gave
  /// its answer: the reply hit the token limit, the server was busy, the
  /// call could not be read. Null when the model did answer — the wizard
  /// then keeps its own "try a clearer premise" line.
  final String? failure;

  /// Slice 8 (design §9.2): the places the scout named from tag
  /// evidence, already resolved into build order. Empty on an untagged
  /// wiki — every consumer must treat that as "flat world, as before".
  final List<WorldProposedPlace> places;
}
