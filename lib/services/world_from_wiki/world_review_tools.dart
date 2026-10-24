// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The reviewers' tool contracts: one verdict on the shelf as a world, one
// verdict per written entry. Each reply is a tool call with the fields
// the loop feeds back; the text floor reads the same JSON out of prose.

import 'package:front_porch_ai/services/llm_service.dart';

import 'world_review_loop.dart';

const String kWorldShelfReviewToolName = 'review_world_shelf';
const String kWorldEntriesReviewToolName = 'review_lorebook_entries';

/// The shelf reviewer: a world, not a list, as of the Moment.
List<Map<String, dynamic>> worldShelfReviewToolSchema() {
  return [
    {
      'type': 'function',
      'function': {
        'name': kWorldShelfReviewToolName,
        'description':
            'Judge a proposed lorebook shelf as a roleplay world: nested '
            'places, each with its own residents; factions with members; '
            'the era as of the given moment; nothing invented. Pass only a '
            'shelf a fan of this setting would accept.',
        'parameters': {
          'type': 'object',
          'properties': {
            'pass': {'type': 'boolean'},
            'problems': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Each problem in one sentence the author can act on: what '
                  'is missing, misplaced, invented or out of its time.',
            },
            'missing': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Index titles that belong on this shelf and are not on it.',
            },
          },
          'required': ['pass', 'problems'],
        },
      },
    },
  ];
}

/// The entries reviewer: one verdict per entry, by name.
List<Map<String, dynamic>> worldEntriesReviewToolSchema() {
  return [
    {
      'type': 'function',
      'function': {
        'name': kWorldEntriesReviewToolName,
        'description':
            'Judge written lorebook entries for roleplay: each as of the '
            'moment with nothing later stated, scene-usable (a person\'s look '
            'and manner and whereabouts; a place\'s sights and who holds it), '
            'two sentences, keys that are its own names, nothing not in the '
            'article. Fail an entry only for a reason the writer can fix.',
        'parameters': {
          'type': 'object',
          'properties': {
            'verdicts': {
              'type': 'array',
              'items': {
                'type': 'object',
                'properties': {
                  'name': {'type': 'string'},
                  'pass': {'type': 'boolean'},
                  'problems': {
                    'type': 'array',
                    'items': {'type': 'string'},
                  },
                },
                'required': ['name', 'pass'],
              },
            },
          },
          'required': ['verdicts'],
        },
      },
    },
  ];
}

/// The shelf verdict from the reviewer's call; [missing] titles fold into
/// the problems so the revise sees them.
WorldVerdict parseWorldShelfVerdict(List<LlmToolCall> calls) {
  for (final call in calls) {
    if (call.name != kWorldShelfReviewToolName) continue;
    final pass = call.arguments['pass'];
    final problems = _strings(call.arguments['problems']);
    final missing = _strings(call.arguments['missing']);
    if (missing.isNotEmpty) {
      problems.add('missing from the shelf: ${missing.join(', ')}');
    }
    if (pass is bool) {
      return WorldVerdict(pass: pass && problems.isEmpty, problems: problems);
    }
    if (problems.isNotEmpty) {
      return WorldVerdict(pass: false, problems: problems);
    }
  }
  return WorldVerdict.skipped;
}

/// Per-entry verdicts by entry name (lower-cased); an entry the reviewer
/// did not name is taken as passed.
Map<String, WorldVerdict> parseWorldEntryVerdicts(List<LlmToolCall> calls) {
  final out = <String, WorldVerdict>{};
  for (final call in calls) {
    if (call.name != kWorldEntriesReviewToolName) continue;
    final raw = call.arguments['verdicts'];
    if (raw is! List) continue;
    for (final v in raw) {
      if (v is! Map) continue;
      final name = v['name']?.toString().trim().toLowerCase() ?? '';
      if (name.isEmpty) continue;
      final pass = v['pass'];
      final problems = _strings(v['problems']);
      out[name] = WorldVerdict(
        pass: pass is bool ? pass && problems.isEmpty : problems.isEmpty,
        problems: problems,
      );
    }
  }
  return out;
}

List<String> _strings(dynamic raw) {
  if (raw is List) {
    return [
      for (final e in raw)
        if (e != null && e.toString().trim().isNotEmpty) e.toString().trim(),
    ];
  }
  if (raw is String && raw.trim().isNotEmpty) return [raw.trim()];
  return [];
}

/// What the entry loop did to one entry, for the Review step: how many
/// tries it took, whether it passed, and the last finding against it.
class WorldEntryNote {
  const WorldEntryNote({
    required this.tries,
    required this.passed,
    this.problem = '',
  });

  final int tries;
  final bool passed;
  final String problem;

  Map<String, dynamic> toJson() => {
    'tries': tries,
    'passed': passed,
    if (problem.isNotEmpty) 'problem': problem,
  };

  static WorldEntryNote? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final tries = raw['tries'];
    return WorldEntryNote(
      tries: tries is int ? tries : int.tryParse('$tries') ?? 1,
      passed: raw['passed'] != false,
      problem: raw['problem']?.toString() ?? '',
    );
  }
}

/// "Passed first try", "Rewritten once · said how the war ends",
/// "Still failing after 3 tries · …": one line under the entry.
String worldEntryNoteCopy(WorldEntryNote? note) {
  if (note == null) return 'Written without a reviewer';
  final why = note.problem.isEmpty ? '' : ' · ${note.problem}';
  if (note.passed) {
    if (note.tries <= 1) return 'Passed first try';
    if (note.tries == 2) return 'Rewritten once$why';
    return 'Passed on try ${note.tries}$why';
  }
  return 'Still failing after ${note.tries} '
      '${note.tries == 1 ? 'try' : 'tries'}$why';
}
