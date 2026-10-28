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

  /// Below this width the caption goes under the thumbnail.
  static const double _sideBySideMin = 240;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // Never wider than the column it sits in, so a narrow window
        // shrinks the thumbnail instead of overflowing.
        final width = box.maxWidth < 96 ? box.maxWidth : 96.0;
        final thumb = _thumb(width);
        final caption = _caption(context);
        if (box.maxWidth < _sideBySideMin) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [thumb, const SizedBox(height: 6), caption],
          );
        }
        return Row(
          children: [
            thumb,
            const SizedBox(width: 10),
            Expanded(child: caption),
          ],
        );
      },
    );
  }

  Widget _thumb(double width) => Semantics(
    button: true,
    label: 'Portrait. Click to zoom in',
    child: MouseRegion(
      cursor: SystemMouseCursors.zoomIn,
      child: Builder(
        builder: (context) => GestureDetector(
          key: const ValueKey('portrait-preview'),
          onTap: () => onZoom(context, bytes),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes,
              width: width,
              height: width * 1.25,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _caption(BuildContext context) {
    final muted =
        context.creatorPalette?.muted ?? AppColors.textTertiary(context);
    return Column(
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
            Flexible(
              child: Text(
                'Click to zoom in',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
