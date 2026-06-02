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

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Plain (non-ChangeNotifier) domain service owning the Sims-style Needs simulation
/// state and logic (decay, stepping, catastrophe, afterglow / post-climax buffers,
/// deltas, long-gen decay, etc.).
///
/// ChatService owns the instance via a private late final and delegates. All cross
/// state (time of day, arousal, group realism map, etc.) that lives in the parent
/// for now is accessed exclusively via callbacks supplied at construction. This
/// keeps the extracted service testable and avoids cycles. (Granular callbacks
/// chosen over a full parent interface ref for this leaf extraction to avoid
/// import cycles and enable isolated tests; see refactoring-guide.md update.)
///
/// Communication back to owner: onNotify (for catastrophe UI jumps), onSaveChat
/// (fire-and-forget persist of vector changes).
///
/// Extraction is mechanical for original methods/fields copied; dispatch condition
/// adapted with dedicated group-mode callback (getIsGroupNonObserverMode) to
/// preserve exact original 1:1 scalar vs group speaker paths. See review responses.
class NeedsSimulation {
  final VoidCallback onNotify;
  final Future<void> Function() onSaveChat;

  // Callbacks for parent-owned cross-domain state (time, arousal, group, etc.).
  // These remain in ChatService until their owning services are extracted in later steps.
  // getCurrentSpeakerIdForRealism: non-nullable (owner always returns a charId; empty string treated as sentinel in some owner paths).
  // getIsGroupNonObserverMode: returns true only for active group + !observer (drives exact 1:1 vs group dispatch in tickDecay).
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

  // Owned simulation state (moved from ChatService scalar fields).
  Map<String, int> _vector = {};
  int _afterglowTurnsRemaining = 0;
  int _arousalSuppressionTurnsRemaining = 0;
  int _postClimaxCrashTurnsRemaining = 0;
  String? _pendingCatastrophe;

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

  // ── Public surface for shims + callers still in ChatService ────────────────

  Map<String, int> get vector => Map<String, int>.unmodifiable(_vector);

  String? get pendingCatastrophe => _pendingCatastrophe;

  int get afterglowTurnsRemaining => _afterglowTurnsRemaining;
  int get arousalSuppressionTurnsRemaining => _arousalSuppressionTurnsRemaining;
  int get postClimaxCrashTurnsRemaining => _postClimaxCrashTurnsRemaining;
  bool get postClimaxCrashActive => _postClimaxCrashTurnsRemaining > 0;
  bool get arousalSuppressionActive => _arousalSuppressionTurnsRemaining > 0;

  // Canonical constants (single source of truth; public aliases for UI/tests).
  // ChatService keeps @Deprecated or value shims for its prior public consts.
  static const List<String> needKeys = [
    'hunger',
    'bladder',
    'energy',
    'social',
    'fun',
    'hygiene',
    'comfort',
  ];

  static const Map<String, int> needDefaults = {
    'hunger': 75,
    'bladder': 80,
    'energy': 80,
    'social': 65,
    'fun': 65,
    'hygiene': 75,
    'comfort': 70,
  };

  static const Map<String, int> needDecay = {
    'hunger': 4,
    'bladder': 6,
    'energy': 3,
    'social': 2,
    'fun': 2,
    'hygiene': 1,
    'comfort': 2,
  };

  static const Map<String, int> needDecayMorning = {'hunger': 6};
  static const Map<String, int> needDecayNight = {'energy': 6};

  static const Map<String, int> needRestore = {
    'hunger': 50,
    'bladder': 70,
    'energy': 40,
    'social': 45,
    'fun': 40,
    'hygiene': 35,
    'comfort': 35,
  };

  static const int needRestoreDefault = 30;

  static const int needUrgentThreshold = 35;
  static const int needCriticalThreshold = 20;
  static const int needFulfillmentScanThreshold = 40;

  static const int arousalSuppressionThreshold = 35;
  static const int arousalSuppressionDefaultTurns = 6;
  static const double postClimaxCrashDecayMultiplier = 1.8;

  static const List<int> needStepUpperBounds = [0, 15, 30, 45, 65];

  static const Map<String, List<String>> needSteppedText = {
    'hunger': [
      'A violent stomach cramp doubles her over. She is genuinely starving — vision swimming, knees weak, barely able to stay upright. The hunger has become a real physical crisis.',
      'Sharp, gnawing cramps twist through her. She feels light-headed and shaky, and her thoughts keep drifting uncontrollably to food. She is struggling to focus on anything else.',
      'Her stomach feels painfully hollow and tight. A constant, distracting ache that makes her restless and short-tempered. She keeps thinking about when she might be able to eat.',
      'A steady, empty feeling sits in her stomach. Her thoughts occasionally wander toward food and she feels a bit distracted or low-energy.',
      'A quiet, background emptiness in her stomach. It is not urgent, but she is aware of it and would welcome a chance to eat soon.',
    ],
    'bladder': [
      'She loses control completely. A sudden, hot rush — she is wetting herself right now in the current scene. The humiliation is immediate and overwhelming.',
      'She is fighting with everything she has not to lose control. Thighs pressed tight, constantly shifting, voice tight with strain. She is very close to having an accident.',
      'A strong, insistent pressure has built up. She is visibly uncomfortable and keeps looking for a polite way to excuse herself soon.',
      'A steady, distracting pressure low in her belly. She feels the need more and more and would like to find a bathroom before too long.',
      'A faint but persistent urge to use the restroom sits at the back of her mind, making her slightly restless.',
    ],
    'energy': [
      'Her body gives out completely. Mid-sentence her eyes flutter and she collapses — slumping to the floor or into {{user}}\'s arms, fully unconscious from exhaustion.',
      'She is barely staying awake. Head nodding, speech slow and heavy, eyes unfocused. She may drift off at any moment.',
      'A heavy, crushing tiredness has settled over her. Every movement feels like effort and her thoughts are slow. She desperately wants to rest.',
      'A deep weariness is weighing on her. She moves a little slower and seems less animated than usual, clearly running low on energy.',
      'A comfortable, heavy tiredness sits behind her eyes. She would happily curl up and rest if the opportunity arose.',
    ],
    'social': [
      'The loneliness has become overwhelming. She feels hollow and raw, on the edge of breaking down if she cannot have real, meaningful connection with someone soon.',
      'She feels painfully isolated. The lack of real connection is starting to hurt, and she may become unusually quiet, clingy, or emotionally fragile.',
      'A deep ache for genuine connection sits in her chest. Casual interaction feels hollow and she keeps seeking more meaningful moments or closeness.',
      'She is feeling the absence of real companionship. She seems a little more eager for meaningful conversation or physical closeness than usual.',
      'A quiet, gentle craving for real connection makes her a bit more warm and attentive than normal.',
    ],
    'fun': [
      'The boredom has become torturous. She feels dangerously restless and may suddenly do something reckless or wildly inappropriate just to feel *something* again.',
      'She is deeply restless and bored out of her mind. She fidgets constantly and will suggest almost anything to break the monotony.',
      'A heavy restlessness has settled over her. Everything feels dull and she keeps looking for any excuse to do something more stimulating.',
      'She is noticeably bored and fidgety. The current situation feels flat and she is actively hoping for a change of pace.',
      'A mild restlessness makes her a little more eager for something fun or different to happen.',
    ],
    'hygiene': [
      'She feels filthy and overwhelmed by it. The grime or smell is so strong it is making her physically uncomfortable and self-conscious to the point of distress.',
      'She feels genuinely dirty and is very aware of it. She keeps wanting to cover herself or pull away from contact until she can clean up.',
      'A persistent feeling of being grimy clings to her. She is self-conscious and keeps thinking about when she can wash or change.',
      'She is starting to feel noticeably unkempt. A quiet discomfort with her own state makes her want to freshen up soon.',
      'A faint, background sense of being a little grubby makes her mildly self-conscious.',
    ],
    'comfort': [
      'The physical discomfort has become unbearable. She cannot stay like this any longer and will do whatever it takes to find relief, even if it disrupts everything else happening.',
      'Her body is in real distress — too hot, too cold, cramped, or aching badly. She is constantly shifting and struggling to focus on anything else.',
      'A strong physical discomfort is wearing on her. She keeps adjusting her position or environment, clearly unable to settle.',
      'She is noticeably uncomfortable. A persistent physical irritation (temperature, pressure, stiffness) makes it hard for her to fully relax.',
      'A mild but persistent physical discomfort sits in the background, making her slightly restless.',
    ],
  };

  static const Map<String, String> needCatastropheNarrative = {
    'hunger':
        'A violent stomach cramp drops her to her knees or against {{user}}. She hasn\'t eaten in far too long; her blood sugar crashes and she nearly faints or becomes too weak to stand. The hunger has turned into a real physical emergency.',
    'bladder':
        'She loses control completely. A sudden, hot, unstoppable rush — she is wetting herself right now, in the current scene, in front of {{user}} or anyone present. The fabric darkens, liquid runs down her legs, the smell fills the air, and her face is a mask of horror and humiliation. The accident is happening / has just happened.',
    'energy':
        'Her body simply shuts down. Mid-sentence her eyes roll back and she collapses — slumping to the floor, onto furniture, or into {{user}}\'s arms — completely unconscious from exhaustion. She is out cold and will not wake for some time.',
    'social':
        'The isolation finally breaks her. She bursts into tears or a raw, desperate plea for real connection, unable to pretend any longer that she is okay alone.',
    'fun':
        'The boredom has driven her to something reckless or wildly inappropriate — she does something dangerous, sexual, or chaotic purely to feel *anything* again.',
    'hygiene':
        'The accumulated grime and smell finally overwhelm her. She gags, tears up, or has a small breakdown about how disgusting she feels, refusing further contact until she can wash.',
    'comfort':
        'The physical misery becomes too much. She cries out, pushes away from whatever is hurting her (the chair, the ropes, the position, the temperature), and demands — or takes — immediate relief no matter what else is happening in the scene.',
  };

  static const Map<String, int> needPostCatastropheFloor = {
    'hunger': 70,
    'bladder': 85,
    'energy': 65,
    'social': 60,
    'fun': 55,
    'hygiene': 70,
    'comfort': 70,
  };

  // ── Control / init / persistence ───────────────────────────────────────────

  void setEnabled(bool enabled) {
    if (enabled) {
      initializeIfNeeded();
    } else {
      _vector.clear();
      _afterglowTurnsRemaining = 0;
      _arousalSuppressionTurnsRemaining = 0;
    }
  }

  void initializeIfNeeded() {
    if (_vector.isEmpty) {
      _vector = Map<String, int>.from(needDefaults);
    }
  }

  void initializeFresh() {
    _vector = {for (final k in needKeys) k: 100};
  }

  String serialize() => jsonEncode(_vector);

  void restoreFromJson(String? json) {
    if (json == null || json.isEmpty) {
      initializeIfNeeded();
      return;
    }
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      _vector = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      initializeIfNeeded();
    }
  }

  void clearVector() {
    _vector.clear();
  }

  void resetBuffers() {
    _afterglowTurnsRemaining = 0;
    _arousalSuppressionTurnsRemaining = 0;
    _postClimaxCrashTurnsRemaining = 0;
  }

  void setVector(Map<String, int> v) {
    _vector = Map<String, int>.from(v);
  }

  void setNeedValue(String need, int value) {
    if (_vector.containsKey(need)) {
      _vector[need] = value.clamp(0, 100);
    }
  }

  void restoreFromSnapshot(Map<dynamic, dynamic> needsData) {
    if (needsData['vector'] is Map) {
      _vector = Map<String, int>.from(needsData['vector'] as Map);
    }
    _afterglowTurnsRemaining =
        (needsData['afterglowTurns'] as int?) ?? _afterglowTurnsRemaining;
    _arousalSuppressionTurnsRemaining =
        (needsData['arousalSuppressionTurns'] as int?) ??
        _arousalSuppressionTurnsRemaining;
    _postClimaxCrashTurnsRemaining =
        (needsData['postClimaxCrashTurns'] as int?) ??
        _postClimaxCrashTurnsRemaining;
  }

  void consumePendingCatastrophe() {
    _pendingCatastrophe = null;
  }

  void setPostClimaxCrashTurns(int turns) {
    _postClimaxCrashTurnsRemaining = turns;
  }

  int needRestoreAmount(String need) {
    return needRestore[need] ?? needRestoreDefault;
  }

  int getNeedStep(String need, int value) {
    for (int s = 0; s < needStepUpperBounds.length; s++) {
      if (value <= needStepUpperBounds[s]) return s;
    }
    return 5; // comfortable
  }

  // ── Core tick + mutation (exact behavior preserved for 1:1 vs group) ────────

  void tickDecay() {
    if (!getNeedsSimEnabled() || !getRealismEnabled()) return;

    // Dispatch exactly matches original ChatService._tickNeedsDecay:
    // if group non-observer: group speaker path (simple decay + afterglow damp read only, early return, no catas/buffer tickdown/enjoys/full multipliers).
    // else: full 1:1 scalar path (interplay multipliers, catas trigger/lift, buffer priority tickdown, enjoys arousal mutation via cb, onSave+notify).
    // getIsGroupNonObserverMode wires to (_activeGroup != null && !_observerMode) in owner.
    // getCurrentSpeakerIdForRealism is still used inside group path (and for other owner sites).
    final isGroupNonObserver = getIsGroupNonObserverMode();
    if (isGroupNonObserver) {
      final sid = getCurrentSpeakerIdForRealism();
      // Group speaker path (non-observer group mode).
      var needs = getGroupNeeds(sid);
      if (needs.isEmpty) {
        needs = Map.fromEntries(needKeys.map((k) => MapEntry(k, 80)));
        // defensive (parent _getGroupNeeds never returns empty; retained verbatim for mechanical fidelity on first extraction)
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

        if (_afterglowTurnsRemaining > 0 &&
            (key == 'hunger' || key == 'energy' || key == 'social')) {
          decay = (decay * 0.45).round();
        }

        final next = (current - decay).clamp(0, 100);
        needs[key] = next;
      }
      setGroupNeeds(sid, needs);
      return; // group path done (buffers not ticked here, per original)
    }

    // 1:1 scalar path (full decay interplay + buffer tickdown + catas + enjoys mutation only in scalar; also used as working copy after loadSpeaker in group)
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

      if (_afterglowTurnsRemaining > 0 &&
          (key == 'hunger' || key == 'energy' || key == 'social')) {
        decay = (decay * 0.45).round();
      }

      final bool suppressionActiveThisTick =
          _arousalSuppressionTurnsRemaining > 0 ||
          (getArousalLevel() >= arousalSuppressionThreshold &&
              (_afterglowTurnsRemaining > 0 ||
                  getCooldownTurnsRemaining() > 0));

      final bool postCrashActiveThisTick =
          _postClimaxCrashTurnsRemaining > 0 &&
          _afterglowTurnsRemaining == 0 &&
          _arousalSuppressionTurnsRemaining == 0;

      final energy = _vector['energy'] ?? 50;
      final fun = _vector['fun'] ?? 50;

      if (key == 'hunger' && energy <= 30) {
        final mult = suppressionActiveThisTick ? 1.15 : 1.35;
        decay = (decay * mult).round();
      }

      if (key == 'comfort' && energy <= 25) {
        final mult = suppressionActiveThisTick ? 1.10 : 1.25;
        decay = (decay * mult).round();
      }

      if (key == 'social' && fun <= 20) {
        final mult = suppressionActiveThisTick ? 1.20 : 1.4;
        decay = (decay * mult).round();
      }

      final bladder = _vector['bladder'] ?? 50;
      if (key == 'comfort' && bladder <= 20) {
        final mult = suppressionActiveThisTick ? 1.10 : 1.2;
        decay = (decay * mult).round();
      }

      if (postCrashActiveThisTick &&
          (key == 'energy' || key == 'fun' || key == 'social')) {
        decay = (decay * postClimaxCrashDecayMultiplier).round();
      }

      _vector[key] = (current - decay).clamp(0, 100);
    }

    // Tick down buffers (1:1 path only, per original structure)
    if (_afterglowTurnsRemaining > 0) {
      _afterglowTurnsRemaining--;
      if (_afterglowTurnsRemaining == 0) {
        debugPrint('[Realism:Needs] Afterglow buffer expired');
      }
    }

    if (_arousalSuppressionTurnsRemaining > 0) {
      _arousalSuppressionTurnsRemaining--;
      if (_arousalSuppressionTurnsRemaining == 0) {
        debugPrint('[Realism:Needs] Arousal suppression (lust haze) expired');
      }
    }

    if (_afterglowTurnsRemaining == 0 &&
        _arousalSuppressionTurnsRemaining == 0 &&
        _postClimaxCrashTurnsRemaining > 0) {
      _postClimaxCrashTurnsRemaining--;
      if (_postClimaxCrashTurnsRemaining == 0) {
        debugPrint(
          '[Realism:Needs] Post-climax crash (lethargy / post-nut sleepiness) expired',
        );
      }
    }

    // Catastrophe trigger (1:1 path only)
    if (_pendingCatastrophe == null &&
        getNeedsSimEnabled() &&
        getRealismEnabled()) {
      String? worstNeed;
      int worstValue = 999;
      for (final key in needKeys) {
        final v = _vector[key] ?? 100;
        if (v <= 0 && v < worstValue) {
          worstValue = v;
          worstNeed = key;
        }
      }
      if (worstNeed != null) {
        _pendingCatastrophe =
            needCatastropheNarrative[worstNeed] ??
            'Something catastrophic just happened because her $worstNeed need hit zero.';
        int floor = needPostCatastropheFloor[worstNeed] ?? 30;

        final text = _pendingCatastrophe!.toLowerCase();
        final wasAccidentOrCollapse =
            text.contains('accident') ||
            text.contains('wetting') ||
            text.contains('lost control') ||
            text.contains('collapsed') ||
            text.contains('faint') ||
            text.contains('out cold');

        if (!wasAccidentOrCollapse) {
          floor = (floor + 12).clamp(0, 100);
        }

        _vector[worstNeed] = floor;
        debugPrint(
          '[Realism:Needs] ⚠️ CATASTROPHE triggered for $worstNeed → lifted to $floor (accident=$wasAccidentOrCollapse)',
        );
      }
    }

    debugPrint('[Realism:Needs] Tick decay applied');

    // Enjoys low hygiene inversion — mutates arousal via callback (cross-domain)
    if (getEnjoysLowHygiene()) {
      final hygiene = _vector['hygiene'] ?? 50;
      if (hygiene < 50) {
        final bonus = ((50 - hygiene) / 10).round().clamp(0, 5);
        final cur = getArousalLevel();
        setArousalLevel((cur + bonus).clamp(-100, 100));
      }
      if (hygiene >= 60) {
        final penalty = ((hygiene - 60) / 10).round().clamp(0, 5);
        final cur = getArousalLevel();
        setArousalLevel((cur - penalty).clamp(-100, 100));
      }
    }

    onSaveChat();
    if (_pendingCatastrophe != null) {
      onNotify();
    }
  }

  void applyLongGenerationNeedsDecay(double lastGenDurationSeconds) {
    if (!getNeedsSimEnabled() ||
        !getRealismEnabled() ||
        lastGenDurationSeconds < 300) {
      return;
    }

    final extraDecay = <String, int>{
      'hunger': 2,
      'bladder': 3,
      'energy': 1,
      'hygiene': 1,
    };

    for (final entry in extraDecay.entries) {
      final key = entry.key;
      final amount = entry.value;
      if (_vector.containsKey(key)) {
        final before = _vector[key]!;
        _vector[key] = (before - amount).clamp(0, 100);
        debugPrint(
          '[Realism:Needs] Long generation extra decay: $key $before → ${_vector[key]} (took ${lastGenDurationSeconds.toStringAsFixed(0)}s)',
        );
      }
    }
  }

  Map<String, Map<String, dynamic>> computeNeedsDeltasWithReasons(
    Map<String, int>? preTurn,
  ) {
    if (preTurn == null || preTurn.isEmpty) return {};

    final deltas = <String, Map<String, dynamic>>{};

    for (final key in needKeys) {
      final before = preTurn[key] ?? needDefaults[key] ?? 50;
      final after = _vector[key] ?? before;
      final delta = after - before;

      String reason;
      if (delta == 0) {
        reason = 'Stable';
      } else if (delta > 0) {
        reason = 'Scene action';
      } else if (_postClimaxCrashTurnsRemaining > 0 &&
          _afterglowTurnsRemaining == 0 &&
          _arousalSuppressionTurnsRemaining == 0) {
        reason = 'Post-orgasm exhaustion';
      } else if (_afterglowTurnsRemaining > 0 &&
          (key == 'hunger' || key == 'energy' || key == 'social')) {
        reason = 'Afterglow buffer';
      } else if (_arousalSuppressionTurnsRemaining > 0) {
        reason = 'Arousal suppression (lust haze)';
      } else {
        reason = 'Natural decay';
      }

      deltas[key] = {'delta': delta, 'reason': reason};
    }

    return deltas;
  }

  void applyNeedsDeltas(
    Map<String, int> deltas, {
    bool fromSexualActivity = false,
  }) {
    if (!getNeedsSimEnabled() || !getRealismEnabled() || deltas.isEmpty) return;

    bool changed = false;
    int totalPositiveImpact = 0;

    for (final entry in deltas.entries) {
      final key = entry.key;
      if (!needKeys.contains(key)) continue;

      final current = _vector[key] ?? 50;
      final newValue = (current + entry.value).clamp(0, 100);
      if (newValue != current) {
        _vector[key] = newValue;
        changed = true;
        if (entry.value > 0) totalPositiveImpact += entry.value;
      }
    }

    if (!changed) return;

    if (fromSexualActivity && totalPositiveImpact >= 8) {
      _afterglowTurnsRemaining = 4;
      _arousalSuppressionTurnsRemaining = arousalSuppressionDefaultTurns;
      debugPrint(
        '[Realism:Needs] Afterglow buffer + arousal suppression started/refreshed ($totalPositiveImpact impact)',
      );
    }

    debugPrint('[Realism:Needs] Applied deltas: $deltas');
    onSaveChat();
    onNotify();
  }
}
