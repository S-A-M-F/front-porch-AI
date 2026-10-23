// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The place-mint tool contract (slice 7): one schema, its fields, its
// list — extracted from realism_tool_schemas.dart, which the 500-line
// ratchet keeps for the per-turn eval tools. Registered into
// realismToolFieldsByTool from that file; the name lives in
// realism_tool_names.dart like every other tool.

import 'package:front_porch_ai/services/chat/realism_tools/realism_tool_names.dart';


// The two schema helpers this file needs, local: the ratchet split keeps
// the per-turn schemas file whole rather than widening its privates.
Map<String, dynamic> _strField(String description) => {
  'type': 'string',
  'description': description,
};
Map<String, dynamic> _tool(
  String name,
  String description,
  Map<String, Map<String, dynamic>> fields,
  List<String> required,
) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': description,
    'parameters': {
      'type': 'object',
      'properties': fields,
      'required': required,
    },
  },
};

final Map<String, Map<String, dynamic>> kPlaceMintFields = {
  'short_description': _strField(
    'A SHORT description of this place (one or two sentences), sized to fit '
    'inside a 600-character scene-setting budget. Ground it in the narration.',
  ),
  'lore_entries': {
    'type': 'array',
    'description':
        'Three to five lore entries that make this place specific. Each entry '
        'has a name, comma-separated trigger keys, and content text grounded in '
        'the narration.',
    'items': {
      'type': 'object',
      'properties': {
        'name': _strField('Display name of the entry.'),
        'keys': _strField(
          'Comma-separated trigger keywords for this entry (e.g. "gate,iron,door").',
        ),
        'content': _strField('The lore text injected when a key matches.'),
      },
    },
  },
};

/// The schema list used by [fireStructuredEval] for the place-mint transport.
final List<Map<String, dynamic>> kPlaceMintTools = [
  _tool(
    kPlaceMintTool,
    'Report a drafted place for the scene: a short description and 3–5 lore entries.',
    kPlaceMintFields,
    const [],
  ),
];

