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

import 'package:front_porch_ai/services/web_server_service.dart';

/// Character + databank + create + chargen non-stream + group + folder routes (Stage 6 registration lift).
/// Bodies delegated via public thins on WebServerService (full body excision follow-up).
class CharacterRoutes {
  final WebServerService _service;

  CharacterRoutes(this._service, Router router) {
    // Characters
    router.get('/api/characters', _service.handleGetCharacters);
    router.get('/api/characters/<id>/avatar', _service.handleGetAvatar);
    router.get('/api/characters/<id>/sessions', _service.handleGetSessions);
    router.get(
      '/api/characters/<id>/detail',
      _service.handleGetCharacterDetail,
    );
    router.post('/api/characters/<id>/edit', _service.handleEditCharacter);
    router.post('/api/characters/<id>/avatar', _service.handleUploadAvatar);
    router.post(
      '/api/characters/<id>/evolution',
      _service.handleUpdateEvolution,
    );
    router.post('/api/characters/<id>/delete', _service.handleDeleteCharacter);
    router.get(
      '/api/characters/<id>/export.png',
      _service.handleExportCharacterPng,
    );
    router.post('/api/characters/import', _service.handleImportCharacter);

    // Data Bank
    router.get('/api/characters/<id>/databank', _service.handleGetDataBank);
    router.post(
      '/api/characters/<id>/databank',
      _service.handleCreateDataBankEntry,
    );
    router.post(
      '/api/characters/<id>/databank/<entryId>/update',
      (shelf.Request r, String id, String entryId) =>
          _service.handleUpdateDataBankEntry(r, id, entryId),
    );
    router.post(
      '/api/characters/<id>/databank/<entryId>/delete',
      (shelf.Request r, String id, String entryId) =>
          _service.handleDeleteDataBankEntry(r, id, entryId),
    );

    // Character creation (chargen entry)
    router.post('/api/characters/create', _service.handleCreateCharacter);

    // Chargen non-stream (AI creator)
    // (thins added in god for the registration lift; streams in sse/ per plan)
    // router.post('/api/chargen/generate', _service.handleChargenGenerate);
    // router.post('/api/chargen/describe', _service.handleChargenDescribe);
    // router.post('/api/chargen/randomname', _service.handleChargenRandomName);
    // router.post('/api/chargen/avatar', _service.handleChargenAvatar);
    // router.post('/api/chargen/save', _service.handleChargenSave);
    // router.post('/api/chargen/expand', _service.handleChargenExpand);

    // Group chat
    // (thins for groups/* + set-next etc added or follow in god)
    // router.get('/api/groups', _service.handleGetGroups);
    // ... (add-character, remove-character, etc per plan)

    // Folders (character organization)
    // router.get('/api/folders', _service.handleGetFolders);
    // ... (create/rename/delete/add-character/remove-character per plan)

    // AI generate (general)
    // router.post('/api/generate', _service.handleGenerate);
  }
}
