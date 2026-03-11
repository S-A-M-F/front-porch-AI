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

import 'dart:ui' show Locale;
import 'package:flutter/services.dart';
import 'package:simple_spell_checker/simple_spell_checker.dart';
import 'package:simple_spell_checker_en_lan/simple_spell_checker_en_lan.dart';

/// Custom [SpellCheckService] for Linux and Windows desktop,
/// powered by [SimpleSpellChecker] with a bundled English dictionary.
class DesktopSpellCheckService extends SpellCheckService {
  static bool _registered = false;
  late final _SpellCheckerHelper _checker;

  DesktopSpellCheckService() {
    if (!_registered) {
      SimpleSpellCheckerEnRegister.registerLan();
      _registered = true;
    }
    _checker = _SpellCheckerHelper(language: 'en', caseSensitive: false);
  }

  // Simple word boundary regex — matches alphabetical words and contractions
  static final _wordPattern = RegExp(r"[a-zA-Z']+");

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async {
    if (text.trim().isEmpty) return null;

    final suggestions = <SuggestionSpan>[];

    for (final match in _wordPattern.allMatches(text)) {
      final word = match.group(0)!;
      // Skip very short words (1-2 chars) to reduce false positives
      if (word.length <= 2) continue;
      // Skip words that are all apostrophes
      if (word.replaceAll("'", '').isEmpty) continue;

      if (!_checker.checkWord(word)) {
        suggestions.add(
          SuggestionSpan(
            TextRange(start: match.start, end: match.end),
            <String>[], // No suggestions — just highlighting
          ),
        );
      }
    }

    return suggestions.isEmpty ? null : suggestions;
  }

  void dispose() {
    _checker.dispose();
  }
}

/// Subclass to expose the @protected [isWordValid] method.
class _SpellCheckerHelper extends SimpleSpellChecker {
  _SpellCheckerHelper({required super.language, super.caseSensitive});

  bool checkWord(String word) => isWordValid(word);
}
