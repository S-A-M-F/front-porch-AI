// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The Review step's bottom bar: Back, the direction's send-back, and
/// Mint World. Its own row, since the shared nav has two buttons.
class WorldReviewNav extends StatelessWidget {
  const WorldReviewNav({
    super.key,
    required this.state,
    required this.onBack,
    required this.onSendBack,
    required this.onMint,
  });

  final WorldFromWikiState state;
  final VoidCallback onBack;
  final VoidCallback onSendBack;
  final VoidCallback onMint;

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    final busy = state.busy;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: StudioColors.lineOf(context))),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 10,
        children: [
          SizedBox(
            height: 50,
            child: TextButton.icon(
              onPressed: busy ? null : onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
              style: TextButton.styleFrom(
                foregroundColor: StudioColors.proseOf(context),
                backgroundColor: StudioColors.raiseOf(context),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: state.directionController,
            builder: (context, _) {
              final canSend =
                  !busy && state.directionController.text.trim().isNotEmpty;
              return SizedBox(
                height: 50,
                child: OutlinedButton(
                  key: const Key('world-from-wiki-send-back-nav'),
                  onPressed: canSend ? onSendBack : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: amber,
                    side: BorderSide(color: amber, width: 1.5),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Send it back around',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              );
            },
          ),
          SizedBox(
            height: 50,
            child: FilledButton(
              key: const Key('world-from-wiki-mint'),
              onPressed: busy || !state.canSave ? null : onMint,
              style: FilledButton.styleFrom(
                backgroundColor: amber,
                foregroundColor: StudioColors.bgOf(context),
                padding: const EdgeInsets.symmetric(horizontal: 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Mint World  →',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
