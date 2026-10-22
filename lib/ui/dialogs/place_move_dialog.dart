// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 6: the confirmed scene move's DIALOG BODY. The clock judge only
// flags an arrival; the chat page opens this through `showWarmDialog`
// (which owns the warm chrome, so this file builds no AlertDialog and
// adds zero to the raw-dialog baseline) and the answer is the only thing
// that moves the scene. "Stay" is honored silently — the place will not
// be offered again until the Setting itself changes.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart' show World;
import 'package:front_porch_ai/services/chat/scene_move_state.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// The dialog's question, phrased against where the scene is now. Paired
/// with the Stay / Move-there actions in [PlaceMoveDialog.actions]; kept
/// separate from [showWarmDialog] so the copy is unit-testable in one spot.
class PlaceMoveDialog {
  const PlaceMoveDialog({required this.move, required this.setting});

  final PendingPlaceMove move;
  final World? setting;

  String get title => 'The scene moved';

  String get question {
    final from = setting?.name;
    return from == null
        ? 'The story reads as arriving at ${move.name}. Move the scene '
              'there?'
        : 'The story reads as arriving at ${move.name} — you are in '
              '$from. Move the scene there?';
  }

  String get consequence {
    final from = setting?.name;
    return from == null
        ? 'Moving makes ${move.name} the setting; its weather and lore '
              'take over.'
        : 'Moving makes ${move.name} the setting and keeps $from live as '
              'lore for the rest of the scene.';
  }

  /// The body widget; the surrounding chrome (title, actions) is the
  /// warm dialog's, so this stays a plain column.
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
