// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/prompt_slots.dart';

import 'prompt_slot_card.dart';

/// Settings → General: the base prompt every group chat uses. On its
/// built-in it is stored blank, so Director Mode keeps its own built-in base;
/// a group's own prompt (Group Settings) wins. Director Mode's rules are
/// added on top either way.
class GroupSystemPromptField extends StatelessWidget {
  const GroupSystemPromptField({super.key});

  @override
  Widget build(BuildContext context) => const PromptSlotCard(
    slot: PromptSlot.group,
    title: 'Group system prompt',
    fieldLabel: 'Group system prompt',
    helper:
        'Used in every group chat, unless that group has its own prompt '
        'in Group Settings. On the built-in, Director Mode uses its own '
        'built-in instead, and it adds its rules on top either way.',
  );
}
