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

/// STT / Whisper + call mode settings.
///
/// Lifted Stage 7.
class SttSettings with SettingsBase {
  bool _sttEnabled = false;
  String _whisperModel = 'base.en'; // 'tiny.en', 'base.en', 'small.en'
  bool _autoSendTranscription = false;
  String? _selectedMicId;
  String _callModelName = '';
  int _callBufferSentences = 3;
  String _callSystemPrompt =
      'You are on a live voice call. Respond naturally as if speaking on the phone. '
      'ALWAYS write in first person — never narrate in third person. '
      'Keep responses concise: 1-3 sentences max. '
      'No actions, no narration, no stage directions — just speak directly.';

  bool get sttEnabled => _sttEnabled;
  String get whisperModel => _whisperModel;
  bool get autoSendTranscription => _autoSendTranscription;
  String? get selectedMicId => _selectedMicId;
  String get callModelName => _callModelName;
  int get callBufferSentences => _callBufferSentences;
  String get callSystemPrompt => _callSystemPrompt;

  void load() {
    _sttEnabled = prefs?.getBool(k('stt_enabled')) ?? false;
    _whisperModel = prefs?.getString(k('whisper_model')) ?? 'base.en';
    _autoSendTranscription =
        prefs?.getBool(k('auto_send_transcription')) ?? false;
    _selectedMicId = prefs?.getString(k('selected_mic_id'));
    _callModelName = prefs?.getString(k('call_model_name')) ?? '';
    _callBufferSentences = prefs?.getInt(k('call_buffer_sentences')) ?? 3;
    final savedCallPrompt = prefs?.getString(k('call_system_prompt'));
    if (savedCallPrompt != null) _callSystemPrompt = savedCallPrompt;
  }

  Future<void> setSttEnabled(bool value) async {
    _sttEnabled = value;
    await prefs?.setBool(k('stt_enabled'), value);
    notify();
  }

  Future<void> setWhisperModel(String value) async {
    _whisperModel = value;
    await prefs?.setString(k('whisper_model'), value);
    notify();
  }

  Future<void> setAutoSendTranscription(bool value) async {
    _autoSendTranscription = value;
    await prefs?.setBool(k('auto_send_transcription'), value);
    notify();
  }

  Future<void> setSelectedMicId(String? value) async {
    _selectedMicId = value;
    if (value != null) {
      await prefs?.setString(k('selected_mic_id'), value);
    } else {
      await prefs?.remove(k('selected_mic_id'));
    }
    notify();
  }

  Future<void> setCallModelName(String value) async {
    _callModelName = value;
    await prefs?.setString(k('call_model_name'), value);
    notify();
  }

  Future<void> setCallBufferSentences(int value) async {
    _callBufferSentences = value.clamp(1, 10);
    await prefs?.setInt(k('call_buffer_sentences'), _callBufferSentences);
    notify();
  }

  Future<void> setCallSystemPrompt(String value) async {
    _callSystemPrompt = value;
    await prefs?.setString(k('call_system_prompt'), value);
    notify();
  }
}
