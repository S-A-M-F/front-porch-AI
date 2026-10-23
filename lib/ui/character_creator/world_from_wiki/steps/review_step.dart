// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Review shelf. Flat exactly as always on an untagged wiki. Slice 8
// (design §9.3): when the scout named places, the shelf groups by place
// — a header row per place carrying its own "own climate" switch — so
// the author signs nations, not a shuffled 40-name list. No select-all
// either way (pinned).

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// One rendered row: a header (place + switch) or a card index.
class _ShelfRow {
  const _ShelfRow.header(this.place) : cardIndex = -1;
  const _ShelfRow.card(this.cardIndex) : place = null;

  final WorldProposedPlace? place;
  final int cardIndex;
  bool get isHeader => place != null;
}

class WorldFromWikiReviewStep extends StatelessWidget {
  const WorldFromWikiReviewStep({super.key, required this.state});

  final WorldFromWikiState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('world-review'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
          child: Text(
            'Sign the cards they proposed. Default is off — no select-all. '
            '${state.signed.length} of ${state.proposed.length} signed'
            '${state.catalogTitleCount > 0 ? worldCatalogCountCopy(titles: state.catalogTitleCount, articles: state.catalogArticleCount, ranked: state.catalogRanked) : '.'}',
            style: TextStyle(color: StudioColors.proseOf(context), height: 1.4),
          ),
        ),
        if (state.proposed.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'No cards. Go back and Scout again.',
              style: TextStyle(color: StudioColors.mutedOf(context)),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final row = _rows[i];
                if (row.isHeader) return _placeHeader(context, row.place!);
                return _cardTile(context, row.cardIndex);
              },
            ),
          ),
      ],
    );
  }

  /// Flat order for no places; grouped (root first, then each place in
  /// build order) when the scout saw tags.
  List<_ShelfRow> get _rows {
    if (state.places.isEmpty) {
      return [
        for (var i = 0; i < state.proposed.length; i++) _ShelfRow.card(i),
      ];
    }
    final byPlace = state.indicesByPlace;
    return [
      for (final i in byPlace[''] ?? const <int>[]) _ShelfRow.card(i),
      for (final p in state.places) ...[
        if ((byPlace[p.key] ?? const []).isNotEmpty) ...[
          _ShelfRow.header(p),
          for (final i in byPlace[p.key]!) _ShelfRow.card(i),
        ],
      ],
    ];
  }

  Widget _cardTile(BuildContext context, int i) {
    final card = state.proposed[i];
    final on = state.signed.contains(i);
    final group = card.group.isEmpty ? '' : ' · ${card.group}';
    final sources = card.sourceTitles.join(', ');
    return CheckboxListTile(
      value: on,
      activeColor: StudioColors.amberOf(context),
      title: Text(card.name),
      // The kind (place, faction, person…) says what the card is; the role
      // word (hub, crown) is engine jargon and shows only without one.
      subtitle: Text(
        '${card.kind.isEmpty ? card.role.name : card.kind}$group'
        '${sources.isEmpty ? '' : '\n$sources'}',
      ),
      isThreeLine: sources.isNotEmpty,
      onChanged: (v) => state.toggleSigned(i, v == true),
    );
  }

  Widget _placeHeader(BuildContext context, WorldProposedPlace place) {
    final own = state.placeClimate.contains(place.key);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.parentName.isEmpty
                      ? place.name
                      : '${place.name} · inside ${place.parentName}',
                  style: TextStyle(
                    color: StudioColors.proseOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (place.climateHint.isNotEmpty)
                  Text(
                    'Weather hint: ${place.climateHint}',
                    style: TextStyle(
                      color: StudioColors.mutedOf(context),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (state.climateEnabled)
            Row(
              children: [
                Text(
                  'Own weather',
                  style: TextStyle(color: StudioColors.mutedOf(context)),
                ),
                Switch(
                  value: own,
                  onChanged: (v) => state.togglePlaceClimate(place.key, v),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
