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

import 'package:front_porch_ai/models/models.dart';

/// The Model Manager's HuggingFace search: the query it sends and what it
/// does with the answer.
///
/// The API filter is `gguf` alone. Community quant repos (ReadyArt,
/// mradermacher, …) almost never set a pipeline tag, so also requiring
/// `text-generation` hid every roleplay tune and left only official base
/// repos. Dropping it lets diffusion, video and speech GGUFs in, which
/// [rank] removes when the repo says what it is.
class HfSearch {
  HfSearch._();

  /// How many repos to ask HuggingFace for. More than [shown] so roleplay
  /// tunes further down the downloads order can rise into the list.
  static const int fetched = 60;

  /// How many results the Model Manager lists (each costs a file fetch).
  static const int shown = 20;

  static Uri searchUri(String baseUrl, String query, {int limit = fetched}) {
    return Uri.parse('$baseUrl/api/models').replace(
      queryParameters: {
        'search': query,
        'filter': 'gguf',
        'sort': 'downloads',
        'direction': '-1',
        'limit': '$limit',
        'full': 'true',
      },
    );
  }

  /// Drops repos that are not chat models, then lists roleplay tunes first.
  /// Within each group HuggingFace's downloads order is kept.
  static List<HFModel> rank(List<HFModel> models, {int limit = shown}) {
    final kept = models.where((m) => !isNonTextModel(m)).toList();
    final order = {for (var i = 0; i < kept.length; i++) kept[i].id: i};
    kept.sort((a, b) {
      final byRp = (b.isRoleplay ? 1 : 0) - (a.isRoleplay ? 1 : 0);
      return byRp != 0 ? byRp : order[a.id]!.compareTo(order[b.id]!);
    });
    return kept.take(limit).toList();
  }

  static const Set<String> _nonTextTasks = {
    'text-to-image',
    'image-to-image',
    'text-to-video',
    'image-to-video',
    'video-to-video',
    'text-to-speech',
    'text-to-audio',
    'audio-to-audio',
    'automatic-speech-recognition',
    'feature-extraction',
    'sentence-similarity',
    'image-classification',
    'image-segmentation',
    'depth-estimation',
    'unconditional-image-generation',
  };

  static const Set<String> _nonTextTags = {
    'diffusers',
    'diffusion-single-file',
    'image-generation',
  };

  /// Families seen as bare GGUF repos with no task tag at all, matched
  /// against the repo id and its `base_model:` tags.
  static const List<String> _nonTextNames = [
    'lightricks/',
    'black-forest-labs/',
    'wan-ai/',
    'hexgrad/',
    'sdxl',
    'stable-diffusion',
  ];

  /// True when the repo describes itself as an image, video, audio or
  /// embedding model. A repo that says nothing is kept: silence is the
  /// normal state of a roleplay quant.
  static bool isNonTextModel(HFModel m) {
    final task = m.pipelineTag?.toLowerCase();
    if (task != null && _nonTextTasks.contains(task)) return true;
    final names = [m.id.toLowerCase()];
    for (final raw in m.tags) {
      final tag = raw.toLowerCase();
      if (_nonTextTasks.contains(tag) || _nonTextTags.contains(tag)) {
        return true;
      }
      if (tag.startsWith('base_model:')) names.add(tag);
    }
    return names.any((n) => _nonTextNames.any(n.contains));
  }
}
