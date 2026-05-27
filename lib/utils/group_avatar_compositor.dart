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

import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Creates a visually pleasing collage PNG from a list of character avatar paths.
///
/// This is used when exporting a Group Card so the resulting PNG file has a
/// recognizable "group" appearance (stacked faces) instead of forcing the user
/// to supply a single cover image.
///
/// The returned bytes are a valid PNG ready to have metadata chunks embedded.
Future<Uint8List> createGroupAvatarCollage(
  List<String?> avatarPaths, {
  int maxCanvasSize = 768,
}) async {
  final validPaths = avatarPaths.whereType<String>().toList();
  final count = validPaths.length.clamp(1, 9);

  if (validPaths.isEmpty) {
    final canvas = img.Image(width: 512, height: 512);
    img.fill(canvas, color: img.ColorRgb8(18, 18, 32));
    return Uint8List.fromList(img.encodePng(canvas));
  }

  // === Dynamic canvas size based on number of avatars ===
  // This is the key improvement the user requested.
  final (canvasW, canvasH, thumbSize) = _getCanvasDimensions(count);

  final canvas = img.Image(width: canvasW, height: canvasH);

  // Dark elegant background
  img.fill(canvas, color: img.ColorRgb8(18, 18, 32));

  final thumbs = <img.Image>[];

  for (final path in validPaths.take(9)) {
    try {
      final bytes = await File(path).readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded != null) {
        decoded = _prepareBustThumbnail(decoded, thumbSize);
        thumbs.add(decoded);
      }
    } catch (_) {}
  }

  if (thumbs.isEmpty) {
    return Uint8List.fromList(img.encodePng(canvas));
  }

  final positions = _computePositions(count, canvasW, canvasH, thumbSize);

  for (int i = 0; i < thumbs.length && i < positions.length; i++) {
    final pos = positions[i];
    final thumb = thumbs[i];

    _drawDropShadow(canvas, pos.x, pos.y, thumbSize);
    _drawNiceBorder(canvas, pos.x, pos.y, thumbSize);

    img.compositeImage(
      canvas,
      thumb,
      dstX: pos.x,
      dstY: pos.y,
      dstW: thumbSize,
      dstH: thumbSize,
    );
  }

  _drawOuterFrame(canvas, canvasW, canvasH);

  return Uint8List.fromList(img.encodePng(canvas));
}

/// Returns (width, height, thumbSize) tuned for the number of characters.
/// Significantly higher resolution than before so the collage doesn't look like dial-up.
(int, int, int) _getCanvasDimensions(int count) {
  switch (count) {
    case 1:
      return (768, 960, 620);           // Nice portrait for singles
    case 2:
      return (1400, 820, 480);          // Proper high-res wide for two characters
    case 3:
      return (1280, 820, 380);
    case 4:
      return (1150, 860, 320);
    default:
      // 5+ people — still high res but more grid-like
      return (1024, 960, 260);
  }
}

/// Prepares a thumbnail with better aspect ratio handling (prefers bust/upper body).
img.Image _prepareBustThumbnail(img.Image src, int targetSize) {
  // Resize while preserving aspect
  final aspect = src.width / src.height;
  int newW, newH;

  if (aspect > 1) {
    // Wider than tall — fit to height
    newH = targetSize;
    newW = (targetSize * aspect).round();
  } else {
    // Taller — fit to width
    newW = targetSize;
    newH = (targetSize / aspect).round();
  }

  var resized = img.copyResize(src, width: newW, height: newH);

  // Center crop to square (biased toward upper part for character portraits)
  final cropX = ((resized.width - targetSize) / 2).clamp(0, resized.width - targetSize).toInt();
  int cropY = ((resized.height - targetSize) * 0.15).clamp(0, resized.height - targetSize).toInt(); // bias upward

  return img.copyCrop(resized, x: cropX, y: cropY, width: targetSize, height: targetSize);
}

class _Pos {
  final int x;
  final int y;
  _Pos(this.x, this.y);
}

List<_Pos> _computePositions(int count, int canvasW, int canvasH, int thumb) {
  switch (count) {
    case 1:
      final x = (canvasW - thumb) ~/ 2;
      final y = (canvasH - thumb) ~/ 2;
      return [_Pos(x, y)];

    case 2:
      // Good overlapping layout for two characters on a wide canvas
      final overlap = (thumb * 0.32).round();
      final left = (canvasW ~/ 2 - thumb) + (overlap ~/ 2) - 30;
      final right = (canvasW ~/ 2 - overlap ~/ 2) + 10;
      final y = (canvasH - thumb) ~/ 2 - 20;
      return [
        _Pos(left, y),
        _Pos(right, y),
      ];

    case 3:
      final top = (canvasH - thumb) ~/ 2 - (thumb * 0.45).round();
      final centerX = canvasW ~/ 2 - thumb ~/ 2;
      return [
        _Pos(centerX, top),
        _Pos(centerX - thumb - 10, top + thumb + 10),
        _Pos(centerX + 10, top + thumb + 10),
      ];

    case 4:
      final gap = 16;
      final left = canvasW ~/ 2 - thumb - gap ~/ 2;
      final right = canvasW ~/ 2 + gap ~/ 2;
      final top = canvasH ~/ 2 - thumb - gap ~/ 2 - 15;
      final bottom = canvasH ~/ 2 + gap ~/ 2 - 10;
      return [
        _Pos(left, top),
        _Pos(right, top),
        _Pos(left + 8, bottom),
        _Pos(right - 8, bottom),
      ];

    default:
      // Grid for 5+
      final positions = <_Pos>[];
      final cols = 3;
      final startX = (canvasW - cols * thumb - (cols - 1) * 12) ~/ 2;
      final rows = (count / cols).ceil();
      final startY = (canvasH - rows * thumb - (rows - 1) * 12) ~/ 2;
      int idx = 0;
      for (int r = 0; r < rows && idx < count; r++) {
        for (int c = 0; c < cols && idx < count; c++) {
          positions.add(_Pos(
            startX + c * (thumb + 12),
            startY + r * (thumb + 12),
          ));
          idx++;
        }
      }
      return positions;
  }
}

/// Nicer layered border with purple accent (works with rectangular canvases)
void _drawNiceBorder(img.Image canvas, int x, int y, int size) {
  // Dark outer
  _drawRectBorder(canvas, x - 4, y - 4, size + 8, size + 8, img.ColorRgb8(35, 33, 48), 2);
  // Purple accent
  _drawRectBorder(canvas, x - 2, y - 2, size + 4, size + 4, img.ColorRgb8(168, 105, 255), 3);
}

/// Simple drop shadow
void _drawDropShadow(img.Image canvas, int x, int y, int size) {
  final shadowColor = img.ColorRgba8(0, 0, 0, 85);
  final offset = 7;
  img.fillRect(
    canvas,
    x1: x + offset,
    y1: y + offset + 5,
    x2: x + size + offset,
    y2: y + size + offset + 5,
    color: shadowColor,
  );
}

/// Outer frame (adapts to rectangular canvas)
void _drawOuterFrame(img.Image canvas, int w, int h) {
  final c = img.ColorRgb8(52, 49, 70);
  // Outer
  _drawRectBorder(canvas, 3, 3, w - 6, h - 6, c, 2);
  // Inner
  _drawRectBorder(canvas, 9, 9, w - 18, h - 18, img.ColorRgb8(32, 30, 46), 1);
}

void _drawRectBorder(img.Image canvas, int x, int y, int w, int h, img.Color color, int thickness) {
  for (int t = 0; t < thickness; t++) {
    // Top
    img.fillRect(canvas, x1: x - t, y1: y - t, x2: x + w + t, y2: y - t + 1, color: color);
    // Bottom
    img.fillRect(canvas, x1: x - t, y1: y + h + t - 1, x2: x + w + t, y2: y + h + t, color: color);
    // Left
    img.fillRect(canvas, x1: x - t, y1: y - t, x2: x - t + 1, y2: y + h + t, color: color);
    // Right
    img.fillRect(canvas, x1: x + w + t - 1, y1: y - t, x2: x + w + t, y2: y + h + t, color: color);
  }
}
