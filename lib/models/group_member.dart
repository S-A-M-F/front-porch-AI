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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';

/// In-memory representation of a group-owned character (first-class entity,
/// completely decoupled from the singular library / CharacterRepository).
///
/// All card data lives in typed columns in the group_members Drift table.
/// Avatar is a single primary PNG in the group's private storage
/// (groups/&lt;groupId&gt;/avatars/&lt;memberId&gt;.png, built with groupsDir + path.join; no dedicated helpers).
/// No multi-avatar or expressions.
///
/// Internal id is a UUID (generated at the moment the member is copied into
/// the group). All per-member keys (realism state, system prompt overrides,
/// objectives, RAG embeddings scoped to group, etc.) use this UUID.
///
/// The only way a group member ever becomes a standalone library character
/// is via the user's explicit "Separate to my library" button.
///
/// This model is a pure data holder + thin adapter. It has no toJson (the
/// Drift row + GroupCard portable format are the persistence/export paths).
class GroupMember {
  final String id; // UUID PK within the group
  final String groupId;

  final String name;
  final String description;
  final String personality;
  final String scenario;
  final String firstMessage;
  final String mesExample;
  final String systemPrompt;
  final String postHistoryInstructions;
  final List<String> alternateGreetings;
  final List<String> tags;
  final String?
  avatarFilename; // basename only; resolve as path.join(storage.groupsDir.path, groupId, 'avatars', filename) (no dedicated group*Dir helpers added per strict no-new-methods rule)
  final String? ttsVoice;
  final Lorebook? lorebook;
  final List<String> worldNames;
  final Map<String, dynamic>? frontPorchExtensions; // parsed
  final Map<String, dynamic>? rawExtensions;
  final Map<String, dynamic> memberState; // small group-scoped JSON

  GroupMember({
    required this.id,
    required this.groupId,
    required this.name,
    this.description = '',
    this.personality = '',
    this.scenario = '',
    this.firstMessage = '',
    this.mesExample = '',
    this.systemPrompt = '',
    this.postHistoryInstructions = '',
    this.alternateGreetings = const [],
    this.tags = const [],
    this.avatarFilename,
    this.ttsVoice,
    this.lorebook,
    this.worldNames = const [],
    this.frontPorchExtensions,
    this.rawExtensions,
    this.memberState = const {},
  });

  /// Factory from a Drift row (GroupMemberRow after codegen).
  /// All JSON columns are safely decoded here.
  factory GroupMember.fromRow(GroupMemberRow row) {
    List<String> parseStringList(String? jsonStr) {
      if (jsonStr == null || jsonStr.isEmpty || jsonStr == '[]') return [];
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (e) {
        debugPrint(
          '[GroupMember.fromRow] parseStringList failed: $e (silent default [] used; data may be lost on bad import/sync)',
        );
      }
      return [];
    }

    Lorebook? parseLorebook(String? jsonStr) {
      if (jsonStr == null || jsonStr.isEmpty) return null;
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map) {
          return Lorebook.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (e) {
        debugPrint(
          '[GroupMember.fromRow] parseLorebook failed: $e (silent default null used)',
        );
      }
      return null;
    }

    Map<String, dynamic>? parseMap(String? jsonStr) {
      if (jsonStr == null || jsonStr.isEmpty || jsonStr == '{}') return null;
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (e) {
        debugPrint(
          '[GroupMember.fromRow] parseMap failed: $e (silent default null used; data may be lost on bad import/sync)',
        );
      }
      return null;
    }

    return GroupMember(
      id: row.id,
      groupId: row.groupId,
      name: row.name,
      description: row.description,
      personality: row.personality,
      scenario: row.scenario,
      firstMessage: row.firstMessage,
      mesExample: row.mesExample,
      systemPrompt: row.systemPrompt,
      postHistoryInstructions: row.postHistoryInstructions,
      alternateGreetings: parseStringList(row.alternateGreetings),
      tags: parseStringList(row.tags),
      avatarFilename: row.avatarFilename,
      ttsVoice: row.ttsVoice,
      lorebook: parseLorebook(row.lorebook),
      worldNames: parseStringList(row.worldNames),
      frontPorchExtensions: parseMap(row.frontPorchExtensions),
      rawExtensions: parseMap(row.rawExtensions),
      memberState: parseMap(row.memberState) ?? const {},
    );
  }

  /// Reconstructs a transient CharacterCard for widgets / FileImage / existing
  /// code that still expects the old shape (GroupMemberCard, NeedsBar, etc.).
  ///
  /// imagePath must be the fully resolved private path on disk
  /// (e.g. path.join(storage.groupsDir.path, groupId, 'avatars', avatarFilename!)).
  ///
  /// The returned card has avatarImages = null and primeAvatarIndex = 1
  /// (multi-avatar is not supported for group members).
  /// This is a compatibility shim only — do not persist the result.
  CharacterCard toCharacterCard({required String resolvedImagePath}) {
    FrontPorchExtensions? fpExt;
    if (frontPorchExtensions != null) {
      try {
        fpExt = FrontPorchExtensions.fromJson(frontPorchExtensions!);
      } catch (_) {}
    }

    return CharacterCard(
      name: name,
      description: description,
      personality: personality,
      scenario: scenario,
      firstMessage: firstMessage,
      mesExample: mesExample,
      systemPrompt: systemPrompt,
      postHistoryInstructions: postHistoryInstructions,
      alternateGreetings: List.from(alternateGreetings),
      tags: List.from(tags),
      imagePath: resolvedImagePath,
      ttsVoice: ttsVoice,
      lorebook: lorebook != null
          ? Lorebook(entries: List.from(lorebook!.entries))
          : null,
      worldNames: List.from(worldNames),
      frontPorchExtensions: fpExt,
      rawExtensions: rawExtensions != null
          ? Map<String, dynamic>.from(rawExtensions!)
          : null,
      // Explicitly no multi-avatar support for groups
      avatarImages: null,
      primeAvatarIndex: 1,
    );
  }
}
