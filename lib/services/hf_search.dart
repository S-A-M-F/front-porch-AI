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

  static Uri searchUri(
    String baseUrl,
    String query, {
    int limit = fetched,
    HfSort sort = HfSort.downloads,
  }) {
    return Uri.parse('$baseUrl/api/models').replace(
      queryParameters: {
        'search': query,
        'filter': 'gguf',
        'sort': sort.apiValue,
        'direction': '-1',
        'limit': '$limit',
        'full': 'true',
      },
    );
  }

  /// Drops repos that are not chat models or that [options] filters out,
  /// then lists roleplay tunes first. Within each group HuggingFace's order
  /// (the chosen sort) is kept.
  static List<HFModel> rank(
    List<HFModel> models, {
    int limit = shown,
    HfSearchOptions options = const HfSearchOptions(),
  }) {
    final kept = models
        .where((m) => !isNonTextModel(m))
        .where((m) => !options.roleplayOnly || m.isRoleplay)
        .where((m) => options.size.admits(paramsBillions(m.name)))
        .toList();
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

  static final RegExp _experts = RegExp(
    r'(\d+)x(\d+(?:\.\d+)?)b(?![a-z])',
    caseSensitive: false,
  );
  static final RegExp _billions = RegExp(
    r'(?<![\d.])(\d+(?:\.\d+)?)b(?![a-z])',
    caseSensitive: false,
  );

  /// Parameter count in billions read from a repo name: `Qwen3.8-27B` → 27,
  /// `Dark-Scarlett-v0.3-26B-A4B` → 26 (the total, not the active experts),
  /// `Mixtral-8x7B` → 56. Null when the name does not say.
  static double? paramsBillions(String name) {
    final moe = _experts.firstMatch(name);
    if (moe != null) {
      return int.parse(moe.group(1)!) * double.parse(moe.group(2)!);
    }
    final plain = _billions.firstMatch(name);
    return plain == null ? null : double.parse(plain.group(1)!);
  }
}

/// HuggingFace's own result orders.
enum HfSort {
  downloads('downloads', 'Most downloaded'),
  likes('likes', 'Most liked'),
  newest('lastModified', 'Recently updated'),
  trending('trendingScore', 'Trending');

  const HfSort(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

/// Size filter on the parameter count read from the repo name.
enum HfSizeBucket {
  any('Any size'),
  small('Up to 13B'),
  medium('14B to 34B'),
  large('35B and up');

  const HfSizeBucket(this.label);

  final String label;

  /// A name with no size in it only passes "Any size".
  bool admits(double? billions) => switch (this) {
    any => true,
    small => billions != null && billions < 13.5,
    medium => billions != null && billions >= 13.5 && billions < 34.5,
    large => billions != null && billions >= 34.5,
  };
}

/// The Model Manager's search filters, shared by desktop and the web relay.
class HfSearchOptions {
  const HfSearchOptions({
    this.sort = HfSort.downloads,
    this.roleplayOnly = false,
    this.size = HfSizeBucket.any,
  });

  final HfSort sort;
  final bool roleplayOnly;
  final HfSizeBucket size;

  HfSearchOptions copyWith({
    HfSort? sort,
    bool? roleplayOnly,
    HfSizeBucket? size,
  }) => HfSearchOptions(
    sort: sort ?? this.sort,
    roleplayOnly: roleplayOnly ?? this.roleplayOnly,
    size: size ?? this.size,
  );

  /// Reads the web relay's `sort`, `rp` and `size` query parameters. Unknown
  /// or missing values fall back to the defaults an older PWA expects.
  factory HfSearchOptions.fromQuery(Map<String, String> query) {
    T pick<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    return HfSearchOptions(
      sort: pick(HfSort.values, query['sort'], HfSort.downloads),
      roleplayOnly: query['rp'] == '1',
      size: pick(HfSizeBucket.values, query['size'], HfSizeBucket.any),
    );
  }
}
