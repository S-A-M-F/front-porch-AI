// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/world_section_card.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/services/storage/settings/web_search_settings.dart';

/// The Book step's wiki card: the saved wikis as tiles that say what kind
/// of wiki each is and, once scouted, how many pages were read; and a
/// way to add one without leaving the wizard.
class BookWikiSection extends StatelessWidget {
  const BookWikiSection({
    super.key,
    required this.state,
    required this.storage,
    required this.wide,
  });

  final WorldFromWikiState state;
  final StorageService storage;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final saved = storage.webSearchSettings.savedWikiUrls;
    final muted = StudioColors.mutedOf(context);
    return WorldSectionCard(
      icon: Icons.menu_book_outlined,
      title: 'The wiki',
      step: 2,
      of: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (saved.isEmpty)
            Text(
              'No wiki saved yet. Add one below, or save a Fandom or Tiddly '
              'address in Porch Life.',
              style: TextStyle(color: muted),
            )
          else
            LayoutBuilder(
              builder: (context, box) {
                final cols = wide ? 3 : 1;
                final tileWidth = cols == 1
                    ? box.maxWidth
                    : (box.maxWidth - 10 * (cols - 1)) / cols;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final url in saved)
                      SizedBox(width: tileWidth, child: _tile(context, url)),
                  ],
                );
              },
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                key: const Key('world-from-wiki-add-wiki'),
                onPressed: state.busy ? null : () => _addWiki(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: StudioColors.amberOf(context),
                  side: BorderSide(color: StudioColors.lineOf(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  '+ Add a wiki',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                'Saved wikis are the same list as Porch Life\'s web search.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, String url) {
    final selected = state.wikiUrl == url;
    final amber = StudioColors.amberOf(context);
    final scouted = selected && state.catalogTitleCount > 0;
    final subtitle = scouted
        ? '${worldWikiKindGuess(url)} · ${state.catalogTitleCount} pages'
              '${state.catalogRanked ? ' linked most' : ''}'
        : worldWikiKindGuess(url);
    return WorldPickTile(
      key: Key('world-from-wiki-wiki-$url'),
      selected: selected,
      onTap: state.busy
          ? null
          : () {
              state.wikiUrl = url;
              state.notify();
            },
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? amber : null,
                  border: selected
                      ? null
                      : Border.all(
                          color: StudioColors.lineOf(context),
                          width: 1.5,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  wikiHostLabel(url),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: StudioColors.inkOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: StudioColors.mutedOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addWiki(BuildContext context) async {
    final controller = TextEditingController();
    // The dialog's own context pops the dialog, never the wizard.
    final url = await showWarmDialogOf<String>(
      context,
      builder: (ctx) => WarmDialog(
        title: 'Add a wiki',
        icon: Icons.menu_book_outlined,
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Wiki address',
            hintText: 'https://bleach.fandom.com',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.trim().isEmpty) return;
    final ok = await storage.webSearchSettings.addSavedWikiUrl(url.trim());
    if (!ok) {
      state.error = 'That is not a wiki address the app can read.';
      state.notify();
      return;
    }
    state.wikiUrl = storage.webSearchSettings.savedWikiUrls.firstWhere(
      (u) => u.contains(wikiHostLabel(url.trim())),
      orElse: () => url.trim(),
    );
    state.notify();
  }
}
