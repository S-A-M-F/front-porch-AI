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
// (character_card import removed - unused post final shim cleanup; storage no longer exposes character card related flat APIs)

// Stage 7: storage decomposition (directories + domain settings; final cleanup complete - shims excised)
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

  // Public accessors to extracted domain settings (post-Stage 7 final shim migration).
  // Callers now use direct e.g. storage.generationSettings.systemPrompt or .setTemperature(v)
  // instead of the old flat shims. Storage owns the instances (for _prefs init, beta _k,
  // single ChangeNotifier notify surface, and wiring). This + dir mgmt is the thinned god.
  // (final shim migration cleanup complete; no old @Deprecated or flat shims remain. Storage pure dir + public wiring only.)
  GenerationSettings get generationSettings => _generationSettings;
  BackendSettings get backendSettings => _backendSettings;
  UiSettings get uiSettings => _uiSettings;
  TtsSettings get ttsSettings => _ttsSettings;
  SttSettings get sttSettings => _sttSettings;
  ImageGenSettings get imageGenSettings => _imageGenSettings;
  ExpressionSettings get expressionSettings => _expressionSettings;
  WebServerSettings get webServerSettings => _webServerSettings;
  CloudSyncSettings get cloudSyncSettings => _cloudSyncSettings;
  RealismSettings get realismSettings => _realismSettings;
  MemorySettings get memorySettings => _memorySettings;
  PresetSettings get presetSettings => _presetSettings;

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

  // (final shim migration cleanup complete IMPL_ID=29bbf59d; all @Deprecated + flat shims excised for tts/stt/image/expression/web/cloud/realism/memory/preset + all flats. Storage is pure directory management (rootPath, dirs, resolveCharacterImage, setRootPath, _copyDirectory, init for dirs + beta/dev override, _initCompleter, _prefs for dir keys only) + public *Settings wiring (late finals for init/single-notifier/beta isolation) only. No _prefs for settings, no notify for settings changes, no flat settings API. Deletion part complete; live post-edit dead grep for old shim symbols in *_service.dart exec =0 outside comments/MD.)
}
