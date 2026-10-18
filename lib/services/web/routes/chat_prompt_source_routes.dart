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

import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

const _kPresets = {'card+amend', 'card', 'user'};

/// The per-chat system prompt source on the phone: the new-chat picker's
/// answer and Chat Settings' System prompt row, as on the desktop.
class WebChatPromptSourceRoutes {
  WebChatPromptSourceRoutes(this._facade, Router router) {
    router.post('/api/chat/prompt-picker', _answer);
    router.post('/api/chat/prompt-source', _set);
  }

  final ChatFacade _facade;

  /// `{preset, remember?, askEveryChat?}`; `{preset: null}` dismisses and
  /// keeps the chat on the inherited default.
  Future<shelf.Response> _answer(shelf.Request request) async {
    final body = await RequestBody.readJsonMap(request);
    final preset = body['preset']?.toString();
    if (preset != null && !_kPresets.contains(preset)) {
      return JsonResponse.badRequest('Unknown preset: $preset');
    }
    final ok = await _facade.answerPromptPicker(
      preset: preset,
      remember: body['remember'] == true,
      askEveryChat: body['askEveryChat'] == true,
    );
    if (!ok) return JsonResponse.error(409, 'No one-on-one chat is open');
    return JsonResponse.ok({'status': 'ok'});
  }

  /// `{source: 'card' | 'user' | null, amendments: bool | null}`; null
  /// follows the defaults.
  Future<shelf.Response> _set(shelf.Request request) async {
    final body = await RequestBody.readJsonMap(request);
    final source = body['source']?.toString();
    if (source != null && source != 'card' && source != 'user') {
      return JsonResponse.badRequest('Unknown source: $source');
    }
    final amendments = body['amendments'];
    if (amendments != null && amendments is! bool) {
      return JsonResponse.badRequest('amendments must be true, false or null');
    }
    final ok = await _facade.setPromptSource(
      source: source,
      amendments: amendments as bool?,
    );
    if (!ok) return JsonResponse.error(409, 'No one-on-one chat is open');
    return JsonResponse.ok({'status': 'ok'});
  }
}
