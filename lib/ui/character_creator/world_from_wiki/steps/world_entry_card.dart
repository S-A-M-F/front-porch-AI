// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_review_actions.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/status_colors.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// One written entry on the Review step: its text and keys editable in
/// place, the reviewer's verdict, Rewrite with a note, Drop, and Keep.
class WorldEntryCard extends StatefulWidget {
  const WorldEntryCard({super.key, required this.state, required this.entry});

  final WorldFromWikiState state;
  final LorebookEntry entry;

  @override
  State<WorldEntryCard> createState() => _WorldEntryCardState();
}

class _WorldEntryCardState extends State<WorldEntryCard> {
  late final TextEditingController _content = TextEditingController(
    text: widget.entry.content,
  );
  final _note = TextEditingController();
  final _newKey = TextEditingController();
  bool _noteOpen = false;
  bool _keyOpen = false;

  String get _name => widget.entry.name;

  @override
  void didUpdateWidget(covariant WorldEntryCard old) {
    super.didUpdateWidget(old);
    // A rewrite replaced the entry: show its new text, not the old field.
    if (widget.entry.content != old.entry.content &&
        _content.text != widget.entry.content) {
      _content.text = widget.entry.content;
      _noteOpen = false;
      _note.clear();
    }
  }

  @override
  void dispose() {
    _content.dispose();
    _note.dispose();
    _newKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final e = widget.entry;
    final pinned = state.isPinned(_name);
    final card = state.engine?.shelfCards[_name.trim().toLowerCase()];
    final kind = [
      if (card != null && card.kind.isNotEmpty) card.kind,
      if (card != null) card.role.name,
    ].join(' · ');
    final ink = StudioColors.inkOf(context);
    final muted = StudioColors.mutedOf(context);
    final line = StudioColors.lineOf(context);
    final amber = StudioColors.amberOf(context);
    return Opacity(
      opacity: pinned ? 0.85 : 1,
      child: Container(
        key: Key('world-entry-$_name'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: StudioColors.cardOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _noteOpen ? amber : line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    e.name,
                    style: TextStyle(fontWeight: FontWeight.w700, color: ink),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (kind.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _chip(context, kind),
                ],
                const SizedBox(width: 8),
                IconButton(
                  key: Key('world-entry-pin-$_name'),
                  tooltip: pinned
                      ? 'Kept as it is; press to unpin'
                      : 'Keep this card as it is',
                  onPressed: state.busy ? null : () => state.togglePin(_name),
                  icon: Icon(
                    pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 18,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: pinned ? amber : null,
                    foregroundColor: pinned
                        ? StudioColors.bgOf(context)
                        : muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: pinned ? amber : line),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _keys(context),
            const SizedBox(height: 8),
            TextField(
              key: Key('world-entry-content-$_name'),
              controller: _content,
              minLines: 2,
              maxLines: 6,
              enabled: !state.busy,
              style: TextStyle(color: ink, height: 1.45),
              onChanged: (v) => state.editEntry(_name, content: v),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: StudioColors.bgOf(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _verdict(context, pinned),
            if (_noteOpen) ...[const SizedBox(height: 8), _noteBox(context)],
            const SizedBox(height: 6),
            Row(
              children: [
                if (!_noteOpen)
                  TextButton(
                    key: Key('world-entry-rewrite-$_name'),
                    onPressed: state.busy
                        ? null
                        : () => setState(() => _noteOpen = true),
                    style: TextButton.styleFrom(foregroundColor: amber),
                    child: const Text('Rewrite…'),
                  ),
                TextButton(
                  key: Key('world-entry-drop-$_name'),
                  onPressed: state.busy ? null : () => state.dropEntry(_name),
                  style: TextButton.styleFrom(foregroundColor: muted),
                  child: const Text('Drop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _keys(BuildContext context) {
    final state = widget.state;
    final keys = widget.entry.keys;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final k in keys)
          InputChip(
            label: Text(k, style: const TextStyle(fontSize: 12)),
            onDeleted: state.busy
                ? null
                : () => state.editEntry(
                    _name,
                    keys: [
                      for (final x in keys)
                        if (x != k) x,
                    ],
                  ),
            visualDensity: VisualDensity.compact,
          ),
        if (_keyOpen)
          SizedBox(
            width: 160,
            child: TextField(
              key: Key('world-entry-new-key-$_name'),
              controller: _newKey,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'a name a chat would say',
              ),
              onSubmitted: (v) {
                final key = v.trim();
                if (key.isNotEmpty) {
                  state.editEntry(_name, keys: [...keys, key]);
                }
                _newKey.clear();
                setState(() => _keyOpen = false);
              },
            ),
          )
        else
          ActionChip(
            label: const Text('+ key', style: TextStyle(fontSize: 12)),
            onPressed: state.busy
                ? null
                : () => setState(() => _keyOpen = true),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _verdict(BuildContext context, bool pinned) {
    final note = widget.state.noteFor(_name);
    final String text;
    final IconData icon;
    final Color color;
    if (pinned) {
      text = 'Kept as it is · a send-back never touches it';
      icon = Icons.push_pin;
      color = StudioColors.mutedOf(context);
    } else if (note == null) {
      text = worldEntryNoteCopy(null);
      icon = Icons.edit_outlined;
      color = StudioColors.mutedOf(context);
    } else if (!note.passed) {
      text = worldEntryNoteCopy(note);
      icon = Icons.error_outline;
      color = StatusColors.warningOf(context);
    } else if (note.tries > 1) {
      text = worldEntryNoteCopy(note);
      icon = Icons.refresh;
      color = StatusColors.cautionOf(context);
    } else {
      text = worldEntryNoteCopy(note);
      icon = Icons.check;
      color = StatusColors.successOf(context);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            key: Key('world-entry-verdict-$_name'),
            style: TextStyle(fontSize: 12, color: color, height: 1.35),
          ),
        ),
      ],
    );
  }

  Widget _noteBox(BuildContext context) {
    final state = widget.state;
    final amber = StudioColors.amberOf(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioColors.bgOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rewrite this card with a note',
            style: TextStyle(
              fontSize: 12,
              color: StudioColors.mutedOf(context),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            key: Key('world-entry-note-$_name'),
            controller: _note,
            minLines: 2,
            maxLines: 4,
            autofocus: true,
            style: TextStyle(color: StudioColors.inkOf(context), fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText:
                  'e.g. Say they were sealed in the palace by Yhwach\'s '
                  'order, and name Senjumaru\'s role.',
              hintStyle: TextStyle(color: StudioColors.mutedOf(context)),
              filled: true,
              fillColor: StudioColors.cardOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                key: Key('world-entry-rewrite-send-$_name'),
                onPressed: state.busy
                    ? null
                    : () {
                        final note = _note.text.trim();
                        if (note.isEmpty) return;
                        state.rewriteEntry(_name, note);
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: amber,
                  foregroundColor: StudioColors.bgOf(context),
                ),
                child: const Text('Rewrite this card'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() {
                  _noteOpen = false;
                  _note.clear();
                }),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: StudioColors.raiseOf(context),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: StudioColors.lineOf(context)),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: StudioColors.proseOf(context)),
    ),
  );
}
