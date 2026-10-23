// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The two locations-flow confirm dialogs (slice 6 move, slice 7 mint),
// extracted from chat_page.scene_dialogs.dart to keep that shell thin:
// the page owns WHEN to ask (the pending flags), this file owns the
// words and the answers. Same showWarmDialog + Navigator.pop contract
// as the guest dialogs remain in the shell.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

Future<void> showPlaceMintFlow(BuildContext context, ChatService chat) async {
  final proposal = chat.pendingPlaceMint;
  if (proposal == null || !context.mounted) {
    return;
  }
  final prompt = PlaceMintDialog(
    proposal: proposal,
    setting: chat.chatPrimaryWorldId == null
        ? null
        : Provider.of<WorldRepository>(
            context,
            listen: false,
          ).worldById(chat.chatPrimaryWorldId!),
  );
  final answer = await showWarmDialog<String>(
    context,
    title: prompt.title,
    icon: Icons.auto_awesome_outlined,
    content: Builder(builder: (ctx) => prompt.build(ctx)),
    barrierDismissible: false,
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, 'ignore'),
        child: const Text('Ignore'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, 'add'),
        child: const Text('Just add'),
      ),
      ElevatedButton(
        onPressed: () => Navigator.pop(context, 'add_move'),
        child: const Text('Add and move'),
      ),
    ],
  );
  switch (answer) {
    case 'add_move':
    case 'add':
      final result = await chat.acceptMintedPlace(
        alsoMove: answer == 'add_move',
      );
      if (!context.mounted) return;
      if (result.ok) {
        // The place arrived — the same confirmation voice an accepted
        // move gets (design §2's Scene-Guest law).
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              answer == 'add_move'
                  ? '${result.world?.name ?? 'The place'} saved; you are '
                        'there now.'
                  : '${result.world?.name ?? 'The place'} saved to the '
                        'library.',
            ),
          ),
        );
      } else if (result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the place: ${result.error}')),
        );
      }
    case 'ignore':
    default:
      chat.ignoreMintedPlace();
  }
}

Future<void> showPlaceMoveFlow(BuildContext context, ChatService chat) async {
  final move = chat.pendingPlaceMove;
  if (move == null || !context.mounted) {
    return;
  }
  final prompt = PlaceMoveDialog(
    move: move,
    setting: chat.chatPrimaryWorldId == null
        ? null
        : Provider.of<WorldRepository>(
            context,
            listen: false,
          ).worldById(chat.chatPrimaryWorldId!),
  );
  final go = await showWarmDialog<bool>(
    context,
    title: prompt.title,
    icon: Icons.explore_outlined,
    content: Builder(builder: (ctx) => prompt.build(ctx)),
    barrierDismissible: false,
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Stay'),
      ),
      ElevatedButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Move there'),
      ),
    ],
  );
  if (go == true) {
    await chat.acceptPlaceMove();
  } else {
    chat.declinePlaceMove();
  }
}
