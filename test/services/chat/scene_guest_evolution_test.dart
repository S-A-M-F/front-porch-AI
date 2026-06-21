// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for Scene Guests (Lite NPCs) Phase 3 — per-guest Character Evolution.
//
// Two independently verifiable surfaces:
//
//  1) The guest-evolution persistence shape. Phase 3 co-locates each guest's
//     participation count + evolved personality/scenario inside the 1:1
//     `groupRealismState` blob (no schema change) under a `guestEvolution`
//     map keyed by the guest's stable charId, alongside the existing
//     `sceneGuests` id list. This test mirrors ChatService's _doSaveChat build
//     and _loadSceneGuestsFromSession parse exactly so a regression in the
//     blob structure (or a key rename) is caught here.
//
//  2) The APPLY path. A guest is a real (lite) library card and evolves through
//     the SAME EvolutionService used for normal characters; its evolved text is
//     stored in the shared evolved maps keyed by charId, so the existing
//     getEffectivePersonality/getEffectiveScenario layering wraps it in the
//     [Character Growth] / [Current Situation] blocks on the guest's turns —
//     with no Realism/Needs involvement. This proves an isLite card layers
//     identically to a normal card.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/evolution_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';

CharacterCard _liteGuest(String name) => CharacterCard(
  name: name,
  description: 'Guest desc',
  personality: 'Guest pers',
  scenario: 'Guest scen',
  frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
);

/// Mirrors ChatService._doSaveChat blob build for the 1:1-with-guests branch.
String buildGuestBlob({
  required List<String> sceneGuestIds,
  required Map<String, int> guestCounts,
  required Map<String, String> evolvedPers,
  required Map<String, String> evolvedScen,
  required List<CharacterCard> guests,
  required String Function(CharacterCard) charIdOf,
}) {
  final guestEvolution = <String, Map<String, dynamic>>{};
  for (final guest in guests) {
    final charId = charIdOf(guest);
    final count = guestCounts[charId] ?? 0;
    final pers = evolvedPers[charId] ?? '';
    final scen = evolvedScen[charId] ?? '';
    if (count == 0 && pers.isEmpty && scen.isEmpty) continue;
    guestEvolution[charId] = {
      'count': count,
      'personality': pers,
      'scenario': scen,
    };
  }
  return jsonEncode({
    'sceneGuests': sceneGuestIds,
    if (guestEvolution.isNotEmpty) 'guestEvolution': guestEvolution,
  });
}

/// Mirrors ChatService._loadSceneGuestsFromSession parse of guest evolution.
({
  List<String> sceneGuestIds,
  Map<String, int> counts,
  Map<String, String> pers,
  Map<String, String> scen,
})
parseGuestBlob(String json) {
  final ids = <String>[];
  final counts = <String, int>{};
  final pers = <String, String>{};
  final scen = <String, String>{};
  final decoded = jsonDecode(json);
  if (decoded is Map && decoded['sceneGuests'] is List) {
    for (final id in decoded['sceneGuests'] as List) {
      final s = id?.toString();
      if (s != null && s.isNotEmpty) ids.add(s);
    }
  }
  if (decoded is Map && decoded['guestEvolution'] is Map) {
    final ge = Map<String, dynamic>.from(decoded['guestEvolution'] as Map);
    ge.forEach((charId, v) {
      if (v is! Map) return;
      final m = Map<String, dynamic>.from(v);
      counts[charId] = (m['count'] as num?)?.toInt() ?? 0;
      final p = (m['personality'] as String?) ?? '';
      final s = (m['scenario'] as String?) ?? '';
      if (p.isNotEmpty) pers[charId] = p;
      if (s.isNotEmpty) scen[charId] = s;
    });
  }
  return (sceneGuestIds: ids, counts: counts, pers: pers, scen: scen);
}

/// Minimal EvolutionService wired exactly like ChatService for the APPLY path
/// (the LLM stream is never used by getEffective*; it only needs to exist).
class _NoopLlm extends LLMService {
  @override
  bool get isReady => true;
  @override
  String get backendName => 'noop';
  @override
  Stream<String> generateStream(GenerationParams params) =>
      const Stream.empty();
}

EvolutionService _applyOnlyService({
  required Map<String, String> evolvedPers,
  required Map<String, String> evolvedScen,
  bool enabled = true,
}) {
  return EvolutionService(
    getLlmService: () => _NoopLlm(),
    stripThinkBlocks: (t) => t,
    getUserName: () => 'User',
    getActiveCharacter: () => null,
    getGroupCharacters: () => const [],
    getMessages: () => const [],
    getCharacterIdFromCard: (c) => c.name.toLowerCase(),
    getSummary: () => '',
    getIsNewChat: () => false,
    fetchRecentMemoryChunksForEvolution: () async => const [],
    getCharacterEvolutionEnabled: () => enabled,
    getEvolvedPersonality: (id) => evolvedPers[id],
    setEvolvedPersonality: (id, v) => evolvedPers[id] = v,
    getEvolvedScenario: (id) => evolvedScen[id],
    setEvolvedScenario: (id, v) => evolvedScen[id] = v,
    getEvolutionCountFor: (_) => 0,
    setEvolutionCountFor: (_, _) {},
    getIsEvolvingCharacter: () => false,
    setIsEvolvingCharacter: (_) {},
    setEvolutionStatus: (_) {},
    setEvolutionError: (_) {},
    persistEvolvedForCharacter: (_, _, _, _) async {},
  );
}

void main() {
  group('Scene Guest evolution — persistence round-trip', () {
    test(
      'guest count + evolved text survive save/load alongside sceneGuests',
      () {
        final guest = _liteGuest('Mara');
        String charIdOf(CharacterCard c) => c.name.toLowerCase();
        final cid = charIdOf(guest);

        final json = buildGuestBlob(
          sceneGuestIds: ['guest-db-id-1'],
          guestCounts: {cid: 3},
          evolvedPers: {cid: 'Mara grew bolder'},
          evolvedScen: {cid: 'Mara now trusts the host'},
          guests: [guest],
          charIdOf: charIdOf,
        );

        // The legacy sceneGuests id list must remain intact.
        expect(json, contains('sceneGuests'));
        expect(json, contains('guest-db-id-1'));

        final loaded = parseGuestBlob(json);
        expect(loaded.sceneGuestIds, ['guest-db-id-1']);
        expect(loaded.counts[cid], 3);
        expect(loaded.pers[cid], 'Mara grew bolder');
        expect(loaded.scen[cid], 'Mara now trusts the host');
      },
    );

    test(
      'guest with no evolution yet omits the guestEvolution key entirely',
      () {
        final guest = _liteGuest('Mara');
        final json = buildGuestBlob(
          sceneGuestIds: ['g1'],
          guestCounts: const {},
          evolvedPers: const {},
          evolvedScen: const {},
          guests: [guest],
          charIdOf: (c) => c.name.toLowerCase(),
        );
        expect(json, isNot(contains('guestEvolution')));
        final loaded = parseGuestBlob(json);
        expect(loaded.sceneGuestIds, ['g1']);
        expect(loaded.counts, isEmpty);
        expect(loaded.pers, isEmpty);
      },
    );

    test(
      'a tracked participation count persists even before any evolved text',
      () {
        // A guest can have taken turns (count > 0) without yet crossing the
        // evolution interval; that cadence progress must survive a reload.
        final guest = _liteGuest('Mara');
        final cid = guest.name.toLowerCase();
        final json = buildGuestBlob(
          sceneGuestIds: ['g1'],
          guestCounts: {cid: 2},
          evolvedPers: const {},
          evolvedScen: const {},
          guests: [guest],
          charIdOf: (c) => c.name.toLowerCase(),
        );
        final loaded = parseGuestBlob(json);
        expect(loaded.counts[cid], 2);
        expect(loaded.pers[cid], isNull);
      },
    );

    test('only guests in the scene are written (no cross-guest leakage)', () {
      final mara = _liteGuest('Mara');
      final bram = _liteGuest('Bram');
      final json = buildGuestBlob(
        sceneGuestIds: ['m', 'b'],
        // Stale entry for a guest no longer in the scene must not be written.
        guestCounts: {'mara': 1, 'ghost': 9},
        evolvedPers: {'ghost': 'leaked'},
        evolvedScen: const {},
        guests: [mara, bram],
        charIdOf: (c) => c.name.toLowerCase(),
      );
      final loaded = parseGuestBlob(json);
      expect(loaded.counts.containsKey('ghost'), isFalse);
      expect(loaded.pers.containsKey('ghost'), isFalse);
      expect(loaded.counts['mara'], 1);
    });
  });

  group('Scene Guest evolution — APPLY layering (lite card, no Realism)', () {
    test(
      'lite guest evolved personality is layered with [Character Growth]',
      () {
        final guest = _liteGuest('Mara');
        final svc = _applyOnlyService(
          evolvedPers: {'mara': 'Mara has become protective'},
          evolvedScen: {},
        );
        final eff = svc.getEffectivePersonality(guest);
        expect(eff, contains('Guest desc'));
        expect(eff, contains('Guest pers'));
        expect(eff, contains('[Character Growth'));
        expect(eff, contains('Mara has become protective'));
      },
    );

    test('lite guest evolved scenario is layered with [Current Situation]', () {
      final guest = _liteGuest('Mara');
      final svc = _applyOnlyService(
        evolvedPers: {},
        evolvedScen: {'mara': 'Mara now lives at the inn'},
      );
      final eff = svc.getEffectiveScenario(guest);
      expect(eff, contains('Guest scen'));
      expect(eff, contains('[Current Situation'));
      expect(eff, contains('Mara now lives at the inn'));
    });

    test('no overlay when the guest has not evolved yet', () {
      final guest = _liteGuest('Mara');
      final svc = _applyOnlyService(evolvedPers: {}, evolvedScen: {});
      expect(
        svc.getEffectivePersonality(guest),
        isNot(contains('[Character Growth')),
      );
      expect(
        svc.getEffectiveScenario(guest),
        isNot(contains('[Current Situation')),
      );
    });
  });
}
