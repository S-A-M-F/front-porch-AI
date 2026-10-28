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

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/models/models.dart';

/// A repo's GGUF files, or why there are none.
class HfFilesResult {
  const HfFilesResult(this.files, [this.problem]);

  final List<HFModelFile> files;
  final HfFilesProblem? problem;
}

/// Lists a HuggingFace repo's GGUF files, subfolders included: big quants
/// often live in a folder per quant, split into parts.
class HfRepoFiles {
  HfRepoFiles._();

  static Future<HfFilesResult> list(
    String baseUrl,
    String repoId, {
    Map<String, String> headers = const {},
  }) async {
    final url = Uri.parse(
      '$baseUrl/api/models/$repoId/tree/main',
    ).replace(queryParameters: {'recursive': 'true'});
    try {
      final response = await http.get(url, headers: headers);
      switch (response.statusCode) {
        case 200:
          break;
        case 401 || 403:
          return const HfFilesResult([], HfFilesProblem.gated);
        case 404:
          return const HfFilesResult([], HfFilesProblem.notFound);
        default:
          debugPrint('HF files ${response.statusCode} for $repoId');
          return const HfFilesResult([], HfFilesProblem.network);
      }
      final data = jsonDecode(response.body) as List<dynamic>;
      return HfFilesResult([
        for (final f in data.cast<Map<String, dynamic>>())
          if (f['type'] != 'directory' &&
              (f['path'] as String? ?? '').toLowerCase().endsWith('.gguf'))
            HFModelFile.fromApiMap(f, repoId, baseUrl: baseUrl),
      ]);
    } catch (e) {
      debugPrint('HF files error for $repoId: $e');
      return const HfFilesResult([], HfFilesProblem.network);
    }
  }
}
