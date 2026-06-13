// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Software Foundation, either version 3 of the License, or
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

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';

/// Plain (non-ChangeNotifier) domain service owning lorebook keyword scanning,
/// trigger/depth state mutation on the live LorebookEntry objects, the
/// _matchKeyword logic (wildcard + exact word-boundary with the raw-string +
/// explicit concat fix), depth decrement (post-AI only for pre-AI triggered
/// entries to preserve sticky for AI-discovered lore), and reset of non-constant
/// trigger state.
///
/// LorebookEntry (isTriggered, remainingDepth, stickyDepth, constant, key,
/// enabled, content, name) + Lorebook live on CharacterCard.lorebook and
/// World.lorebook (part of loaded card/group/world data from DB). The scanner
/// mutates them in-place (exact mechanical preservation of prior behavior).
/// Scanner owns no separate trigger map or per-char state.
///
/// ChatService owns the instance via late final (after nsfw) + thin
/// delegations at call sites. 0 new private methods in god.
///
/// Cross-state for characters (group vs 1:1: _groupCharacters vs _activeCharacter)
/// and world lookup (_worldRepository) supplied exclusively via 3 granular cbs
/// at construction: onNotify, getLoreCharacters, resolveWorld.
/// (Mirrors nsfw's 3-group-cbs + time/relationship granular patterns.)
/// This keeps the service testable in isolation (createTestLorebookScanner with
/// live closures), avoids cycles with god's _groupRealism / _messages / load/save
/// / pending / active state, and is future-friendly for step8+ prompt builders.
///
/// 1:1 vs group parity preserved exactly: group has group-level lorebook +
/// per-member char lorebooks + per-char attached worlds; scanner's scan/reset
/// always process the characters provided by the cb (which for group is all
/// _groupCharacters, for 1:1 the single); depth tracking per-entry works for
/// members. (Inherit flag affects only god's getActive/build filters for
/// injection/sidebar, not scanning/triggering — preserved.)
///
/// Boundaries kept in god (per plan for step 7 / step 8):
/// - getActiveGroupLoreEntries (for lorebook sidebar) + _buildLorebookContext
///   (the prompt injection text builder) + pre-AI triggered snapshot collection
///   stay in god. (They contain the (triggered || constant) filter logic on
///   entries; lorebook injection text / full context building kept thin/stayed
///   in god per plan for step8.)
/// - The keep reset blocks in sync sites (startNewChat 1:1+group both branches now explicit,
///   setActive*, _loadLastSession incl. empty/0-session, setActiveGroup x2, ext-seed, delete,
///   fork, group paths, regen/swipe; 6 call sites on-disk for resetLorebookTriggerState) now call scanner.reset + list
///   lorebook_scanner explicitly in comments (cross-ref to prior nsfw/time
///   hygiene; startNew hygiene completed per review).
/// - oneShot vs normal lorebook parity qualified: scan on finalResponse +
///   preAi decr after AI, user-text scan in sendMessage, greeting scans, and
///   resets are all delegated (dispatch preserved exactly); no behavior change.
///
/// @Deprecated shims: none (scan/match/decr were private _ ; getActiveGroupLoreEntries
/// public getter body stays in god for smallest mechanical change — no body moved).
///
/// 0 new private methods added to ChatService as part of this step (thins +
/// delegations at all ~10 call sites + reset calls in keep-sync blocks only;
/// deletions of moved code are mandatory part of the task).
///
/// aug exercising only passive/qualified (resets/loads/scans/greetings hit by
/// pre-existing startNew/setActive/_loadLast/group/greeting/sendMessage paths
/// in key suites; full keyword/depth/scan/inject behavior only in dedicated + manual).
/// test count via grep -c '^\s*test(' post any delete/edge (modeled on nsfw).
/// real owner dispatch via live wiring in key suites (realism_engine, group_realism,
/// session etc).
///
/// lorebook injection text / full context building kept thin/stayed in god per plan for step8.
class LorebookScanner {
  final VoidCallback onNotify;
  final List<CharacterCard> Function() getLoreCharacters;
  final World? Function(String name) resolveWorld;

  LorebookScanner({
    required this.onNotify,
    required this.getLoreCharacters,
    required this.resolveWorld,
  });

  // ── Public surface (for thin delegations in ChatService + direct test callers) ──

  /// Scan the given text against relevant lorebooks for current context
  /// (group members or the active 1:1 char + their attached worlds).
  /// For each enabled entry, split its comma key, test _matchKeyword (lower),
  /// on hit: set isTriggered=true (if not), remainingDepth=stickyDepth.
  /// If any change, calls onNotify (matches original notifyListeners).
  /// Verbatim from god _scanLorebook.
  void scanLorebook(String text) {
    final characters = getLoreCharacters();
    if (characters.isEmpty) return;

    final lowerText = text.toLowerCase();
    bool changed = false;

    for (final ch in characters) {
      if (ch.lorebook != null) {
        for (final entry in ch.lorebook!.entries) {
          if (!entry.enabled) continue;

          final keys = entry.key
              .split(',')
              .map((k) => k.trim().toLowerCase())
              .where((k) => k.isNotEmpty)
              .toList();

          for (final key in keys) {
            if (_matchKeyword(key, lowerText)) {
              if (!entry.isTriggered) {
                entry.isTriggered = true;
                changed = true;
              }
              entry.remainingDepth = entry.stickyDepth;
              break;
            }
          }
        }
      }

      // Scan shared Worlds
      for (final worldName in ch.worldNames) {
        final world = resolveWorld(worldName);
        if (world == null) continue;

        for (final entry in world.lorebook.entries) {
          if (!entry.enabled) continue;

          final keys = entry.key
              .split(',')
              .map((k) => k.trim().toLowerCase())
              .where((k) => k.isNotEmpty)
              .toList();

          for (final key in keys) {
            if (_matchKeyword(key, lowerText)) {
              if (!entry.isTriggered) {
                entry.isTriggered = true;
                changed = true;
              }
              entry.remainingDepth = entry.stickyDepth;
              break;
            }
          }
        }
      }
    }

    if (changed) {
      onNotify();
    }
  }

  /// Match a keyword against text with wildcard (*) and word-boundary support.
  /// - `pot*` matches `potato`, `pottery`, `potion`
  /// - `fire` matches `fire` (whole word only, not `fireball`)
  /// - `*ball` matches `fireball`, `snowball`
  ///
  /// Preserves the raw-string + string concatenation fix exactly:
  ///   RegExp(r'\b' + RegExp.escape(key) + r'\b')
  /// (Because Dart raw strings (r'...') do not process ${} interpolation;
  /// the original god code had this comment + fix for the gotcha.)
  bool _matchKeyword(String key, String text) {
    if (key.contains('*')) {
      // Wildcard pattern: escape regex specials except *, then replace * with .*
      final escaped = RegExp.escape(key).replaceAll(r'\*', '.*');
      return RegExp(escaped).hasMatch(text);
    } else {
      // Exact word match with word boundaries
      // Using string concatenation instead of ${} inside a raw string
      // because Dart raw strings (r'...') do not process ${} interpolation.
      return RegExp(r'\b' + RegExp.escape(key) + r'\b').hasMatch(text);
    }
  }

  /// Public exposure of keyword matcher for tests (and any direct callers).
  /// Delegates to the internal impl (preserves the concat/raw fix).
  bool matchKeyword(String key, String text) => _matchKeyword(key, text);

  /// Decrement remainingDepth only for the provided set of entries.
  /// Used after AI response finalization so that lore entries *discovered in the AI's
  /// own response* keep their full stickyDepth for the next user turn.
  /// Only non-constant entries are decremented; when remaining <=0 , isTriggered=false.
  /// If any un-trigger happens, calls onNotify.
  /// Verbatim from god _decrementLoreDepthForEntries.
  void decrementLoreDepthForEntries(Set<LorebookEntry> entriesToDecrement) {
    if (entriesToDecrement.isEmpty) return;
    bool changed = false;

    for (final entry in entriesToDecrement) {
      if (entry.isTriggered && !entry.constant) {
        entry.remainingDepth--;
        if (entry.remainingDepth <= 0) {
          entry.isTriggered = false;
          changed = true;
        }
      }
    }

    if (changed) {
      onNotify();
    }
  }

  /// Reset lorebook trigger state (isTriggered=false + remainingDepth=0) for
  /// all non-constant entries on the current characters (via cb) + their
  /// attached world lorebooks.
  /// Constant entries are explicitly skipped (they are always active if enabled).
  /// Replaces all prior inline reset blocks in god; supports the "keep reset
  /// blocks in sync" hygiene across startNew/setActive/load/empty/group etc.
  /// No notify (original zeros did not notify inside the block; load/greeting
  /// etc drive subsequent UI).
  void resetLorebookTriggerState() {
    final characters = getLoreCharacters();
    for (final ch in characters) {
      if (ch.lorebook != null) {
        for (final entry in ch.lorebook!.entries) {
          if (!entry.constant) {
            entry.isTriggered = false;
            entry.remainingDepth = 0;
          }
        }
      }
      for (final worldName in ch.worldNames) {
        final world = resolveWorld(worldName);
        if (world != null) {
          for (final entry in world.lorebook.entries) {
            if (!entry.constant) {
              entry.isTriggered = false;
              entry.remainingDepth = 0;
            }
          }
        }
      }
    }
  }
}
