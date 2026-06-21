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
import 'dart:developer';

/// A side character the primary (host) narrated into the scene who looks like a
/// recurring, named participant the user might want to promote to a Scene Guest.
class DetectedCharacter {
  const DetectedCharacter({required this.name, required this.descriptor});

  /// The proper name the host gave them (e.g. "Mara", "Old Bartender Greaves").
  final String name;

  /// A one-line descriptor used as the mint concept (e.g. "the host's sister").
  final String descriptor;
}

/// Periodically scans the recent PRIMARY narration of a 1:1 chat for a newly
/// introduced, recurring, NAMED side character and surfaces it as a candidate
/// Scene Guest (Lite NPC).
///
/// Pure leaf, modelled exactly on [SceneGuestDirector]: it never imports
/// `ChatService` (or any heavy service); everything it needs is injected as a
/// small callback, so it stays unit-testable with plain closures. It does ZERO
/// Realism / Needs work — it only reads text and proposes a name. Accepting the
/// proposal routes back through the existing parity-safe mint+enter flow.
///
/// One token-cheap LLM eval per scan (reusing the injected [fireLLMEval] +
/// [stripThinkBlocks] surface — no new LLM-firing path). It asks for any
/// newly-introduced, named character who appears to be a RECURRING participant
/// (not a one-off passing mention, not the host, not the user), returning strict
/// JSON `{"name": ..., "descriptor": ...}` or `{"name": null}`. It defaults to
/// "no detection" on empty / parse failure (the KoboldCPP empty-eval gotcha —
/// see CLAUDE.md), then filters the candidate against the host name, the user
/// name, the current Scene Guests, and the already-offered/ignored set.
class CastDetector {
  CastDetector({
    required List<String> Function() getRecentPrimaryTexts,
    required Future<String?> Function(String prompt) fireLLMEval,
    required String Function(String text) stripThinkBlocks,
    required String Function() getHostName,
    required String Function() getUserName,
    required List<String> Function() getSceneGuestNames,
    required Set<String> Function() getOfferedOrIgnoredNames,
  }) : _getRecentPrimaryTexts = getRecentPrimaryTexts,
       _fireLLMEval = fireLLMEval,
       _stripThinkBlocks = stripThinkBlocks,
       _getHostName = getHostName,
       _getUserName = getUserName,
       _getSceneGuestNames = getSceneGuestNames,
       _getOfferedOrIgnoredNames = getOfferedOrIgnoredNames;

  final List<String> Function() _getRecentPrimaryTexts;
  final Future<String?> Function(String prompt) _fireLLMEval;
  final String Function(String text) _stripThinkBlocks;
  final String Function() _getHostName;
  final String Function() _getUserName;
  final List<String> Function() _getSceneGuestNames;
  final Set<String> Function() _getOfferedOrIgnoredNames;

  /// Run one detection pass. Returns a fresh, filtered [DetectedCharacter] or
  /// `null` when there is nothing worth surfacing (no narration, empty/garbled
  /// eval, no candidate, or the candidate fails a filter).
  Future<DetectedCharacter?> detect() async {
    final texts = _getRecentPrimaryTexts()
        .where((t) => t.trim().isNotEmpty)
        .toList();
    if (texts.isEmpty) return null;

    final raw = await _fireLLMEval(_buildPrompt(texts));
    if (raw == null) return null; // empty / cancelled / backend down
    final text = _stripThinkBlocks(raw).trim();
    if (text.isEmpty) return null;

    final candidate = _parse(text);
    if (candidate == null) return null;
    return _accept(candidate) ? candidate : null;
  }

  /// Tiny extraction prompt — the recent primary narration + strict JSON only.
  String _buildPrompt(List<String> texts) {
    final host = _getHostName();
    final user = _getUserName();
    final narration = texts.map((t) => '- ${_oneLine(t)}').join('\n');
    return 'In a roleplay, "$host" is the main character and "$user" is the user. '
        'Read $host\'s recent narration below and find any OTHER named character '
        '$host has introduced who seems to be a RECURRING participant in the '
        'scene (e.g. a sibling, friend, rival, or regular like a bartender) — '
        'NOT a one-off passing mention, NOT $host, NOT $user.\n\n'
        'Recent narration:\n$narration\n\n'
        'If there is exactly one such recurring named character, respond with '
        'ONLY this JSON: {"name": "<their name>", "descriptor": "<a short '
        'phrase describing who they are>"}\n'
        'If there is no such character (or only passing mentions), respond with '
        'ONLY: {"name": null}';
  }

  /// Parse the strict JSON reply into a candidate (pre-filter). Tolerant of
  /// surrounding prose / code fences; defaults to null on any failure.
  DetectedCharacter? _parse(String text) {
    var jsonStr = text;
    if (jsonStr.contains('```')) {
      final fence = RegExp(
        r'```(?:json)?\s*\n?(.*?)\n?```',
        dotAll: true,
      ).firstMatch(jsonStr);
      if (fence != null) jsonStr = fence.group(1)!.trim();
    }
    final objMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(jsonStr);
    if (objMatch == null) return null;

    Map<String, dynamic> obj;
    try {
      obj = jsonDecode(objMatch.group(0)!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final rawName = obj['name'];
    if (rawName is! String) return null; // null or non-string → no detection
    final name = rawName.trim();
    final descriptor = (obj['descriptor'] is String)
        ? (obj['descriptor'] as String).trim()
        : '';
    return DetectedCharacter(name: name, descriptor: descriptor);
  }

  /// Final filter: require a plausible proper name and reject the host, the
  /// user, an existing Scene Guest, or anything already offered/ignored.
  bool _accept(DetectedCharacter c) {
    final name = c.name.trim();
    // Plausible proper name: non-empty and contains at least one letter.
    if (name.isEmpty || !RegExp(r'[A-Za-z]').hasMatch(name)) return false;

    final lower = name.toLowerCase();
    final host = _getHostName().trim().toLowerCase();
    final user = _getUserName().trim().toLowerCase();

    // Reject if it equals/contains the host or user name (either direction).
    if (_collides(lower, host) || _collides(lower, user)) {
      log('[CastDetector] Rejected "$name" (host/user collision).');
      return false;
    }

    // Reject names already present as Scene Guests.
    for (final g in _getSceneGuestNames()) {
      if (_collides(lower, g.trim().toLowerCase())) {
        log('[CastDetector] Rejected "$name" (already a scene guest).');
        return false;
      }
    }

    // Reject anything already offered or explicitly ignored this session.
    if (_getOfferedOrIgnoredNames().contains(lower)) {
      log('[CastDetector] Rejected "$name" (already offered/ignored).');
      return false;
    }
    return true;
  }

  /// Case-insensitive collision: true when either name contains the other
  /// (guards against "Mara" vs "Mara Vance" and the host's first name).
  bool _collides(String a, String b) {
    if (b.isEmpty) return false;
    return a == b || a.contains(b) || b.contains(a);
  }

  String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
