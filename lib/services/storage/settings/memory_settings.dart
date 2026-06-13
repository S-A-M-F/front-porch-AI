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

import 'settings_base.dart';

/// RAG / memory, summary, auto-persona, character evolution, fact extraction
/// intervals and toggles (memory_settings per Stage 7 plan).
///
/// Lifted mechanical.
class MemorySettings with SettingsBase {
  // Summary
  bool _summaryEnabled = false;
  int _summaryInterval = 10;
  int _summaryMaxWords = 200;
  static const String defaultSummaryPrompt =
      'Provide a concise summary of the conversation so far in {{words}} words or fewer. '
      'Focus on: key plot points, character developments, important decisions, emotional shifts, '
      'and any established facts. Preserve character names, locations, and relationships. '
      'If a previous summary exists, update it with new events rather than starting fresh.';
  String _summaryPrompt = defaultSummaryPrompt;

  // RAG
  bool _ragEnabled = false;
  int _ragRetrievalCount = 10;
  int _ragWindowSize = 5;
  String _ragEmbeddingSource = 'auto';
  String _ragEmbeddingModel = 'text-embedding-3-small';

  // Auto persona / fact / evolution (unified cadence in practice)
  bool _autoPersonaEnabled = false;
  int _autoPersonaInterval = 10;
  bool _characterEvolutionEnabled = false;
  int _evolutionInterval = 10;

  bool get summaryEnabled => _summaryEnabled;
  int get summaryInterval => _summaryInterval;
  int get summaryMaxWords => _summaryMaxWords;
  String get summaryPrompt => _summaryPrompt;

  bool get ragEnabled => _ragEnabled;
  int get ragRetrievalCount => _ragRetrievalCount;
  int get ragWindowSize => _ragWindowSize;
  String get ragEmbeddingSource => _ragEmbeddingSource;
  String get ragEmbeddingModel => _ragEmbeddingModel;

  bool get autoPersonaEnabled => _autoPersonaEnabled;
  int get autoPersonaInterval => _autoPersonaInterval;
  bool get characterEvolutionEnabled => _characterEvolutionEnabled;
  int get evolutionInterval => _evolutionInterval;

  void load() {
    _summaryEnabled = prefs?.getBool(k('summary_enabled')) ?? false;
    _summaryInterval = prefs?.getInt(k('summary_interval')) ?? 10;
    _summaryMaxWords = prefs?.getInt(k('summary_max_words')) ?? 200;
    _summaryPrompt =
        prefs?.getString(k('summary_prompt')) ?? defaultSummaryPrompt;

    _ragEnabled = prefs?.getBool(k('rag_enabled')) ?? false;
    _ragRetrievalCount = prefs?.getInt(k('rag_retrieval_count')) ?? 5;
    _ragWindowSize = prefs?.getInt(k('rag_window_size')) ?? 5;
    _ragEmbeddingSource = prefs?.getString(k('rag_embedding_source')) ?? 'auto';
    _ragEmbeddingModel =
        prefs?.getString(k('rag_embedding_model')) ?? 'text-embedding-3-small';

    _autoPersonaEnabled = prefs?.getBool(k('auto_persona_enabled')) ?? false;
    _autoPersonaInterval = prefs?.getInt(k('auto_persona_interval')) ?? 10;

    _characterEvolutionEnabled =
        prefs?.getBool(k('character_evolution_enabled')) ?? false;
    _evolutionInterval = prefs?.getInt(k('evolution_interval')) ?? 10;
  }

  Future<void> setSummaryEnabled(bool value) async {
    _summaryEnabled = value;
    await prefs?.setBool(k('summary_enabled'), value);
    notify();
  }

  Future<void> setSummaryInterval(int value) async {
    _summaryInterval = value.clamp(3, 50);
    await prefs?.setInt(k('summary_interval'), _summaryInterval);
    notify();
  }

  Future<void> setSummaryMaxWords(int value) async {
    _summaryMaxWords = value.clamp(50, 1000);
    await prefs?.setInt(k('summary_max_words'), _summaryMaxWords);
    notify();
  }

  Future<void> setSummaryPrompt(String value) async {
    _summaryPrompt = value;
    await prefs?.setString(k('summary_prompt'), value);
    notify();
  }

  Future<void> setRagEnabled(bool value) async {
    _ragEnabled = value;
    await prefs?.setBool(k('rag_enabled'), value);
    notify();
  }

  Future<void> setRagRetrievalCount(int value) async {
    _ragRetrievalCount = value.clamp(0, 50);
    await prefs?.setInt(k('rag_retrieval_count'), _ragRetrievalCount);
    notify();
  }

  Future<void> setRagWindowSize(int value) async {
    _ragWindowSize = value.clamp(2, 15);
    await prefs?.setInt(k('rag_window_size'), _ragWindowSize);
    notify();
  }

  Future<void> setRagEmbeddingSource(String value) async {
    _ragEmbeddingSource = value;
    await prefs?.setString(k('rag_embedding_source'), value);
    notify();
  }

  Future<void> setRagEmbeddingModel(String value) async {
    _ragEmbeddingModel = value;
    await prefs?.setString(k('rag_embedding_model'), value);
    notify();
  }

  Future<void> setAutoPersonaEnabled(bool value) async {
    _autoPersonaEnabled = value;
    await prefs?.setBool(k('auto_persona_enabled'), value);
    notify();
  }

  Future<void> setAutoPersonaInterval(int value) async {
    _autoPersonaInterval = value.clamp(5, 50);
    await prefs?.setInt(k('auto_persona_interval'), _autoPersonaInterval);
    notify();
  }

  Future<void> setCharacterEvolutionEnabled(bool value) async {
    _characterEvolutionEnabled = value;
    await prefs?.setBool(k('character_evolution_enabled'), value);
    notify();
  }

  Future<void> setEvolutionInterval(int value) async {
    _evolutionInterval = value.clamp(10, 50);
    await prefs?.setInt(k('evolution_interval'), _evolutionInterval);
    notify();
  }
}
