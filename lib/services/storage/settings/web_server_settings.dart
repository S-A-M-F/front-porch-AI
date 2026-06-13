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

/// Web server persisted settings (enabled, port, PIN).
///
/// Note: runtime state (hasActiveClient, activeSessions, markClientActive,
/// autostart logic) lives in WebServerService (see Stage 6 extraction).
/// Shims on StorageService preserve the 3 persisted getters/setters exactly.
class WebServerSettings with SettingsBase {
  bool _webServerEnabled = false;
  int _webServerPort = 8085;
  String _webServerPin = '';

  bool get webServerEnabled => _webServerEnabled;
  int get webServerPort => _webServerPort;
  String get webServerPin => _webServerPin;

  void load() {
    _webServerEnabled = prefs?.getBool(k('web_server_enabled')) ?? false;
    _webServerPort = prefs?.getInt(k('web_server_port')) ?? 8085;
    _webServerPin = prefs?.getString(k('web_server_pin')) ?? '';
  }

  Future<void> setWebServerEnabled(bool value) async {
    _webServerEnabled = value;
    await prefs?.setBool(k('web_server_enabled'), value);
    notify();
  }

  Future<void> setWebServerPort(int value) async {
    _webServerPort = value;
    await prefs?.setInt(k('web_server_port'), value);
    notify();
  }

  Future<void> setWebServerPin(String value) async {
    _webServerPin = value;
    await prefs?.setString(k('web_server_pin'), value);
    notify();
  }
}
