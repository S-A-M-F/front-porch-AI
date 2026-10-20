// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The prompt-picker SOW preview widgets (approved design): the two full
/// prompt panes and the "What gets sent" resolved preview. Split out of
/// prompt_source_picker.dart to keep both files under the size bar.

/// The prompt text with {{char}} / {{user}} macros picked out in honey —
/// the approved design's highlight, kept as the raw token so the pane
/// shows the prompt exactly as it is authored.
TextSpan promptMacroText(
  BuildContext context,
  String text, {
  Color? colorOverride,
  String suffix = '',
}) {
  final base = TextStyle(
    color: colorOverride ?? AppColors.textPrimary(context),
  );
  final honey = base.copyWith(
    color: AppColors.porchHoneyOf(context),
    fontWeight: FontWeight.bold,
  );
  final children = <InlineSpan>[];
  final pattern = RegExp(r'\{\{(?:char|user)\}\}');
  var cursor = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > cursor) {
      children.add(
        TextSpan(text: text.substring(cursor, match.start), style: base),
      );
    }
    children.add(TextSpan(text: match.group(0), style: honey));
    cursor = match.end;
  }
  final tail = '${text.substring(cursor)}$suffix';
  if (tail.isNotEmpty) {
    children.add(TextSpan(text: tail, style: base));
  }
  return TextSpan(children: children);
}

/// The card / user prompt pair — side-by-side on wide surfaces, stacked on
/// narrow ones. Both prompts show in full; each pane scrolls on its own.
class PromptSourcePanes extends StatelessWidget {
  const PromptSourcePanes({
    super.key,
    required this.cardPrompt,
    required this.userPrompt,
    required this.usesCard,
    required this.cardController,
    required this.userController,
  });

  final String cardPrompt;
  final String userPrompt;
  final bool usesCard;
  final ScrollController cardController;
  final ScrollController userController;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final card = PromptSourcePane(
          paneId: 'card',
          title: 'Character card prompt',
          body: cardPrompt,
          selected: usesCard,
          maxPaneHeight: wide ? 220 : 160,
          controller: cardController,
        );
        final user = PromptSourcePane(
          paneId: 'user',
          title: 'Your prompt (Settings → General)',
          body: userPrompt,
          selected: !usesCard,
          maxPaneHeight: wide ? 220 : 160,
          controller: userController,
        );
        return wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: card),
                  const SizedBox(width: 12),
                  Expanded(child: user),
                ],
              )
            : Column(children: [card, const SizedBox(height: 12), user]);
      },
    );
  }
}

class PromptSourcePane extends StatelessWidget {
  const PromptSourcePane({
    super.key,
    required this.paneId,
    required this.title,
    required this.body,
    required this.selected,
    required this.maxPaneHeight,
    required this.controller,
  });

  final String paneId;
  final String title;
  final String body;
  final bool selected;
  final double maxPaneHeight;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: selected ? 1 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundOf(context),
          border: Border.all(
            color: selected
                ? AppColors.porchHoneyOf(context)
                : AppColors.borderOf(context),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: AppColors.cardOf(context),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ),
                  if (selected) _baseTag(context),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxPaneHeight),
              child: SingleChildScrollView(
                key: ValueKey('prompt-pane-$paneId'),
                controller: controller,
                padding: const EdgeInsets.all(12),
                child: SelectableText.rich(
                  promptMacroText(context, body),
                  style: const TextStyle(fontSize: 12, height: 1.45),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _baseTag(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'BASE',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: AppColors.porchHoneyOf(context),
        ),
      ),
    );
  }
}

/// The resolved prompt: the selected base, the amendment block visually
/// tagged where it lands, and the approximate token cost against the
/// context budget.
class PromptResolvedPreview extends StatelessWidget {
  const PromptResolvedPreview({
    super.key,
    required this.base,
    required this.baseName,
    required this.amendment,
    required this.usesAmendments,
    required this.approxTokens,
  });

  final String base;
  final String baseName;
  final String amendment;
  final bool usesAmendments;
  final int approxTokens;

  @override
  Widget build(BuildContext context) {
    final modeLabel =
        'base: $baseName${usesAmendments ? ' + amendment' : ' · no amendment'}';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: AppColors.cardOf(context),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'What gets sent',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ),
                Text(
                  modeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText.rich(
                    promptMacroText(context, base),
                    style: const TextStyle(fontSize: 12, height: 1.45),
                  ),
                  if (usesAmendments && amendment.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: AppColors.porchTerracottaOf(context),
                            width: 3,
                          ),
                        ),
                      ),
                      child: SelectableText.rich(
                        promptMacroText(
                          context,
                          amendment.trim(),
                          colorOverride: AppColors.porchTerracottaOf(context),
                          suffix: '  ← global amendment',
                        ),
                        style: const TextStyle(fontSize: 12, height: 1.45),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.borderOf(context)),
              ),
            ),
            child: Text.rich(
              TextSpan(
                text: '≈ ',
                children: [
                  TextSpan(
                    text: '$approxTokens tokens',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.journalAccentOf(context),
                    ),
                  ),
                  const TextSpan(
                    text:
                        ' counted against the context budget before history '
                        'trimming · macros resolved per speaker',
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
