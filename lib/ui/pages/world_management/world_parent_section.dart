// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Part of" picker, climate inherit/own pair, live-chat impact note and the
// Setting-prose preview (locations slice 3, mockup p2). Mounted by
// WorldBasicsSection between the description field and the climate
// controls; every decision it edits lives on the draft.

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'world_edit_draft.dart';

class WorldParentSection extends StatelessWidget {
  const WorldParentSection({
    super.key,
    required this.repo,
    required this.draft,
    required this.draftEditingId,
    required this.setDialogState,
  });

  final WorldRepository repo;
  final WorldEditDraft draft;
  // The row id being edited ('' while creating) — the world a preview
  // and candidate filter pretend the draft currently is.
  final String draftEditingId;
  final StateSetter setDialogState;

  /// The world as it would be saved right now — preview and candidate
  /// filtering both read this, so what the author sees is what Save does.
  World _draftWorld() => World(
    id: draftEditingId.isEmpty ? null : draftEditingId,
    name: draft.nameController.text.trim(),
    description: draft.descController.text.trim(),
    lorebook: Lorebook(entries: []),
    climateEnabled: draft.climateEnabled,
    parentWorldId: draft.parentWorldId,
    injectDescription: draft.injectDescription,
  );

  @override
  Widget build(BuildContext context) {
    final all = repo.placeWorlds;
    final self = draftEditingId.isEmpty ? null : repo.worldById(draftEditingId);
    final candidates = parentPickCandidates(
      self,
      all,
      (id) => repo.worldById(id),
    );
    final parent = draft.parentWorldId == null
        ? null
        : repo.worldById(draft.parentWorldId!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Part of',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String?>(
          key: const Key('world-part-of-picker'),
          // ignore: deprecated_member_use
          value: draft.parentWorldId,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: draft.parentError != null
                    ? StatusColors.alertFill
                    : AppColors.borderOf(context),
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            errorText: draft.parentError,
          ),
          dropdownColor: AppColors.surfaceOf(context),
          items: [
            const DropdownMenuItem<String?>(
              child: Text('Not inside anything (its own world)'),
            ),
            for (final c in candidates)
              DropdownMenuItem<String?>(
                value: c.id,
                child: Text(
                  _pathLabel(c),
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
              ),
          ],
          onChanged: (v) => setDialogState(() {
            draft.parentWorldId = v;
            draft.parentError = null;
          }),
        ),
        const SizedBox(height: 6),
        Text(
          'A place inside another world shares its parent\'s lore and '
          'description. Rooms can go two levels deep '
          '(town › building › room).',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
            height: 1.35,
          ),
        ),
        if (parent != null) ...[
          const SizedBox(height: 12),
          _climatePair(context, parent),
          if (draft.willReparent) ...[
            const SizedBox(height: 12),
            _impactNote(context, parent),
          ],
          const SizedBox(height: 12),
          _prosePreview(context),
        ],
      ],
    );
  }

  /// "Town Hall" vs "Bletchmore Academy · inside Bletchfield" — the
  /// dropdown shows the depth so a room never reads like a town.
  String _pathLabel(World c) {
    final p = c.parentWorldId == null ? null : repo.worldById(c.parentWorldId!);
    return p == null ? c.name : '${c.name} · inside ${p.name}';
  }

  Widget _climatePair(BuildContext context, World parent) {
    final own = draft.climateEnabled;
    final parentBiome = Biome.resolve(
      biomeId: parent.biomeId,
      biomeJson: parent.biomeJson,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CLIMATE',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _modeCard(
                context,
                selected: !own,
                title: 'Inherit from ${parent.name}',
                body:
                    '${parentBiome.displayName} · Weather, atmosphere and '
                    'gravity come from the parent.',
                onTap: () => setDialogState(() => draft.climateEnabled = false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _modeCard(
                context,
                selected: own,
                title: 'Own climate',
                body:
                    'This place authors its own weather, for itself and the '
                    'places inside it.',
                onTap: () => setDialogState(() => draft.climateEnabled = true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Pick Own climate for a continent on Earth or a greenhouse in '
          'the tundra.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 10.5,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _modeCard(
    BuildContext context, {
    required bool selected,
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: Key(
        selected ? 'climate-mode-selected' : 'climate-mode-${title.hashCode}',
      ),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerOf(
            context,
          ).withValues(alpha: selected ? 0.9 : 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.formAccentOf(context)
                : AppColors.borderOf(context).withValues(alpha: 0.4),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 16,
                  color: selected
                      ? AppColors.formAccentOf(context)
                      : AppColors.textTertiary(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _impactNote(BuildContext context, World parent) {
    final inheritClause = draft.climateEnabled
        ? ''
        : ', and its weather if this place inherits';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.formAccentOf(context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 15,
            color: AppColors.formAccentOf(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Chats set here will get ${parent.name}\'s lore$inheritClause.',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _prosePreview(BuildContext context) {
    final chain = [_draftWorld(), ...repo.chainFor(draft.parentWorldId ?? '')];
    final text = buildWorldInjection(chain);
    final body = text.startsWith('Setting — where you are:\n')
        ? text.substring('Setting — where you are:\n'.length)
        : text;
    final count = body.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SETTING PROSE PREVIEW',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                '$count / $kWorldInjectionMaxChars characters',
                style: TextStyle(
                  color: count > kWorldInjectionMaxChars
                      ? StatusColors.alertFill
                      : AppColors.textTertiary(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body.isEmpty
                ? 'Nothing injected yet — write the place first.'
                : body,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 11.5,
              height: 1.45,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'What the model reads when this place is the Setting. This '
            'place comes first; the parent fills what is left of the budget.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
