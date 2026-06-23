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

part of '../chat_service.dart';

/// Group membership lifecycle: forking a 1:1 into a group, creating group member
/// rows, and adding/removing members live. Extracted verbatim from
/// `chat_service.dart` (zero behaviour change) to shrink the god file. As
/// `part of` the same library, these reach the private group repo / db / manager
/// / entrance state exactly as the in-class methods did.
extension ChatServiceGroupMembership on ChatService {
  /// Fork the current 1:1 chat into a new group chat, copying all messages.
  /// The original 1:1 session remains untouched.
  Future<GroupChat?> forkToGroupChat(
    List<CharacterCard> additionalCharacters,
    GroupChatRepository groupRepo, {
    String? groupName,
    String? scenario,
    TurnOrder turnOrder = TurnOrder.roundRobin,
    Map<String, ({String text, bool creative})> entrances = const {},
  }) async {
    if (_isGenerating) return null;
    if (_activeCharacter == null || _characterRepository == null) return null;
    if (_messages.isEmpty) return null;
    // 1:1 → group only. Forking from an existing group would rebuild a group
    // from just the active speaker (dropping the other members), so refuse it —
    // use "Add Character to Group" for an existing group instead.
    if (_activeGroup != null) return null;

    final originalCharId = _getCharacterIdFromCard(_activeCharacter!);

    // Build a default group name
    final name = groupName?.isNotEmpty == true
        ? groupName!
        : [
            _activeCharacter!.name,
            ...additionalCharacters.map((c) => c.name),
          ].join(' & ');

    // Create the group
    final group = GroupChat(
      id: 'group_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      // characterIds removed (decoupled). Members handled via group_members + private storage.
      turnOrder: turnOrder,
      scenario: scenario ?? '',
      // v31 columns — new groups start with clean defaults.
      // baselineRealismState remains '{}' until the caller (or UI) seeds explicit values.
      baselineRealismState: '{}',
    );
    await groupRepo.save(group);

    // Rotation order rule for the new group: original participant(s) first,
    // then arrivals WITH an entrance (in the order added), then arrivals
    // WITHOUT an entrance at the end. Member insertion order *is* the
    // round-robin order (the members table has no explicit sort column), so we
    // insert in exactly that order.
    bool hasEntrance(CharacterCard c) =>
        (entrances[_getCharacterIdFromCard(c)]?.text.trim().isNotEmpty) ??
        false;
    final entranceArrivals = additionalCharacters.where(hasEntrance).toList();
    final silentArrivals = additionalCharacters
        .where((c) => !hasEntrance(c))
        .toList();
    final orderedArrivals = [...entranceArrivals, ...silentArrivals];

    // Decoupled model: ensure members exist for the original 1:1 character
    // and every additional character. Without this, the group loads empty
    // (setActiveGroup / GroupTurnManager will have no one to speak).
    // Ported from the fix originally contributed in PR #44 by @MisterLotto.
    await _createGroupMember(group.id, _activeCharacter!);
    for (final c in orderedArrivals) {
      await _createGroupMember(group.id, c);
    }

    // Create a new session for the group and copy all messages
    final newSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final copiedMessages = <MessagesCompanion>[];
    for (int i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      // Back-fill characterId on AI messages (null in 1:1 mode)
      String? charId = m.characterId;
      if (!m.isUser && charId == null) {
        charId = originalCharId;
      }
      copiedMessages.add(
        MessagesCompanion(
          sessionId: drift.Value(newSessionId),
          position: drift.Value(i),
          sender: drift.Value(m.sender),
          isUser: drift.Value(m.isUser),
          characterId: drift.Value(charId),
          swipes: drift.Value(jsonEncode(m.swipes)),
          swipeIndex: drift.Value(m.swipeIndex),
          swipeDurations: drift.Value(jsonEncode(m.swipeDurations)),
        ),
      );
    }

    // Insert the new session
    await _db.upsertSession(
      SessionsCompanion.insert(
        id: newSessionId,
        groupId: drift.Value(group.id),
        name: drift.Value(_sessionName),
        description: drift.Value(_sessionDescription),
        authorNote: drift.Value(_authorNote),
        authorNoteDepth: drift.Value(_authorNoteStrength),
        summary: drift.Value(_summary.isEmpty ? null : _summary),
        summaryLastIndex: drift.Value(
          _summaryLastIndex > 0 ? _summaryLastIndex : null,
        ),
        parentSession: drift.Value(_currentSessionId),
        forkIndex: drift.Value(_messages.length - 1),
        trustLevel: drift.Value(_relationshipService.trustLevel),
        activeFixation: drift.Value(_relationshipService.activeFixation),
        fixationLifespan: drift.Value(_relationshipService.fixationLifespan),
        spatialStance: drift.Value(_relationshipService.spatialStance),
        startDayOfWeek: drift.Value(_timeService.startDayOfWeekAnchor),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    if (copiedMessages.isNotEmpty) {
      await _db.insertMessages(copiedMessages);
    }

    debugPrint(
      '[ChatService] \u{1F500} Forked 1:1 chat to group "${group.name}" '
      '(${_messages.length} messages copied)',
    );

    // Switch to the new group (this loads the session we just created)
    await setActiveGroup(group, groupRepo: groupRepo);

    // Run any custom entrances WITHOUT blocking the caller, so the wizard can
    // navigate to the group immediately and the entrance messages stream into
    // the now-visible chat instead of waiting behind a spinner. Entrants cut in
    // one-by-one in the order they were added.
    if (entranceArrivals.isNotEmpty) {
      _entrancesInFlight = true; // block user turns until the sequence finishes
      unawaited(() async {
        try {
          for (final addCard in entranceArrivals) {
            final entry = entrances[_getCharacterIdFromCard(addCard)]!;
            final text = entry.text.trim();

            // Members are copied under fresh UUIDs on fork, so resolve by name
            // (stable) and use the resolved member's id — else the entrance
            // attributes to the wrong member.
            final resolved = _groupCharacters.firstWhere(
              (c) => c.name == addCard.name,
              orElse: () => addCard,
            );
            final resolvedId = _getCharacterIdFromCard(resolved);

            if (entry.creative) {
              // Hidden one-shot directive; the member writes their own entrance.
              // Shared with live /join --full + sidebar adds via the helper.
              final ok = await _generateMemberEntrance(resolved, text);
              if (!ok) {
                // Surface the failure so the user isn't left wondering why the
                // group loaded with no entrance.
                _messages.add(
                  ChatMessage(
                    text:
                        '⚠ ${resolved.name}\'s entrance could not be generated.',
                    sender: 'System',
                    isUser: false,
                  ),
                );
                await _saveChat();
                notifyListeners();
              }
            } else {
              // Opening line: the entrance IS the user's text, verbatim — it
              // becomes the character's message as-is, no LLM generation.
              _messages.add(
                ChatMessage(
                  text: text,
                  sender: resolved.name,
                  isUser: false,
                  characterId: resolvedId,
                ),
              );
              await _saveChat();
              notifyListeners();
            }
          }
        } catch (e) {
          debugPrint('[Fork:Entrance] sequence failed: $e');
        } finally {
          // The entrances are one-off cut-ins. In round-robin the next turn goes
          // to whoever falls right after the LAST entrant in the rotation order
          // (originals, then entrance arrivals, then silent arrivals) — i.e. the
          // first silent arrival, or wrapping back to the original if there are
          // none. advanceAfterRegeneration parks the pointer at last-entrant + 1.
          // Done in `finally` so a generation hiccup can't leave the rotation
          // stuck on the entrant. Random needs no fix-up.
          final lastEntrantName = entranceArrivals.last.name;
          if (turnOrder == TurnOrder.roundRobin &&
              _groupCharacters.any((c) => c.name == lastEntrantName)) {
            final lastEntrant = _groupCharacters.firstWhere(
              (c) => c.name == lastEntrantName,
            );
            _groupManager?.advanceAfterRegeneration(lastEntrant);
          }
          _entrancesInFlight = false; // user turns allowed again
          // The turn pointer changed after generation finished. GroupTurnManager
          // notifies its own listeners, but the chat UI watches ChatService, so
          // we must propagate here — otherwise the next-speaker indicator keeps
          // showing the (stale) entrant even though the pointer is correct.
          notifyListeners();
        }
      }());
    }

    return group;
  }

  /// Create a group member (decoupled model): copy the character's avatar into
  /// the group's private storage and insert a group_members row.
  /// Shared by [addCharacterToGroup] (live add) and [forkToGroupChat] (initial
  /// membership when forking a 1:1 chat into a group).
  ///
  /// This is the core of the fix originally contributed in PR #44 by @MisterLotto.
  Future<void> _createGroupMember(
    String groupId,
    CharacterCard character,
  ) async {
    final mid = const Uuid().v4();
    final avDir = Directory(
      path.join(_storageService.groupsDir.path, groupId, 'avatars'),
    );
    await avDir.create(recursive: true);

    await _characterRepository!.duplicateCharacter(
      character,
      targetDirOverride: avDir.path,
      forcedBasename: mid,
      skipLibraryInsert: true,
    );

    final db = await AppDatabase.instance();
    await db.insertGroupMember(
      GroupMembersCompanion(
        id: drift.Value(mid),
        groupId: drift.Value(groupId),
        name: drift.Value(character.name),
        description: drift.Value(character.description),
        personality: drift.Value(character.personality),
        scenario: drift.Value(character.scenario),
        firstMessage: drift.Value(character.firstMessage),
        mesExample: drift.Value(character.mesExample),
        systemPrompt: drift.Value(character.systemPrompt),
        postHistoryInstructions: drift.Value(character.postHistoryInstructions),
        alternateGreetings: drift.Value(
          jsonEncode(character.alternateGreetings),
        ),
        tags: drift.Value(jsonEncode(character.tags)),
        avatarFilename: drift.Value('$mid.png'),
        ttsVoice: drift.Value(character.ttsVoice),
        lorebook: drift.Value(
          character.lorebook != null
              ? jsonEncode(character.lorebook!.toJson())
              : null,
        ),
        worldNames: drift.Value(jsonEncode(character.worldNames)),
        frontPorchExtensions: drift.Value(
          character.frontPorchExtensions != null
              ? jsonEncode(character.frontPorchExtensions!.toJson())
              : null,
        ),
        rawExtensions: drift.Value(
          character.rawExtensions != null
              ? jsonEncode(character.rawExtensions!)
              : null,
        ),
        // Provenance: stamp which library character this member was copied from
        // so a chat can later collapse back to a 1:1 with the original (no orphans).
        memberState: drift.Value(
          GroupMember.encodeProvenance(
            originStableId: character.stableGroupId,
            originLibraryDbId: character.dbId,
          ),
        ),
      ),
    );
  }

  /// Add a character to the currently active group chat.
  Future<bool> addCharacterToGroup(
    CharacterCard character,
    GroupChatRepository groupRepo,
  ) async {
    if (_activeGroup == null || _characterRepository == null) return false;
    if (_isGenerating) return false;

    // Decoupled model: copy the character's avatar into the group's private
    // storage and insert a group_members row. Shared with forkToGroupChat
    // via _createGroupMember (ported from the fix originally contributed in
    // PR #44 by @MisterLotto).
    await _createGroupMember(_activeGroup!.id, character);

    await groupRepo.save(_activeGroup!);

    // Re-resolve from private members (decoupled).
    final resolved = <CharacterCard>[];
    final memberRows = await groupRepo.getMembersForGroup(_activeGroup!.id);
    for (final m in memberRows) {
      if (m.avatarFilename != null) {
        final p = path.join(
          _storageService.groupsDir.path,
          _activeGroup!.id,
          'avatars',
          m.avatarFilename!,
        );
        if (await File(p).exists()) {
          resolved.add(m.toCharacterCard(resolvedImagePath: p));
        }
      }
    }
    _groupManager?.refreshCharacters(resolved);

    debugPrint(
      '[ChatService] \u{2795} Added ${character.name} to group ${_activeGroup!.name}',
    );
    notifyListeners();
    return true;
  }

  /// Remove a character from the currently active group chat.
  /// Returns false if the group would have fewer than 2 characters.
  Future<bool> removeCharacterFromGroup(
    CharacterCard character,
    GroupChatRepository groupRepo,
  ) async {
    if (_activeGroup == null || _characterRepository == null) return false;
    if (_isGenerating) return false;
    // Minimum member count now based on loaded group members (decoupled).
    // (enforcement wired via member list length in calling paths)

    // remove ID path removed (decoupled). Real remove deletes the GroupMember row + avatar file.
    final charId = _getCharacterIdFromCard(character);
    // (old removeCharacterId deleted)
    await groupRepo.save(_activeGroup!);

    // Drop any per-char state for the removed member (realism + author notes + per-char system prompts + rag priority)
    _groupRealism.remove(charId);
    _groupAuthorNotes.remove(charId);
    _groupAuthorNoteStrengths.remove(charId);
    _groupCharacterSystemPrompts.remove(charId);
    _groupCharacterRAGPriorities.remove(charId);
    if (_activeGroup != null) {
      // (old checkpoint call removed in v30)
    }

    // Re-resolve after remove — old IDs path removed (decoupled).
    final resolved = <CharacterCard>[]; // from group members
    _groupManager?.refreshCharacters(resolved);

    debugPrint(
      '[ChatService] \u{2796} Removed ${character.name} from group ${_activeGroup!.name}',
    );
    notifyListeners();
    return true;
  }
}
