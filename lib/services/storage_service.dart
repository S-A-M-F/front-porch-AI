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

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:front_porch_ai/app_version.dart';
import '../models/character_card.dart';

// Stage 7: storage decomposition (directories + domain settings; shims preserve public API)
import 'storage/directories.dart';
import 'storage/settings/generation_settings.dart';
import 'storage/settings/backend_settings.dart';
import 'storage/settings/ui_settings.dart';
import 'storage/settings/tts_settings.dart';
import 'storage/settings/stt_settings.dart';
import 'storage/settings/image_gen_settings.dart';
import 'storage/settings/expression_settings.dart';
import 'storage/settings/web_server_settings.dart';
import 'storage/settings/cloud_sync_settings.dart';
import 'storage/settings/realism_settings.dart';
import 'storage/settings/memory_settings.dart';
import 'storage/settings/preset_settings.dart';

class StorageService extends ChangeNotifier {
  final Completer<void> _initCompleter = Completer<void>();
  Future<void> get initialized => _initCompleter.future;

  SharedPreferences? _prefs;
  String? _rootPath;
  String? _customModelsPath;
  Directory? _binDir;

  // Stage 7: domain settings (plain classes + base mixin; single Storage ChangeNotifier surface)
  late final GenerationSettings _generationSettings = GenerationSettings();
  late final BackendSettings _backendSettings = BackendSettings();
  late final UiSettings _uiSettings = UiSettings();
  late final TtsSettings _ttsSettings = TtsSettings();
  late final SttSettings _sttSettings = SttSettings();
  late final ImageGenSettings _imageGenSettings = ImageGenSettings();
  late final ExpressionSettings _expressionSettings = ExpressionSettings();
  late final WebServerSettings _webServerSettings = WebServerSettings();
  late final CloudSyncSettings _cloudSyncSettings = CloudSyncSettings();
  late final RealismSettings _realismSettings = RealismSettings();
  late final MemorySettings _memorySettings = MemorySettings();
  late final PresetSettings _presetSettings = PresetSettings();

  // Directories lifted to directories.dart (Stage 7); thin god owns root state for setRootPath.
  // Getter ensures live values after setRootPath / setCustomModelsPath.
  AppDirectories get directories =>
      AppDirectories(rootPath: _rootPath, customModelsPath: _customModelsPath);

  String? get rootPath => _rootPath;
  String? get customModelsPath => _customModelsPath;
  Directory get binDir => _binDir ?? Directory(_rootPath ?? '');
  Directory get modelsDir => directories.modelsDir;
  Directory get chatsDir => directories.chatsDir;
  Directory get worldsDir => directories.worldsDir;

  Directory get charactersDir => directories.charactersDir;

  /// Directory for all group-private data (decoupled from singular library characters).
  /// Each group gets its own subdirectory (by group id) under here to store its
  /// member avatar PNGs (primary only; no multi-avatar or expressions per spec).
  /// Group data is NEVER written to or resolved from the global charactersDir or library.
  /// The only bridge to library is the user's explicit "Separate to my library" action.
  Directory get groupsDir => directories.groupsDir;

  File resolveCharacterImage(String imagePath) =>
      directories.resolveCharacterImage(imagePath);

  Directory characterAvatarDir(String characterName) =>
      directories.characterAvatarDir(characterName);

  Directory get customBackgroundDir => directories.customBackgroundDir;

  // === Stage 7 backward-compat shims (exact public API preserved; callers need no changes) ===
  // All delegate to the extracted *Settings (or directories). @Deprecated per plan.
  // Once callers migrate (future), thin drops to ~dir mgmt + init + _k/root helpers.

  // Directories (already delegated above; root/custom exposed for setRootPath consumers)

  // Generation
  @Deprecated('Use generationSettings.systemPrompt (Stage 7)')
  String get systemPrompt => _generationSettings.systemPrompt;
  static const String defaultSystemPrompt =
      GenerationSettings.defaultSystemPrompt;

  @Deprecated('Use generationSettings (Stage 7)')
  Future<void> setSystemPrompt(String value) =>
      _generationSettings.setSystemPrompt(value);
  @Deprecated('Use generationSettings (Stage 7)')
  Future<void> setMinP(double value) => _generationSettings.setMinP(value);
  @Deprecated('Use generationSettings (Stage 7)')
  Future<void> setTemperature(double value) =>
      _generationSettings.setTemperature(value);
  @Deprecated('Use generationSettings (Stage 7)')
  Future<void> setRepeatPenalty(double value) =>
      _generationSettings.setRepeatPenalty(value);
  @Deprecated('Use generationSettings (Stage 7)')
  Future<void> setRepeatPenaltyTokens(int value) =>
      _generationSettings.setRepeatPenaltyTokens(value);
  @Deprecated('Use generationSettings (Stage 7)')
  Future<void> setDynamicTempEnabled(bool value) =>
      _generationSettings.setDynamicTempEnabled(value);
  @Deprecated('Use generationSettings (Stage 7)')
  Future<void> setDynamicTempRange(double value) =>
      _generationSettings.setDynamicTempRange(value);
  @Deprecated('Use generationSettings (Stage 7)')
  Future<void> setXtcThreshold(double value) =>
      _generationSettings.setXtcThreshold(value);
  @Deprecated('Use generationSettings (Stage 7)')
  Future<void> setXtcProbability(double value) =>
      _generationSettings.setXtcProbability(value);
  @Deprecated('Use generationSettings (Stage 7)')
  Future<void> setMaxLength(int value) =>
      _generationSettings.setMaxLength(value);
  @Deprecated('Use generationSettings (Stage 7)')
  Future<void> setMinLength(int value) =>
      _generationSettings.setMinLength(value);
  @Deprecated('Use generationSettings (Stage 7)')
  Future<void> setStopSequences(List<String> value) =>
      _generationSettings.setStopSequences(value);
  @Deprecated('Use generationSettings (Stage 7)')
  Future<void> addStopSequence(String value) =>
      _generationSettings.addStopSequence(value);
  @Deprecated('Use generationSettings (Stage 7)')
  Future<void> removeStopSequence(String value) =>
      _generationSettings.removeStopSequence(value);

  double get minP => _generationSettings.minP;
  double get temperature => _generationSettings.temperature;
  double get repeatPenalty => _generationSettings.repeatPenalty;
  int get repeatPenaltyTokens => _generationSettings.repeatPenaltyTokens;
  bool get dynamicTempEnabled => _generationSettings.dynamicTempEnabled;
  double get dynamicTempRange => _generationSettings.dynamicTempRange;
  double get xtcThreshold => _generationSettings.xtcThreshold;
  double get xtcProbability => _generationSettings.xtcProbability;
  int get maxLength => _generationSettings.maxLength;
  int get minLength => _generationSettings.minLength;
  List<String> get stopSequences => _generationSettings.stopSequences;

  // Backend (remote, reasoning, launch flags, kcpps, gpu/context)
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setBackendType(String value) =>
      _backendSettings.setBackendType(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setRemoteApiKey(String value) =>
      _backendSettings.setRemoteApiKey(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setRemoteApiUrl(String value) =>
      _backendSettings.setRemoteApiUrl(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setRemoteModelName(String value) =>
      _backendSettings.setRemoteModelName(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setReasoningEnabled(bool value) =>
      _backendSettings.setReasoningEnabled(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setReasoningEffort(String value) =>
      _backendSettings.setReasoningEffort(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setKoboldThinkingModel(bool value) =>
      _backendSettings.setKoboldThinkingModel(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setAutostartBackend(bool value) =>
      _backendSettings.setAutostartBackend(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setAutostartPseudoRemote(bool value) =>
      _backendSettings.setAutostartPseudoRemote(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setLastUsedModelPath(String? value) =>
      _backendSettings.setLastUsedModelPath(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setActiveKcppsPath(String? value) =>
      _backendSettings.setActiveKcppsPath(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setUseCublas(bool value) => _backendSettings.setUseCublas(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setUseVulkan(bool value) => _backendSettings.setUseVulkan(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setUseMetal(bool value) => _backendSettings.setUseMetal(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setUseRocm(bool value) => _backendSettings.setUseRocm(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setFlashAttentionEnabled(bool value) =>
      _backendSettings.setFlashAttentionEnabled(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setMlockEnabled(bool value) =>
      _backendSettings.setMlockEnabled(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setBlasBatchSize(int value) =>
      _backendSettings.setBlasBatchSize(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setGpuId(int value) => _backendSettings.setGpuId(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setGpuLayers(int value) => _backendSettings.setGpuLayers(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setContextSize(int value) =>
      _backendSettings.setContextSize(value);
  @Deprecated('Use backendSettings (Stage 7)')
  Future<void> setModelPreset(String modelPath, String? kcppsPath) =>
      _presetSettings.setModelPreset(modelPath, kcppsPath);

  String get backendType => _backendSettings.backendType;
  String get remoteApiKey => _backendSettings.remoteApiKey;
  String get remoteApiUrl => _backendSettings.remoteApiUrl;
  String get remoteModelName => _backendSettings.remoteModelName;
  bool get reasoningEnabled => _backendSettings.reasoningEnabled;
  String get reasoningEffort => _backendSettings.reasoningEffort;
  bool get koboldThinkingModel => _backendSettings.koboldThinkingModel;
  bool get autostartBackend => _backendSettings.autostartBackend;
  bool get autostartPseudoRemote => _backendSettings.autostartPseudoRemote;
  String? get lastUsedModelPath => _backendSettings.lastUsedModelPath;
  String? get activeKcppsPath => _backendSettings.activeKcppsPath;
  bool get kcppsHasModel => _backendSettings.kcppsHasModel;
  bool get kcppsModelFileExists => _backendSettings.kcppsModelFileExists;
  bool? get useCublas => _backendSettings.useCublas;
  bool? get useVulkan => _backendSettings.useVulkan;
  bool? get useMetal => _backendSettings.useMetal;
  bool? get useRocm => _backendSettings.useRocm;
  bool get flashAttentionEnabled => _backendSettings.flashAttentionEnabled;
  bool get mlockEnabled => _backendSettings.mlockEnabled;
  int get blasBatchSize => _backendSettings.blasBatchSize;
  int get gpuId => _backendSettings.gpuId;
  int get gpuLayers => _backendSettings.gpuLayers;
  int get contextSize => _backendSettings.contextSize;
  Map<String, String> get modelPresetMap => _presetSettings.modelPresetMap;

  // UI (colors, fonts, bg, buffer, sort, effective helpers)
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setBubbleOpacity(double value) =>
      _uiSettings.setBubbleOpacity(value);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setGlobalUserBubbleColor(Color value) =>
      _uiSettings.setGlobalUserBubbleColor(value);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setGlobalUserTextColor(Color value) =>
      _uiSettings.setGlobalUserTextColor(value);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setGlobalAiBubbleColor(Color value) =>
      _uiSettings.setGlobalAiBubbleColor(value);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setGlobalAiTextColor(Color value) =>
      _uiSettings.setGlobalAiTextColor(value);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setGlobalDialogueColor(Color value) =>
      _uiSettings.setGlobalDialogueColor(value);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setGlobalActionColor(Color value) =>
      _uiSettings.setGlobalActionColor(value);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setGlobalChatFontFamily(String value) =>
      _uiSettings.setGlobalChatFontFamily(value);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setIsDark(bool value) => _uiSettings.setIsDark(value);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setTextScale(double value) => _uiSettings.setTextScale(value);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setChatBackground(String value) =>
      _uiSettings.setChatBackground(value);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> addCustomBackground(String id, String name, String filePath) =>
      _uiSettings.addCustomBackground(id, name, filePath);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> removeCustomBackground(String id) =>
      _uiSettings.removeCustomBackground(id);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setDisplayBufferEnabled(bool value) =>
      _uiSettings.setDisplayBufferEnabled(value);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setTargetDisplayTps(double value) =>
      _uiSettings.setTargetDisplayTps(value);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setBufferDurationSeconds(double value) =>
      _uiSettings.setBufferDurationSeconds(value);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setSortMode(String value) => _uiSettings.setSortMode(value);
  @Deprecated('Use uiSettings (Stage 7)')
  Future<void> setGridScale(double value) => _uiSettings.setGridScale(value);

  double get bubbleOpacity => _uiSettings.bubbleOpacity;
  Color get globalUserBubbleColor => _uiSettings.globalUserBubbleColor;
  Color get globalUserTextColor => _uiSettings.globalUserTextColor;
  Color get globalAiBubbleColor => _uiSettings.globalAiBubbleColor;
  Color get globalAiTextColor => _uiSettings.globalAiTextColor;
  Color get globalDialogueColor => _uiSettings.globalDialogueColor;
  Color get globalActionColor => _uiSettings.globalActionColor;
  bool get isDark => _uiSettings.isDark;
  String get globalChatFontFamily => _uiSettings.globalChatFontFamily;
  double get textScale => _uiSettings.textScale;
  String get chatBackground => _uiSettings.chatBackground;
  List<Map<String, String>> get customBackgrounds =>
      _uiSettings.customBackgrounds;
  bool get displayBufferEnabled => _uiSettings.displayBufferEnabled;
  double get targetDisplayTps => _uiSettings.targetDisplayTps;
  double get bufferDurationSeconds => _uiSettings.bufferDurationSeconds;
  String get sortMode => _uiSettings.sortMode;
  double get gridScale => _uiSettings.gridScale;

  bool hasCustomBackgroundWithName(String name) =>
      _uiSettings.hasCustomBackgroundWithName(name);

  // Effective color/font (per-char override support preserved)
  Color getUserBubbleColor(CharacterCard? character) =>
      _uiSettings.getUserBubbleColor(character);
  Color getUserTextColor(CharacterCard? character) =>
      _uiSettings.getUserTextColor(character);
  Color getAiBubbleColor(CharacterCard? character) =>
      _uiSettings.getAiBubbleColor(character);
  Color getAiTextColor(CharacterCard? character) =>
      _uiSettings.getAiTextColor(character);
  Color getDialogueColor(CharacterCard? character) =>
      _uiSettings.getDialogueColor(character);
  Color getActionColor(CharacterCard? character) =>
      _uiSettings.getActionColor(character);
  String getChatFontFamily(CharacterCard? character) =>
      _uiSettings.getChatFontFamily(character);

  // TTS
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setTtsEnabled(bool value) => _ttsSettings.setTtsEnabled(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setTtsEngine(String value) => _ttsSettings.setTtsEngine(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setTtsVoiceModel(String value) =>
      _ttsSettings.setTtsVoiceModel(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setTtsSpeechRate(double value) =>
      _ttsSettings.setTtsSpeechRate(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setTtsAutoPlay(bool value) => _ttsSettings.setTtsAutoPlay(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setOpenaiTtsApiKey(String value) =>
      _ttsSettings.setOpenaiTtsApiKey(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setOpenaiTtsModel(String value) =>
      _ttsSettings.setOpenaiTtsModel(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setOpenaiTtsBaseUrl(String value) =>
      _ttsSettings.setOpenaiTtsBaseUrl(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setElevenlabsApiKey(String value) =>
      _ttsSettings.setElevenlabsApiKey(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setElevenlabsModel(String value) =>
      _ttsSettings.setElevenlabsModel(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setElevenlabsStability(double value) =>
      _ttsSettings.setElevenlabsStability(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setElevenlabsSimilarity(double value) =>
      _ttsSettings.setElevenlabsSimilarity(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setElevenlabsStyle(double value) =>
      _ttsSettings.setElevenlabsStyle(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setTtsNarrateQuotedOnly(bool value) =>
      _ttsSettings.setTtsNarrateQuotedOnly(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setTtsIgnoreAsterisks(bool value) =>
      _ttsSettings.setTtsIgnoreAsterisks(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setTtsConcurrency(int value) =>
      _ttsSettings.setTtsConcurrency(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setTtsAudioLookahead(int value) =>
      _ttsSettings.setTtsAudioLookahead(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setKvQuantizationLevel(int value) =>
      _ttsSettings.setKvQuantizationLevel(value);
  @Deprecated('Use ttsSettings (Stage 7)')
  Future<void> setDirectorDelay(double value) =>
      _ttsSettings.setDirectorDelay(value);

  bool get ttsEnabled => _ttsSettings.ttsEnabled;
  String get ttsEngine => _ttsSettings.ttsEngine;
  String get ttsVoiceModel => _ttsSettings.ttsVoiceModel;
  double get ttsSpeechRate => _ttsSettings.ttsSpeechRate;
  bool get ttsAutoPlay => _ttsSettings.ttsAutoPlay;
  String get openaiTtsApiKey => _ttsSettings.openaiTtsApiKey;
  String get openaiTtsModel => _ttsSettings.openaiTtsModel;
  String get openaiTtsBaseUrl => _ttsSettings.openaiTtsBaseUrl;
  String get elevenlabsApiKey => _ttsSettings.elevenlabsApiKey;
  String get elevenlabsModel => _ttsSettings.elevenlabsModel;
  double get elevenlabsStability => _ttsSettings.elevenlabsStability;
  double get elevenlabsSimilarity => _ttsSettings.elevenlabsSimilarity;
  double get elevenlabsStyle => _ttsSettings.elevenlabsStyle;
  bool get ttsNarrateQuotedOnly => _ttsSettings.ttsNarrateQuotedOnly;
  bool get ttsIgnoreAsterisks => _ttsSettings.ttsIgnoreAsterisks;
  int get ttsConcurrency => _ttsSettings.ttsConcurrency;
  int get ttsAudioLookahead => _ttsSettings.ttsAudioLookahead;
  double get directorDelay => _ttsSettings.directorDelay;
  int get kvQuantizationLevel => _ttsSettings.kvQuantizationLevel;

  // STT
  @Deprecated('Use sttSettings (Stage 7)')
  Future<void> setSttEnabled(bool value) => _sttSettings.setSttEnabled(value);
  @Deprecated('Use sttSettings (Stage 7)')
  Future<void> setWhisperModel(String value) =>
      _sttSettings.setWhisperModel(value);
  @Deprecated('Use sttSettings (Stage 7)')
  Future<void> setAutoSendTranscription(bool value) =>
      _sttSettings.setAutoSendTranscription(value);
  @Deprecated('Use sttSettings (Stage 7)')
  Future<void> setSelectedMicId(String? value) =>
      _sttSettings.setSelectedMicId(value);
  @Deprecated('Use sttSettings (Stage 7)')
  Future<void> setCallModelName(String value) =>
      _sttSettings.setCallModelName(value);
  @Deprecated('Use sttSettings (Stage 7)')
  Future<void> setCallBufferSentences(int value) =>
      _sttSettings.setCallBufferSentences(value);
  @Deprecated('Use sttSettings (Stage 7)')
  Future<void> setCallSystemPrompt(String value) =>
      _sttSettings.setCallSystemPrompt(value);

  bool get sttEnabled => _sttSettings.sttEnabled;
  String get whisperModel => _sttSettings.whisperModel;
  bool get autoSendTranscription => _sttSettings.autoSendTranscription;
  String? get selectedMicId => _sttSettings.selectedMicId;
  String get callModelName => _sttSettings.callModelName;
  int get callBufferSentences => _sttSettings.callBufferSentences;
  String get callSystemPrompt => _sttSettings.callSystemPrompt;

  // Image gen
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setImageGenEnabled(bool value) =>
      _imageGenSettings.setImageGenEnabled(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setImageGenBackend(String value) =>
      _imageGenSettings.setImageGenBackend(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setLocalImageGenUrl(String value) =>
      _imageGenSettings.setLocalImageGenUrl(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setImageGenModel(String value) =>
      _imageGenSettings.setImageGenModel(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setImageGenSize(String value) =>
      _imageGenSettings.setImageGenSize(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setImageGenNegativePrompt(String value) =>
      _imageGenSettings.setImageGenNegativePrompt(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setImageGenStyle(String value) =>
      _imageGenSettings.setImageGenStyle(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setImageGenPromptParadigm(String value) =>
      _imageGenSettings.setImageGenPromptParadigm(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setImageGenLora(String value) =>
      _imageGenSettings.setImageGenLora(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setImageGenLoraWeight(double value) =>
      _imageGenSettings.setImageGenLoraWeight(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setImageGenSteps(int value) =>
      _imageGenSettings.setImageGenSteps(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setImageGenCfgScale(double value) =>
      _imageGenSettings.setImageGenCfgScale(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setImageGenSampler(String value) =>
      _imageGenSettings.setImageGenSampler(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setImageGenSeed(int value) =>
      _imageGenSettings.setImageGenSeed(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setDrawThingsGrpcHost(String value) =>
      _imageGenSettings.setDrawThingsGrpcHost(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setDrawThingsGrpcPort(int value) =>
      _imageGenSettings.setDrawThingsGrpcPort(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setDrawThingsSampler(int value) =>
      _imageGenSettings.setDrawThingsSampler(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setDrawThingsShift(double value) =>
      _imageGenSettings.setDrawThingsShift(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setDrawThingsStrength(double value) =>
      _imageGenSettings.setDrawThingsStrength(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setDrawThingsSeedMode(int value) =>
      _imageGenSettings.setDrawThingsSeedMode(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setDrawThingsTeaCache(bool value) =>
      _imageGenSettings.setDrawThingsTeaCache(value);
  @Deprecated('Use imageGenSettings (Stage 7)')
  Future<void> setDrawThingsCfgZeroStar(bool value) =>
      _imageGenSettings.setDrawThingsCfgZeroStar(value);

  bool get imageGenEnabled => _imageGenSettings.imageGenEnabled;
  String get imageGenBackend => _imageGenSettings.imageGenBackend;
  String get localImageGenUrl => _imageGenSettings.localImageGenUrl;
  String get imageGenModel => _imageGenSettings.imageGenModel;
  String get imageGenSize => _imageGenSettings.imageGenSize;
  String get imageGenNegativePrompt => _imageGenSettings.imageGenNegativePrompt;
  String get imageGenStyle => _imageGenSettings.imageGenStyle;
  String get imageGenPromptParadigm => _imageGenSettings.imageGenPromptParadigm;
  String get imageGenLora => _imageGenSettings.imageGenLora;
  double get imageGenLoraWeight => _imageGenSettings.imageGenLoraWeight;
  int get imageGenSteps => _imageGenSettings.imageGenSteps;
  double get imageGenCfgScale => _imageGenSettings.imageGenCfgScale;
  String get imageGenSampler => _imageGenSettings.imageGenSampler;
  int get imageGenSeed => _imageGenSettings.imageGenSeed;
  String get drawThingsGrpcHost => _imageGenSettings.drawThingsGrpcHost;
  int get drawThingsGrpcPort => _imageGenSettings.drawThingsGrpcPort;
  int get drawThingsSampler => _imageGenSettings.drawThingsSampler;
  double get drawThingsShift => _imageGenSettings.drawThingsShift;
  double get drawThingsStrength => _imageGenSettings.drawThingsStrength;
  int get drawThingsSeedMode => _imageGenSettings.drawThingsSeedMode;
  bool get drawThingsTeaCache => _imageGenSettings.drawThingsTeaCache;
  bool get drawThingsCfgZeroStar => _imageGenSettings.drawThingsCfgZeroStar;

  // Expression
  @Deprecated('Use expressionSettings (Stage 7)')
  Future<void> setExpressionEnabled(bool value) =>
      _expressionSettings.setExpressionEnabled(value);
  @Deprecated('Use expressionSettings (Stage 7)')
  Future<void> setExpressionClassificationMode(String value) =>
      _expressionSettings.setExpressionClassificationMode(value);
  @Deprecated('Use expressionSettings (Stage 7)')
  Future<void> setExpressionDisplayMode(String value) =>
      _expressionSettings.setExpressionDisplayMode(value);
  @Deprecated('Use expressionSettings (Stage 7)')
  Future<void> setExpressionRerollSame(bool value) =>
      _expressionSettings.setExpressionRerollSame(value);
  @Deprecated('Use expressionSettings (Stage 7)')
  Future<void> setExpressionFallback(String value) =>
      _expressionSettings.setExpressionFallback(value);

  bool get expressionEnabled => _expressionSettings.expressionEnabled;
  String get expressionClassificationMode =>
      _expressionSettings.expressionClassificationMode;
  String get expressionDisplayMode => _expressionSettings.expressionDisplayMode;
  bool get expressionRerollSame => _expressionSettings.expressionRerollSame;
  String get expressionFallback => _expressionSettings.expressionFallback;

  // Web server (persisted only; runtime in WebServerService post Stage 6)
  @Deprecated('Use webServerSettings (Stage 7)')
  Future<void> setWebServerEnabled(bool value) =>
      _webServerSettings.setWebServerEnabled(value);
  @Deprecated('Use webServerSettings (Stage 7)')
  Future<void> setWebServerPort(int value) =>
      _webServerSettings.setWebServerPort(value);
  @Deprecated('Use webServerSettings (Stage 7)')
  Future<void> setWebServerPin(String value) =>
      _webServerSettings.setWebServerPin(value);

  bool get webServerEnabled => _webServerSettings.webServerEnabled;
  int get webServerPort => _webServerSettings.webServerPort;
  String get webServerPin => _webServerSettings.webServerPin;

  // Cloud
  @Deprecated('Use cloudSyncSettings (Stage 7)')
  Future<void> setCloudSyncEnabled(bool value) =>
      _cloudSyncSettings.setCloudSyncEnabled(value);
  @Deprecated('Use cloudSyncSettings (Stage 7)')
  Future<void> setCloudSyncProvider(String value) =>
      _cloudSyncSettings.setCloudSyncProvider(value);
  @Deprecated('Use cloudSyncSettings (Stage 7)')
  Future<void> setCloudSyncUrl(String value) =>
      _cloudSyncSettings.setCloudSyncUrl(value);
  @Deprecated('Use cloudSyncSettings (Stage 7)')
  Future<void> setCloudSyncUsername(String value) =>
      _cloudSyncSettings.setCloudSyncUsername(value);
  @Deprecated('Use cloudSyncSettings (Stage 7)')
  Future<void> setCloudSyncPassword(String value) =>
      _cloudSyncSettings.setCloudSyncPassword(value);
  @Deprecated('Use cloudSyncSettings (Stage 7)')
  Future<void> setCloudSyncLastTime(String value) =>
      _cloudSyncSettings.setCloudSyncLastTime(value);

  bool get cloudSyncEnabled => _cloudSyncSettings.cloudSyncEnabled;
  String get cloudSyncProvider => _cloudSyncSettings.cloudSyncProvider;
  String get cloudSyncUrl => _cloudSyncSettings.cloudSyncUrl;
  String get cloudSyncUsername => _cloudSyncSettings.cloudSyncUsername;
  String get cloudSyncPassword => _cloudSyncSettings.cloudSyncPassword;
  String get cloudSyncLastTime => _cloudSyncSettings.cloudSyncLastTime;

  // Realism
  @Deprecated('Use realismSettings (Stage 7)')
  Future<void> setRealismOneShotEval(bool value) =>
      _realismSettings.setRealismOneShotEval(value);
  @Deprecated('Use realismSettings (Stage 7)')
  Future<void> setRealismDefault(bool value) =>
      _realismSettings.setRealismDefault(value);
  @Deprecated('Use realismSettings (Stage 7)')
  Future<void> setNsfwCooldownDefault(bool value) =>
      _realismSettings.setNsfwCooldownDefault(value);
  @Deprecated('Use realismSettings (Stage 7)')
  Future<void> setPassageOfTimeDefault(bool value) =>
      _realismSettings.setPassageOfTimeDefault(value);
  @Deprecated('Use realismSettings (Stage 7)')
  Future<void> setBannedPhrases(List<String> value) =>
      _realismSettings.setBannedPhrases(value);

  bool get realismDefault => _realismSettings.realismDefault;
  bool get nsfwCooldownDefault => _realismSettings.nsfwCooldownDefault;
  bool get passageOfTimeDefault => _realismSettings.passageOfTimeDefault;
  bool get realismOneShotEval => _realismSettings.realismOneShotEval;
  List<String> get bannedPhrases => _realismSettings.bannedPhrases;

  // Memory (RAG, summary, auto-persona, evolution)
  @Deprecated('Use memorySettings (Stage 7)')
  Future<void> setSummaryEnabled(bool value) =>
      _memorySettings.setSummaryEnabled(value);
  @Deprecated('Use memorySettings (Stage 7)')
  Future<void> setSummaryInterval(int value) =>
      _memorySettings.setSummaryInterval(value);
  @Deprecated('Use memorySettings (Stage 7)')
  Future<void> setSummaryMaxWords(int value) =>
      _memorySettings.setSummaryMaxWords(value);
  @Deprecated('Use memorySettings (Stage 7)')
  Future<void> setSummaryPrompt(String value) =>
      _memorySettings.setSummaryPrompt(value);
  @Deprecated('Use memorySettings (Stage 7)')
  Future<void> setRagEnabled(bool value) =>
      _memorySettings.setRagEnabled(value);
  @Deprecated('Use memorySettings (Stage 7)')
  Future<void> setRagRetrievalCount(int value) =>
      _memorySettings.setRagRetrievalCount(value);
  @Deprecated('Use memorySettings (Stage 7)')
  Future<void> setRagWindowSize(int value) =>
      _memorySettings.setRagWindowSize(value);
  @Deprecated('Use memorySettings (Stage 7)')
  Future<void> setRagEmbeddingSource(String value) =>
      _memorySettings.setRagEmbeddingSource(value);
  @Deprecated('Use memorySettings (Stage 7)')
  Future<void> setRagEmbeddingModel(String value) =>
      _memorySettings.setRagEmbeddingModel(value);
  @Deprecated('Use memorySettings (Stage 7)')
  Future<void> setAutoPersonaEnabled(bool value) =>
      _memorySettings.setAutoPersonaEnabled(value);
  @Deprecated('Use memorySettings (Stage 7)')
  Future<void> setAutoPersonaInterval(int value) =>
      _memorySettings.setAutoPersonaInterval(value);
  @Deprecated('Use memorySettings (Stage 7)')
  Future<void> setCharacterEvolutionEnabled(bool value) =>
      _memorySettings.setCharacterEvolutionEnabled(value);
  @Deprecated('Use memorySettings (Stage 7)')
  Future<void> setEvolutionInterval(int value) =>
      _memorySettings.setEvolutionInterval(value);

  bool get summaryEnabled => _memorySettings.summaryEnabled;
  int get summaryInterval => _memorySettings.summaryInterval;
  int get summaryMaxWords => _memorySettings.summaryMaxWords;
  String get summaryPrompt => _memorySettings.summaryPrompt;
  bool get ragEnabled => _memorySettings.ragEnabled;
  int get ragRetrievalCount => _memorySettings.ragRetrievalCount;
  int get ragWindowSize => _memorySettings.ragWindowSize;
  String get ragEmbeddingSource => _memorySettings.ragEmbeddingSource;
  String get ragEmbeddingModel => _memorySettings.ragEmbeddingModel;
  bool get autoPersonaEnabled => _memorySettings.autoPersonaEnabled;
  int get autoPersonaInterval => _memorySettings.autoPersonaInterval;
  bool get characterEvolutionEnabled =>
      _memorySettings.characterEvolutionEnabled;
  int get evolutionInterval => _memorySettings.evolutionInterval;

  // Presets / saved prompts
  @Deprecated('Use presetSettings (Stage 7)')
  Future<void> savePrompt(String name, String content) =>
      _presetSettings.savePrompt(name, content);
  @Deprecated('Use presetSettings (Stage 7)')
  Future<void> deleteSavedPrompt(String name) =>
      _presetSettings.deleteSavedPrompt(name);
  @Deprecated('Use presetSettings (Stage 7)')
  void loadSavedPrompt(String name) {
    // Note: original called setSystemPrompt inside; shim preserves by using current generation
    _presetSettings.loadSavedPrompt(name, setSystemPrompt);
  }

  List<Map<String, String>> get savedPrompts => _presetSettings.savedPrompts;

  // setCustomModelsPath (dir related, stays close to root)
  @Deprecated('Use directories / set on storage (Stage 7)')
  Future<void> setCustomModelsPath(String? value) async {
    _customModelsPath = value;
    if (value != null && value.isNotEmpty) {
      await _prefs?.setString(_k('custom_models_path'), value);
      await modelsDir.create(
        recursive: true,
      ); // re-ensure at new custom models path (smallest for original contract + init parity)
    } else {
      await _prefs?.remove(_k('custom_models_path'));
    }
    notifyListeners();
  }

  // (End of Stage 7 shims)

  // Settings (DELETED Stage 7 — all fields/loads/setters lifted; see shims + *Settings classes)
  // Original bodies excised (deletion part of task; grep post for old symbols in exec code must be 0).
  // (fields + classic getters excised here; shims above provide the surface)

  StorageService() {
    _init();
  }

  // ── Beta / stable isolation ────────────────────────────────────────────────
  //
  // ALL of the logic below is driven by [isPreRelease] from app_version.dart.
  // When a stable tag is built (e.g. v0.9.8 — no "-Beta" suffix),
  // isPreRelease returns false and every method here behaves exactly as before.
  // No code needs to be reverted when merging the beta branch into main.

  /// SharedPreferences key used to persist the root data directory.
  /// Beta builds use a separate key so a custom beta path never overwrites
  /// the user's stable path choice.
  static String get _rootPathKey =>
      isPreRelease ? 'root_path_beta' : 'root_path';

  /// Prefix all SharedPreferences keys for beta builds so settings (API keys,
  /// TTS config, etc.) are completely isolated from the stable installation.
  /// Returns [key] unchanged for stable builds — zero reversal needed on merge.
  static String _k(String key) => isPreRelease ? 'beta_$key' : key;

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    final docsDir = await getApplicationDocumentsDirectory();

    // For developers running from source (`flutter run`), allow forcing the
    // exact same data directory as the packaged app via environment variable.
    // This makes cloud sync testing from source behave identically to packaged builds.
    String? devOverride;
    if (isPreRelease) {
      devOverride = Platform.environment['FRONT_PORCH_AI_DATA_DIR'];
    }

    // Beta builds default to a completely separate data directory so they
    // never touch a stable user's characters, chats, or database.
    final defaultRootName = isPreRelease ? 'FrontPorchAI-Beta' : 'FrontPorchAI';
    final defaultRoot = path.join(docsDir.path, defaultRootName);
    _rootPath = devOverride ?? _prefs?.getString(_rootPathKey) ?? defaultRoot;
    if (devOverride != null) {
      debugPrint('[Storage] Using dev override data directory: $_rootPath');
    }
    _binDir = Directory(path.join(_rootPath!, 'koboldcpp_bin'));

    // Ensure directories exist
    await chatsDir.create(recursive: true);
    await modelsDir.create(recursive: true);
    await worldsDir.create(recursive: true);
    await charactersDir.create(recursive: true);
    await groupsDir.create(recursive: true);
    await customBackgroundDir.create(recursive: true);

    // Stage 7: initialize domain settings (plain classes) + load (moved from god)
    // Single notify surface preserved (see plan "Why not multiple ChangeNotifiers").
    _generationSettings.initializeBase(_prefs, notifyListeners);
    _backendSettings.initializeBase(_prefs, notifyListeners);
    _uiSettings.initializeBase(_prefs, notifyListeners);
    _ttsSettings.initializeBase(_prefs, notifyListeners);
    _sttSettings.initializeBase(_prefs, notifyListeners);
    _imageGenSettings.initializeBase(_prefs, notifyListeners);
    _expressionSettings.initializeBase(_prefs, notifyListeners);
    _webServerSettings.initializeBase(_prefs, notifyListeners);
    _cloudSyncSettings.initializeBase(_prefs, notifyListeners);
    _realismSettings.initializeBase(_prefs, notifyListeners);
    _memorySettings.initializeBase(_prefs, notifyListeners);
    _presetSettings.initializeBase(_prefs, notifyListeners);

    _generationSettings.load();
    _backendSettings.load();
    _uiSettings.load();
    _ttsSettings.load();
    _sttSettings.load();
    _imageGenSettings.load();
    _expressionSettings.load();
    _webServerSettings.load();
    _cloudSyncSettings.load();
    _realismSettings.load();
    _memorySettings.load();
    _presetSettings.load();

    // Ensure default immersive prompt (was in god init; now on preset)
    if (!_presetSettings.savedPrompts.any(
      (p) => p['name'] == 'Immersive Roleplay',
    )) {
      await _presetSettings.savePrompt(
        'Immersive Roleplay',
        PresetSettings.defaultSystemPrompt,
      );
    }

    // Load settings (DELETED in Stage 7 — bodies lifted to the *Settings.load(); see above + shims)
    // Original load code excised (deletion part of task).
    _customModelsPath = _prefs?.getString(_k('custom_models_path'));

    if (!_initCompleter.isCompleted) _initCompleter.complete();
    notifyListeners();
  }

  /// Change the root installation directory and relocate all data files.
  /// Moves KoboldManager/ (DB + characters), chats/, worlds/, and models/
  /// from the old root to the new one. Closes and reopens the database.
  Future<void> setRootPath(String pathStr) async {
    final oldRoot = _rootPath;
    if (oldRoot == pathStr) return; // No-op if same path

    // Directories to move from old root to new root
    final dirsToMove = [
      'KoboldManager',
      'chats',
      'worlds',
      'models',
      'koboldcpp_bin',
    ];

    for (final dirName in dirsToMove) {
      final oldDir = Directory(path.join(oldRoot ?? '', dirName));
      final newDir = Directory(path.join(pathStr, dirName));
      if (await oldDir.exists() && !await newDir.exists()) {
        try {
          await newDir.create(recursive: true);
          await for (final entity in oldDir.list(recursive: false)) {
            final baseName = path.basename(entity.path);
            final newPath = path.join(newDir.path, baseName);
            if (entity is File) {
              await entity.copy(newPath);
            } else if (entity is Directory) {
              await _copyDirectory(entity, Directory(newPath));
            }
          }
          // Clean up old directory after successful copy
          await oldDir.delete(recursive: true);
          debugPrint('Relocated $dirName to $pathStr (old deleted)');
        } catch (e) {
          debugPrint('Error relocating $dirName: $e');
        }
      }
    }

    _rootPath = pathStr;
    _binDir = Directory(path.join(_rootPath!, 'koboldcpp_bin'));
    await _prefs?.setString(_rootPathKey, pathStr);

    // Ensure directories exist at the new location
    await chatsDir.create(recursive: true);
    await modelsDir.create(recursive: true);
    await worldsDir.create(recursive: true);
    await charactersDir.create(recursive: true);
    await groupsDir.create(recursive: true);

    notifyListeners();
  }

  /// Recursively copy a directory and its contents.
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final baseName = path.basename(entity.path);
      final newPath = path.join(destination.path, baseName);
      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      }
    }
  }

  // (All old set* / persist / _parseKcppsFile / old expression fields DELETED in Stage 7;
  // lifted to settings/* + directories; shims above + dir mgmt below provide surface.
  // Deletion part of task; post-edit grep for excised symbols (setTemperature, _expressionEnabled etc) in executable code = 0.)
}
