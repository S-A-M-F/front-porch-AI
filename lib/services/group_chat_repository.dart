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
import 'package:drift/drift.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/cloud_sync_service.dart';

/// Persists group chat definitions to the database.
class GroupChatRepository extends ChangeNotifier {
  final StorageService _storageService;
  AppDatabase _db;
  final List<GroupChat> _groups = [];

  List<GroupChat> get groups => List.unmodifiable(_groups);

  GroupChatRepository(this._storageService, this._db) {
    _load();
  }

  /// Update the database reference (e.g. after cloud sync replaces the DB file).
  void updateDatabase(AppDatabase db) {
    _db = db;
  }

  Future<void> _load() async {
    await _storageService.initialized;
    _groups.clear();

    try {
      final dbGroups = await _db.getAllGroups();
      for (final g in dbGroups) {
        List<String> charIds = [];
        try {
          charIds = List<String>.from(jsonDecode(g.characterIds));
        } catch (_) {}

        // Path B transition: extract per-char system prompts from the realism JSON if present
        Map<String, String> charPrompts = {};
        String realismJsonForModel = g.defaultMemberRealismState;
        try {
          final decoded = jsonDecode(g.defaultMemberRealismState);
          if (decoded is Map && decoded.containsKey('character_system_prompts')) {
            final promptsRaw = decoded['character_system_prompts'];
            if (promptsRaw is Map) {
              charPrompts = promptsRaw.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
            }
            // Remove the key from the realism blob for the model (it will be re-merged on save if needed)
            final mutable = Map<String, dynamic>.from(decoded);
            mutable.remove('character_system_prompts');
            realismJsonForModel = jsonEncode(mutable);
          }
        } catch (_) {}

        _groups.add(
          GroupChat(
            id: g.id,
            name: g.name,
            characterIds: charIds,
            turnOrder: TurnOrder.values.firstWhere(
              (e) => e.name == g.turnOrder,
              orElse: () => TurnOrder.roundRobin,
            ),
            autoAdvance: g.autoAdvance,
            directorMode: g.directorMode,
            firstMessage: g.firstMessage,
            scenario: g.scenario,
            systemPrompt: g.systemPrompt,
            defaultMemberRealismState: realismJsonForModel,
            characterSystemPrompts: charPrompts,
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to load groups from DB: $e');
    }

    notifyListeners();
  }

  /// Reload groups from DB (e.g. after cloud sync).
  Future<void> reload() async {
    await _load();
  }

  Future<void> save(GroupChat group) async {
    // Save to database
    final existing = await _db.getGroupById(group.id);

    // Path B transition: merge characterSystemPrompts into the realism JSON
    // under 'character_system_prompts' so we don't need a new DB column yet.
    String realismToStore = group.defaultMemberRealismState;
    if (group.characterSystemPrompts.isNotEmpty) {
      try {
        final decoded = jsonDecode(group.defaultMemberRealismState);
        final mutable = (decoded is Map)
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
        mutable['character_system_prompts'] = group.characterSystemPrompts;
        realismToStore = jsonEncode(mutable);
      } catch (_) {
        // If the realism JSON is invalid or empty, just store the prompts
        realismToStore = jsonEncode({'character_system_prompts': group.characterSystemPrompts});
      }
    }

    final companion = GroupsCompanion(
      id: Value(group.id),
      name: Value(group.name),
      characterIds: Value(jsonEncode(group.characterIds)),
      turnOrder: Value(group.turnOrder.name),
      autoAdvance: Value(group.autoAdvance),
      directorMode: Value(group.directorMode),
      firstMessage: Value(group.firstMessage),
      scenario: Value(group.scenario),
      systemPrompt: Value(group.systemPrompt),
      defaultMemberRealismState: Value(realismToStore),
    );

    if (existing != null) {
      await _db.updateGroup(companion);
    } else {
      await _db.insertGroup(
        GroupsCompanion.insert(
          id: group.id,
          name: group.name,
          characterIds: Value(jsonEncode(group.characterIds)),
          turnOrder: Value(group.turnOrder.name),
          autoAdvance: Value(group.autoAdvance),
          directorMode: Value(group.directorMode),
          firstMessage: Value(group.firstMessage),
          scenario: Value(group.scenario),
          systemPrompt: Value(group.systemPrompt),
          defaultMemberRealismState: Value(realismToStore),
        ),
      );
    }

    final idx = _groups.indexWhere((g) => g.id == group.id);
    if (idx >= 0) {
      _groups[idx] = group;
    } else {
      _groups.add(group);
    }
    notifyListeners();
  }

  Future<void> delete(
    String groupId, {
    CloudSyncService? cloudSyncService,
  }) async {
    // Delete from database
    await _db.deleteGroupById(groupId);
    _groups.removeWhere((g) => g.id == groupId);

    // Delete associated chat sessions from database
    final sessions = await _db.getSessionsForGroup(groupId);
    for (final session in sessions) {
      await _db.deleteMessagesForSession(session.id);
      await _db.deleteSessionById(session.id);
    }

    // Delete from cloud storage
    if (cloudSyncService != null) {
      cloudSyncService.deleteRemoteGroupChat(groupId);
    }

    notifyListeners();
  }

  GroupChat? getById(String id) {
    return _groups.where((g) => g.id == id).firstOrNull;
  }
}
