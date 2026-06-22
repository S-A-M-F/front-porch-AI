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

// Additional service fakes for provider-backed page / dialog goldens.
//
// Each fake implements only the getters widgets read at build time; everything
// else delegates to noSuchMethod.

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/download_task.dart';
import 'package:front_porch_ai/models/local_model_info.dart';
import 'package:front_porch_ai/services/cloud_sync_service.dart';
import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:front_porch_ai/services/model_manager.dart';

/// [CloudSyncService] double. Exposes the status surface that
/// [CloudSyncPage._buildCloudSyncSection] reads at build time.
class FakeCloudSyncService extends ChangeNotifier implements CloudSyncService {
  FakeCloudSyncService({
    this.isConnected = false,
    this.status = SyncStatus.idle,
    this.progress = 0.0,
    this.lastError,
    this.cloudRoot = '/FrontPorchAI',
  });

  @override
  final bool isConnected;
  @override
  final SyncStatus status;
  @override
  final double progress;
  @override
  final String? lastError;
  @override
  final String cloudRoot;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [ModelManager] double. Exposes the getters [ModelManagerPage.build] reads
/// directly (localModels, modelsPath, downloadManager, customModelsPath).
/// [downloadManager] returns a real [DownloadManager] with an empty queue so
/// [DownloadQueuePanel] can read its list getters without IO.
class FakeModelManager extends ChangeNotifier implements ModelManager {
  FakeModelManager({
    List<LocalModelInfo>? localModels,
    this.modelsPath = '/models',
    this.statusMessage = '',
  }) : _localModels = localModels ?? const [];

  final List<LocalModelInfo> _localModels;

  @override
  final String modelsPath;
  @override
  final String statusMessage;

  @override
  List<LocalModelInfo> get localModels => _localModels;
  @override
  Map<String, DownloadTask> get downloadingFiles => const {};
  @override
  Set<String> get downloadedFilenames => const {};

  // A real DownloadManager with an empty queue supplies the DownloadQueuePanel
  // list getters without needing a separate fake hierarchy.
  final DownloadManager _downloadManager = DownloadManager(
    targetDir: Directory.systemTemp.path,
  );
  @override
  DownloadManager get downloadManager => _downloadManager;
  @override
  Future<void> refreshModels() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [HardwareService] double. Seeds a deterministic [HardwareInfo] so
/// [ModelManagerPage] can display VRAM and GPU name without real detection.
class FakeHardwareService extends ChangeNotifier implements HardwareService {
  FakeHardwareService({HardwareInfo? hardwareInfo})
    : _hardwareInfo =
          hardwareInfo ??
          HardwareInfo(
            gpuName: 'NVIDIA GeForce RTX 4070',
            vramMb: 12288,
            ramMb: 32768,
            vendor: 'Nvidia',
            hasCuda: true,
          );

  final HardwareInfo _hardwareInfo;

  @override
  HardwareInfo? get hardwareInfo => _hardwareInfo;
  @override
  bool get isDetecting => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
