// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_review_actions.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// What the reviewers did this run, in plain lines; empty when every
/// entry passed first time and the shelf was never sent back.
List<String> worldReviewFindings(WorldFromWikiState state) {
  final lines = <String>[];
  if (state.shelfNotes.isNotEmpty) {
    final first = state.shelfNotes.first;
    final short = first.contains(';') ? first.split(';').first : first;
    lines.add(
      state.shelfRevised
          ? 'The shelf was sent back and revised: $short.'
          : 'The shelf reviewer noted: $short.',
    );
  }
  final notes = state.engine?.entryNotes.values ?? const <WorldEntryNote>[];
  final total = notes.length;
  if (total > 0) {
    final rewritten = notes.where((n) => n.passed && n.tries > 1).length;
    final failing = notes.where((n) => !n.passed).length;
    if (rewritten > 0) {
      lines.add(
        '$rewritten of $total entries ${rewritten == 1 ? 'was' : 'were'} '
        'rewritten by the entry reviewer.',
      );
    }
    if (failing > 0) {
      lines.add(
        '$failing ${failing == 1 ? 'entry is' : 'entries are'} still '
        'marked by the reviewer; the last try stands.',
      );
    }
  }
  return lines;
}

/// The Review step's head: the reviewers' findings, and the author's
/// direction box with its scope and the send-back button.
class WorldDirectionBox extends StatefulWidget {
  const WorldDirectionBox({super.key, required this.state});

  final WorldFromWikiState state;

  @override
  State<WorldDirectionBox> createState() => _WorldDirectionBoxState();
}

class _WorldDirectionBoxState extends State<WorldDirectionBox> {
  bool _findingsOpen = true;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final findings = worldReviewFindings(state);
    final ink = StudioColors.inkOf(context);
    final muted = StudioColors.mutedOf(context);
    final line = StudioColors.lineOf(context);
    final amber = StudioColors.amberOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: BoxDecoration(
            color: StudioColors.cardOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: amber),
                  const SizedBox(width: 10),
                  Text(
                    'What the reviewers did this run',
                    style: TextStyle(fontWeight: FontWeight.w700, color: ink),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        setState(() => _findingsOpen = !_findingsOpen),
                    child: Text(_findingsOpen ? 'Hide' : 'Show'),
                  ),
                ],
              ),
              if (_findingsOpen) ...[
                const SizedBox(height: 6),
                if (findings.isEmpty)
                  Text(
                    'Every entry passed the reviewer first time, and the '
                    'shelf was never sent back.',
                    key: const Key('world-review-findings'),
                    style: TextStyle(color: StudioColors.proseOf(context)),
                  )
                else
                  for (final f in findings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '•  $f',
                        key: const Key('world-review-findings'),
                        style: TextStyle(
                          color: StudioColors.proseOf(context),
                          height: 1.45,
                        ),
                      ),
                    ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: StudioColors.cardOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: amber),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your direction',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'In your own words. Your note goes into the same loop the '
                'reviewers use: the cards it names are rewritten and reviewed '
                'again, a card it asks for is written from its page, the rest '
                'stay as they are.',
                style: TextStyle(color: muted, fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('world-from-wiki-direction'),
                controller: state.directionController,
                minLines: 3,
                maxLines: 6,
                enabled: !state.busy,
                style: TextStyle(color: ink),
                decoration: InputDecoration(
                  hintText:
                      'e.g. The Royal Guard card should name all four, not '
                      'just Ichibe. Karakura needs the Kurosaki Clinic. Less '
                      'about Aizen, he is sealed.',
                  hintStyle: TextStyle(color: muted),
                  filled: true,
                  fillColor: StudioColors.bgOf(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              RadioGroup<bool>(
                groupValue: state.directionWholeWorld,
                onChanged: (v) {
                  if (state.busy) return;
                  state.directionWholeWorld = v ?? false;
                  state.notify();
                },
                child: Wrap(
                  spacing: 18,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Apply to',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                    _scope(context, 'The cards my note names', false),
                    _scope(context, 'The whole world', true),
                    ListenableBuilder(
                      listenable: state.directionController,
                      builder: (context, _) {
                        final canSend =
                            !state.busy &&
                            state.directionController.text.trim().isNotEmpty;
                        return OutlinedButton.icon(
                          key: const Key('world-from-wiki-send-back'),
                          onPressed: canSend
                              ? () => state.sendBackAround(
                                  state.directionController.text,
                                  wholeWorld: state.directionWholeWorld,
                                )
                              : null,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Send it back around'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: amber,
                            side: BorderSide(color: amber, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _scope(BuildContext context, String label, bool wholeWorld) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<bool>(
          value: wholeWorld,
          activeColor: StudioColors.amberOf(context),
        ),
        Text(label, style: TextStyle(color: StudioColors.inkOf(context))),
      ],
    );
  }
}
