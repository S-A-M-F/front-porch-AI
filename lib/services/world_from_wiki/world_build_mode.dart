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

/// How far the writer may go beyond the record it was given
/// (docs/design/world-from-character.md §3.3). All three read the same
/// facts and in all three a contradiction is a finding; they differ in
/// what the model may add: nothing, texture, or new things. A null mode
/// on the engine means the wiki's own rules, unchanged.
enum WorldBuildMode { factsOnly, faithful, creative }

extension WorldBuildModeX on WorldBuildMode {
  static WorldBuildMode fromName(String? name, {WorldBuildMode? fallback}) =>
      WorldBuildMode.values.asNameMap()[name?.trim()] ??
      fallback ??
      WorldBuildMode.factsOnly;

  String get label => switch (this) {
    WorldBuildMode.factsOnly => 'Facts only',
    WorldBuildMode.faithful => 'Faithful',
    WorldBuildMode.creative => 'Creative',
  };

  /// The tile's "What it does" line.
  String get does => switch (this) {
    WorldBuildMode.factsOnly =>
      'Restates what the chat, its Journal, Growth rings and Objectives, '
          'and the card say, in the world\'s voice. The model writes the '
          'sentences; it adds no fact.',
    WorldBuildMode.faithful =>
      'Keeps every fact as the spine and rounds it out: a place gets the '
          'look its lines imply, a person their manner, a gap between known '
          'events a line of connective tissue.',
    WorldBuildMode.creative =>
      'The same facts, and the model may invent around them: new places, '
          'people and events the chat only hints at, and a climate guessed '
          'from the card.',
  };

  /// The tile's "Never" line.
  String get never => switch (this) {
    WorldBuildMode.factsOnly =>
      'A new name, place, event or detail. A sentence the lines do not '
          'state is sent back; a card nothing supports is dropped; weather '
          'only if the chat shows some.',
    WorldBuildMode.faithful =>
      'A new named place, person, faction, item or event, and nothing that '
          'changes what happened. Rounded-out sentences are marked at '
          'Review.',
    WorldBuildMode.creative =>
      'A contradiction of the chat. Invented cards start unsigned on the '
          'Shelf and are marked at Review.',
  };

  /// The one line under the three tiles.
  static const String explainer =
      'All three read the same record. They differ in what the model may '
      'add: nothing, texture, or new things. Whatever is added is marked, '
      'so you can drop it before Mint.';

  /// Whether the fill loop may hunt for cards the index only hints at.
  bool get fills => this == WorldBuildMode.creative;

  /// Whether the scout may keep a card that names no page of the index.
  bool get allowsUnsourced => this == WorldBuildMode.creative;

  /// Whether a climate may be guessed from the card when the chat shows
  /// no weather.
  bool get guessesClimate => this == WorldBuildMode.creative;

  /// What an entry's "added" verdict is called on the Review step.
  String get addedLabel => switch (this) {
    WorldBuildMode.factsOnly => 'beyond the lines',
    WorldBuildMode.faithful => 'rounded out',
    WorldBuildMode.creative => 'extrapolated',
  };

  /// The lines the write header carries for this mode.
  String get writeRule => switch (this) {
    WorldBuildMode.factsOnly =>
      'FACTS ONLY: the SOURCE LINES under each card are the whole truth. '
          'Restate what they say, in the world\'s voice; where they are '
          'silent, stop. Add no name, place, event, date, number or detail '
          'they do not state. The user is {{user}}; never give them a name.',
    WorldBuildMode.faithful =>
      'FAITHFUL: the SOURCE LINES are the spine. You may give them texture '
          '(the look a place implies, a person\'s manner, a sentence between '
          'two known events) but never a new named place, person, faction, '
          'item or event, and nothing that changes what happened. The user '
          'is {{user}}; never give them a name.',
    WorldBuildMode.creative =>
      'CREATIVE: the SOURCE LINES are true and may not be contradicted. '
          'Around them you may invent: places, people and events the chat '
          'only hints at. A card with no source lines is yours to write to '
          'fit the world. The user is {{user}}; never give them a name.',
  };

  /// The entry reviewer's rule for this mode, and what to report as added.
  String get reviewRule => switch (this) {
    WorldBuildMode.factsOnly =>
      'This world is FACTS ONLY: an entry fails when any sentence states '
          'something its SOURCE LINES do not (a name, a place, an event, a '
          'date, a detail); put that sentence in added. Phrasing and voice '
          'are not findings.',
    WorldBuildMode.faithful =>
      'This world is FAITHFUL: texture is allowed (a look, a manner, '
          'connective tissue) and is reported in added, not failed; an entry '
          'fails when it introduces a named place, person, faction, item or '
          'event not in its SOURCE LINES, or changes what happened.',
    WorldBuildMode.creative =>
      'This world is CREATIVE: invention is allowed and is reported in '
          'added, not failed; an entry fails only when it contradicts its '
          'SOURCE LINES. An entry with no source lines is judged on '
          'roleplay use alone.',
  };

  /// The shelf reviewer's line for this mode.
  String get shelfRule => switch (this) {
    WorldBuildMode.creative =>
      'Cards marked invented were proposed from the premise, not the '
          'index; that is allowed here. Fault them only when they '
          'contradict the index.',
    _ =>
      'Every card must name a title from the index; a card from outside '
          'the record does not belong on this shelf.',
  };

  /// The Review step's verdict for a card nothing in the record supports.
  String get missCopy => switch (this) {
    WorldBuildMode.creative => 'no source lines; written from the premise',
    _ => 'nothing in the chat to write this from',
  };
}
