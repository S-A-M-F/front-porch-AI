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

        // characterSystemPrompts is now stored in its own first-class column (v32).
        // Full deprecation of the previous Path B blob hack inside defaultMemberRealismState.
        Map<String, String> charPrompts = {};
        try {
          final decoded = jsonDecode(g.characterSystemPrompts);
          if (decoded is Map) {
            charPrompts = decoded.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
          }
        } catch (_) {}

        // Parse worldIds (JSON array) — safe default to empty list on any decode error.
        List<String> worldIdList = [];
        try {
          final decodedWorlds = jsonDecode(g.worldIds);
          if (decodedWorlds is List) {
            worldIdList = decodedWorlds.map((e) => e.toString()).toList();
          }
        } catch (_) {}

        // Construct GroupChat using *real column values* from the v31 schema additions.
        // Old groups receive the DB column defaults (false, '', '[]', true, '{}') which
        // preserve previous behavior and require no one-time promotion logic here.
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
            defaultMemberRealismState: g.defaultMemberRealismState,
            characterSystemPrompts: charPrompts,
            // v31 first-class columns (read directly; no longer silently defaulting):
            chaosModeEnabled: g.chaosModeEnabled,
            chaosNsfwEnabled: g.chaosNsfwEnabled,
            groupLorebook: g.groupLorebook,
            worldIds: worldIdList,
            inheritCharacterLorebooks: g.inheritCharacterLorebooks,
            baselineRealismState: g.baselineRealismState,
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

    // characterSystemPrompts is now persisted in its own dedicated column (v32).
    // Full removal of the previous Path B transitional blob logic that merged it
    // into defaultMemberRealismState. defaultMemberRealismState is written as-is.
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
      defaultMemberRealismState: Value(group.defaultMemberRealismState),
      characterSystemPrompts: Value(jsonEncode(group.characterSystemPrompts)),
      chaosModeEnabled: Value(group.chaosModeEnabled),
      chaosNsfwEnabled: Value(group.chaosNsfwEnabled),
      groupLorebook: Value(group.groupLorebook),
      worldIds: Value(jsonEncode(group.worldIds)),
      inheritCharacterLorebooks: Value(group.inheritCharacterLorebooks),
      baselineRealismState: Value(group.baselineRealismState),
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
          defaultMemberRealismState: Value(group.defaultMemberRealismState),
          characterSystemPrompts: Value(jsonEncode(group.characterSystemPrompts)),
          chaosModeEnabled: Value(group.chaosModeEnabled),
          chaosNsfwEnabled: Value(group.chaosNsfwEnabled),
          groupLorebook: Value(group.groupLorebook),
          worldIds: Value(jsonEncode(group.worldIds)),
          inheritCharacterLorebooks: Value(group.inheritCharacterLorebooks),
          baselineRealismState: Value(group.baselineRealismState),
        ),
      );
    }

    // Replace in the in-memory list so subsequent reads see the saved state.
    // We replace the whole object (the caller owns the instance we were given).
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
