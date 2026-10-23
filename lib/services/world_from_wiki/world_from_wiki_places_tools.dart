// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 8 (design §9.2/§9.4) tool contracts for the place half of
// World-from-Wiki: the scout's `places` array item, and the per-place
// profile call that replaces the single world-level climate pass.
// Split from world_from_wiki_tools.dart to keep that file off the
// 500-line bar.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/llm_service.dart';

import 'world_from_wiki_tools.dart';

import 'world_places.dart';

const String kWorldPlaceProfileToolName = 'write_place_profile';

/// The most places one scout may name. Design §9.2 said eight; the
/// maintainer's hand-built Bleach world has eleven, nested.
const int kWorldScoutPlaceMax = 12;

/// How many characters of each place source ride the profile prompt.
/// A people chapter is ~8k; two articles plus the tag evidence fit any
/// 8k window without squeezing the batch prompts elsewhere.
const int kWorldPlaceProfileSourceChars = 3000;

/// The scout's place item (referenced from worldScoutToolSchema).
Map<String, dynamic> worldPlaceItemSchema() {
  return {
    'type': 'object',
    'properties': {
      'name': {
        'type': 'string',
        'description': 'Place name, verbatim from a tag or chapter.',
      },
      'keys': {'description': 'Trigger words for the place, string or array.'},
      'sourceTitles': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            'Up to 4 index titles that describe this place (peoples and '
            'geography chapters).',
      },
      'parentName': {
        'type': 'string',
        'description':
            'Containing place from this same list (a tribe under its '
            'people), empty for a top-level nation.',
      },
      'climateHint': {
        'type': 'string',
        'description':
            'One line the sources imply — "mist-bound winter forest", '
            '"maritime". Plain words, never a biome id.',
      },
    },
    'required': ['name'],
  };
}

/// One call per place that the author flagged for its own weather, or
/// that carries a climate hint: a short description sized for the
/// Setting slot, and the authored biome when one is warranted.
List<Map<String, dynamic>> worldPlaceProfileToolSchema() {
  return [
    {
      'type': 'function',
      'function': {
        'name': kWorldPlaceProfileToolName,
        'description':
            'Write the profile of one place in this world: its short '
            'description (2–4 sentences, what a scene set there must '
            'know) and, only when the sources show a distinct climate, '
            'the weather for THAT place. Call once, after reading the '
            'supplied sources.',
        'parameters': {
          'type': 'object',
          'properties': {
            'description': {
              'type': 'string',
              'description':
                  '2–4 sentences. Concrete, in the world\'s own terms.',
            },
            'biome': {
              'type': 'object',
              'description':
                  'Omit when the place simply takes the world\'s weather.',
              'properties': {
                'displayName': {'type': 'string'},
                'temperatureBand': {'type': 'string'},
                'humidityBand': {'type': 'string'},
                'prevailingSky': {'type': 'string'},
                'windBand': {'type': 'string'},
                'seasonFeel': {'type': 'string'},
                'summary': {'type': 'string'},
              },
              'required': ['displayName', 'summary'],
            },
          },
          'required': ['description'],
        },
      },
    },
  ];
}

/// Places the scout named; junk entries are dropped, not fatal. The
/// catalog check is looser than for cards — a place name is usually a
/// tag, not a page title, so it rides verbatim.
List<WorldProposedPlace> parseWorldScoutPlaces(List<LlmToolCall> calls) {
  final out = <WorldProposedPlace>[];
  final seen = <String>{};
  for (final call in calls) {
    if (call.name != kWorldScoutToolName) continue;
    final raw = call.arguments['places'];
    if (raw is! List) continue;
    for (final item in raw.whereType<Map>()) {
      final place = WorldProposedPlace.tryParse(
        Map<String, dynamic>.from(item),
      );
      if (place == null) continue;
      if (!seen.add(place.key)) continue;
      out.add(place);
      if (out.length >= kWorldScoutPlaceMax) return out;
    }
  }
  return out;
}

/// One profile answer: description + optional validated biome (the
/// same Biome.fromJson gate the world-level climate pass uses).
({String description, Map<String, dynamic>? biome})? parseWorldPlaceProfileCall(
  List<LlmToolCall> calls, {
  required String expectTool,
}) {
  for (final call in calls) {
    if (call.name != expectTool) continue;
    final description = call.arguments['description']?.toString().trim() ?? '';
    if (description.isEmpty) continue;
    Map<String, dynamic>? biome;
    final raw = call.arguments['biome'];
    if (raw is Map) {
      final json = Map<String, dynamic>.from(raw);
      try {
        final parsed = Biome.fromJson(json);
        final problems = parsed.validate();
        if (problems.isEmpty) {
          biome = json;
        } else {
          // A refused biome must not vanish silently — it is the one
          // number a review can otherwise never see (same honesty law
          // as the world-level climate pass).
          debugPrint('[World] place biome refused: ${problems.join('; ')}');
        }
      } catch (e) {
        debugPrint('[World] place biome junk ($e)');
      }
    }
    return (description: description, biome: biome);
  }
  return null;
}
