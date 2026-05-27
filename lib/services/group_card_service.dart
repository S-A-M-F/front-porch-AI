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
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:front_porch_ai/models/group_card.dart';
import 'package:front_porch_ai/utils/png_metadata_utils.dart';
import 'package:front_porch_ai/utils/group_avatar_compositor.dart';

/// Service for reading and writing Front Porch Group Cards (single PNG containing
/// multiple full character definitions + group orchestration settings).
///
/// The on-disk format uses a dedicated `fpa_group` tEXt chunk (base64-encoded JSON)
/// so that the file is completely invisible to SillyTavern and other standard
/// character-card importers. This is intentional for safety and to establish a
/// clean new standard.
class GroupCardService {
  static const String groupChunkKeyword = 'fpa_group';
  static const String specName = 'front_porch_group_card';
  static const String specVersion = '1.0';

  /// Saves a GroupCard as a PNG with embedded metadata.
  ///
  /// If [sourceImagePath] is provided, that image is used as the visual cover.
  /// Otherwise a collage is automatically generated from the member avatars
  /// (the recommended "magic" path for group exports).
  Future<void> saveGroupCardAsPng(
    GroupCard groupCard,
    String outputPath, {
    String? sourceImagePath,
  }) async {
    img.Image? visual;

    if (sourceImagePath != null) {
      try {
        final bytes = await File(sourceImagePath).readAsBytes();
        visual = img.decodeImage(bytes);
      } catch (_) {}
    }

    if (visual == null) {
      // Auto-generate a nice collage from the member avatars
      final avatarPaths = groupCard.members
          .map((c) => c.imagePath)
          .toList(growable: false);
      final collageBytes = await createGroupAvatarCollage(avatarPaths);
      visual = img.decodePng(collageBytes);
    }

    if (visual == null) {
      // Last-resort placeholder
      visual = img.Image(width: 512, height: 512);
      img.fill(visual, color: img.ColorRgb8(40, 40, 70));
    }

    // Only downscale if the collage is *extremely* large.
    // We want high-res group card visuals, not 2010-era thumbnails.
    if (visual.width > 2048 || visual.height > 2048) {
      visual = img.copyResize(visual, width: 1600);
    }

    // Enhance member data with embedded avatar images for better round-tripping.
    // This allows imported Group Cards to restore the original character avatars
    // instead of just colored placeholders.
    final baseData = groupCard.toJson();
    final enhancedMembers = <Map<String, dynamic>>[];

    for (final member in groupCard.members) {
      final memberJson = member.toJson();

      // Try to embed the actual avatar image (resized for size)
      if (member.imagePath != null) {
        try {
          final avatarFile = File(member.imagePath!);
          if (await avatarFile.exists()) {
            var avatarImg = img.decodeImage(await avatarFile.readAsBytes());
            if (avatarImg != null) {
              // Resize down if very large to keep the Group Card PNG reasonable
              if (avatarImg.width > 512 || avatarImg.height > 512) {
                avatarImg = img.copyResize(avatarImg, width: 512);
              }
              final avatarBytes = img.encodePng(avatarImg);
              memberJson['avatar_base64'] = base64Encode(avatarBytes);
            }
          }
        } catch (_) {
          // Ignore avatar embedding failures — fall back to placeholder on import
        }
      }

      enhancedMembers.add(memberJson);
    }

    // Replace members in the data with the avatar-enhanced versions
    final enhancedData = Map<String, dynamic>.from(baseData);
    enhancedData['members'] = enhancedMembers;

    // Build the portable envelope (same shape we document in the spec)
    final envelope = {
      'spec': specName,
      'spec_version': specVersion,
      'data': enhancedData,
    };

    final jsonStr = jsonEncode(envelope);
    final base64Str = base64Encode(utf8.encode(jsonStr));

    // Use the image package textData path (simple and reliable when we control creation)
    visual.textData ??= {};
    visual.textData![groupChunkKeyword] = base64Str;

    final pngBytes = img.encodePng(visual);
    await File(outputPath).writeAsBytes(pngBytes);
  }

  /// Reads a GroupCard from a PNG file.
  ///
  /// Returns null if the file does not contain a valid `fpa_group` chunk or
  /// the JSON does not match the expected Front Porch group card shape.
  Future<GroupCard?> readGroupCard(String path) async {
    final bytes = await File(path).readAsBytes();

    // Try the dedicated group keyword first
    String? payload = PngMetadataUtils.extractTextChunk(bytes, groupChunkKeyword);

    if (payload == null) {
      // Also accept the chunk under the image package's textData if present
      try {
        final decoded = img.decodePng(bytes);
        if (decoded?.textData != null &&
            decoded!.textData!.containsKey(groupChunkKeyword)) {
          payload = decoded.textData![groupChunkKeyword];
        }
      } catch (_) {}
    }

    if (payload == null) return null;

    try {
      final jsonStr = utf8.decode(base64Decode(payload));
      final envelope = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Accept both the canonical envelope and a raw data object for flexibility
      final data = (envelope['data'] ?? envelope) as Map<String, dynamic>;

      // Basic shape validation
      if (data['members'] is! List) {
        return null;
      }

      return GroupCard.fromJson(data);
    } catch (e) {
      print('Failed to parse Front Porch group card: $e');
      return null;
    }
  }
}
