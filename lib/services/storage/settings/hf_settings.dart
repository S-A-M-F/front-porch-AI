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

/// The optional HuggingFace access token: gated repos (official Llama,
/// Gemma, some tunes) list and download only with one. Kept in app
/// preferences like the remote API keys; macOS ad-hoc and nightly builds
/// often have no usable keychain (see WebSearchSettings).
class HfSettings with SettingsBase {
  String _token = '';

  String get token => _token;
  bool get hasToken => _token.isNotEmpty;

  /// `Authorization` for a request to [url] when it goes to [hfHost]; empty
  /// for any other host, so the token never leaves HuggingFace's own API.
  Map<String, String> headersFor(Uri url, String hfHost) =>
      hasToken && url.host == hfHost
      ? {'Authorization': 'Bearer $_token'}
      : const {};

  void load() {
    _token = prefs?.getString(k('hf_token'))?.trim() ?? '';
  }

  /// Saves the token; blank clears it.
  Future<void> setToken(String value) async {
    _token = value.trim();
    if (_token.isEmpty) {
      await prefs?.remove(k('hf_token'));
    } else {
      await prefs?.setString(k('hf_token'), _token);
    }
    notify();
  }
}
