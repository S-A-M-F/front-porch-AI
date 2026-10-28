// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Dart gate on written entries: what a model gets wrong in keys and
// length that no second model call is needed to fix. The first live Bleach
// world had 70 keys that were other entries' names (Soul Society fired on
// "Gotei 13") and keys like "selection" that fire in any sentence.

import 'world_craft_mechanics.dart';
import 'world_from_wiki_tools.dart';

/// A single lowercase word this long or shorter is treated as a common
/// word, never a lore trigger, unless it is the entry's own name.
const int kWorldKeyCommonWordMax = 12;

/// Keys an entry may keep: its own names and aliases. A key that is
/// another entry's name is dropped (that entry has it), a single common
/// lowercase word is dropped, the entry's name is always first, and at
/// most [kWorldLoreKeysMax] remain. Never empty: the name stays.
List<String> polishWorldKeys(
  String name,
  List<String> keys, {
  required Set<String> otherNamesLower,
}) {
  final own = name.trim();
  final ownLower = own.toLowerCase();
  final out = <String>[];
  final seen = <String>{};
  void add(String k) {
    final t = k.trim();
    if (t.isEmpty || !seen.add(t.toLowerCase())) return;
    out.add(t);
  }

  if (own.isNotEmpty) add(own);
  for (final k in keys) {
    final t = k.trim();
    final lower = t.toLowerCase();
    if (t.isEmpty || lower == ownLower) continue;
    if (otherNamesLower.contains(lower)) continue;
    if (_isCommonWord(t)) continue;
    add(t);
  }
  return out.take(kWorldLoreKeysMax).toList();
}

bool _isCommonWord(String key) {
  if (key.contains(' ') || key.contains('-') || key.contains("'")) {
    return false;
  }
  if (key.length > kWorldKeyCommonWordMax) return false;
  return RegExp(r'^[a-z]+$').hasMatch(key);
}

/// Problems with one written entry that only a rewrite can fix; the
/// entry loop feeds them back. Empty when the entry passes the gate.
List<String> worldEntryGate(WorldCraftDraft draft) {
  final problems = <String>[];
  final len = draft.content.trim().length;
  if (len < kWorldLoreContentMin) {
    problems.add(
      '${draft.name}: $len characters; write two full sentences '
      '($kWorldLoreContentMin–$kWorldLoreContentMax)',
    );
  }
  if (draft.content.contains('{{')) {
    problems.add('${draft.name}: template braces in the text');
  }
  return problems;
}

/// The drafts of one book with their keys polished against the names of
/// every card on the shelf.
List<WorldCraftDraft> polishWorldDrafts(
  List<WorldCraftDraft> drafts, {
  required Iterable<String> allNames,
}) {
  final names = {for (final n in allNames) n.trim().toLowerCase()};
  return [
    for (final d in drafts)
      WorldCraftDraft(
        name: d.name,
        keys: polishWorldKeys(
          d.name,
          d.keys,
          otherNamesLower: {...names}..remove(d.name.trim().toLowerCase()),
        ),
        content: d.content,
        role: d.role,
        group: d.group,
      ),
  ];
}
