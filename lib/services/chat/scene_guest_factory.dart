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

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/character_gen_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat/chat_command_handler.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';

/// Mints Scene Guests (Lite NPCs): generates a character from a name + concept,
/// tags it `tier == 'lite'` (no Realism/Needs state), and persists it via the
/// canonical path (PNG with embedded extensions, then repo insert).
///
/// Extracted from `ChatService` so the god file stays thin; it depends only on
/// standalone services. Returns a [GuestMintResult] for the caller to report.
class SceneGuestFactory {
  const SceneGuestFactory(this._repository, this._storage);

  final CharacterRepository _repository;
  final StorageService _storage;

  /// Generate + mark-lite + persist a guest. [host] supplies scene context
  /// (scenario / NSFW intent). [llm] must already be ready.
  Future<GuestMintResult> mint({
    required String name,
    required String concept,
    required LLMService? llm,
    required CharacterCard? host,
  }) async {
    if (llm == null || !llm.isReady) {
      return const GuestMintResult.failure('the LLM backend is not ready');
    }

    CharacterCard? card;
    try {
      card = await CharacterGenService(llm).generateCharacter(
        name: name,
        concept: concept,
        // Seed scene context from the host's scenario so the guest fits.
        scenario: host?.scenario ?? '',
        worldLore: host?.scenario,
        // Inherit the host's NSFW cooldown intent as the best available signal
        // that this scene allows mature content.
        nsfwEnabled: host?.frontPorchExtensions?.nsfwCooldownEnabled ?? false,
      );
    } catch (e) {
      debugPrint('[SceneGuest:mint] generation failed: $e');
      return GuestMintResult.failure('$e');
    }
    if (card == null) {
      return const GuestMintResult.failure(
        'the LLM did not produce a valid card',
      );
    }
    if (card.description.isEmpty && concept.isNotEmpty) {
      card.description = concept;
    }

    // Mark as a lite Scene Guest (no Realism/Needs state).
    final ext = (card.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
      tier: 'lite',
    );
    card.frontPorchExtensions = ext;

    try {
      final charDir = _storage.charactersDir;
      if (!charDir.existsSync()) charDir.createSync(recursive: true);
      final epoch = DateTime.now().millisecondsSinceEpoch;
      final safeName = name
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(' ', '_');
      final imagePath = p.join(charDir.path, '${safeName}_$epoch.png');
      card.imagePath = imagePath;
      ext.ensureStableId();
      await V2CardService().saveCardAsPng(card, imagePath, null);
      await _repository.addCharacter(card);
    } catch (e) {
      debugPrint('[SceneGuest:mint] persist failed: $e');
      return GuestMintResult.failure(
        'saved generation but failed to store: $e',
      );
    }
    if (card.dbId == null) {
      return const GuestMintResult.failure('created card has no id');
    }
    return GuestMintResult.success(card);
  }
}
