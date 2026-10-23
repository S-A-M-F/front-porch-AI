// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 7: the mint ask, Scene-Guest style. The judge heard the
// narration name a place that is not in the library; this dialog puts
// the three honest answers in front of the author — Add and move, Just
// add, Ignore — and nothing is minted until a tap. Copy lives here so
// desktop and web answer the same question in the same words.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart' show World;
import 'package:front_porch_ai/services/chat/scene_mint_state.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

class PlaceMintDialog {
  const PlaceMintDialog({required this.proposal, required this.setting});

  final ProposedPlace proposal;
  final World? setting;

  String get title => 'A new place in the story';

  String get question {
    final where = setting?.name;
    final base =
        'The story just described ${proposal.name}'
        '${proposal.descriptor.isEmpty ? '' : ' — ${proposal.descriptor}'}.';
    return where == null
        ? '$base Save it as a place?'
        : '$base Save it as a place inside $where?';
  }

  String get consequence =>
      'It arrives with a short description and a few lore entries '
      'written from what the story showed, inheriting the setting\'s '
      'weather. You can edit or delete it later like any place.';

  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        question,
        style: TextStyle(
          color: AppColors.textSecondary(context),
          height: 1.4,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        consequence,
        style: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 12,
          height: 1.35,
        ),
      ),
    ],
  );
}
