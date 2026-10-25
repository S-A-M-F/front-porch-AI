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

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/accent_colors.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/download_status_colors.dart';
import 'package:front_porch_ai/ui/widgets/hf_quant_row.dart';

/// Glassmorphic card displaying a HuggingFace model with expandable quant options.
///
/// Collapsed state shows model name, author, and stats.
/// Expanded state shows all available GGUF files with VRAM indicators.
class HFModelCard extends StatefulWidget {
  /// The HuggingFace model to display.
  final HFModel model;

  /// Available VRAM in MB for fit calculations.
  final int availableVramMb;

  /// Context size to use for VRAM estimation.
  final int contextSize;

  /// Callback when user taps the download button for a specific file.
  final ValueChanged<HFModelFile> onDownload;

  /// Map of currently downloading files (filename -> task).
  final Map<String, DownloadTask> downloadingFiles;

  /// Set of already downloaded filenames.
  final Set<String> downloadedFiles;

  /// Queues a whole quant (every part of a split one). Without it a tap
  /// falls back to [onDownload] with the quant's first file.
  final ValueChanged<HfQuant>? onDownloadQuant;

  /// Opens the repo's model card; no button without it.
  final ValueChanged<String>? onShowModelCard;

  const HFModelCard({
    super.key,
    required this.model,
    required this.availableVramMb,
    this.contextSize = 16384,
    required this.onDownload,
    this.downloadingFiles = const {},
    this.downloadedFiles = const {},
    this.onDownloadQuant,
    this.onShowModelCard,
  });

  @override
  State<HFModelCard> createState() => _HFModelCardState();
}

class _HFModelCardState extends State<HFModelCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  bool _isHovered = false;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.isLight(context)
                  ? AppColors.cardOf(context)
                  : (_isHovered
                        ? AppColors.porchAmberOf(
                            context,
                          ).withValues(alpha: 0.12)
                        : AppColors.porchAmberOf(
                            context,
                          ).withValues(alpha: 0.06)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderOf(context), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header (always visible)
                InkWell(
                  onTap: _toggleExpanded,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Model icon
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.porchAmberOf(
                              context,
                            ).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.science_rounded,
                            color: DownloadStatusColors.verifying,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Model info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.model.name,
                                style: TextStyle(
                                  color: AppColors.textPrimary(context),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      widget.model.author,
                                      style: TextStyle(
                                        color: AppColors.textTertiary(context),
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (widget.model.isRoleplay) ...[
                                    const SizedBox(width: 8),
                                    _roleplayBadge(),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Stats
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _statChip(
                              Icons.download_rounded,
                              widget.model.downloadsDisplay,
                            ),
                            const SizedBox(width: 8),
                            _statChip(
                              Icons.favorite_rounded,
                              widget.model.likesDisplay,
                            ),
                            const SizedBox(width: 12),

                            // Expand arrow
                            AnimatedRotation(
                              turns: _isExpanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 300),
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: AppColors.iconSecondary(context),
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Expanded quant options
                SizeTransition(
                  sizeFactor: _expandAnimation,
                  // Old axisAlignment: -1 (vertical) per the SDK migration formula.
                  alignment: Alignment.topLeft,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerOf(context),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onShowModelCard != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () =>
                                  widget.onShowModelCard!(widget.model.id),
                              icon: const Icon(
                                Icons.description_outlined,
                                size: 16,
                              ),
                              label: const Text('Model card'),
                            ),
                          ),
                        _buildQuantList(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleplayBadge() {
    final gold = AccentColors.goldOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AccentColors.goldEdgeOf(context)),
      ),
      child: Text(
        'Roleplay',
        style: TextStyle(
          color: gold,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.iconSecondary(context)),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  static String _problemText(HfFilesProblem? problem) => switch (problem) {
    HfFilesProblem.gated =>
      'Gated repo — accept its licence on huggingface.co, then add a '
          'HuggingFace token in Settings → Backend',
    HfFilesProblem.notFound => 'This repo is gone or was renamed',
    HfFilesProblem.network =>
      'Could not load the file list — check your connection',
    null => 'No GGUF files available',
  };

  Widget _buildQuantList() {
    final files = widget.model.files;
    if (files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            _problemText(widget.model.filesProblem),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textTertiary(context)),
          ),
        ),
      );
    }

    // Smallest first; split parts are one row, projectors listed apart.
    final quants = HfQuant.group(files);
    final models = [
      for (final q in quants)
        if (!q.isProjector) q,
    ];
    final projectors = [
      for (final q in quants)
        if (q.isProjector) q,
    ];
    final best = HfQuant.bestFit(
      models,
      vramMb: widget.availableVramMb,
      contextSize: widget.contextSize,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final q in models) _quantRow(q, bestFit: identical(q, best)),
        if (projectors.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
            child: Text(
              'Vision add-on — lets the model see images; '
              'paired with what you download from this repo',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 11,
              ),
            ),
          ),
          for (final q in projectors) _quantRow(q, bestFit: false),
        ],
      ],
    );
  }

  Widget _quantRow(HfQuant q, {required bool bestFit}) {
    final tasks = [
      for (final name in q.localFilenames) ?widget.downloadingFiles[name],
    ];
    final String? title = q.isSplit
        ? '${q.title} · ${q.parts.length} parts'
        : (q.primary.filename.contains('/') ? q.primary.basename : null);
    return HFQuantRow(
      file: q.combined,
      title: title,
      bestFit: bestFit,
      unavailableReason: q.isComplete
          ? null
          : 'Incomplete upload: ${q.parts.length} of ${q.partsExpected} '
                'parts are on HuggingFace',
      availableVramMb: widget.availableVramMb,
      contextSize: widget.contextSize,
      downloadTask: tasks.firstOrNull,
      isDownloaded: q.localFilenames.every(widget.downloadedFiles.contains),
      onDownload: (_) => widget.onDownloadQuant != null
          ? widget.onDownloadQuant!(q)
          : widget.onDownload(q.primary),
    );
  }
}
