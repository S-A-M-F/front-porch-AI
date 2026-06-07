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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/app_version.dart';

/// Shared mixin for domain settings classes extracted from StorageService.
///
/// Provides:
/// - _prefs reference (set via initializeBase from the owning StorageService)
/// - k(key) prefix helper that applies beta_ isolation exactly as before
/// - notify() hook that calls the StorageService's notifyListeners()
///
/// This keeps a *single* ChangeNotifier surface (StorageService) for all
/// settings consumers using context.watch / context.select. See Stage 7 plan
/// and CLAUDE "Why not use multiple ChangeNotifiers".
mixin SettingsBase {
  // These are populated by StorageService via initializeBase().
  // Non-underscored names for cross-file visibility (separate libraries under lib/services/storage/settings/*);
  // they act as the private storage for implementors. See plan for SettingsBase.
  SharedPreferences? prefs; // ignore: unused_field - provided to `with` classes
  VoidCallback? onNotify; // ignore: unused_field - provided to `with` classes

  /// Must be called by StorageService after obtaining its _prefs, before load().
  void initializeBase(SharedPreferences? p, VoidCallback n) {
    prefs = p;
    onNotify = n;
  }

  /// Beta-aware key prefix. Exact match to old StorageService._k .
  String k(String key) => isPreRelease ? 'beta_$key' : key;

  /// Delegates to the owning StorageService.notifyListeners() .
  void notify() => onNotify?.call();
}
