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

/// One entry in the slash-command reference, used by the input "type /" helper
/// panel (and any cheat-sheet). [example] is what tapping the row inserts.
class SlashCommandInfo {
  const SlashCommandInfo(this.command, this.example, this.description);

  /// The bare command token (no slash), e.g. `create`.
  final String command;

  /// A usage example shown to the user, e.g. `/create <name>: <concept>`.
  final String example;

  /// One-line description of what it does.
  final String description;
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
    required Future<void> Function(String name, String concept) createGuest,
    required Future<void> Function(CharacterCard guest) exitGuest,
    required List<CharacterCard> Function() getJoinableCharacters,
    required Future<void> Function(CharacterCard guest) joinGuest,
    required void Function(String initialFilter) requestGuestPicker,
    required Future<bool> Function() runCastScan,
    required Future<void> Function(CharacterCard guest) speakGuest,
  }) : _setExpression = setExpression,
       _activeCharacterIsSet = activeCharacterIsSet,
       _getSceneGuestCards = getSceneGuestCards,
       _setPendingGuestDeparture = setPendingGuestDeparture,
       _onSystemMessage = onSystemMessage,
       _generatePrimaryTurn = generatePrimaryTurn,
       _createGuest = createGuest,
       _exitGuest = exitGuest,
       _getJoinableCharacters = getJoinableCharacters,
       _joinGuest = joinGuest,
       _requestGuestPicker = requestGuestPicker,
       _runCastScan = runCastScan,
       _speakGuest = speakGuest;

  final void Function(String? label) _setExpression;
  final bool Function() _activeCharacterIsSet;
  final List<CharacterCard> Function() _getSceneGuestCards;
  final void Function(String? guestName) _setPendingGuestDeparture;
  final void Function(String message) _onSystemMessage;
  final Future<void> Function() _generatePrimaryTurn;
  final Future<void> Function(String name, String concept) _createGuest;
  final Future<void> Function(CharacterCard guest) _exitGuest;
  final List<CharacterCard> Function() _getJoinableCharacters;
  final Future<void> Function(CharacterCard guest) _joinGuest;
  final void Function(String initialFilter) _requestGuestPicker;
  final Future<bool> Function() _runCastScan;
  final Future<void> Function(CharacterCard guest) _speakGuest;

  /// The user-facing slash-command reference (single source of truth for the
  /// "type /" helper panel). Order = display order. Aliases (/turn, /detect,
  /// /expression-clear) are intentionally omitted to keep the list scannable.
  static const List<SlashCommandInfo> commands = [
    SlashCommandInfo(
      'create',
      '/create <name>: <concept>',
      'Create a new guest NPC and bring them into the scene',
    ),
    SlashCommandInfo(
      'join',
      '/join [name]',
      'Bring one of your existing characters in as a guest',
    ),
    SlashCommandInfo(
      'speak',
      '/speak [name]',
      'Make a guest who is present take a turn right now',
    ),
    SlashCommandInfo(
      'exit',
      '/exit [name]',
      'Have a guest leave the scene (narrated by your character)',
    ),
    SlashCommandInfo(
      'scan',
      '/scan',
      'Scan the scene for a new recurring character to add',
    ),
    SlashCommandInfo(
      'expression',
      '/expression [emotion]',
      "Set the character's expression (omit to clear it)",
    ),
  ];

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

      case 'join':
        await _handleJoin(args);
        return true;

      case 'speak':
      case 'turn':
        await _handleSpeak(args);
        return true;

      case 'scan':
      case 'detect':
        // Manual cast-detection trigger: force an immediate scan of the host's
        // recent narration for a recurring side character, bypassing the
        // automatic per-turn cadence (works on an already-loaded chat too).
        if (!_activeCharacterIsSet()) {
          _onSystemMessage('⚠ NPC detection only runs inside a 1:1 chat.');
          return true;
        }
        _onSystemMessage('🔍 Scanning the scene for a recurring character…');
        if (!await _runCastScan()) {
          _onSystemMessage('No new recurring character was found to add.');
        }
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
  // or `/create <name>` (empty concept). Parses the name/concept and delegates
  // to the injected [createGuest], which generates + persists the lite NPC,
  // adds it to the scene, drives the live status line, and has it enter — all
  // busy-guarded, with no saved 'System' chat litter.
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

    // Generation, the live status line, and the entrance are all handled by the
    // injected orchestrator (busy-guarded, no saved 'System' litter).
    await _createGuest(name, concept);
  }

  // ── Scene Guest: /join [name] ───────────────────────────────────────────
  // Brings an EXISTING library character into the 1:1 scene as a Scene Guest —
  // no new card is minted; it reuses the SAME parity-safe enter path as
  // `/create` (the joined character generates a contextual entrance from the
  // chat history + its own card, and carries no Realism/Needs while a guest).
  //   • `/join`            → open the character picker (browse the full list).
  //   • `/join <name>`     → join an unambiguous match outright; otherwise open
  //                          the picker pre-filtered to the typed text.
  // The candidate list (injected) already excludes the host and anyone already
  // present, so this leaf only resolves the user's intent against it.
  Future<void> _handleJoin(String args) async {
    if (!_activeCharacterIsSet()) {
      _onSystemMessage('⚠ Scene Guests can only be added inside a 1:1 chat.');
      return;
    }

    final candidates = _getJoinableCharacters();
    if (candidates.isEmpty) {
      _onSystemMessage(
        '⚠ No other characters are available to join this chat.',
      );
      return;
    }

    final wanted = args.trim();
    if (wanted.isEmpty) {
      _requestGuestPicker(''); // browse the full list
      return;
    }

    // Exact (case-insensitive) name match wins outright.
    final lower = wanted.toLowerCase();
    for (final c in candidates) {
      if (c.name.toLowerCase() == lower) {
        await _joinGuest(c);
        return;
      }
    }

    // Otherwise a single substring match joins directly; 0 or 2+ matches fall
    // back to the picker pre-filtered to what was typed.
    final partial = candidates
        .where((c) => c.name.toLowerCase().contains(lower))
        .toList();
    if (partial.length == 1) {
      await _joinGuest(partial.first);
      return;
    }
    _requestGuestPicker(wanted);
  }

  // ── Scene Guest: /speak [name] (alias /turn) ────────────────────────────
  // Force a PRESENT guest to take a turn right now, bypassing the auto chime-in
  // heuristic + LLM gate. Bare `/speak` targets the only/most-recent guest. An
  // unrecognized name surfaces the list of valid guests instead of doing
  // nothing.
  Future<void> _handleSpeak(String args) async {
    if (!_activeCharacterIsSet()) {
      _onSystemMessage('⚠ Scene Guests only exist inside a 1:1 chat.');
      return;
    }
    final guests = _getSceneGuestCards();
    if (guests.isEmpty) {
      _onSystemMessage(
        '⚠ No scene guests are present. Add one with /create or /join first.',
      );
      return;
    }

    final names = guests.map((g) => g.name).join(', ');
    final wanted = args.trim();
    CharacterCard? target;
    if (wanted.isEmpty) {
      target = guests.last; // the only / most-recent guest
    } else {
      final lower = wanted.toLowerCase();
      for (final g in guests) {
        if (g.name.toLowerCase() == lower) {
          target = g;
          break;
        }
      }
      if (target == null) {
        final partial = guests
            .where((g) => g.name.toLowerCase().contains(lower))
            .toList();
        if (partial.length == 1) {
          target = partial.first;
        } else if (partial.length > 1) {
          _onSystemMessage(
            '⚠ "$args" matches more than one guest. Use the full name. '
            'Present guests: $names.',
          );
          return;
        }
      }
    }

    if (target == null) {
      _onSystemMessage(
        '⚠ "$args" is not a current scene guest. '
        'Valid guests right now: $names.',
      );
      return;
    }

    await _speakGuest(target);
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
        // Substring fallback — but if more than one guest matches, removing
        // the first silently could exit the wrong one. Ask the user to be
        // specific instead.
        final partial = guests
            .where((g) => g.name.toLowerCase().contains(wanted))
            .toList();
        if (partial.length > 1) {
          final names = partial.map((g) => g.name).join(', ');
          _onSystemMessage('⚠ "$args" matches multiple guests ($names). '
              'Use the full name.');
          return;
        }
        if (partial.length == 1) target = partial.first;
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
