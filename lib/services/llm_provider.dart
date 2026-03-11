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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// The available backend types.
enum BackendType { kobold, openRouter }

/// Manages switching between LLM backends (local KoboldCPP vs remote APIs).
///
/// Sits between ChatService and the actual backend implementations.
/// Listens to StorageService for config changes and hot-swaps the active service.
class LLMProvider extends ChangeNotifier {
  final KoboldService _koboldService;
  final OpenRouterService _openRouterService;
  final StorageService _storageService;

  BackendType _activeBackend = BackendType.kobold;

  BackendType get activeBackend => _activeBackend;
  LLMService get activeService =>
      _activeBackend == BackendType.kobold ? _koboldService : _openRouterService;

  /// Whether the currently active backend is the local KoboldCPP.
  bool get isLocal => _activeBackend == BackendType.kobold;

  /// Convenience getters for the underlying services (for UI that needs specifics).
  KoboldService get koboldService => _koboldService;
  OpenRouterService get openRouterService => _openRouterService;

  LLMProvider(this._koboldService, this._openRouterService, this._storageService) {
    // Sync from persisted settings
    _syncFromStorage();
    _storageService.addListener(_syncFromStorage);
  }

  @override
  void dispose() {
    _storageService.removeListener(_syncFromStorage);
    super.dispose();
  }

  void _syncFromStorage() {
    final typeStr = _storageService.backendType;
    final newType = typeStr == 'openRouter' ? BackendType.openRouter : BackendType.kobold;

    // Update OpenRouter config
    _openRouterService.configure(
      apiUrl: _storageService.remoteApiUrl,
      apiKey: _storageService.remoteApiKey,
      modelName: _storageService.remoteModelName,
    );

    if (newType != _activeBackend) {
      _activeBackend = newType;
      notifyListeners();
    }
  }

  /// Switch the active backend and persist the choice.
  /// Returns `true` if KoboldCPP was running and got shut down.
  Future<bool> setActiveBackend(BackendType type) async {
    if (type == _activeBackend) return false;

    bool stoppedKobold = false;

    // Auto-shutdown KoboldCPP when switching away from local
    if (type == BackendType.openRouter && _koboldService.isRunning) {
      await _koboldService.stopKobold();
      stoppedKobold = true;
    }

    _activeBackend = type;
    await _storageService.setBackendType(
        type == BackendType.openRouter ? 'openRouter' : 'kobold');
    notifyListeners();
    return stoppedKobold;
  }
}
