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

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class MockStorageService extends Fake implements StorageService {
  @override
  Directory get modelsDir => Directory('test_models');
  @override
  String? get rootPath => 'test_root';
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

void main() {
  test('Model Auto-Discovery Verification', () async {
    final mockStorage = MockStorageService();
    
    // Clean up
    final modelDir = Directory('test_models');
    if (await modelDir.exists()) await modelDir.delete(recursive: true);
    await modelDir.create();

    final modelManager = ModelManager(mockStorage);

    // Initial state
    await modelManager.refreshModels();
    expect(modelManager.models.length, 0);

    // 1. Manually add a .gguf file
    final testFile = File(path.join(modelDir.path, 'test_model.gguf'));
    await testFile.writeAsString('fake model content');

    // 2. Refresh and verify
    await modelManager.refreshModels();
    expect(modelManager.models.length, 1);
    expect(path.basename(modelManager.models.first.path), 'test_model.gguf');

    // 3. Add a non-gguf file
    final otherFile = File(path.join(modelDir.path, 'README.txt'));
    await otherFile.writeAsString('not a model');

    // 4. Refresh and verify (count should still be 1)
    await modelManager.refreshModels();
    expect(modelManager.models.length, 1);

    // 5. Delete and refresh
    await testFile.delete();
    await modelManager.refreshModels();
    expect(modelManager.models.length, 0);

    // 6. Test recursive discovery
    final subDir = Directory(path.join(modelDir.path, 'subfolder'));
    await subDir.create();
    final deepFile = File(path.join(subDir.path, 'deep_model.gguf'));
    await deepFile.writeAsString('deep content');

    await modelManager.refreshModels();
    expect(modelManager.models.length, 1);
    expect(path.basename(modelManager.models.first.path), 'deep_model.gguf');

    // Final clean up
    await modelDir.delete(recursive: true);
  });
}
