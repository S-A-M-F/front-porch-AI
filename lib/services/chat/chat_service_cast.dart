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

/// "One chat, a cast that changes" — cast-shrinking operations (Phase 3):
/// per-member cleanup on removal, and the automatic collapse of a group back to
/// a 1:1 with the original library character once only one member remains. Kept
/// out of the god file and the membership leaf to respect the 500-line cap.
extension ChatServiceCast on ChatService {
  /// Delete every trace of a removed group member so nothing is orphaned: the
  /// DB row, the private avatar file, the per-member persisted state (objectives
  /// / embeddings / data-bank — all keyed by the member's UNIQUE instance id, so
  /// scoped deletes are safe), and the six in-memory per-character maps. (The old
  /// stub dropped only five of the maps and never touched the DB row or avatar.)
  Future<void> _deleteMemberCleanup(String charId, String? avatarFilename) async {
    final groupId = _activeGroup?.id;
    await _db.deleteGroupMember(charId);
    if (groupId != null && avatarFilename != null) {
      try {
        final f = File(
          path.join(
            _storageService.groupsDir.path,
            groupId,
            'avatars',
            avatarFilename,
          ),
        );
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('[Cast] avatar delete failed (non-fatal): $e');
      }
    }
    // charId == the member's unique instance UUID, so these never touch another
    // character's rows.
    await _db.deleteObjectivesForCharacter(charId);
    await _db.deleteEmbeddingsForCharacter(charId);
    await _db.deleteDataBankEntriesForCharacter(charId);
    _groupRealism.remove(charId);
    _groupAuthorNotes.remove(charId);
    _groupAuthorNoteStrengths.remove(charId);
    _groupCharacterSystemPrompts.remove(charId);
    _groupCharacterRAGPriorities.remove(charId);
    _groupObjectives.remove(charId);
    // Per-character evolution (trait development) — mirror resetCharacterEvolution
    // so a removed member leaves no evolved-trait residue behind.
    _evolvedPersonalities.remove(charId);
    _evolvedScenarios.remove(charId);
    _groupEvolutionCounts.remove(charId);
  }

  /// Automatically collapse a group that has dropped to a SINGLE member back
  /// into a 1:1 with that member's ORIGINAL library character (a one-character
  /// group is nonsense). Re-homes the CURRENT session in place (keeps all
  /// history), carries the survivor's realism back into the 1:1 scalar columns
  /// (the inverse of Phase 2's [_carryHostRealismIntoForkedGroup]), then
  /// dissolves the now-empty group (member rows + private avatars + definition).
  ///
  /// If the survivor's origin can't be resolved (legacy/ambiguous — see
  /// [MemberOriginResolver]) it stays a one-member cast rather than guessing.
  /// Returns true if it collapsed.
  Future<bool> _collapseGroupToSolo(GroupChatRepository groupRepo) async {
    final group = _activeGroup;
    final sessionId = _currentSessionId;
    if (group == null || sessionId == null) return false;
    if (_groupCharacters.length != 1) return false;

    final sole = _groupCharacters.first;
    final soleId = _getCharacterIdFromCard(sole); // member instance id (mid)

    // Resolve the survivor back to its origin library character (Phase 1). The
    // origin link lives on the member ROW (memberState), not the loaded card.
    final rows = await groupRepo.getMembersForGroup(group.id);
    String? originStamp;
    for (final m in rows) {
      if (m.id == soleId) {
        originStamp = m.originStableId;
        break;
      }
    }
    final origin = MemberOriginResolver.resolve(
      stampedOriginStableId: originStamp,
      memberName: sole.name,
      libraryCharacters:
          _characterRepository?.characters ?? const <CharacterCard>[],
    );
    if (origin == null || origin.dbId == null) {
      debugPrint('[Cast] collapse skipped: ${sole.name} origin unresolvable');
      _setGuestStatus(
        '⚠ Couldn’t match ${sole.name} back to a library character, so this '
        'stays a group. (Re-import or rename it to match the original.)',
        isError: true,
      );
      notifyListeners();
      return false;
    }

    // Safety: only auto-dissolve when THIS is the group's only session. Dissolving
    // (groupRepo.delete) hard-deletes every session of the group AND its messages,
    // so if the user started other conversations in this group, collapsing here
    // would destroy them. In that (rare) case stay a one-member cast instead.
    final groupSessions = await _db.getSessionsForGroup(group.id);
    if (groupSessions.length > 1) {
      debugPrint(
        '[Cast] collapse skipped: group "${group.name}" has '
        '${groupSessions.length} sessions — not auto-dissolving (would lose history)',
      );
      _setGuestStatus(
        '⚠ This group has other saved conversations, so it can’t auto-collapse '
        'to a 1:1. Delete the other group chats first.',
        isError: true,
      );
      notifyListeners();
      return false;
    }

    // 1) While still in group mode, load the survivor's per-character realism
    //    into the working scalars and snapshot it (the same snapshot shape
    //    regenerate/Phase-2 use, incl. time + needs).
    final bool wasRealismOn = _realismEnabled;
    final bool wasNeedsOn = _needsSimEnabled;
    Map<String, dynamic>? snapshot;
    if (wasRealismOn) {
      _loadGroupRealismIntoScalars(soleId);
      snapshot = _captureRealismState();
    }

    // 2) Re-home the session to a 1:1 owned by the library character. Bump
    //    createdAt so setActiveCharacter's most-recent-session load lands on
    //    exactly this session; clear group_realism_state so the 1:1 load doesn't
    //    try to hydrate group state.
    final reHomed = await _db.patchSession(
      SessionsCompanion(
        id: drift.Value(sessionId),
        groupId: const drift.Value(null),
        characterId: drift.Value(origin.dbId),
        groupRealismState: const drift.Value('{}'),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    if (!reHomed) {
      // Session row not found — abort BEFORE dissolving so we never delete the
      // group while its session is still group-homed (which would orphan it).
      debugPrint('[Cast] collapse aborted: re-home patchSession matched no row');
      notifyListeners();
      return false;
    }

    // 3) Dissolve the now-empty group: member rows + private avatars + the group
    //    definition. The re-homed session's groupId is null, so the repo's
    //    by-groupId session sweep cannot touch it (its history survives).
    await groupRepo.delete(group.id);

    // Clean up the survivor's now-orphaned per-member persisted state: its member
    // row is gone, and the collapsed 1:1 keys realism/memory by the library id,
    // not the old instance id — so drop the group's RAG embeddings + the
    // survivor's objectives/data-bank rows so nothing dangles. (Group-era quests
    // and semantic memory do NOT carry into the 1:1 — messages and realism do;
    // re-keying for full continuity is a future refinement.)
    try {
      await _db.deleteEmbeddingsForCharacter('group_${group.id}');
      await _db.deleteObjectivesForCharacter(soleId);
      await _db.deleteDataBankEntriesForCharacter(soleId);
    } catch (e) {
      debugPrint('[Cast] orphan cleanup (non-fatal): $e');
    }

    // 4) Re-enter as a 1:1 on the re-homed session (newest → loaded). Safety net:
    //    force the exact session if some other session of this character is newer.
    await setActiveCharacter(origin);
    if (_currentSessionId != sessionId) {
      await loadSession(sessionId);
    }

    // 5) Restore the carried realism into the 1:1 scalars and persist to the
    //    session's scalar columns (setActiveCharacter reset them; the re-homed
    //    session's stale columns are overwritten here with the survivor's state).
    if (wasRealismOn && snapshot != null) {
      _realismEnabled = true;
      _needsSimEnabled = wasNeedsOn;
      _relationshipService.restoreFromMessageState(snapshot);
      _moodDecayCounter =
          (snapshot['moodDecayCounter'] as int?) ?? _moodDecayCounter;
      _characterEmotion =
          (snapshot['characterEmotion'] as String?) ?? _characterEmotion;
      _emotionIntensity =
          (snapshot['emotionIntensity'] as String?) ?? _emotionIntensity;
      _nsfwService.restoreNsfwFromMessageState(snapshot);
      _timeService.restoreTimeFromRealismState(snapshot);
      if (wasNeedsOn) {
        final needs = snapshot['needs'];
        if (needs is Map && needs['vector'] is Map) {
          _needsSimulation.restoreFromSnapshot({
            'vector': Map<String, int>.from(needs['vector'] as Map),
          });
        } else {
          _needsSimulation.initializeFresh();
        }
      } else {
        _needsSimulation.clearVector();
      }
      await _saveChat();
    }
    notifyListeners();
    debugPrint('[Cast] collapsed group "${group.name}" → 1:1 with ${origin.name}');
    return true;
  }
}
