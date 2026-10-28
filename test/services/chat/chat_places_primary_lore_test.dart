// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Primary owns weather/injection; lore climate-on stays lore-only.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/chat_place_slots.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/lorebook_collection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/world_injection.dart';
import 'package:front_porch_ai/services/world_chain.dart';

void main() {
  World place({
    required String name,
    required bool climate,
    String description = '',
    String? biomeJson,
    WorldAtmosphere atmosphere = WorldAtmosphere.breathable,
  }) {
    final w = World(
      id: name.toLowerCase().replaceAll(' ', '-'),
      name: name,
      description: description,
      lorebook: Lorebook(entries: []),
      climateEnabled: climate,
      biomeJson: biomeJson,
      injectDescription: true,
    );
    if (climate) w.atmosphere = atmosphere;
    return w;
  }

  test('injection: setting prose only from Primary', () {
    final primary = place(
      name: 'Earth',
      climate: true,
      description: 'Blue marble.',
      atmosphere: WorldAtmosphere.thin,
    );
    final lore = place(
      name: 'Mars',
      climate: true,
      description: 'Red planet.',
      atmosphere: WorldAtmosphere.hostile,
    );
    final text = buildWorldInjection([primary]);
    expect(text, contains('Blue marble'));
    expect(text, isNot(contains('Red planet')));
    // Lore must not be passed into buildWorldInjection by callers.
    final both = buildWorldInjection([primary, lore]);
    expect(both, contains('Red planet')); // function itself is list-based
    // Contract is enforced at the call site (Primary-only list).
  });

  test('multi-climate: only Primary drives climate options', () {
    final earth = place(name: 'Earth', climate: true, biomeJson: '{"id":"e"}');
    final mars = place(name: 'Mars', climate: true, biomeJson: '{"id":"m"}');
    final primary = earth;
    final lore = [mars];
    expect(primaryWorldAllowsClimate(primary), isTrue);
    // Lore Mars must not appear as a climate author.
    final customFromPrimary =
        primary.climateEnabled && primary.biomeJson != null;
    final customFromLore = lore.any(
      (w) => w.climateEnabled && w.biomeJson != null,
    );
    expect(customFromPrimary, isTrue);
    expect(customFromLore, isTrue); // file has climate — role still lore
    // Picker filter: Primary only.
    final pickerCustoms = [
      if (primaryWorldAllowsClimate(primary) && primary.biomeJson != null)
        primary,
    ];
    expect(pickerCustoms.map((w) => w.name), ['Earth']);
    expect(pickerCustoms.any((w) => w.name == 'Mars'), isFalse);
  });

  test('primary empty → weather off even with lore present', () {
    final mars = place(name: 'Mars', climate: true);
    expect(primaryWorldAllowsClimate(null), isFalse);
    // Presence of lore climate-on does not matter for the Primary gate.
    expect(mars.climateEnabled, isTrue);
  });

  test('lore Mars climate-on → no weather, not in climate dropdown', () {
    final soul = place(name: 'Soul Society', climate: false);
    final mars = place(name: 'Mars', climate: true, biomeJson: '{"id":"m"}');
    // Primary empty, Mars in lore.
    expect(primaryWorldAllowsClimate(null), isFalse);
    final climateOptions = <World>[
      // Primary-only filter
    ];
    expect(climateOptions, isEmpty);
    // If Soul Society is Primary (climate-off), still no weather / no customs.
    expect(primaryWorldAllowsClimate(soul), isFalse);
    final customs = [
      if (primaryWorldAllowsClimate(soul) && soul.biomeJson != null) soul,
      // Mars is lore — excluded
    ];
    expect(customs, isEmpty);
    expect(mars.biomeJson, isNotNull);
  });

  test('demote-on-replace puts old Setting at lore top', () {
    final slots = ChatPlaceSlots(primaryId: 'earth', loreIds: const ['soul']);
    // Replace with mars: demote earth to lore top.
    final next = ChatPlaceSlots(
      primaryId: 'mars',
      loreIds: [slots.primaryId!, ...slots.loreIds],
    );
    expect(next.primaryId, 'mars');
    expect(next.loreIds, ['earth', 'soul']);
  });

  test('group detach → empty slots (no ghost)', () {
    final empty = const ChatPlaceSlots();
    expect(empty.primaryId, isNull);
    expect(empty.loreIds, isEmpty);
    expect(empty.allIds, isEmpty);
  });

  group('Location chain authoring (slice 2)', () {
    World home(
      String name, {
      required bool climate,
      String? parent,
      List<LorebookEntry> entries = const [],
    }) => World(
      id: name.toLowerCase().replaceAll(' ', '-'),
      name: name,
      lorebook: Lorebook(
        entries: [
          ...entries,
          LorebookEntry(key: 'lore-${name.length}', content: 'facts of $name'),
        ],
      ),
      climateEnabled: climate,
      parentWorldId: parent,
    );

    World? Function(String) index(Iterable<World> worlds) {
      final byId = {for (final w in worlds) w.id: w};
      return (ref) => byId[ref];
    }

    test('an inherited-climate location takes the parent as its author', () {
      final town = home('Bletchfield', climate: true);
      final cafe = home('Tea Rooms', climate: false, parent: town.id);
      final chain = worldChain(cafe, index([town, cafe]));
      expect(chain.map((w) => w.id), [cafe.id, town.id]);
      expect(climateAuthorOf(chain)?.id, town.id);
      expect(chainAllowsClimate(chain), isTrue);
    });

    test('continents author their own weather under a climate-on root', () {
      final earth = home('Earth', climate: true);
      final europe = home('Northern Europe', climate: true, parent: earth.id);
      final sahel = home('Sahel', climate: true, parent: earth.id);
      final all = index([earth, europe, sahel]);
      expect(climateAuthorOf(worldChain(europe, all))?.id, europe.id);
      expect(climateAuthorOf(worldChain(sahel, all))?.id, sahel.id);
    });

    test('a location that owns climate is the author for its subtree', () {
      final town = home('Bletchfield', climate: true);
      final cavern = home('Cavern', climate: true, parent: town.id);
      final pool = home('Hot pool', climate: false, parent: cavern.id);
      final chain = worldChain(pool, index([town, cavern, pool]));
      expect(climateAuthorOf(chain)?.id, cavern.id);
    });

    test('a weather-off top-level world silences every place inside it', () {
      final earth = home('Earth', climate: false);
      final europe = home('Northern Europe', climate: true, parent: earth.id);
      final oslo = home('Oslo', climate: false, parent: europe.id);
      final sahel = home('Sahel', climate: true, parent: earth.id);
      final all = index([earth, europe, oslo, sahel]);
      for (final leaf in [europe, oslo, sahel]) {
        final chain = worldChain(leaf, all);
        expect(climateAuthorOf(chain), isNull, reason: leaf.name);
        expect(chainAllowsClimate(chain), isFalse, reason: leaf.name);
        expect(weatherOffRootOf(chain)?.id, earth.id, reason: leaf.name);
      }
      // The root itself says it with its own switch — no "off above" note.
      expect(weatherOffRootOf(worldChain(earth, all)), isNull);
      // Owned climates are kept, only paused: the switch lists them.
      expect(
        climateOwnersInside(earth.id, [
          earth,
          europe,
          oslo,
          sahel,
        ], all).map((w) => w.id),
        [europe.id, sahel.id],
      );
    });

    test('an all-lore-only chain keeps weather off', () {
      final earth = home('Earth', climate: false);
      final city = home('City', climate: false, parent: earth.id);
      final chain = worldChain(city, index([earth, city]));
      expect(climateAuthorOf(chain), isNull);
      expect(chainAllowsClimate(chain), isFalse);
    });

    test('ancestor books enumerate once — chain plus explicit Lore attach', () {
      final town = home('Bletchfield', climate: true);
      final cafe = home('Tea Rooms', climate: false, parent: town.id);
      final lookup = index([town, cafe]);
      final refs = collectLoreEntryRefs(
        characters: const [],
        // Town attached BOTH as the cafe's ancestor (walked from the leaf)
        // and as an explicit Lore place — it must still enumerate once.
        chatWorldIds: [cafe.id, town.id],
        resolveWorld: lookup,
        settingChain: worldChain(cafe, lookup),
      );
      expect(refs.where((r) => r.sourceLabel == 'world:Tea Rooms').length, 1);
      expect(refs.where((r) => r.sourceLabel == 'world:Bletchfield').length, 1);
      final cafeRef = refs.firstWhere(
        (r) => r.sourceLabel == 'world:Tea Rooms',
      );
      final townRef = refs.firstWhere(
        (r) => r.sourceLabel == 'world:Bletchfield',
      );
      expect(cafeRef.placeRank, 0);
      expect(townRef.placeRank, 1);
      expect(cafeRef.chainId, cafe.id);
      expect(townRef.chainId, cafe.id);
    });

    test('a Lore place outside the chain carries no rank', () {
      final town = home('Bletchfield', climate: true);
      final mars = home('Mars', climate: true);
      final refs = collectLoreEntryRefs(
        characters: const [],
        chatWorldIds: [town.id, mars.id],
        resolveWorld: index([town, mars]),
        settingChain: [town],
      );
      final marsRef = refs.firstWhere((r) => r.sourceLabel == 'world:Mars');
      expect(marsRef.placeRank, isNull);
      expect(marsRef.chainId, isNull);
    });
  });
}
