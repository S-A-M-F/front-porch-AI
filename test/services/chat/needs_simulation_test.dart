// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the extracted NeedsSimulation (plain class).
// Verifies decay, stepping, catastrophe, buffers, deltas, fresh init, serialize/restore,
// and 1:1 vs group path behavior via callbacks. No behavior change vs pre-extraction.
// Uses createTestSim factory (Issue 14) for all ctors.
// Callback contract note for future extractors (growing surface as steps 2-15 proceed):
//   All get*/set*/on* passed at construction must be exercised at least once in tests
//   (current coverage includes time, arousal, group, speaker, observer, enabled, enjoys, notify, save).
// Real dispatch (via getIsGroupNonObserverMode + getCurrentSpeakerIdForRealism) is exercised
// (no more universal speakerId=null forcing for 1:1 paths).

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';

/// Test factory to reduce 13+ callback boilerplate across tests (and future extractions).
/// Supplies realistic defaults; use overrides for targeted state (e.g. speaker, group flag, time).
/// For values mutated by the test after construction (timeOfDay, arousal, speaker etc.),
/// pass live getters via *Fn params so sim callbacks see updates (e.g. timeOfDayFn: () => timeOfDay).
NeedsSimulation createTestSim({
  List<String>? notifies,
  List<String>? saves,
  String Function()? timeOfDayFn,
  bool Function()? realismFn,
  int Function()? arousalFn,
  bool Function()? nsfwCooldownFn,
  int Function()? cooldownFn,
  bool Function()? observerFn,
  String Function()? speakerIdFn,
  bool Function()? isGroupNonObserverFn,
  Map<String, Map<String, int>>? groupNeeds,
  bool Function()? enjoysFn,
  bool Function()? simEnabledFn,
  void Function(int)? onSetArousal,
}) {
  final n = notifies ?? <String>[];
  final s = saves ?? <String>[];
  final gn = groupNeeds ?? <String, Map<String, int>>{};

  return NeedsSimulation(
    onNotify: () => n.add('notify'),
    onSaveChat: () async => s.add('save'),
    getTimeOfDay: timeOfDayFn ?? () => 'morning',
    getRealismEnabled: realismFn ?? () => true,
    getArousalLevel: arousalFn ?? () => 0,
    getNsfwCooldownEnabled: nsfwCooldownFn ?? () => false,
    getCooldownTurnsRemaining: cooldownFn ?? () => 0,
    getObserverMode: observerFn ?? () => false,
    getCurrentSpeakerIdForRealism: speakerIdFn ?? () => 'char-1',
    getIsGroupNonObserverMode: isGroupNonObserverFn ?? () => false,
    getGroupNeeds: (id) => gn[id] ?? {},
    setGroupNeeds: (id, nn) => gn[id] = Map.from(nn),
    getEnjoysLowHygiene: enjoysFn ?? () => false,
    getNeedsSimEnabled: simEnabledFn ?? () => true,
    setArousalLevel: (v) {
      onSetArousal?.call(v);
    },
  );
}

void main() {
  group('NeedsSimulation (extracted)', () {
    late NeedsSimulation sim;
    late List<String> notifies;
    late List<String> saves;
    late String timeOfDay;
    late bool realism;
    late int arousal;
    late bool nsfwCooldown;
    late int cooldown;
    late bool observer;
    late String speakerId;
    late bool isGroupNonObserver;
    late Map<String, Map<String, int>> groupNeeds;
    late bool enjoys;
    late bool simEnabled;
    late int setArousalCalls;

    setUp(() {
      notifies = [];
      saves = [];
      timeOfDay = 'morning';
      realism = true;
      arousal = 0;
      nsfwCooldown = false;
      cooldown = 0;
      observer = false;
      speakerId = 'char-1';
      isGroupNonObserver = false;
      groupNeeds = {};
      enjoys = false;
      simEnabled = true;
      setArousalCalls = 0;

      sim = createTestSim(
        notifies: notifies,
        saves: saves,
        timeOfDayFn: () => timeOfDay,
        realismFn: () => realism,
        arousalFn: () => arousal,
        nsfwCooldownFn: () => nsfwCooldown,
        cooldownFn: () => cooldown,
        observerFn: () => observer,
        speakerIdFn: () => speakerId,
        isGroupNonObserverFn: () => isGroupNonObserver,
        groupNeeds: groupNeeds,
        enjoysFn: () => enjoys,
        simEnabledFn: () => simEnabled,
        onSetArousal: (v) {
          arousal = v;
          setArousalCalls++;
        },
      );
      sim.resetBuffers();
      sim.clearVector();
    });

    test('initializeFresh sets all to 100', () {
      sim.initializeFresh();
      expect(sim.vector.values.every((v) => v == 100), true);
      expect(sim.vector.length, NeedsSimulation.needKeys.length);
    });

    test('initializeIfNeeded seeds from defaults when empty', () {
      sim.initializeIfNeeded();
      expect(sim.vector['hunger'], NeedsSimulation.needDefaults['hunger']);
    });

    test('serialize/restore roundtrips vector', () {
      sim.initializeFresh();
      sim.setNeedValue('hunger', 42);
      final json = sim.serialize();
      final sim2 = createTestSim(
        notifies: [],
        saves: [],
        timeOfDayFn: () => 'morning',
        realismFn: () => true,
        arousalFn: () => 0,
        nsfwCooldownFn: () => false,
        cooldownFn: () => 0,
        observerFn: () => false,
        speakerIdFn: () => 'char-1',
        isGroupNonObserverFn: () => false,
        groupNeeds: {},
        enjoysFn: () => false,
        simEnabledFn: () => true,
      );
      sim2.restoreFromJson(json);
      expect(sim2.vector['hunger'], 42);
    });

    test(
      'tickDecay applies base decay in 1:1 path and persists via callback',
      () async {
        sim.initializeFresh();
        timeOfDay = 'afternoon';
        // 1:1 scalar path is now default (isGroupNonObserver=false); no need to force speakerId.
        // (Previously speakerId=null was used to mask dispatch; now uses real group flag cb.)
        sim.tickDecay();
        // fresh=100 -4 (base hunger) in afternoon = 96
        expect(sim.vector['hunger'], 96);
        expect(saves, isNotEmpty);
      },
    );

    test(
      'tickDecay triggers catastrophe at 0 and lifts to floor + notifies',
      () {
        // Force a need low
        sim.setVector({
          'hunger': 1,
          'bladder': 80,
          'energy': 80,
          'social': 65,
          'fun': 65,
          'hygiene': 75,
          'comfort': 70,
        });
        simEnabled = true;
        realism = true;
        // catas logic is on 1:1 scalar path (default isGroupNonObserver=false)
        sim.tickDecay();
        expect(sim.pendingCatastrophe, isNotNull);
        expect(sim.pendingCatastrophe!.toLowerCase(), contains('hunger'));
        // After catas the value should be lifted (floor ~70 + possible relief)
        expect(sim.vector['hunger'], greaterThan(60));
        expect(notifies, isNotEmpty);
      },
    );

    test('getNeedStep and thresholds match canonical', () {
      expect(sim.getNeedStep('hunger', 0), 0);
      expect(
        sim.getNeedStep('energy', 20),
        2,
      ); // 20 <=30 -> step 2 (per _needStepUpperBounds)
      expect(sim.getNeedStep('fun', 50), 4);
      expect(sim.getNeedStep('comfort', 100), 5);
      expect(NeedsSimulation.needUrgentThreshold, 35);
    });

    test(
      'applyNeedsDeltas from sexual starts afterglow + suppression (reverted to exact original control flow for mechanical fidelity; accumulation inside changed, sexual block after !changed return)',
      () {
        // Use non-cap starting values so deltas cause mutation (original semantics: total only from mutating positives).
        // "At-cap sexual start buffers" is proposed future behavior, not part of this mechanical extraction step.
        sim.setVector({
          'hunger': 90,
          'bladder': 90,
          'energy': 90,
          'social': 90,
          'fun': 90,
          'hygiene': 90,
          'comfort': 90,
        });
        simEnabled = true;
        realism = true;
        sim.applyNeedsDeltas({
          'fun': 20,
          'social': 10,
        }, fromSexualActivity: true);
        expect(sim.afterglowTurnsRemaining, 4);
        expect(
          sim.arousalSuppressionTurnsRemaining,
          NeedsSimulation.arousalSuppressionDefaultTurns,
        );
      },
    );

    test('applyLongGenerationNeedsDecay only when >300s', () {
      sim.initializeFresh();
      // applyLong takes explicit duration (no cb); gate inside
      sim.applyLongGenerationNeedsDecay(10);
      final before = Map.from(sim.vector);
      sim.applyLongGenerationNeedsDecay(400);
      expect(sim.vector['hunger'], lessThan(before['hunger']!));
    });

    test(
      'group path in tick uses callbacks and does not touch scalar buffers decrement',
      () {
        speakerId = 'g1';
        groupNeeds['g1'] = {
          'hunger': 50,
          'bladder': 50,
          'energy': 50,
          'social': 50,
          'fun': 50,
          'hygiene': 50,
          'comfort': 50,
        };
        isGroupNonObserver =
            true; // drives group path (exact dispatch, no speakerId forcing hack)
        observer = false;
        simEnabled = true;
        realism = true;
        timeOfDay = 'night';
        // set a buffer to test read-but-no-decrement
        sim.setVector({
          'hunger': 50,
        }); // scalar for group working copy not used in tick group
        sim.tickDecay();
        // group should have decayed energy at night
        expect(groupNeeds['g1']!['energy'], lessThan(50));
        // buffers should not have been ticked (group early return)
        expect(sim.afterglowTurnsRemaining, 0); // was 0
      },
    );

    test('enjoys low hygiene affects arousal via callback', () {
      sim.setVector({
        'hygiene': 30,
        'hunger': 50,
        'bladder': 50,
        'energy': 50,
        'social': 50,
        'fun': 50,
        'comfort': 50,
      });
      enjoys = true;
      arousal = 10;
      simEnabled = true;
      realism = true;
      // 1:1 tick path for enjoys hygiene mutation (default isGroupNonObserver=false)
      sim.tickDecay();
      expect(setArousalCalls, greaterThan(0));
      expect(arousal, greaterThan(10)); // bonus applied
    });

    test(
      'setEnabled false clears vector and buffers (except post per original set)',
      () {
        // lowered so sexual deltas mutate and start buffers (reverted original semantics)
        sim.setVector({
          'hunger': 90,
          'bladder': 90,
          'energy': 90,
          'social': 90,
          'fun': 90,
          'hygiene': 90,
          'comfort': 90,
        });
        sim.applyNeedsDeltas({'fun': 15}, fromSexualActivity: true);
        sim.setEnabled(false);
        expect(sim.vector.isEmpty, true);
        expect(sim.afterglowTurnsRemaining, 0);
        expect(sim.arousalSuppressionTurnsRemaining, 0);
      },
    );

    // ── Additional coverage added in fix round (bugs 3, nits, plan) ──────────

    test(
      'restoreFromSnapshot roundtrips buffers + vector (happy + partial)',
      () {
        sim.initializeFresh();
        sim.setVector({'hunger': 40, 'energy': 55});
        // start some buffers via sexual on lowered
        sim.applyNeedsDeltas({'fun': 12}, fromSexualActivity: true);
        expect(sim.afterglowTurnsRemaining, 4);
        final snap = {
          'vector': sim.vector,
          'afterglowTurns': 3,
          'arousalSuppressionTurns': 5,
          'postClimaxCrashTurns': 2,
        };
        sim.restoreFromSnapshot(snap);
        expect(sim.vector['hunger'], 40);
        expect(sim.afterglowTurnsRemaining, 3);
        expect(sim.arousalSuppressionTurnsRemaining, 5);
        expect(sim.postClimaxCrashTurnsRemaining, 2);

        // partial: missing keys keep prior
        sim.restoreFromSnapshot({
          'vector': {'bladder': 77},
        });
        expect(sim.vector['bladder'], 77);
        expect(sim.afterglowTurnsRemaining, 3); // preserved
      },
    );

    test(
      'computeNeedsDeltasWithReasons exact reasons for buffer combos + postClimax + early return',
      () {
        // no pre -> empty
        expect(sim.computeNeedsDeltasWithReasons(null), isEmpty);
        expect(sim.computeNeedsDeltasWithReasons({}), isEmpty);

        // natural decay (simulate by manual vector change + no buffers)
        final natSim = createTestSim(
          simEnabledFn: () => true,
          realismFn: () => true,
        );
        natSim.initializeFresh();
        final preNat = Map<String, int>.from(natSim.vector);
        natSim.setVector({
          'hunger': 71,
          'energy': 77,
        }); // -4 hunger, -3 energy from defaults 75/80
        var deltas = natSim.computeNeedsDeltasWithReasons(preNat);
        expect(deltas['hunger']!['reason'], 'Natural decay');
        expect(deltas['energy']!['reason'], 'Natural decay');

        // afterglow for hunger key (afterglow branch before sup)
        final agSim = createTestSim(
          simEnabledFn: () => true,
          realismFn: () => true,
        );
        agSim.initializeFresh();
        agSim.setVector({
          'hunger': 80,
          'bladder': 80,
          'energy': 80,
          'social': 80,
          'fun': 80,
          'hygiene': 80,
          'comfort': 80,
        });
        final preAg = Map<String, int>.from(agSim.vector);
        agSim.applyNeedsDeltas({'fun': 12}, fromSexualActivity: true);
        expect(
          agSim.afterglowTurnsRemaining,
          4,
          reason:
              'afterglow must be active for reason test (fun delta from 80 must mutate)',
        );
        // apply negative delta on hunger-eligible key while afterglow active
        agSim.applyNeedsDeltas({'hunger': -15});
        deltas = agSim.computeNeedsDeltasWithReasons(preAg);
        expect(deltas['hunger']!['reason'], 'Afterglow buffer');

        // post climax
        final pcSim = createTestSim(
          simEnabledFn: () => true,
          realismFn: () => true,
        );
        pcSim.initializeFresh();
        final prePc = Map<String, int>.from(pcSim.vector);
        pcSim.setPostClimaxCrashTurns(2);
        pcSim.setVector({'energy': 50});
        deltas = pcSim.computeNeedsDeltasWithReasons(prePc);
        expect(deltas['energy']!['reason'], 'Post-orgasm exhaustion');

        // suppression (afterglow>0 but for bladder key which skips afterglow if, hits sup)
        final supSim = createTestSim(
          simEnabledFn: () => true,
          realismFn: () => true,
        );
        supSim.initializeFresh();
        supSim.setVector({
          'hunger': 80,
          'bladder': 80,
          'energy': 80,
          'social': 80,
          'fun': 80,
          'hygiene': 80,
          'comfort': 80,
        });
        final preSup = Map<String, int>.from(supSim.vector);
        supSim.applyNeedsDeltas(
          {'fun': 20},
          fromSexualActivity: true,
        ); // total >=8 to start buffers per reverted original
        supSim.setVector({'bladder': 65});
        deltas = supSim.computeNeedsDeltasWithReasons(preSup);
        expect(deltas['bladder']!['reason'], 'Arousal suppression (lust haze)');
      },
    );

    test(
      'setPostClimaxCrashTurns direct + affects tick multiplier + getter',
      () {
        final pcDirect = createTestSim(
          simEnabledFn: () => true,
          realismFn: () => true,
          isGroupNonObserverFn: () => false,
        );
        pcDirect.initializeFresh();
        pcDirect.resetBuffers();
        expect(pcDirect.postClimaxCrashActive, false);
        pcDirect.setPostClimaxCrashTurns(3);
        expect(pcDirect.postClimaxCrashTurnsRemaining, 3);
        expect(pcDirect.postClimaxCrashActive, true);
        expect(
          pcDirect.afterglowTurnsRemaining,
          0,
          reason: 'ensure no afterglow for pure postcrash mult',
        );
        expect(
          pcDirect.arousalSuppressionTurnsRemaining,
          0,
          reason: 'ensure no sup for pure postcrash mult',
        );

        // set vector, no other buffers, tick should *1.8 on energy/fun/social
        pcDirect.setVector({
          'energy': 80,
          'fun': 80,
          'social': 80,
          'hunger': 80,
          'bladder': 80,
          'hygiene': 80,
          'comfort': 80,
        });
        pcDirect.tickDecay(); // with post>0 and after/sup=0 -> multiplier
        // base energy decay=3 *1.8 =5.4 -> round(5.4)=5 , 80-5=75
        expect(
          pcDirect.vector['energy'],
          closeTo(75, 0),
          reason: 'post crash *1.8 on energy when no other buffers',
        );
        pcDirect.setPostClimaxCrashTurns(0);
      },
    );

    test(
      'public surface smoke: restore/set/clear/needRestore/consume/getters',
      () {
        sim.resetBuffers();
        expect(sim.postClimaxCrashActive, false);
        expect(sim.needRestoreAmount('hunger'), 50);
        expect(sim.needRestoreAmount('nonexistent'), 30);

        sim.initializeIfNeeded();
        expect(sim.vector.isNotEmpty, true);
        sim.setNeedValue('bladder', 42);
        expect(sim.vector['bladder'], 42);
        sim.setNeedValue('bladder', 999);
        expect(sim.vector['bladder'], 100); // clamped

        sim.clearVector();
        expect(sim.vector.isEmpty, true);
        sim.initializeIfNeeded(); // already populated no-op path
        expect(sim.vector.isNotEmpty, true);

        sim.resetBuffers();
        expect(sim.afterglowTurnsRemaining, 0);
        expect(sim.arousalSuppressionTurnsRemaining, 0);
        expect(sim.postClimaxCrashTurnsRemaining, 0);

        sim.setPostClimaxCrashTurns(1);
        sim.consumePendingCatastrophe(); // no-op if none
        expect(sim.pendingCatastrophe, isNull);

        // active getters (post already set above; re-assert after possible)
        expect(sim.postClimaxCrashActive, true);
        expect(sim.arousalSuppressionActive, false);

        sim.setVector({'hunger': 55});
        expect(sim.vector['hunger'], 55);
      },
    );

    test('restoreFromJson error paths fall back to initialize', () {
      sim.clearVector();
      sim.restoreFromJson(null);
      expect(sim.vector.isNotEmpty, true); // initialized

      sim.clearVector();
      sim.restoreFromJson('');
      expect(sim.vector.isNotEmpty, true);

      sim.clearVector();
      sim.restoreFromJson('not json at all {');
      expect(sim.vector.isNotEmpty, true);
      expect(sim.vector['hunger'], NeedsSimulation.needDefaults['hunger']);
    });

    test(
      'tickDecay complex multipliers + buffer priority tickdown + afterglow damp + variants + postcrash',
      () {
        // base + damp + time + interplay + priority
        sim.initializeFresh(); // 100s
        timeOfDay = 'morning'; // hunger +2
        isGroupNonObserver = false;
        // set low energy for hunger boost, low fun for social, low bladder for comfort
        sim.setVector({
          'hunger': 80,
          'bladder': 15,
          'energy': 25,
          'social': 70,
          'fun': 15,
          'hygiene': 80,
          'comfort': 80,
        });
        // no buffers -> full multipliers
        sim.tickDecay();
        // hunger: base4 * morning(6) * (energy<=30 ->1.35) = 6*1.35~8.1->8 , 80-8=72
        expect(
          sim.vector['hunger'],
          72,
          reason: 'morning + energy<=30 mult 1.35 documented',
        );
        // comfort: energy<=25 triggers 1.25 first (decay=2*1.25r=3), then bladder<=20 triggers *1.2 (3*1.2r=4), 80-4=76
        expect(
          sim.vector['comfort'],
          76,
          reason:
              'combined energy-low + bladder-low multipliers on comfort (order in original code)',
        );
        // social: base2 * (fun<=20 ->1.4) =2.8->3 ,70-3=67
        expect(sim.vector['social'], 67);

        // now start afterglow (damp 0.45 on hunger/energy/social) using main sim (known 1:1 dispatch)
        sim.resetBuffers();
        isGroupNonObserver = false;
        timeOfDay = 'afternoon';
        sim.setVector({
          'hunger': 80,
          'energy': 80,
          'social': 80,
          'bladder': 80,
          'fun': 80,
          'hygiene': 80,
          'comfort': 80,
        });
        sim.applyNeedsDeltas({'fun': 10}, fromSexualActivity: true);
        sim.tickDecay();
        // hunger with afterglow: base4 *0.45 ~1.8 round 2, 80-2=78
        expect(
          sim.vector['hunger'],
          78,
          reason: 'afterglow damp 0.45x on hunger key',
        );
        expect(
          sim.afterglowTurnsRemaining,
          3,
        ); // ticked down (priority before post)

        // postcrash *1.8 only when after+sup ==0
        sim.setPostClimaxCrashTurns(1);
        // clear afterglow/sup by? set remaining 0 (no public for afterglow, use time tick or direct test via another)
        // use fresh sim for postcrash only
        final pcSim = createTestSim();
        pcSim.initializeFresh();
        pcSim.setVector({
          'energy': 80,
          'fun': 80,
          'social': 80,
          'hunger': 80,
          'bladder': 80,
          'hygiene': 80,
          'comfort': 80,
        });
        pcSim.setPostClimaxCrashTurns(1);
        pcSim.tickDecay();
        // energy base3 *1.8 ~5.4->5 ,80-5=75
        expect(
          pcSim.vector['energy'],
          closeTo(75, 0),
          reason: 'postClimaxCrash *1.8 when afterglow+suppression==0',
        );
        expect(
          pcSim.postClimaxCrashTurnsRemaining,
          0,
        ); // ticked (priority: only after others 0)

        // catas does not fire when already pending
        sim.setVector({'hunger': 0});
        sim.tickDecay(); // may set pending
        final had = sim.pendingCatastrophe;
        sim.tickDecay(); // second should not overwrite
        expect(sim.pendingCatastrophe, had);
      },
    );
  });
}
