// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Shelf step: every card they proposed starts signed; untick what
// should not be written. Counts and the reviewer's word up top, kind
// filters, "Only the backbone" for a shorter write, and the places as
// groups with the hub card first, each with "Sign all here" / "Unsign all
// here". No select-all pill over the whole shelf. From the approved uplift
// sketch; every colour is the theme's.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/world_section_card.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_shelf_actions.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// How many of a group's cards show before "Show the other N".
const int kWorldShelfCardsShown = 8;

class WorldFromWikiReviewStep extends StatefulWidget {
  const WorldFromWikiReviewStep({super.key, required this.state});

  final WorldFromWikiState state;

  @override
  State<WorldFromWikiReviewStep> createState() =>
      _WorldFromWikiReviewStepState();
}

class _WorldFromWikiReviewStepState extends State<WorldFromWikiReviewStep> {
  final Set<String> _expanded = {};

  WorldFromWikiState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('world-review'),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 760;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _heading(context, wide),
                  const SizedBox(height: 16),
                  if (state.proposed.isEmpty)
                    Text(
                      'No cards. Go back and Scout again.',
                      style: TextStyle(color: StudioColors.mutedOf(context)),
                    )
                  else ...[
                    _reviewBanner(context),
                    const SizedBox(height: 14),
                    _filters(context),
                    const SizedBox(height: 18),
                    ..._groups(context, wide),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, bool wide) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The shelf',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
            color: StudioColors.inkOf(context),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Every card they proposed is signed. Untick what you don't want "
          'written; the Review step at the end is where the rest gets fixed.',
          style: TextStyle(
            color: StudioColors.proseOf(context),
            fontSize: 15,
            height: 1.45,
          ),
        ),
      ],
    );
    final counts = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _count(context, '${state.proposed.length}', 'cards'),
        _count(context, '${state.places.length}', 'places'),
        _count(context, '${state.signed.length}', 'signed', accent: true),
      ],
    );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: 12), counts],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: title),
        const SizedBox(width: 16),
        counts,
      ],
    );
  }

  Widget _count(
    BuildContext context,
    String n,
    String label, {
    bool accent = false,
  }) => Container(
    key: Key('world-shelf-count-$label'),
    constraints: const BoxConstraints(minWidth: 86),
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    decoration: BoxDecoration(
      color: StudioColors.cardOf(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: StudioColors.lineOf(context)),
    ),
    child: Column(
      children: [
        Text(
          n,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: accent
                ? StudioColors.amberOf(context)
                : StudioColors.inkOf(context),
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: StudioColors.mutedOf(context)),
        ),
      ],
    ),
  );

  Widget _reviewBanner(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      color: StudioColors.cardOf(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: StudioColors.lineOf(context)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          state.shelfRevised ? Icons.refresh : Icons.check,
          size: 18,
          color: StudioColors.amberOf(context),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            state.shelfReviewLine,
            key: const Key('world-shelf-review-line'),
            style: TextStyle(color: StudioColors.proseOf(context), height: 1.4),
          ),
        ),
      ],
    ),
  );

  Widget _filters(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      WorldPill(
        key: const Key('world-shelf-filter-all'),
        text: 'All ${state.proposed.length}',
        selected: state.shelfFilter.isEmpty,
        onTap: () => state.setShelfFilter(''),
      ),
      for (final f in kWorldShelfFilters)
        WorldPill(
          key: Key('world-shelf-filter-${f.label}'),
          text: '${f.label} ${state.countFor(f.kinds)}',
          selected: state.shelfFilter == f.label,
          onTap: () => state.setShelfFilter(f.label),
        ),
      const SizedBox(width: 8),
      TextButton(
        key: const Key('world-shelf-only-backbone'),
        onPressed: state.keepBackbone,
        style: TextButton.styleFrom(
          foregroundColor: StudioColors.amberOf(context),
        ),
        child: const Text(
          'Only the backbone',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      Text(
        'era, places, factions, events: a shorter write',
        style: TextStyle(fontSize: 12, color: StudioColors.mutedOf(context)),
      ),
    ],
  );

  /// Root first, then each place in build order; a flat shelf is one
  /// group with no header.
  List<Widget> _groups(BuildContext context, bool wide) {
    if (state.places.isEmpty) {
      return [
        _group(
          context,
          placeKey: '',
          title: 'The shelf',
          place: null,
          indices: [for (var i = 0; i < state.proposed.length; i++) i],
          wide: wide,
        ),
      ];
    }
    final byPlace = state.indicesByPlace;
    final out = <Widget>[];
    final root = byPlace[''] ?? const <int>[];
    if (root.isNotEmpty) {
      out.add(
        _group(
          context,
          placeKey: '',
          title: 'The world',
          place: null,
          indices: root,
          wide: wide,
        ),
      );
    }
    for (final p in state.places) {
      final indices = byPlace[p.key] ?? const <int>[];
      if (indices.isEmpty) continue;
      if (out.isNotEmpty) out.add(const SizedBox(height: 22));
      out.add(
        _group(
          context,
          placeKey: p.key,
          title: p.name,
          place: p,
          indices: indices,
          wide: wide,
        ),
      );
    }
    return out;
  }

  Widget _group(
    BuildContext context, {
    required String placeKey,
    required String title,
    required WorldProposedPlace? place,
    required List<int> indices,
    required bool wide,
  }) {
    final shown = indices.where(state.passesFilter).toList();
    final open = _expanded.contains(placeKey);
    final visible = open ? shown : shown.take(kWorldShelfCardsShown).toList();
    final hidden = shown.length - visible.length;
    final signedHere = state.signedIn(placeKey);
    final allSigned = signedHere == indices.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: StudioColors.lineOf(context)),
            ),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: StudioColors.inkOf(context),
                ),
              ),
              if (place != null && place.parentName.isNotEmpty)
                WorldChip('inside ${place.parentName}'),
              WorldChip('${indices.length} cards · $signedHere signed'),
              if (place != null && place.climateHint.isNotEmpty)
                WorldChip('Weather hint: ${place.climateHint}'),
              if (place != null && state.climateEnabled)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Own weather',
                      style: TextStyle(
                        fontSize: 12,
                        color: StudioColors.mutedOf(context),
                      ),
                    ),
                    Switch(
                      value: state.placeClimate.contains(place.key),
                      onChanged: (v) => state.togglePlaceClimate(place.key, v),
                    ),
                  ],
                ),
              TextButton(
                key: Key('world-shelf-sign-all-$placeKey'),
                onPressed: () => state.signAllIn(placeKey, on: !allSigned),
                style: TextButton.styleFrom(
                  foregroundColor: allSigned
                      ? StudioColors.mutedOf(context)
                      : StudioColors.amberOf(context),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  allSigned ? 'Unsign all here' : 'Sign all here',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (visible.isEmpty)
          Text(
            'Nothing of that kind here.',
            style: TextStyle(color: StudioColors.mutedOf(context)),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final cols = wide ? 2 : 1;
              final w = cols == 1
                  ? box.maxWidth
                  : (box.maxWidth - 8 * (cols - 1)) / cols;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final i in visible)
                    SizedBox(width: w, child: _cardTile(context, i)),
                ],
              );
            },
          ),
        if (hidden > 0 || (open && shown.length > kWorldShelfCardsShown))
          Center(
            child: TextButton(
              key: Key('world-shelf-more-$placeKey'),
              onPressed: () => setState(() {
                if (!_expanded.remove(placeKey)) _expanded.add(placeKey);
              }),
              style: TextButton.styleFrom(
                foregroundColor: StudioColors.mutedOf(context),
              ),
              child: Text(
                open
                    ? 'Show fewer'
                    : 'Show the other $hidden card${hidden == 1 ? '' : 's'} in $title',
              ),
            ),
          ),
      ],
    );
  }

  Widget _cardTile(BuildContext context, int i) {
    final card = state.proposed[i];
    final on = state.signed.contains(i);
    final amber = StudioColors.amberOf(context);
    final kind = state.kindOf(card);
    final role =
        card.role == WorldCraftRole.era ||
            card.role == WorldCraftRole.hub ||
            card.role == WorldCraftRole.crown
        ? ' · ${card.role.name}'
        : '';
    final group = card.group.isEmpty ? '' : ' · ${card.group}';
    final sources = card.sourceTitles.join(', ');
    // A Material of its own: a list tile paints its ink on the nearest
    // Material, which a decorated box would hide.
    return Material(
      color: StudioColors.cardOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: on ? amber : StudioColors.lineOf(context),
          width: on ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: CheckboxListTile(
        value: on,
        activeColor: amber,
        dense: true,
        contentPadding: const EdgeInsets.fromLTRB(8, 2, 12, 2),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(card.name),
        // The kind (place, faction, person…) says what the card is; the
        // role word (era, hub, crown) rides along when it means something.
        subtitle: Text(
          '$kind$role$group${sources.isEmpty ? '' : '\n$sources'}',
          maxLines: sources.isEmpty ? 1 : 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: sources.isNotEmpty,
        onChanged: (v) => state.toggleSigned(i, v == true),
      ),
    );
  }
}
