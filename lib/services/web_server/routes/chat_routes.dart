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

import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web_server_service.dart';

/// Chat + summary routes (Stage 6 registration lift).
/// Bodies delegated via public thins on WebServerService (full body excision follow-up).
class ChatRoutes {
  final WebServerService _service;

  ChatRoutes(this._service, Router router) {
    router.get('/api/chat/state', _service.handleGetChatState);
    router.post('/api/chat/author-note', _service.handleSetAuthorNote);
    router.post('/api/chat/select', _service.handleChatSelect);
    router.post('/api/chat/send', _service.handleChatSend);
    router.post('/api/chat/stop', _service.handleChatStop);
    router.post('/api/chat/regenerate', _service.handleChatRegenerate);
    router.post('/api/chat/session', _service.handleChatSession);
    router.post('/api/chat/swipe', _service.handleChatSwipe);
    router.post('/api/chat/continue', _service.handleChatContinue);
    router.post('/api/chat/edit', _service.handleChatEdit);
    router.post('/api/chat/delete', _service.handleChatDelete);
    router.post('/api/chat/impersonate', _service.handleChatImpersonate);
    router.post('/api/chat/cycle-greeting', _service.handleChatCycleGreeting);
    router.post('/api/chat/fork', _service.handleChatFork);
    router.post('/api/chat/session/delete', _service.handleDeleteSession);
    router.get('/api/chat/stream', _service.handleChatStream);
    router.get('/api/chat/summary', _service.handleGetSummary);
    router.post('/api/chat/summary', _service.handleSetSummary);
    router.post('/api/chat/summary/pause', _service.handleSummaryPause);
    router.post(
      '/api/chat/summary/regenerate',
      _service.handleSummaryRegenerate,
    );
  }
}
