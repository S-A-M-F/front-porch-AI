// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Quest Confirmation Dialog — Accept/Decline popup for new quests

import 'package:flutter/material.dart';
import 'package:front_porch_ai/rpg/models/quest.dart';

class QuestConfirmationDialog extends StatelessWidget {
  final Quest quest;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const QuestConfirmationDialog({
    super.key,
    required this.quest,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              child: Row(
                children: [
                  const Text('📜', style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('New Quest',
                          style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 11,
                            fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                        const SizedBox(height: 2),
                        Text(quest.title,
                          style: const TextStyle(color: Colors.white, fontSize: 18,
                            fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Description
            if (quest.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Text(quest.description,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, height: 1.5)),
              ),

            // Objectives
            if (quest.objectives.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('OBJECTIVES',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10,
                        fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    ...quest.objectives.map((obj) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('○ ', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 13)),
                          Expanded(
                            child: Text(obj.description,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                          ),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ],

            // Rewards
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(
                  children: [
                    Text('REWARDS',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10,
                        fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                    const Spacer(),
                    if (quest.xpReward > 0) ...[
                      const Text('⭐', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text('${quest.xpReward} XP',
                        style: const TextStyle(color: Color(0xFF22D3EE), fontSize: 13,
                          fontWeight: FontWeight.w600)),
                    ],
                    if (quest.xpReward > 0 && quest.goldReward > 0)
                      const SizedBox(width: 16),
                    if (quest.goldReward > 0) ...[
                      const Text('🪙', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text('${quest.goldReward} Gold',
                        style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 13,
                          fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
            ),

            // Buttons
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Decline
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDecline,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Decline',
                        style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Accept
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: const Text('Accept Quest',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
