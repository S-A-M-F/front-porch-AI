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

import 'dart:convert';

import 'package:image/image.dart' as img;

/// Shared PNG tEXt / iTXt chunk utilities for character cards and group cards.
///
/// These helpers provide reliable extraction that works even for cards created
/// by external tools (the `image` package's textData handling is not always
/// sufficient for third-party PNGs).
class PngMetadataUtils {
  /// Extracts the text payload for a given keyword from a PNG's tEXt or iTXt chunks.
  ///
  /// Returns null if the PNG signature is invalid, the keyword is not found,
  /// or the chunk is malformed.
  ///
  /// Supports both uncompressed tEXt and iTXt (international text) chunks.
  static String? extractTextChunk(List<int> bytes, String keyword) {
    if (bytes.length < 8) return null;

    // PNG signature
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    for (int i = 0; i < 8; i++) {
      if (bytes[i] != signature[i]) return null;
    }

    int offset = 8;

    while (offset + 12 <= bytes.length) {
      final length =
          (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      offset += 4;

      final type = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      offset += 4;

      final dataStart = offset;
      final dataEnd = offset + length;

      if (dataEnd + 4 > bytes.length) break;

      if (type == 'tEXt') {
        final data = bytes.sublist(dataStart, dataEnd);
        final nullIndex = data.indexOf(0);
        if (nullIndex != -1) {
          final chunkKeyword = String.fromCharCodes(data.sublist(0, nullIndex));
          if (chunkKeyword == keyword) {
            return String.fromCharCodes(data.sublist(nullIndex + 1));
          }
        }
      } else if (type == 'iTXt') {
        final data = bytes.sublist(dataStart, dataEnd);
        final nullIndex = data.indexOf(0);
        if (nullIndex != -1) {
          final chunkKeyword = String.fromCharCodes(data.sublist(0, nullIndex));
          if (chunkKeyword == keyword) {
            // iTXt layout after keyword\0:
            // compressionFlag(1), compressionMethod(1), languageTag\0, translatedKeyword\0, text
            int pos = nullIndex + 1;
            if (pos + 2 <= data.length) {
              pos += 2; // skip flags
              while (pos < data.length && data[pos] != 0) {
                pos++;
              }
              pos++; // skip language null
              while (pos < data.length && data[pos] != 0) {
                pos++;
              }
              pos++; // skip translated keyword null
              if (pos < data.length) {
                return utf8.decode(data.sublist(pos));
              }
            }
          }
        }
      }

      offset = dataEnd + 4;

      if (type == 'IEND') break;
    }

    return null;
  }

  /// Encodes an [image] as PNG with an additional uncompressed tEXt chunk.
  ///
  /// The [keyword] (max 79 bytes, ASCII) and [text] payload are stored in a
  /// standard tEXt chunk so tools like SillyTavern ignore it (they only look
  /// for the 'chara' chunk). Front Porch group cards use the 'fpa_group' keyword.
  ///
  /// This re-uses the `image` package's built-in textData support for maximum
  /// compatibility with how V2 character cards are already written.
  static List<int> encodeWithTextChunk(
    img.Image image,
    String keyword,
    String text,
  ) {
    image.textData ??= {};
    image.textData![keyword] = text;
    return img.encodePng(image);
  }
}
