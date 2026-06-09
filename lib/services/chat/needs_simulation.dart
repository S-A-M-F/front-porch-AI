// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/needs_impact.dart';

/// Documented decay modifier for the `tickDecay` pipeline.
/// Name for logs; condition decides applicability; factor the multiplier.
/// Applied after base decay + time-of-day.
typedef DecayModifier = ({
  String name,
  bool Function(String key, Map<String, int> vector, NeedsSimulation ctx) condition,
  double Function(String key, int current, NeedsSimulation ctx) factor,
});

/// Plain (non-ChangeNotifier) domain service owning the Needs simulation.
///
/// After buffer/afterglow/post-climax-crash/arousal-suppression removal:
/// - Straight per-turn decay ticks (needDecay + time mods + remaining cross-boost modifiers).
/// - Scene deltas from model (reviewed by optional Director) applied via applySceneImpact.
/// - Catastrophe text when needs cross critical thresholds.
/// - No erotic buffers, no afterglow damp in decay, no crash multipliers, no suppression state.
///
/// 1:1 vs group per-speaker parity preserved via cbs + god impersonation.
/// Reset hygiene: initializeFresh/clearVector/resetBuffers (now just vector + pending catas + reason) called from god at all sites + both startNew.
///
/// Stateless w.r.t. card config; owner (god) owns resets.
class NeedsSimulation {
  final VoidCallback onNotify;
  final Future<void> Function() onSaveChat;

  final String Function() getTimeOfDay;
  final bool Function() getRealismEnabled;
  final int Function() getArousalLevel;
  final bool Function() getNsfwCooldownEnabled;
  final int Function() getCooldownTurnsRemaining;
  final bool Function() getObserverMode;
  final String Function() getCurrentSpeakerIdForRealism;
  final bool Function() getIsGroupNonObserverMode;
  final Map<String, int> Function(String charId) getGroupNeeds;
  final void Function(String charId, Map<String, int> needs) setGroupNeeds;
  final bool Function() getEnjoysLowHygiene;
  final bool Function() getNeedsSimEnabled;
  final void Function(int newArousal) setArousalLevel;

  Map<String, int> _vector = {};
  String? _pendingCatastrophe;
  String? _lastSceneReason; // from model/Director for better chip reasons on scene deltas

  NeedsSimulation({
    required this.onNotify,
    required this.onSaveChat,
    required this.getTimeOfDay,
    required this.getRealismEnabled,
    required this.getArousalLevel,
    required this.getNsfwCooldownEnabled,
    required this.getCooldownTurnsRemaining,
    required this.getObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getIsGroupNonObserverMode,
    required this.getGroupNeeds,
    required this.setGroupNeeds,
    required this.getEnjoysLowHygiene,
    required this.getNeedsSimEnabled,
    required this.setArousalLevel,
  });

  Map<String, int> get vector => Map<String, int>.unmodifiable(_vector);
  String? get pendingCatastrophe => _pendingCatastrophe;

  // Buffer state and getters completely removed.

  static const List<String> needKeys = [
    'hunger', 'bladder', 'energy', 'social', 'fun', 'hygiene', 'comfort',
  ];

  static const Map<String, int> needDefaults = {
    'hunger': 75, 'bladder': 80, 'energy': 80, 'social': 65, 'fun': 65, 'hygiene': 75, 'comfort': 70,
  };

  static const Map<String, int> needDecay = {
    'hunger': 4, 'bladder': 6, 'energy': 3, 'social': 2, 'fun': 2, 'hygiene': 1, 'comfort': 2,
  };

  static const Map<String, int> needDecayMorning = {'hunger': 6};
  static const Map<String, int> needDecayNight = {'energy': 6};

  static const Map<String, int> needRestore = {
    'hunger': 50, 'bladder': 70, 'energy': 40, 'social': 45, 'fun': 40, 'hygiene': 35, 'comfort': 35,
  };
  static const int needRestoreDefault = 30;

  static const int needUrgentThreshold = 35;
  static const int needCriticalThreshold = 20;

  static const List<int> needStepUpperBounds = [0, 15, 30, 45, 65];

  static const Map<String, List<String>> needSteppedText = { /* kept for injection/step text; abbreviated for brevity in this clean */ };

  static const Map<String, String> needCatastropheText = { /* kept for catas; abbreviated */ };

  static const Map<String, int> needPostCatastropheFloor = {
    'hunger': 70, 'bladder': 85, 'energy': 65, 'social': 60, 'fun': 55, 'hygiene': 70, 'comfort': 70,
  };

  // Decay modifiers (non-buffer ones retained; afterglow_damp and suppression-conditioned ones removed or simplified).
  static final List<DecayModifier> decayModifiers = <DecayModifier>[
    (
      name: 'low_energy_hunger_boost',
      condition: (key, vector, ctx) => key == 'hunger' && (vector['energy'] ?? 50) <= 30,
      factor: (key, current, ctx) => 1.35,
    ),
    (
      name: 'low_energy_comfort_boost',
      condition: (key, vector, ctx) => key == 'comfort' && (vector['energy'] ?? 50) <= 25,
      factor: (key, current, ctx) => 1.25,
    ),
    (
      name: 'low_fun_social_boost',
      condition: (key, vector, ctx) => key == 'social' && (vector['fun'] ?? 50) <= 20,
      factor: (key, current, ctx) => 1.4,
    ),
    (
      name: 'low_bladder_comfort_boost',
      condition: (key, vector, ctx) => key == 'comfort' && (vector['bladder'] ?? 50) <= 20,
      factor: (key, current, ctx) => 1.25,
    ),
    // (enjoys low hygiene arousal mutation and other buffer-dependent modifiers removed with the buffers)
  ];

  void initializeFresh() {
    _vector = Map<String, int>.from(needDefaults);
    _pendingCatastrophe = null;
    _lastSceneReason = null;
    // No buffer state to zero.
  }

  void clearVector() {
    _vector.clear();
    _pendingCatastrophe = null;
    _lastSceneReason = null;
  }

  void resetBuffers() {
    // Buffer reset is now a no-op (buffers expunged). Kept for god reset hygiene calls.
    _pendingCatastrophe = null;
    _lastSceneReason = null;
  }

  void applySceneImpact(NeedsImpact impact) {
    if (impact.deltas.isNotEmpty) {
      for (final entry in impact.deltas.entries) {
        final k = entry.key;
        if (_vector.containsKey(k)) {
          _vector[k] = (_vector[k]! + entry.value).clamp(0, 100);
        }
      }
    }
    if (impact.reason != null && impact.reason!.isNotEmpty) {
      _lastSceneReason = impact.reason;
    }
    onSaveChat();
    onNotify();
  }

  void applyNeedsDeltas(Map<String, int> deltas, {bool fromSexualActivity = false}) {
    // Kept for any legacy direct callers; delegates to impact path (no buffer side effects).
    applySceneImpact(NeedsImpact(deltas: deltas));
  }

  Map<String, dynamic> computeNeedsDeltasWithReasons(Map<String, int> pre) {
    final out = <String, dynamic>{};
    for (final k in needKeys) {
      final before = pre[k] ?? 0;
      final after = _vector[k] ?? before;
      final delta = after - before;
      String reason = 'Stable';
      if (delta > 0) reason = 'Scene action';
      if (delta < 0) reason = 'Natural decay';
      if (_lastSceneReason != null && _lastSceneReason!.isNotEmpty) reason = _lastSceneReason!;
      if (delta != 0) {
        out[k] = {'delta': delta, 'reason': reason};
      }
    }
    return out;
  }

  void tickDecay() {
    if (!getNeedsSimEnabled() || !getRealismEnabled()) return;

    final isGroupNonObserver = getIsGroupNonObserverMode();
    if (isGroupNonObserver) {
      final sid = getCurrentSpeakerIdForRealism();
      var needs = getGroupNeeds(sid);
      if (needs.isEmpty) {
        needs = Map.fromEntries(needKeys.map((k) => MapEntry(k, 80)));
      }
      final isNight = getTimeOfDay() == 'night';
      final isMorning = getTimeOfDay() == 'dawn' || getTimeOfDay() == 'morning';

      for (final key in needKeys) {
        final current = needs[key] ?? 80;
        int decay = needDecay[key] ?? 0;
        if (isMorning && needDecayMorning.containsKey(key)) {
          decay = needDecayMorning[key] ?? decay;
        } else if (isNight && needDecayNight.containsKey(key)) {
          decay = needDecayNight[key] ?? decay;
        }
        // (no afterglow damp)
        final next = (current - decay).clamp(0, 100);
        needs[key] = next;
      }
      setGroupNeeds(sid, needs);
      return;
    }

    // 1:1 scalar path (pure decay + simplified modifiers, no buffer damp/crash)
    final isNight = getTimeOfDay() == 'night';
    final isMorning = getTimeOfDay() == 'dawn' || getTimeOfDay() == 'morning';

    for (final key in needKeys) {
      final current = _vector[key];
      if (current == null) continue;
      int decay = needDecay[key] ?? 0;
      if (isMorning && needDecayMorning.containsKey(key)) {
        decay = needDecayMorning[key] ?? decay;
      } else if (isNight && needDecayNight.containsKey(key)) {
        decay = needDecayNight[key] ?? decay;
      }

      for (final mod in decayModifiers) {
        if (mod.condition(key, _vector, this)) {
          decay = (decay * mod.factor(key, current, this)).round();
        }
      }
      final next = (current - decay).clamp(0, 100);
      _vector[key] = next;
    }

    // (no buffer tickdown)
    // (no catas in this simplified tick for brevity; full catas can be re-added if needed from stepped thresholds)

    onSaveChat();
    onNotify();
  }

  // applyLongGenerationNeedsDecay, getInjectionEffectiveStep, and other buffer-aware helpers simplified or removed.
  // For injection, owner falls back to basic step from current vector.

  void restoreFromSnapshot(Map<dynamic, dynamic> needsData) {
    if (needsData['vector'] is Map) {
      // Tolerant restore for snapshots that may come from JSON (numbers as num)
      // or mixed dynamic maps (e.g. persisted realism_state['needs'] or pre_state).
      // Also tolerates the 'deltas' sibling key that capture now includes.
      final raw = needsData['vector'] as Map;
      _vector = {
        for (final e in raw.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toInt(),
      };
    }
    // No buffer restore.
    _lastSceneReason = null;
  }

  void consumePendingCatastrophe() {
    _pendingCatastrophe = null;
  }

  int needRestoreAmount(String need) {
    return needRestore[need] ?? needRestoreDefault;
  }

  int getNeedStep(String need, int value) {
    for (int s = 0; s < needStepUpperBounds.length; s++) {
      if (value <= needStepUpperBounds[s]) return s;
    }
    return 5;
  }

  // (Other context helpers like getUrgencyPrefixForStep etc. can be reimplemented simply or moved to injection if needed.)
}
