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

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/creator_palette.dart';

/// The generated portrait once it is saved as the card image: a thumbnail
/// that opens the full-size zoomable viewer ([onZoom]) when clicked.
class PortraitPreview extends StatelessWidget {
  const PortraitPreview({super.key, required this.bytes, required this.onZoom});

  final Uint8List bytes;

  /// Opens the full-size viewer on [bytes].
  final void Function(BuildContext context, Uint8List bytes) onZoom;

  @override
  Widget build(BuildContext context) {
    final muted =
        context.creatorPalette?.muted ?? AppColors.textTertiary(context);
    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Portrait. Click to zoom in',
          child: MouseRegion(
            cursor: SystemMouseCursors.zoomIn,
            child: GestureDetector(
              key: const ValueKey('portrait-preview'),
              onTap: () => onZoom(context, bytes),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  bytes,
                  width: 96,
                  height: 120,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Saved & set as the card image.',
                style: TextStyle(
                  color:
                      context.creatorPalette?.prose ??
                      AppColors.textSecondary(context),
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.zoom_in, size: 14, color: muted),
                  const SizedBox(width: 4),
                  Text(
                    'Click to zoom in',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
