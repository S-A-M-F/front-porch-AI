// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import '../chat_components.dart';

class ChatEvaluationProgress extends StatelessWidget {
  const ChatEvaluationProgress({
    super.key,
    required this.chatService,
    this.inline = false,
  });
  final ChatService chatService;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final minimized = storage.uiSettings.evaluationMinimized;
    void change(bool value) async {
      try {
        await storage.uiSettings.setEvaluationMinimized(value);
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save evaluation view: $error')),
        );
      }
    }

    return buildChatEvaluationOverlay(
      chatService: chatService,
      minimized: minimized,
      onChanged: change,
      inline: inline,
    );
  }
}

Widget buildChatEvaluationOverlay({
  required ChatService chatService,
  required bool minimized,
  required ValueChanged<bool> onChanged,
  required bool inline,
}) {
  final stoppingReply =
      chatService.isEvaluatingRealism || chatService.isProcessingGreeting;
  final showingRealism = stoppingReply || chatService.isVerifyingRealism;
  if (!showingRealism && !chatService.isCheckingCompletion) {
    return const SizedBox.shrink();
  }
  if (inline) {
    final pass = chatService.verificationPass;
    final max = chatService.verificationMaxPasses;
    final title = chatService.isProcessingGreeting
        ? 'Reading the room…'
        : chatService.isVerifyingRealism
        ? 'Verifying Realism output${max > 0 ? ' (pass $pass/$max)' : ''}'
        : chatService.isEvaluatingRealism
        ? 'Realism Engine'
        : 'Objective Engine';
    return EvaluationProgressShell(
      title: title,
      minimized: minimized,
      onExpand: () => onChanged(false),
      onStop: stoppingReply
          ? () {
              if (!chatService.isCancellingRealismEval) {
                chatService.cancelRealismEval();
              }
            }
          : chatService.isCheckingCompletion && !chatService.isVerifyingRealism
          ? chatService.skipObjectiveCheck
          : null,
      stopLabel: stoppingReply ? 'Stop this reply' : 'Skip goal check',
    );
  }
  if (minimized) return const SizedBox.shrink();
  return showingRealism
      ? RealismProcessingOverlay(
          chatService: chatService,
          isGreeting: chatService.isProcessingGreeting,
          onMinimize: () => onChanged(true),
        )
      : ObjectiveCheckOverlay(
          chatService: chatService,
          onMinimize: () => onChanged(true),
        );
}
