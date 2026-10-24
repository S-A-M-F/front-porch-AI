// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/book_depth_section.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/book_wiki_section.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/world_progress_panel.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/world_section_card.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The Book step as four cards with a job each — the world, the wiki, how
/// deep, what to make — and, while Scout runs, the progress card above a
/// dimmed form. From the approved uplift sketch; every colour is the
/// theme's.
class WorldFromWikiBookStep extends StatelessWidget {
  const WorldFromWikiBookStep({super.key, required this.state});

  final WorldFromWikiState state;

  Future<void> _attach(BuildContext context) async {
    final result = await GuardedPicker.pickFiles(
      context,
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md', 'pdf', 'json', 'csv'],
      allowMultiple: true,
    );
    if (result == null) return;
    for (final f in result.files) {
      if (!state.loreFiles.any((e) => e.name == f.name)) {
        state.loreFiles.add(f);
      }
    }
    state.notify();
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    return SingleChildScrollView(
      key: const ValueKey('world-book'),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 760;
              final form = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _worldCard(context, wide),
                  const SizedBox(height: 18),
                  BookWikiSection(state: state, storage: storage, wide: wide),
                  const SizedBox(height: 18),
                  BookDepthSection(
                    storage: storage,
                    wide: wide,
                    enabled: !state.busy,
                  ),
                  const SizedBox(height: 18),
                  _makeCard(context, wide),
                ],
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _heading(context),
                  const SizedBox(height: 20),
                  if (state.scouting) ...[
                    WorldProgressPanel(
                      state: state,
                      fallback: 'Scouting…',
                      subtitle:
                          'Scout · reading the index, not the articles · '
                          'the model is thinking',
                      stages: kWorldScoutStages,
                      stage: worldScoutStageOf(state.status),
                      onStop: state.abortWrite,
                    ),
                    const SizedBox(height: 18),
                    IgnorePointer(child: Opacity(opacity: 0.45, child: form)),
                  ] else
                    form,
                  if (state.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      state.error!,
                      key: const Key('world-from-wiki-book-error'),
                      style: TextStyle(color: StudioColors.honeyOf(context)),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'The book',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.bold,
          color: StudioColors.inkOf(context),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Name the world, pick its wiki, say how deep to dig. Scout proposes '
        'a shelf of cards from the wiki\'s index, not one card per page.',
        style: TextStyle(
          color: StudioColors.proseOf(context),
          fontSize: 15,
          height: 1.45,
        ),
      ),
    ],
  );

  InputDecoration _field(BuildContext context, String label, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: StudioColors.mutedOf(context)),
        filled: true,
        fillColor: StudioColors.bgOf(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _worldCard(BuildContext context, bool wide) {
    final ink = StudioColors.inkOf(context);
    final name = TextField(
      controller: state.nameController,
      enabled: !state.busy,
      style: TextStyle(color: ink),
      decoration: _field(context, 'World name'),
    );
    final premise = TextField(
      controller: state.premiseController,
      enabled: !state.busy,
      minLines: 1,
      maxLines: 3,
      style: TextStyle(color: ink),
      decoration: _field(
        context,
        'One-line premise',
        hint:
            'The Wandenreich invades Soul Society and the Gotei 13 must answer',
      ),
    );
    return WorldSectionCard(
      icon: Icons.public,
      title: 'The world',
      step: 1,
      of: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: name),
                const SizedBox(width: 14),
                Expanded(child: premise),
              ],
            )
          else ...[
            name,
            const SizedBox(height: 12),
            premise,
          ],
          const SizedBox(height: 14),
          _momentCard(context),
        ],
      ),
    );
  }

  /// The Moment as a story card: where the world is frozen.
  Widget _momentCard(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: StudioColors.bgOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amber.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, size: 16, color: amber),
              const SizedBox(width: 8),
              Text(
                'Where the story stands',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: StudioColors.inkOf(context),
                ),
              ),
              const SizedBox(width: 8),
              const WorldChip('optional'),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('world-from-wiki-moment'),
            controller: state.momentController,
            enabled: !state.busy,
            style: TextStyle(color: StudioColors.inkOf(context)),
            decoration: InputDecoration(
              hintText: 'the night after the first invasion',
              hintStyle: TextStyle(color: StudioColors.mutedOf(context)),
              filled: true,
              fillColor: StudioColors.cardOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The point in the story the world is frozen at. Cards are '
            'written as things are then; what happens after stays '
            'unwritten, so you can play it.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: StudioColors.mutedOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _makeCard(BuildContext context, bool wide) {
    final lore = _toggleTile(
      context,
      icon: Icons.menu_book_outlined,
      title: 'Lorebooks',
      blurb: "They scout a shelf of cards; untick any you don't want written.",
      value: state.lorebooksOn,
      onChanged: (v) {
        state.lorebooksOn = v;
        state.notify();
      },
    );
    final climate = _toggleTile(
      context,
      icon: Icons.cloud_outlined,
      title: 'Climate',
      blurb:
          'Off by default. On, each place with its own sky gets its own '
          'weather.',
      value: state.climateEnabled,
      onChanged: (v) {
        state.climateEnabled = v;
        state.notify();
      },
    );
    return WorldSectionCard(
      icon: Icons.edit_outlined,
      title: 'What to make',
      step: 4,
      of: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: lore),
                const SizedBox(width: 10),
                Expanded(child: climate),
              ],
            )
          else ...[
            lore,
            const SizedBox(height: 10),
            climate,
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: state.busy ? null : () => _attach(context),
                icon: const Icon(Icons.attach_file, size: 16),
                label: Text(
                  state.loreFiles.isEmpty
                      ? 'Attach lore files'
                      : '${state.loreFiles.length} file(s) attached',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: StudioColors.amberOf(context),
                  side: BorderSide(color: StudioColors.lineOf(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Text(
                'Optional notes the writer may read; they never override the wiki.',
                style: TextStyle(
                  fontSize: 12,
                  color: StudioColors.mutedOf(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggleTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String blurb,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: StudioColors.bgOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioColors.lineOf(context)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: StudioColors.amberOf(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: StudioColors.inkOf(context),
                  ),
                ),
                Text(
                  blurb,
                  style: TextStyle(
                    fontSize: 12,
                    color: StudioColors.mutedOf(context),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeTrackColor: StudioColors.amberOf(context),
            onChanged: state.busy ? null : onChanged,
          ),
        ],
      ),
    );
  }
}
