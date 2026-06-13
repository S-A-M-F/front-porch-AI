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

/// Cloud sync provider/credentials/interval/lastSync settings.
///
/// Lifted Stage 7. Secrets (password) written only to prefs with beta_
/// prefix isolation; never logged.
class CloudSyncSettings with SettingsBase {
  bool _cloudSyncEnabled = false;
  String _cloudSyncProvider = 'none'; // 'none', 'webdav', 'gdrive'
  String _cloudSyncUrl = '';
  String _cloudSyncUsername = '';
  String _cloudSyncPassword = '';
  String _cloudSyncLastTime = '';

  bool get cloudSyncEnabled => _cloudSyncEnabled;
  String get cloudSyncProvider => _cloudSyncProvider;
  String get cloudSyncUrl => _cloudSyncUrl;
  String get cloudSyncUsername => _cloudSyncUsername;
  String get cloudSyncPassword => _cloudSyncPassword;
  String get cloudSyncLastTime => _cloudSyncLastTime;

  void load() {
    _cloudSyncEnabled = prefs?.getBool(k('cloud_sync_enabled')) ?? false;
    _cloudSyncProvider = prefs?.getString(k('cloud_sync_provider')) ?? 'none';
    _cloudSyncUrl = prefs?.getString(k('cloud_sync_url')) ?? '';
    _cloudSyncUsername = prefs?.getString(k('cloud_sync_username')) ?? '';
    _cloudSyncPassword = prefs?.getString(k('cloud_sync_password')) ?? '';
    _cloudSyncLastTime = prefs?.getString(k('cloud_sync_last_time')) ?? '';
  }

  Future<void> setCloudSyncEnabled(bool value) async {
    _cloudSyncEnabled = value;
    await prefs?.setBool(k('cloud_sync_enabled'), value);
    notify();
  }

  Future<void> setCloudSyncProvider(String value) async {
    _cloudSyncProvider = value;
    await prefs?.setString(k('cloud_sync_provider'), value);
    notify();
  }

  Future<void> setCloudSyncUrl(String value) async {
    _cloudSyncUrl = value;
    await prefs?.setString(k('cloud_sync_url'), value);
    notify();
  }

  Future<void> setCloudSyncUsername(String value) async {
    _cloudSyncUsername = value;
    await prefs?.setString(k('cloud_sync_username'), value);
    notify();
  }

  Future<void> setCloudSyncPassword(String value) async {
    _cloudSyncPassword = value;
    await prefs?.setString(k('cloud_sync_password'), value);
    notify();
  }

  Future<void> setCloudSyncLastTime(String value) async {
    _cloudSyncLastTime = value;
    await prefs?.setString(k('cloud_sync_last_time'), value);
    notify();
  }
}
