// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/world_section_card.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';

/// The Book step's "How deep" card: Quick, Full or Deep as tiles with the
/// trade-off and a time estimate written on each, and the wizard's own
/// context as a row of pills. Both read the stored value so a change made
/// elsewhere (the phone) shows here on rebuild.
class BookDepthSection extends StatelessWidget {
  const BookDepthSection({
    super.key,
    required this.storage,
    required this.wide,
    required this.enabled,
    this.forCharacter = false,
  });

  final StorageService storage;
  final bool wide;
  final bool enabled;

  /// A chat source: Deep is not offered (a stored Deep shows as Full) and
  /// the tiles carry the chat's smaller counts and times.
  final bool forCharacter;

  List<WorldWikiDepth> get _depths => forCharacter
      ? const [WorldWikiDepth.quick, WorldWikiDepth.full]
      : WorldWikiDepth.values;

  @override
  Widget build(BuildContext context) {
    final muted = StudioColors.mutedOf(context);
    final stored = worldWizardDepth(storage);
    final depth = forCharacter ? worldCharacterDepth(stored) : stored;
    return WorldSectionCard(
      icon: Icons.layers_outlined,
      title: 'How deep',
      step: 3,
      of: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final cols = wide ? _depths.length : 1;
              final w = cols == 1
                  ? box.maxWidth
                  : (box.maxWidth - 10 * (cols - 1)) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final d in _depths)
                    SizedBox(width: w, child: _depthTile(context, d, depth)),
                ],
              );
            },
          ),
          if (forCharacter) ...[
            const SizedBox(height: 8),
            Text(
              kWorldCharacterNoDeepCopy,
              style: TextStyle(fontSize: 12, color: muted, height: 1.4),
            ),
          ],
          const SizedBox(height: 14),
          _contextRow(context),
          const SizedBox(height: 6),
          Text(
            'How much the model may read and write in one go. A bigger '
            'window lets a thinking model finish the card list in one '
            'piece; a smaller one has the index asked in parts.',
            style: TextStyle(fontSize: 12, color: muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _depthTile(BuildContext context, WorldWikiDepth d, WorldWikiDepth on) {
    final selected = d == on;
    final amber = StudioColors.amberOf(context);
    final ink = StudioColors.inkOf(context);
    final muted = StudioColors.mutedOf(context);
    final prose = StudioColors.proseOf(context);
    return WorldPickTile(
      key: Key('world-from-wiki-depth-${d.name}'),
      selected: selected,
      onTap: enabled
          ? () => storage.webSearchSettings.setWorldWikiDepth(d.index)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                d.label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: ink,
                ),
              ),
              const Spacer(),
              Text(
                forCharacter
                    ? '~${worldCharacterCardTarget(d)} cards'
                    : d.cardsLabel,
                style: TextStyle(fontSize: 12, color: selected ? amber : muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            forCharacter ? worldCharacterDepthBlurb(d) : d.blurb,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: selected ? prose : muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            forCharacter ? worldCharacterDepthTime(d) : d.timeHint,
            style: TextStyle(fontSize: 12, color: prose),
          ),
        ],
      ),
    );
  }

  Widget _contextRow(BuildContext context) {
    final value = storage.webSearchSettings.worldWikiContextSize;
    final chat = storage.backendSettings.contextSize;
    final choices = [...kWorldWikiContextChoices];
    if (value != 0 && !choices.contains(value)) choices.add(value);
    choices.sort();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            'Context for this wizard',
            style: TextStyle(
              fontSize: 13,
              color: StudioColors.mutedOf(context),
            ),
          ),
        ),
        WorldPill(
          key: const Key('world-from-wiki-context-0'),
          text: 'Same as chat (${worldWikiContextLabel(chat)})',
          selected: value == 0,
          onTap: enabled
              ? () => storage.webSearchSettings.setWorldWikiContextSize(0)
              : null,
        ),
        for (final c in choices)
          WorldPill(
            key: Key('world-from-wiki-context-$c'),
            text: worldWikiContextLabel(c),
            selected: value == c,
            onTap: enabled
                ? () => storage.webSearchSettings.setWorldWikiContextSize(c)
                : null,
          ),
      ],
    );
  }
}
