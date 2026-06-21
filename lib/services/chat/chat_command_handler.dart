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

import 'package:front_porch_ai/models/character_card.dart';

/// Result of an attempted Scene Guest mint, surfaced back to the handler so it
/// can report progress/errors uniformly. On success [card] is the minted (and
/// already-persisted) lite NPC; on failure [card] is null and [error] explains.
class GuestMintResult {
  const GuestMintResult.success(this.card) : error = null;
  const GuestMintResult.failure(this.error) : card = null;

  final CharacterCard? card;
  final String? error;

  bool get ok => card != null;
}

/// Parses and dispatches in-chat slash commands.
///
/// This leaf keeps the slash-command surface out of the `ChatService` god file.
/// It owns command parsing and the Scene-Guest (Lite NPC) entry/exit flow, but
/// never imports `ChatService` or any heavy service: every action it needs is
/// injected as a small callback. This keeps the handler pure (and unit-testable
/// with plain closures), preserves Realism/Needs parity (it does no realism
/// work), and keeps `ChatService` net-smaller.
class ChatCommandHandler {
  ChatCommandHandler({
    required void Function(String? label) setExpression,
    required bool Function() activeCharacterIsSet,
    required List<CharacterCard> Function() getSceneGuestCards,
    required void Function(String? guestName) setPendingGuestDeparture,
    required void Function(String message) onSystemMessage,
    required Future<void> Function() generatePrimaryTurn,
    required Future<GuestMintResult> Function(String name, String concept)
    mintGuest,
    required Future<void> Function(CharacterCard guest) enterGuest,
    required Future<void> Function(CharacterCard guest) exitGuest,
  }) : _setExpression = setExpression,
       _activeCharacterIsSet = activeCharacterIsSet,
       _getSceneGuestCards = getSceneGuestCards,
       _setPendingGuestDeparture = setPendingGuestDeparture,
       _onSystemMessage = onSystemMessage,
       _generatePrimaryTurn = generatePrimaryTurn,
       _mintGuest = mintGuest,
       _enterGuest = enterGuest,
       _exitGuest = exitGuest;

  final void Function(String? label) _setExpression;
  final bool Function() _activeCharacterIsSet;
  final List<CharacterCard> Function() _getSceneGuestCards;
  final void Function(String? guestName) _setPendingGuestDeparture;
  final void Function(String message) _onSystemMessage;
  final Future<void> Function() _generatePrimaryTurn;
  final Future<GuestMintResult> Function(String name, String concept)
  _mintGuest;
  final Future<void> Function(CharacterCard guest) _enterGuest;
  final Future<void> Function(CharacterCard guest) _exitGuest;

  /// Attempt to handle [rawInput] as a slash command.
  ///
  /// Returns `true` if the input was a recognized command (and was handled, or
  /// surfaced an error). Returns `false` for non-commands or unknown commands,
  /// in which case the caller should treat the input as a normal message.
  Future<bool> handle(String rawInput) async {
    final trimmed = rawInput.trim();
    if (!trimmed.startsWith('/')) return false;

    final body = trimmed.substring(1);
    final spaceIdx = body.indexOf(RegExp(r'\s'));
    final command = (spaceIdx < 0 ? body : body.substring(0, spaceIdx))
        .toLowerCase();
    final args = spaceIdx < 0 ? '' : body.substring(spaceIdx + 1).trim();

    switch (command) {
      case 'expression-set':
      case 'expression':
        _setExpression(args.isNotEmpty ? args.toLowerCase() : null);
        return true;

      case 'expression-clear':
        _setExpression(null);
        return true;

      case 'create':
        await _handleCreate(args);
        return true;

      case 'exit':
        await _handleExit(args);
        return true;

      default:
        return false; // unknown command — caller sends as a normal message
    }
  }

  // ── Scene Guest: /create ────────────────────────────────────────────────
  // Syntax: `/create <name>: <concept>`, `/create <name> | <concept>`,
  // or `/create <name>` (empty concept). Mints a lite NPC (via the injected
  // [mintGuest], which gens + persists it), adds it to the scene, and has it
  // speak its entrance via the existing engine ([enterGuest]).
  Future<void> _handleCreate(String args) async {
    if (!_activeCharacterIsSet()) {
      _onSystemMessage('⚠ Scene Guests can only be added inside a 1:1 chat.');
      return;
    }
    if (args.trim().isEmpty) {
      _onSystemMessage('⚠ Usage: /create <name>: <concept>');
      return;
    }

    // Split name from concept on the first ':' or '|'.
    final String name;
    final String concept;
    final m = RegExp(r'[:|]').firstMatch(args);
    if (m != null) {
      name = args.substring(0, m.start).trim();
      concept = args.substring(m.end).trim();
    } else {
      name = args.trim();
      concept = '';
    }
    if (name.isEmpty) {
      _onSystemMessage('⚠ Usage: /create <name>: <concept>');
      return;
    }

    _onSystemMessage('⏳ Creating scene guest "$name"…');

    final result = await _mintGuest(name, concept);
    if (!result.ok) {
      _onSystemMessage('⚠ Failed to create "$name": ${result.error}');
      return;
    }

    // Have the new guest enter the scene via the existing generation engine.
    await _enterGuest(result.card!);
  }

  // ── Scene Guest: /exit [name] ───────────────────────────────────────────
  // Removes the named guest (or the only/last guest when omitted) from the
  // scene. The host narrates the departure on its next turn ([exitGuest] arms
  // the one-shot directive + removes the guest; we then trigger a primary
  // generation). The character stays in the library (still "known").
  Future<void> _handleExit(String args) async {
    final guests = _getSceneGuestCards();
    if (guests.isEmpty) {
      _onSystemMessage('⚠ There are no scene guests to exit.');
      return;
    }

    final wanted = args.trim().toLowerCase();
    CharacterCard? target;
    if (wanted.isEmpty) {
      target = guests.last; // the only/most-recent guest
    } else {
      for (final g in guests) {
        if (g.name.toLowerCase() == wanted) {
          target = g;
          break;
        }
      }
      if (target == null) {
        for (final g in guests) {
          if (g.name.toLowerCase().contains(wanted)) {
            target = g;
            break;
          }
        }
      }
    }

    if (target == null) {
      _onSystemMessage('⚠ No scene guest named "$args" is present.');
      return;
    }

    await _exitGuest(target);
    _setPendingGuestDeparture(target.name);

    // Narrate the departure through the primary character's next turn.
    await _generatePrimaryTurn();
  }
}
