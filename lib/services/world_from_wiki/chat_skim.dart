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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/llm_service.dart';

import 'world_chat_record.dart';
import 'world_craft_mechanics.dart';
import 'world_from_wiki_budget.dart';
import 'world_from_wiki_ops.dart';
import 'world_progress_copy.dart';

/// The Skim's tool: the named things one part of the chat shows.
const String kWorldSkimToolName = 'skim_chat';

/// Names one part may list at most; the parts merge after.
const int kWorldSkimNamesPerPart = 20;

/// One named thing the chat shows, merged across the parts that name it.
class WorldSkimName {
  WorldSkimName({
    required this.name,
    required this.kind,
    this.aliases = const [],
    this.parent = '',
    this.note = '',
    this.mentions = 1,
    Set<int>? parts,
  }) : parts = parts ?? {};

  final String name;

  /// One of [kWorldCardKinds]; the Skim maps anything else to concept.
  final String kind;
  final List<String> aliases;

  /// The place this lies inside when the chat says so ("the Tea Rooms in
  /// Bletchfield"); '' otherwise.
  final String parent;

  /// One line of what it is, in the chat's own words.
  final String note;

  /// How many parts named it: the index is ranked by this.
  int mentions;
  final Set<int> parts;

  String get key => name.trim().toLowerCase();

  /// Whether [other] is the same thing under another spelling.
  bool matches(WorldSkimName other) {
    final mine = {key, for (final a in aliases) a.trim().toLowerCase()};
    final theirs = {
      other.key,
      for (final a in other.aliases) a.trim().toLowerCase(),
    };
    return mine.intersection(theirs).isNotEmpty;
  }

  WorldSkimName merged(WorldSkimName other) => WorldSkimName(
    name: name,
    kind: kind,
    aliases: {
      ...aliases,
      if (other.name.trim().toLowerCase() != key) other.name.trim(),
      ...other.aliases,
    }.toList(),
    parent: parent.isNotEmpty ? parent : other.parent,
    note: note.isNotEmpty ? note : other.note,
    mentions: mentions + other.mentions,
    parts: {...parts, ...other.parts},
  );
}

/// What a whole Skim produced.
class WorldSkimResult {
  const WorldSkimResult({
    required this.names,
    required this.weather,
    required this.parts,
  });

  /// Named things, most-mentioned first.
  final List<WorldSkimName> names;

  /// The weather and season words each part showed; '' for none.
  final List<String> weather;
  final int parts;

  bool get hasWeather => weather.any((w) => w.trim().isNotEmpty);
}

List<Map<String, dynamic>> worldSkimToolSchema() => [
  {
    'type': 'function',
    'function': {
      'name': kWorldSkimToolName,
      'description':
          'Index one stretch of a roleplay chat: every named place, '
          'faction, event, concept, race, item and side person it shows, '
          'as the chat has them. Never the main character and never the '
          'user. Nothing invented.',
      'parameters': {
        'type': 'object',
        'properties': {
          'names': {
            'type': 'array',
            'description': 'Up to $kWorldSkimNamesPerPart named things.',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'kind': {'type': 'string', 'enum': kWorldCardKinds},
                'aliases': {
                  'description':
                      'Other spellings the chat uses, string or array.',
                },
                'parent': {
                  'type': 'string',
                  'description':
                      'For a place: the place it lies inside when the '
                      'text says so; else empty.',
                },
                'note': {
                  'type': 'string',
                  'description': 'One line of what it is, from the chat alone.',
                },
              },
              'required': ['name', 'kind'],
            },
          },
          'weather': {
            'type': 'string',
            'description':
                'The weather and season words this stretch shows, or '
                'empty.',
          },
        },
        'required': ['names'],
      },
    },
  },
];

/// The names the Skim must never list, lowercase: the character, the
/// user, and their first names.
Set<String> worldSkimExclusions(String characterName, String userName) {
  final out = <String>{'user', 'you', kWorldUserMacro.toLowerCase()};
  for (final n in [characterName, userName]) {
    final full = n.trim().toLowerCase();
    if (full.isEmpty) continue;
    out.add(full);
    final first = full.split(RegExp(r'\s+')).first;
    if (first.length > 2) out.add(first);
  }
  return out;
}

String worldSkimPrompt({
  required String characterName,
  required int index,
  required int total,
  required int from,
  required int to,
  required String notes,
  required String chunk,
}) =>
    'You are indexing a roleplay chat so a world can be built from it. '
    'CHARACTER: $characterName — never list them. The user is '
    '$kWorldUserMacro — never list them.\n'
    'PART $index of $total (messages $from to $to):\n'
    '${notes.isEmpty ? '' : '$notes\n'}'
    '$chunk\n\n'
    'Call $kWorldSkimToolName once: every named place, faction, event, '
    'concept, race, item and side person this stretch shows, one line '
    'each as the chat has it (nothing invented), the aliases the chat '
    'uses, the parent place when the text says where a place lies, and '
    'the weather or season words if any. Up to $kWorldSkimNamesPerPart.';

/// The names and weather one part answered, [exclude]d names dropped.
({List<WorldSkimName> names, String weather}) parseWorldSkimCalls(
  List<LlmToolCall> calls, {
  required Set<String> exclude,
  required int part,
}) {
  final names = <WorldSkimName>[];
  var weather = '';
  for (final call in calls) {
    if (call.name != kWorldSkimToolName) continue;
    final w = call.arguments['weather']?.toString().trim() ?? '';
    if (w.isNotEmpty && weather.isEmpty) weather = w;
    final raw = call.arguments['names'];
    if (raw is! List) continue;
    for (final item in raw) {
      if (item is! Map) continue;
      final name = item['name']?.toString().trim() ?? '';
      if (name.isEmpty || exclude.contains(name.toLowerCase())) continue;
      final kindRaw = item['kind']?.toString().trim().toLowerCase() ?? '';
      final aliases = _strings(item['aliases'])
        ..removeWhere(
          (a) =>
              a.toLowerCase() == name.toLowerCase() ||
              exclude.contains(a.toLowerCase()),
        );
      names.add(
        WorldSkimName(
          name: name,
          kind: kWorldCardKinds.contains(kindRaw) ? kindRaw : 'concept',
          aliases: aliases,
          parent: item['parent']?.toString().trim() ?? '',
          note: item['note']?.toString().trim() ?? '',
          parts: {part},
        ),
      );
      if (names.length >= kWorldSkimNamesPerPart) break;
    }
  }
  return (names: names, weather: weather);
}

/// Every part's names as one list, the same thing under two spellings
/// merged, most-mentioned first.
List<WorldSkimName> mergeWorldSkimNames(Iterable<List<WorldSkimName>> parts) {
  final out = <WorldSkimName>[];
  for (final list in parts) {
    for (final n in list) {
      final i = out.indexWhere((o) => o.matches(n));
      if (i < 0) {
        out.add(n);
      } else {
        out[i] = out[i].merged(n);
      }
    }
  }
  out.sort((a, b) => b.mentions.compareTo(a.mentions));
  return out;
}

List<String> _strings(dynamic raw) {
  if (raw is List) {
    return [
      for (final e in raw)
        if (e != null && e.toString().trim().isNotEmpty) e.toString().trim(),
    ];
  }
  if (raw is String) {
    return [
      for (final p in raw.split(','))
        if (p.trim().isNotEmpty) p.trim(),
    ];
  }
  return [];
}

/// Runs the Skim: one tool call per part of [record], each with that
/// stretch's Journal and Growth notes, the parts merged after. Progress
/// goes through [onProgress] like every other pass.
Future<WorldSkimResult> runWorldSkim(
  WorldChatRecord record, {
  required LLMService llm,
  required WorldWikiBudget budget,
  String userName = '',
  void Function(String message)? onProgress,
  Duration callTimeout = kWorldToolCallTimeout,
  Duration retryPause = const Duration(seconds: 2),
  bool Function()? isAborted,
}) async {
  final chunks = record.chunks;
  final memory = record.memory();
  final exclude = worldSkimExclusions(record.characterName, userName);
  onProgress?.call(
    worldProgressSkimPlan(
      record.messageCount,
      chunks.length,
      record.objectives.length,
    ),
  );
  final partNames = <List<WorldSkimName>>[];
  final weather = <String>[];
  for (var i = 0; i < chunks.length; i++) {
    if (isAborted?.call() ?? false) break;
    final chunk = chunks[i];
    final start = i * kWorldSkimChunk;
    onProgress?.call(
      worldProgressSkimPart(
        i + 1,
        chunks.length,
        start + 1,
        start + chunk.length,
      ),
    );
    final notes = memory.chunkNotes(start, start + chunk.length);
    final head = worldSkimPrompt(
      characterName: record.characterName,
      index: i + 1,
      total: chunks.length,
      from: start + 1,
      to: start + chunk.length,
      notes: notes,
      chunk: '',
    );
    final text = budget.clipForReply(
      [for (final l in chunk) '${l.sender}: ${l.text}'].join('\n'),
      want: 1024,
      fixedTokens: worldWikiEstimateTokens(head) + 64,
    );
    final prompt = worldSkimPrompt(
      characterName: record.characterName,
      index: i + 1,
      total: chunks.length,
      from: start + 1,
      to: start + chunk.length,
      notes: notes,
      chunk: text,
    );
    final resp = await askToolsTwice(
      llm,
      params: GenerationParams(
        prompt: prompt,
        maxLength: budget.replyFor(prompt, floor: 1024),
        minLength: 16,
        temperature: 0.2,
        reasoningEnabled: true,
        toolChoice: kWorldSkimToolName,
      ),
      tools: worldSkimToolSchema(),
      label: 'skim part ${i + 1}',
      note: onProgress,
      toolName: kWorldSkimToolName,
      floorKey: 'names',
      pause: retryPause,
      timeout: callTimeout,
    );
    if (resp == null) {
      debugPrint('[World] skim part ${i + 1}: no answer');
      weather.add('');
      continue;
    }
    final got = parseWorldSkimCalls(resp.calls, exclude: exclude, part: i);
    partNames.add(got.names);
    weather.add(got.weather);
    onProgress?.call(
      worldProgressSkimDone(
        i + 1,
        chunks.length,
        got.names.length,
        got.names.map((n) => n.name).take(6).join(', '),
      ),
    );
    if (got.weather.isNotEmpty) {
      onProgress?.call(worldProgressSkimWeather(got.weather));
    }
  }
  final names = mergeWorldSkimNames(partNames);
  onProgress?.call(worldProgressSkimReady(names.length));
  return WorldSkimResult(names: names, weather: weather, parts: chunks.length);
}
