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

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

/// The shared pool of saved prompts behind web Settings' two prompt slots,
/// as on the desktop. Built-ins are never in the pool, and a new prompt
/// never overwrites one already there unless the slot asked to update it.
class WebSavedPromptRoutes {
  WebSavedPromptRoutes(this._storage, Router router) {
    router.post('/api/saved-prompts', _save);
    router.post('/api/saved-prompts/delete', _delete);
  }

  final StorageService _storage;

  Map<String, dynamic> _pool() => {
    'savedPrompts': userSavedPrompts(_storage.presetSettings.savedPrompts),
  };

  /// `{name, content, overwrite?}`. Without `overwrite: true` a taken name is
  /// refused with 409.
  Future<shelf.Response> _save(shelf.Request request) async {
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final name = body['name']?.toString().trim() ?? '';
    final content = body['content'];
    if (name.isEmpty || content is! String) {
      return JsonResponse.badRequest('name and content are required');
    }
    // The hidden, untouched seed is not the user's, so it may be replaced.
    final taken = userSavedPrompts(
      _storage.presetSettings.savedPrompts,
    ).any((p) => p['name'] == name);
    if (taken && body['overwrite'] != true) {
      return JsonResponse.error(
        409,
        'You already have a prompt called "$name". Pick another name.',
      );
    }
    await _storage.presetSettings.savePrompt(name, content);
    return JsonResponse.ok(_pool());
  }

  /// `{name}`. Slots that named it let go of it.
  Future<shelf.Response> _delete(shelf.Request request) async {
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final name = body['name']?.toString() ?? '';
    if (name.isEmpty) return JsonResponse.badRequest('name is required');
    await _storage.presetSettings.deleteSavedPrompt(name);
    return JsonResponse.ok(_pool());
  }
}
