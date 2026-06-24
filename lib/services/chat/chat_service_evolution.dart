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

part of '../chat_service.dart';

/// Character-evolution accessors and manual edit/reset/load helpers (evolved
/// personality + scenario deltas, per-character in both 1:1 and group modes).
/// Extracted verbatim from `chat_service.dart` (zero behaviour change) to shrink
/// the god file. The backing `_groupEvolutionCounts` field and the
/// `EvolutionService` leaf stay in the main library; as `part of` it, this
/// extension reaches `_evolvedPersonalities`, `_evolvedScenarios`, `_db`,
/// `_tryParseJsonMap`, and the session columns exactly as before.
extension ChatServiceEvolution on ChatService {
  /// Public getter: raw evolved personality delta for the active character (null if none).
  /// This bypasses the enabled flag and [Character Growth] layering (returns the stored growth text only).
  /// In group mode, returns null — use getEvolvedPersonalityFor(card) instead.
  /// Injection paths use the _getEffectivePersonality thin (delegates to leaf for full base + layered block when enabled).
  /// Legacy/compat name retained for public surface (see god coord note in step 14 plan).
  String? get getEffectivePersonality {
    if (_activeCharacter == null) return null;
    final charId = _getCharacterIdFromCard(_activeCharacter!);
    final evolved = _evolvedPersonalities[charId];
    return (evolved != null && evolved.isNotEmpty) ? evolved : null;
  }

  /// Public getter: raw evolved scenario delta for the active character (null if none).
  /// This bypasses the enabled flag and [Current Situation] layering.
  /// In group mode, returns null — use getEvolvedScenarioFor(card) instead.
  /// See note on getEffectivePersonality (raw vs layered via thins/leaf).
  String? get getEffectiveScenario {
    if (_activeCharacter == null) return null;
    final charId = _getCharacterIdFromCard(_activeCharacter!);
    final evolved = _evolvedScenarios[charId];
    return (evolved != null && evolved.isNotEmpty) ? evolved : null;
  }

  /// Get evolved personality for a specific character (works in both 1:1 and group mode).
  String? getEvolvedPersonalityFor(CharacterCard card) {
    final charId = _getCharacterIdFromCard(card);
    final evolved = _evolvedPersonalities[charId];
    return (evolved != null && evolved.isNotEmpty) ? evolved : null;
  }

  /// Get evolved scenario for a specific character (works in both 1:1 and group mode).
  String? getEvolvedScenarioFor(CharacterCard card) {
    final charId = _getCharacterIdFromCard(card);
    final evolved = _evolvedScenarios[charId];
    return (evolved != null && evolved.isNotEmpty) ? evolved : null;
  }

  /// Get evolution count for a specific character.
  int getEvolutionCountFor(CharacterCard card) {
    final charId = _getCharacterIdFromCard(card);
    return _groupEvolutionCounts[charId] ?? 0;
  }

  /// Load evolved fields for all characters in the active group from the
  /// session's JSON map columns (group_evolved_personalities/scenarios).
  Future<void> _loadGroupEvolvedFields() async {
    if (_activeGroup == null || _currentSessionId == null) return;
    try {
      final session = await _db.getSessionById(_currentSessionId!);
      if (session == null) return;
      final personalities = _tryParseJsonMap(session.groupEvolvedPersonalities);
      final scenarios = _tryParseJsonMap(session.groupEvolvedScenarios);
      for (final ch in _groupCharacters) {
        final charId = _getCharacterIdFromCard(ch);
        _evolvedPersonalities[charId] = personalities[charId] ?? '';
        _evolvedScenarios[charId] = scenarios[charId] ?? '';
        _groupEvolutionCounts[charId] = 0;
      }
    } catch (e) {
      debugPrint('[Evolution] Failed to load group evolved fields: $e');
    }
  }

  /// Whether evolution extraction is currently running.
  bool get isEvolvingCharacter => _isEvolvingCharacter;

  /// Current status message during evolution.
  String get evolutionStatus => _evolutionStatus;

  /// Error message from the last evolution attempt (empty if no error).
  String get evolutionError => _evolutionError;

  /// Reset evolved fields back to original for a character.
  /// In 1:1 mode, targets the active character. In group mode, pass an explicit target.
  Future<void> resetCharacterEvolution({CharacterCard? target}) async {
    final card = target ?? _activeCharacter;
    if (_currentSessionId == null) return;
    final charId = card != null ? _getCharacterIdFromCard(card) : null;

    if (_activeGroup != null && charId != null) {
      // Group mode: remove this char's key from both JSON map columns
      final session = await _db.getSessionById(_currentSessionId!);
      if (session != null) {
        final personalities = _tryParseJsonMap(
          session.groupEvolvedPersonalities,
        );
        final scenarios = _tryParseJsonMap(session.groupEvolvedScenarios);
        personalities.remove(charId);
        scenarios.remove(charId);
        await _db.patchSession(
          SessionsCompanion(
            id: drift.Value(_currentSessionId!),
            groupEvolvedPersonalities: drift.Value(jsonEncode(personalities)),
            groupEvolvedScenarios: drift.Value(jsonEncode(scenarios)),
          ),
        );
      }
    } else {
      // 1:1 mode: clear plain columns
      await _db.patchSession(
        SessionsCompanion(
          id: drift.Value(_currentSessionId!),
          evolvedPersonality: const drift.Value(''),
          evolvedScenario: const drift.Value(''),
          evolutionCount: const drift.Value(0),
        ),
      );
    }

    if (charId != null) {
      _evolvedPersonalities.remove(charId);
      _evolvedScenarios.remove(charId);
      _groupEvolutionCounts.remove(charId);
    }
    if (_activeCharacter != null &&
        (charId == null ||
            _getCharacterIdFromCard(_activeCharacter!) == charId)) {
      _characterEvolutionCount = 0;
    }
    notifyListeners();
    debugPrint(
      '[Evolution] Reset to original for ${card?.name ?? "active character"}',
    );
  }

  /// Update the evolved personality text manually (user edits).
  /// In group mode, pass an explicit target character.
  Future<void> updateEvolvedPersonality(
    String text, {
    CharacterCard? target,
  }) async {
    if (_currentSessionId == null) return;
    final card = target ?? _activeCharacter;
    final charId = card != null ? _getCharacterIdFromCard(card) : null;

    if (_activeGroup != null && charId != null) {
      final session = await _db.getSessionById(_currentSessionId!);
      if (session != null) {
        final personalities = _tryParseJsonMap(
          session.groupEvolvedPersonalities,
        );
        personalities[charId] = text;
        await _db.patchSession(
          SessionsCompanion(
            id: drift.Value(_currentSessionId!),
            groupEvolvedPersonalities: drift.Value(jsonEncode(personalities)),
          ),
        );
      }
    } else {
      await _db.patchSession(
        SessionsCompanion(
          id: drift.Value(_currentSessionId!),
          evolvedPersonality: drift.Value(text),
        ),
      );
    }
    if (charId != null) _evolvedPersonalities[charId] = text;
    notifyListeners();
  }

  /// Update the evolved scenario text manually (user edits).
  /// In group mode, pass an explicit target character.
  Future<void> updateEvolvedScenario(
    String text, {
    CharacterCard? target,
  }) async {
    if (_currentSessionId == null) return;
    final card = target ?? _activeCharacter;
    final charId = card != null ? _getCharacterIdFromCard(card) : null;

    if (_activeGroup != null && charId != null) {
      final session = await _db.getSessionById(_currentSessionId!);
      if (session != null) {
        final scenarios = _tryParseJsonMap(session.groupEvolvedScenarios);
        scenarios[charId] = text;
        await _db.patchSession(
          SessionsCompanion(
            id: drift.Value(_currentSessionId!),
            groupEvolvedScenarios: drift.Value(jsonEncode(scenarios)),
          ),
        );
      }
    } else {
      await _db.patchSession(
        SessionsCompanion(
          id: drift.Value(_currentSessionId!),
          evolvedScenario: drift.Value(text),
        ),
      );
    }
    if (charId != null) _evolvedScenarios[charId] = text;
    notifyListeners();
  }
}
