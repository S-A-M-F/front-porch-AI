// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/hf_readme.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';

/// Loads one repo's model card.
typedef HfReadmeLoader = Future<HfReadme> Function(String repoId);

/// The model downloader's "Model card": the repo's README and its facts,
/// with a way through to the original model's card (a quant repo's own
/// card is often a list of files).
Future<void> showHfReadme(
  BuildContext context, {
  required String repoId,
  required HfReadmeLoader load,
}) {
  return showWarmDialog<void>(
    context,
    title: 'Model card',
    icon: Icons.description_outlined,
    width: 680,
    content: HfReadmeView(repoId: repoId, load: load),
    actions: [warmDialogCancel(context, label: 'Close')],
  );
}

/// The dialog's body; [load] is asked again for each card the user opens.
class HfReadmeView extends StatefulWidget {
  const HfReadmeView({super.key, required this.repoId, required this.load});

  final String repoId;
  final HfReadmeLoader load;

  @override
  State<HfReadmeView> createState() => _HfReadmeViewState();
}

class _HfReadmeViewState extends State<HfReadmeView> {
  /// The cards opened so far; the last is on show, Back pops it.
  late final List<String> _trail = [widget.repoId];
  late Future<HfReadme> _card = widget.load(widget.repoId);

  void _open(String repoId) => setState(() {
    _trail.add(repoId);
    _card = widget.load(repoId);
  });

  void _back() => setState(() {
    _trail.removeLast();
    _card = widget.load(_trail.last);
  });

  static String _problemText(HfFilesProblem problem) => switch (problem) {
    HfFilesProblem.gated =>
      'Gated repo — accept its licence on huggingface.co, then add a '
          'HuggingFace token in Settings → Backend to read its card here.',
    HfFilesProblem.notFound => 'This repo is gone or was renamed.',
    HfFilesProblem.network =>
      'Could not load the model card — check your connection.',
  };

  Future<void> _launch(String href) async {
    final url = Uri.tryParse(href);
    if (url == null || !(url.scheme == 'https' || url.scheme == 'http')) {
      return;
    }
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = math.min(560.0, MediaQuery.sizeOf(context).height * 0.6);
    final repoId = _trail.last;
    return FutureBuilder<HfReadme>(
      key: ValueKey(repoId),
      future: _card,
      builder: (context, snap) {
        final card = snap.data;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_trail.length > 1)
                  IconButton(
                    tooltip: 'Back to ${_trail[_trail.length - 2]}',
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    onPressed: _back,
                  ),
                Expanded(
                  child: SelectableText(
                    repoId,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _launch('https://huggingface.co/$repoId'),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Open on HuggingFace'),
                ),
              ],
            ),
            if (card == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _facts(context, card),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: _body(context, card),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _facts(BuildContext context, HfReadme card) {
    final muted = TextStyle(
      color: AppColors.textSecondary(context),
      fontSize: 12,
    );
    final updated = card.lastModified;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (card.license != null)
          Text('Licence: ${card.license}', style: muted),
        if (updated != null)
          Text(
            'Updated ${updated.year}-${'${updated.month}'.padLeft(2, '0')}-'
            '${'${updated.day}'.padLeft(2, '0')}',
            style: muted,
          ),
        for (final base in card.baseModels)
          if (base != card.repoId)
            ActionChip(
              avatar: const Icon(Icons.account_tree_outlined, size: 14),
              label: Text('Original: $base'),
              tooltip: 'Show the card of the model this was made from',
              onPressed: () => _open(base),
            ),
      ],
    );
  }

  Widget _body(BuildContext context, HfReadme card) {
    final note = card.problem != null
        ? _problemText(card.problem!)
        : (card.markdown.isEmpty ? 'This repo has no model card.' : null);
    if (note != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          note,
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: MarkdownBody(
          data: card.markdown,
          selectable: true,
          onTapLink: (text, href, title) {
            if (href != null) _launch(href);
          },
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
              height: 1.4,
            ),
            h1: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
            h2: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            h3: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            a: TextStyle(
              color: AppColors.porchAmberOf(context),
              decoration: TextDecoration.underline,
            ),
            code: TextStyle(
              color: AppColors.textPrimary(context),
              fontFamily: 'monospace',
              fontSize: 12,
            ),
            codeblockDecoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(6),
            ),
            listBullet: TextStyle(color: AppColors.textSecondary(context)),
            tableBody: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
