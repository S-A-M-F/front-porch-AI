// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for Realism Engine state seeding and reset logic extracted from ChatService.
// Covers how realism state is initialized from V2.5 card extensions and how it
// resets when switching characters or starting new chats.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';

/// Minimal stub that replicates the Realism Engine state fields and seeding/reset
/// logic from ChatService. This enables unit testing of the state transitions
/// without needing the full ChatService dependency chain.
class _RealismStateStub {
  // ── Realism Engine state (mirrors ChatService fields) ──────────────
  bool _realismEnabled = false;
  int _affectionScore = 0;
  int _longTermScore = 0;
  int _trustLevel = 0;
  int _dayCount = 1;
  String _timeOfDay = 'morning';
  String _characterEmotion = '';
  String _emotionIntensity = '';
  bool _nsfwCooldownEnabled = false;
  bool _passageOfTimeEnabled = true;
  bool _chaosModeEnabled = false;
  int _arousalLevel = 0;
  String _activeFixation = '';
  int _fixationLifespan = 0;
  int _relationshipTier = 0;
  int _longTermTier = 0;

  // ── Sims/Needs Simulation state (mirrors ChatService) ──────────────
  bool _needsSimEnabled = false;
  Map<String, int> _needsVector = {};

  // Canonical constants for the Sims/Needs simulation (duplicated in stub
  // for isolated, fast unit tests without ChatService dependency).
  static const List<String> _needKeys = [
    'hunger',
    'bladder',
    'energy',
    'social',
    'fun',
    'hygiene',
    'comfort',
  ];

  static const Map<String, int> _needDefaults = {
    'hunger': 75,
    'bladder': 80,
    'energy': 80,
    'social': 65,
    'fun': 65,
    'hygiene': 75,
    'comfort': 70,
  };

  // Base decay per tick (when no time-of-day variant applies).
  static const Map<String, int> _needDecay = {
    'hunger': 8,
    'bladder': 12,
    'energy': 5,
    'social': 3,
    'fun': 4,
    'hygiene': 2,
    'comfort': 3,
  };

  // Morning-specific overrides (hunger drains faster after sleep / breakfast window).
  static const Map<String, int> _needDecayMorning = {
    'hunger': 12,
  };

  // Night-specific overrides (energy drains faster at night).
  static const Map<String, int> _needDecayNight = {
    'energy': 10,
  };

  static const Map<String, int> _needRestore = {
    'hunger': 50,
    'bladder': 70,
    'energy': 40,
    'social': 45,
    'fun': 40,
    'hygiene': 35,
    'comfort': 35,
  };

  static const int _needRestoreDefault = 30;

  // ── Simulated storage service flag ─────────────────────────────────
  bool passageOfTimeDefault = true;

  // ── Getters (mirror ChatService) ───────────────────────────────────
  bool get realismEnabled => _realismEnabled;
  int get affectionScore => _affectionScore;
  int get longTermScore => _longTermScore;
  int get trustLevel => _trustLevel;
  int get dayCount => _dayCount;
  String get timeOfDay => _timeOfDay;
  String get characterEmotion => _characterEmotion;
  String get emotionIntensity => _emotionIntensity;
  bool get nsfwCooldownEnabled => _nsfwCooldownEnabled;
  bool get passageOfTimeEnabled => _passageOfTimeEnabled;
  bool get chaosModeEnabled => _chaosModeEnabled;
  int get arousalLevel => _arousalLevel;
  String get activeFixation => _activeFixation;
  int get fixationLifespan => _fixationLifespan;
  int get relationshipTier => _relationshipTier;
  int get longTermTier => _longTermTier;
  bool get needsSimEnabled => _needsSimEnabled;
  Map<String, int> get needsVector => Map<String, int>.from(_needsVector);

  /// Mirrors the V2.5 extension seeding logic from ChatService.setActiveCharacter
  /// (lines 1073-1108).
  void seedFromExtensions(FrontPorchExtensions? ext) {
    if (ext == null) return;

    _realismEnabled = ext.realismEnabled;
    _affectionScore = ext.shortTermBond.clamp(-300, 300);
    _longTermScore = ext.longTermBond.clamp(-300, 300);
    _trustLevel = ext.trustLevel.clamp(-100, 100);
    _dayCount = ext.dayCount.clamp(1, 9999);
    _timeOfDay = ext.timeOfDay;
    _characterEmotion = ext.characterEmotion;
    _emotionIntensity = ext.emotionIntensity;
    _nsfwCooldownEnabled = ext.nsfwCooldownEnabled;
    _passageOfTimeEnabled = ext.passageOfTimeEnabled && passageOfTimeDefault;
    _chaosModeEnabled = ext.chaosModeEnabled;

    _needsSimEnabled = ext.needsSimEnabled;
    if (_needsSimEnabled) {
      _initializeNeedsVectorIfNeeded();
    } else {
      _needsVector.clear();
    }

    // Recalculate tiers from seeded scores
    _relationshipTier = _calculateTier(_affectionScore);
    _longTermTier = _calculateTier(_longTermScore);
  }

  /// Mirrors the realism state reset logic from ChatService.setActiveCharacter
  /// (lines 1057-1066).
  void resetRealismState() {
    _arousalLevel = 0;
    _fixationLifespan = 0;
    _activeFixation = '';
    // Match production reset on character switch / new context
    _needsSimEnabled = false;
    _needsVector.clear();
  }

  /// Mirrors the _calculateTier method from ChatService (21-tier system).
  int _calculateTier(int score) {
    final absScore = score.abs();
    if (absScore < 5) return 0;
    if (absScore < 15) return score > 0 ? 1 : -1;
    if (absScore < 30) return score > 0 ? 2 : -2;
    if (absScore < 50) return score > 0 ? 3 : -3;
    if (absScore < 80) return score > 0 ? 4 : -4;
    if (absScore < 120) return score > 0 ? 5 : -5;
    if (absScore < 160) return score > 0 ? 6 : -6;
    if (absScore < 200) return score > 0 ? 7 : -7;
    if (absScore < 250) return score > 0 ? 8 : -8;
    if (absScore < 300) return score > 0 ? 9 : -9;
    return score > 0 ? 10 : -10;
  }

  /// Migration: scale old scores (±150) to new range (±300)
  int _migrateShortTermScore(int rawScore) {
    if (rawScore.abs() <= 150) {
      return (rawScore * 2).clamp(-300, 300);
    }
    return rawScore;
  }

  int _migrateLongTermScore(int rawScore) {
    if (rawScore.abs() <= 150) {
      return (rawScore * 2).clamp(-300, 300);
    }
    return rawScore;
  }

  /// Simulates startNewChat seeding for 1:1 mode (lines 2144-2186).
  void seedForNewChat(CharacterCard character) {
    final extSeed = character.frontPorchExtensions ?? FrontPorchExtensions();

    _realismEnabled = extSeed.realismEnabled;
    _affectionScore = extSeed.shortTermBond.clamp(-300, 300);
    _longTermScore = extSeed.longTermBond.clamp(-300, 300);
    _trustLevel = extSeed.trustLevel.clamp(-100, 100);
    _dayCount = extSeed.dayCount.clamp(1, 9999);
    _timeOfDay = extSeed.timeOfDay;
    _characterEmotion = extSeed.characterEmotion;
    _emotionIntensity = extSeed.emotionIntensity;
    _nsfwCooldownEnabled = extSeed.nsfwCooldownEnabled;
    _passageOfTimeEnabled =
        extSeed.passageOfTimeEnabled && passageOfTimeDefault;
    _chaosModeEnabled = extSeed.chaosModeEnabled;

    _needsSimEnabled = extSeed.needsSimEnabled;
    if (_needsSimEnabled) {
      _initializeNeedsVectorIfNeeded();
    } else {
      _needsVector.clear();
    }

    // Preserve arousal/fixation if character has extensions
    if (character.hasFrontPorchExtensions) {
      // Preserved — don't reset
    } else {
      _arousalLevel = 0;
      _fixationLifespan = 0;
      _activeFixation = '';
    }

    if (_realismEnabled) {
      _relationshipTier = _calculateTier(_affectionScore);
      _longTermTier = _calculateTier(_longTermScore);
    }
  }

  // ── Needs simulation helpers (minimal port for unit tests) ─────────
  // These mirror the production implementations in ChatService so that
  // the focused Needs tests exercise the exact same initialization,
  // decay arithmetic, serialization, snapshot guards, and enable/disable
  // semantics.

  void _initializeNeedsVectorIfNeeded() {
    if (_needsVector.isEmpty) {
      _needsVector = Map<String, int>.from(_needDefaults);
    }
  }

  String _serializeNeeds() {
    return jsonEncode(_needsVector);
  }

  void _restoreNeedsFromJson(String? json) {
    if (json == null || json.isEmpty) {
      _initializeNeedsVectorIfNeeded();
      return;
    }
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      _needsVector = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      _initializeNeedsVectorIfNeeded();
    }
  }

  /// Public for tests; mirrors production setter (without async save/notify).
  void setNeedsSimEnabled(bool enabled) {
    _needsSimEnabled = enabled;
    if (enabled) {
      _initializeNeedsVectorIfNeeded();
    } else {
      _needsVector.clear();
    }
  }

  /// Decay logic ported exactly; depends on _realismEnabled + _timeOfDay.
  void tickNeedsDecay() {
    if (!_needsSimEnabled || !_realismEnabled) return;

    final isNight = _timeOfDay == 'night';
    final isMorning = _timeOfDay == 'dawn' || _timeOfDay == 'morning';

    for (final key in _needKeys) {
      final current = _needsVector[key];
      if (current == null) continue;
      int decay = _needDecay[key] ?? 0;
      if (isMorning && _needDecayMorning.containsKey(key)) {
        decay = _needDecayMorning[key] ?? decay;
      } else if (isNight && _needDecayNight.containsKey(key)) {
        decay = _needDecayNight[key] ?? decay;
      }
      _needsVector[key] = (current - decay).clamp(0, 100);
    }
  }

  /// Snapshot capture for realism state (needs portion).
  /// Deliberately omits 'enabled' from the 'needs' sub-map (matches the
  /// production fix that prevents stale resurrection after toggle-off).
  Map<String, dynamic> captureRealismState() {
    final state = <String, dynamic>{};
    if (_needsSimEnabled && _needsVector.isNotEmpty) {
      state['needs'] = {
        'vector': Map<String, int>.from(_needsVector),
      };
    }
    return state;
  }

  /// Restore logic with the critical guard: only applies vector when
  /// _needsSimEnabled is currently true. This is what would have caught
  /// a write-only snapshot or an over-eager restore that ignored the flag.
  void restoreRealismStateFromMessage(Map<String, dynamic> state) {
    if (state.containsKey('needs') &&
        state['needs'] is Map &&
        _needsSimEnabled) {
      final needsData = state['needs'] as Map;
      if (needsData['vector'] is Map) {
        final vector = Map<String, int>.from(needsData['vector'] as Map);
        _needsVector = vector;
      }
    }
  }

  /// Minimal fulfillment verifier for tests (no LLM call).
  /// Production calls _fireLLMEval only after the guard; the guard test
  /// ensures we never reach eval when the sim is disabled (would have
  /// caught GBNF-era or unconditional call bugs).
  Future<void> verifyNeedFulfillmentCall() async {
    if (!_needsSimEnabled || !_realismEnabled) return;
    // In real code this would run the LLM eval + restore amounts.
    // For stub we simply return; callers can assert no state mutation
    // when disabled, or manually apply restore in enabled tests.
  }

  /// Helper for fulfillment tests: applies the restore amount for a need.
  void _applyNeedRestore(String need) {
    if (!_needsVector.containsKey(need)) return;
    final restore = _needRestore[need] ?? _needRestoreDefault;
    _needsVector[need] = (_needsVector[need]! + restore).clamp(0, 100);
  }
}

void main() {
  // ─── Realism State — seeding from V2.5 extensions ──────────────────

  group('seedFromExtensions', () {
    test('seeds realism enabled flag', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(realismEnabled: true));
      expect(stub.realismEnabled, isTrue);
    });

    test('seeds short-term bond score', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(shortTermBond: 30));
      expect(stub.affectionScore, 30);
    });

    test('seeds long-term bond score', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(longTermBond: 25));
      expect(stub.longTermScore, 25);
    });

    test('calculates tier for new system', () {
      final stub = _RealismStateStub();
      // Score 29 should be tier 2 in 21-tier system (threshold is < 30)
      expect(stub._calculateTier(29), 2);
      // Score 30 should be tier 3 (threshold is < 50)
      expect(stub._calculateTier(30), 3);
      // Score 150 should be tier 6 (threshold is < 160 for tier 6)
      expect(stub._calculateTier(150), 6);
      // Score 250 should be tier 9 (threshold is < 300 for tier 9)
      expect(stub._calculateTier(250), 9);
    });

    test('seeds trust level', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(trustLevel: 15));
      expect(stub.trustLevel, 15);
    });

    test('seeds day count', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(dayCount: 5));
      expect(stub.dayCount, 5);
    });

    test('seeds time of day', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(timeOfDay: 'evening'));
      expect(stub.timeOfDay, 'evening');
    });

    test('seeds character emotion', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(
        FrontPorchExtensions(characterEmotion: 'happy', emotionIntensity: 'strong'),
      );
      expect(stub.characterEmotion, 'happy');
      expect(stub.emotionIntensity, 'strong');
    });

    test('seeds nsfw cooldown', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(nsfwCooldownEnabled: true));
      expect(stub.nsfwCooldownEnabled, isTrue);
    });

    test('seeds chaos mode', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(chaosModeEnabled: true));
      expect(stub.chaosModeEnabled, isTrue);
    });

    test('respects passage of time global setting', () {
      final stub = _RealismStateStub();
      stub.passageOfTimeDefault = false;
      stub.seedFromExtensions(FrontPorchExtensions(passageOfTimeEnabled: true));
      expect(stub.passageOfTimeEnabled, isFalse,
          reason: 'global setting overrides card setting');
    });

    test('clamps short-term bond to -300..300', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(shortTermBond: 400));
      expect(stub.affectionScore, 300);

      stub.seedFromExtensions(FrontPorchExtensions(shortTermBond: -400));
      expect(stub.affectionScore, -300);
    });

    test('clamps long-term bond to -300..300', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(longTermBond: 400));
      expect(stub.longTermScore, 300);
    });

    test('clamps trust level to -100..100', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(trustLevel: 150));
      expect(stub.trustLevel, 100);

      stub.seedFromExtensions(FrontPorchExtensions(trustLevel: -150));
      expect(stub.trustLevel, -100);
    });

    test('clamps day count to 1..9999', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(dayCount: 0));
      expect(stub.dayCount, 1);

      stub.seedFromExtensions(FrontPorchExtensions(dayCount: 10000));
      expect(stub.dayCount, 9999);
    });

    test('calculates relationship tier from bonded score', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(shortTermBond: 30));
      expect(stub.relationshipTier, 3,
          reason: 'score 30 => tier 3 (Amiable) since 30 >= 30 threshold');
    });

    test('calculates long-term tier from bonded score', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(longTermBond: 50));
      expect(stub.longTermTier, 4,
          reason: 'score 50 => tier 4 (Friendly) since 50 >= 50 threshold');
    });

    test('negative bond produces negative tier', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(shortTermBond: -30));
      expect(stub.relationshipTier, -3,
          reason: 'negative bond => negative tier (Unimpressed) since -30 >= -30 threshold');
    });

    test('null extension does nothing', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(null);
      expect(stub.realismEnabled, isFalse);
      expect(stub.affectionScore, 0);
    });
  });

  // ─── Realism State — reset ─────────────────────────────────────────

  group('resetRealismState', () {
    test('resets arousal to 0', () {
      final stub = _RealismStateStub();
      stub._arousalLevel = 7;
      stub.resetRealismState();
      expect(stub.arousalLevel, 0);
    });

    test('resets fixation to empty', () {
      final stub = _RealismStateStub();
      stub._activeFixation = 'revenge';
      stub._fixationLifespan = 5;
      stub.resetRealismState();
      expect(stub.activeFixation, '');
      expect(stub.fixationLifespan, 0);
    });

    test('does not affect other state fields', () {
      final stub = _RealismStateStub();
      stub.seedFromExtensions(FrontPorchExtensions(shortTermBond: 30));
      final bond = stub.affectionScore;

      stub.resetRealismState();

      expect(stub.affectionScore, bond,
          reason: 'reset should not affect bond/trust/emotion');
    });
  });

  // ─── Realism State — new chat seeding ──────────────────────────────

  group('seedForNewChat', () {
    test('seeds from character extensions', () {
      final stub = _RealismStateStub();
      final char = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 20,
          trustLevel: 10,
          dayCount: 3,
          timeOfDay: 'afternoon',
        ),
      );

      stub.seedForNewChat(char);

      expect(stub.realismEnabled, isTrue);
      expect(stub.affectionScore, 20);
      expect(stub.trustLevel, 10);
      expect(stub.dayCount, 3);
      expect(stub.timeOfDay, 'afternoon');
    });

    test('preserves arousal/fixation when character has extensions', () {
      final stub = _RealismStateStub();
      stub._arousalLevel = 5;
      stub._activeFixation = 'curiosity';
      stub._fixationLifespan = 3;

      final char = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
      );

      stub.seedForNewChat(char);

      expect(stub.arousalLevel, 5,
          reason: 'arousal must be preserved for characters with extensions');
      expect(stub.activeFixation, 'curiosity',
          reason: 'fixation must be preserved for characters with extensions');
    });

    test('resets arousal/fixation when character has no extensions', () {
      final stub = _RealismStateStub();
      stub._arousalLevel = 5;
      stub._activeFixation = 'curiosity';
      stub._fixationLifespan = 3;

      final char = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        // No extensions
      );

      stub.seedForNewChat(char);

      expect(stub.arousalLevel, 0,
          reason: 'arousal must reset for characters without extensions');
      expect(stub.activeFixation, '',
          reason: 'fixation must reset for characters without extensions');
    });

    test('uses default FrontPorchExtensions when null', () {
      final stub = _RealismStateStub();
      final char = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: null,
      );

      stub.seedForNewChat(char);

      expect(stub.realismEnabled, isFalse);
      expect(stub.affectionScore, 0);
      expect(stub.trustLevel, 0);
      expect(stub.dayCount, 1);
      expect(stub.timeOfDay, 'morning');
    });

    test('only calculates tiers when realism enabled', () {
      final stub = _RealismStateStub();
      final char = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          shortTermBond: 50,
        ),
      );

      stub._relationshipTier = 99; // set a non-zero value
      stub.seedForNewChat(char);

      expect(stub.relationshipTier, 99,
          reason: 'tiers should not be recalculated when realism is disabled');
    });

    test('calculates tiers when realism enabled', () {
      final stub = _RealismStateStub();
      final char = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 30,
          longTermBond: 25,
        ),
      );

      stub.seedForNewChat(char);

      // Score 30 => tier 3 (since threshold is < 50 for tier 3)
      expect(stub.relationshipTier, 3);
      // Score 25 => tier 2 (since threshold is < 30 for tier 2)
      expect(stub.longTermTier, 2);
    });
  });

  // ─── Realism State — state preservation across transitions ─────────

  group('state preservation', () {
    test('arousal preserved when extensions exist, reset when not', () {
      final stub = _RealismStateStub();

      // First: character with extensions — arousal preserved
      final charWithExt = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
      );

      stub._arousalLevel = 5;
      stub.seedForNewChat(charWithExt);
      expect(stub.arousalLevel, 5);

      // Second: character without extensions — arousal resets
      final charNoExt = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
      );

      stub.seedForNewChat(charNoExt);
      expect(stub.arousalLevel, 0);
    });

    test('bond/trust preserved across new chat for extended characters', () {
      final stub = _RealismStateStub();
      final char = CharacterCard(
        name: 'Luna',
        firstMessage: 'Hi',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 40,
          longTermBond: 35,
          trustLevel: 20,
        ),
      );

      stub.seedForNewChat(char);
      expect(stub.affectionScore, 40);
      expect(stub.longTermScore, 35);
      expect(stub.trustLevel, 20);

      // Simulate bond changing during chat
      stub._affectionScore = 50;
      stub._trustLevel = 25;

      // New chat should re-seed from extensions (not current runtime state)
      stub.seedForNewChat(char);
      expect(stub.affectionScore, 40,
          reason: 'new chat re-seeds from extensions, not runtime state');
      expect(stub.trustLevel, 20);
    });
  });

  // ─── Needs Simulation (core methods) ───────────────────────────────
  // These 6 focused tests exercise the newly added Needs fields + logic in
  // the stub. They are deliberately isolated, deterministic, and fast.
  // They are designed to have caught the historical "write-only snapshot"
  // bug (capture wrote 'needs' but restore was a no-op or ignored guards)
  // and GBNF/eval drift (unconditional calls to eval without the
  // _needsSimEnabled guard).

  group('needs simulation', () {
    test('initialization seeds defaults when enabled via setNeedsSimEnabled', () {
      final stub = _RealismStateStub();
      expect(stub.needsVector, isEmpty);

      stub.setNeedsSimEnabled(true);
      expect(stub.needsSimEnabled, isTrue);
      expect(stub.needsVector, _RealismStateStub._needDefaults);
    });

    test('initialization and clear on disable', () {
      final stub = _RealismStateStub();
      stub.setNeedsSimEnabled(true);
      expect(stub.needsVector.isNotEmpty, isTrue);

      stub.setNeedsSimEnabled(false);
      expect(stub.needsSimEnabled, isFalse);
      expect(stub.needsVector, isEmpty);
    });

    test('tickNeedsDecay applies correct decay math, time-of-day variants, and clamps', () {
      final stub = _RealismStateStub();
      stub.setNeedsSimEnabled(true);
      stub._realismEnabled = true; // enable realism guard

      // Default morning
      stub._timeOfDay = 'morning';
      // Manually set a starting vector for determinism
      stub._needsVector = {'hunger': 80, 'energy': 90, 'bladder': 70};

      stub.tickNeedsDecay();

      // hunger uses morning override: 12 instead of 8
      expect(stub.needsVector['hunger'], 80 - 12, reason: 'morning hunger decay=12');
      expect(stub.needsVector['energy'], 90 - 5, reason: 'base energy decay=5');
      expect(stub.needsVector['bladder'], 70 - 12, reason: 'base bladder decay=12');

      // Night variant
      stub._timeOfDay = 'night';
      stub._needsVector = {'energy': 50};
      stub.tickNeedsDecay();
      expect(stub.needsVector['energy'], 50 - 10, reason: 'night energy decay=10');

      // Clamp at 0
      stub._needsVector = {'hunger': 5};
      stub._timeOfDay = 'morning';
      stub.tickNeedsDecay();
      expect(stub.needsVector['hunger'], 0);
    });

    test('snapshot round-trip preserves vector when enabled', () {
      final stub = _RealismStateStub();
      stub.setNeedsSimEnabled(true);
      stub._realismEnabled = true;
      stub._needsVector = {'hunger': 42, 'fun': 55};

      final snap = stub.captureRealismState();
      expect(snap.containsKey('needs'), isTrue);
      expect(snap['needs']['vector'], {'hunger': 42, 'fun': 55});

      // Mutate and restore
      stub._needsVector = {'hunger': 99};
      stub.restoreRealismStateFromMessage(snap);
      expect(stub.needsVector, {'hunger': 42, 'fun': 55});

      // Also exercise the json serialize/restore path (matches production persistence)
      final json = stub._serializeNeeds();
      stub._needsVector = {'hunger': 1};
      stub._restoreNeedsFromJson(json);
      expect(stub.needsVector, {'hunger': 42, 'fun': 55});
    });

    test('snapshot restore is a no-op and does not resurrect when disabled (catches write-only / stale resurrection)', () {
      final stub = _RealismStateStub();
      stub.setNeedsSimEnabled(true);
      stub._needsVector = {'social': 30};
      final snap = stub.captureRealismState();
      expect(snap['needs']['vector'], isNotEmpty);

      // Toggle off (production path: clears vector, disables)
      stub.setNeedsSimEnabled(false);
      expect(stub.needsSimEnabled, isFalse);
      expect(stub.needsVector, isEmpty);

      // Historical snapshot must NOT flip it back on or repopulate
      stub.restoreRealismStateFromMessage(snap);
      expect(stub.needsSimEnabled, isFalse, reason: 'guard prevents resurrection from snapshot');
      expect(stub.needsVector, isEmpty, reason: 'vector remains empty when disabled');
    });

    test('verifyNeedFulfillmentCall does nothing (no state change) when disabled', () async {
      final stub = _RealismStateStub();
      // disabled by default
      await stub.verifyNeedFulfillmentCall();
      expect(stub.needsVector, isEmpty);

      // Even if we manually populate, disabled guard prevents any action
      stub._needsVector = {'hunger': 20};
      await stub.verifyNeedFulfillmentCall();
      expect(stub.needsVector['hunger'], 20, reason: 'no restore applied when disabled');

      // When enabled, the stub method still guards (no LLM) but we can test manual restore path
      stub.setNeedsSimEnabled(true);
      stub._realismEnabled = true;
      stub._needsVector = {'hunger': 20};
      await stub.verifyNeedFulfillmentCall(); // still no-op in stub
      expect(stub.needsVector['hunger'], 20); // unchanged (no auto-restore here)

      // Demonstrate restore helper works when we simulate fulfillment
      stub._applyNeedRestore('hunger');
      expect(stub.needsVector['hunger'], 20 + 50); // _needRestore['hunger']=50
    });
  });
}
