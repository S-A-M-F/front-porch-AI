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

/// A HuggingFace repo's model card: its README as plain markdown, plus the
/// facts from the card's metadata. Desktop and the PWA render the same
/// [markdown], which [clean] has already stripped of HTML.
class HfReadme {
  const HfReadme({
    required this.repoId,
    this.markdown = '',
    this.license,
    this.baseModels = const [],
    this.tags = const [],
    this.lastModified,
    this.problem,
  });

  final String repoId;
  final String markdown;
  final String? license;

  /// The models this repo was made from (`base_model`). A quant repo's own
  /// card is often boilerplate; the original's is the one worth reading.
  final List<String> baseModels;
  final List<String> tags;
  final DateTime? lastModified;
  final HfFilesProblem? problem;

  Map<String, dynamic> toJson() => {
    'repoId': repoId,
    'markdown': markdown,
    'license': license,
    'baseModels': baseModels,
    'tags': tags,
    'lastModified': lastModified?.toIso8601String(),
    'problem': problem?.name,
  };

  /// Asks for the card's metadata and its README. A repo with no README
  /// still returns its facts with empty [markdown].
  static Future<HfReadme> fetch(
    String baseUrl,
    String repoId, {
    Map<String, String> headers = const {},
  }) async {
    try {
      final info = await http.get(
        Uri.parse('$baseUrl/api/models/$repoId'),
        headers: headers,
      );
      final problem = switch (info.statusCode) {
        200 => null,
        401 || 403 => HfFilesProblem.gated,
        404 => HfFilesProblem.notFound,
        _ => HfFilesProblem.network,
      };
      if (problem != null) return HfReadme(repoId: repoId, problem: problem);
      final meta = jsonDecode(info.body) as Map<String, dynamic>;
      final card = meta['cardData'];
      final cardData = card is Map<String, dynamic> ? card : const {};

      final readme = await http.get(
        Uri.parse('$baseUrl/$repoId/raw/main/README.md'),
        headers: headers,
      );
      return HfReadme(
        repoId: repoId,
        markdown: readme.statusCode == 200 ? clean(readme.body) : '',
        // A gated repo shows its facts to anyone but its README only to
        // accounts that accepted the licence.
        problem: readme.statusCode == 401 || readme.statusCode == 403
            ? HfFilesProblem.gated
            : null,
        license: _string(cardData['license']),
        baseModels: _strings(cardData['base_model']),
        tags: [
          for (final t in _strings(meta['tags']))
            if (!t.contains(':')) t,
        ],
        lastModified: DateTime.tryParse('${meta['lastModified']}'),
      );
    } catch (e) {
      debugPrint('HF card error for $repoId: $e');
      return HfReadme(repoId: repoId, problem: HfFilesProblem.network);
    }
  }

  static String? _string(Object? v) => v is String && v.isNotEmpty ? v : null;

  static List<String> _strings(Object? v) => switch (v) {
    String s when s.isNotEmpty => [s],
    List l => [for (final x in l) '$x'],
    _ => const [],
  };

  static final RegExp _frontMatter = RegExp(
    r'^﻿?---\r?\n[\s\S]*?\r?\n---[ \t]*(\r?\n|$)',
  );
  static final RegExp _dropWhole = RegExp(
    r'<(script|style|svg)\b[\s\S]*?</\1\s*>|<!--[\s\S]*?-->',
    caseSensitive: false,
  );
  static final RegExp _img = RegExp(r'<img\b[^>]*>', caseSensitive: false);
  static final RegExp _attr = RegExp(
    r'''\b(alt|src)\s*=\s*("([^"]*)"|'([^']*)')''',
    caseSensitive: false,
  );
  static final RegExp _anchor = RegExp(
    r'''<a\b[^>]*\bhref\s*=\s*("([^"]*)"|'([^']*)')[^>]*>([\s\S]*?)</a\s*>''',
    caseSensitive: false,
  );
  static final RegExp _lineBreak = RegExp(
    r'<br\s*/?>|</?(p|div|tr|li|h[1-6]|details|summary|center|table)\b[^>]*>',
    caseSensitive: false,
  );
  static final RegExp _anyTag = RegExp(r'</?[a-zA-Z][^>]*>');
  static final RegExp _markdownImage = RegExp(
    r'!\[([^\]]*)\]\(([^)\s]+)[^)]*\)',
  );

  /// README → markdown both surfaces can render safely: no YAML front
  /// matter, no HTML (an `<img>` or markdown image becomes a link to the
  /// picture, so nothing loads from a third-party host unasked), and no
  /// runs of blank lines.
  static String clean(String raw) {
    var s = raw.replaceFirst(_frontMatter, '');
    // Code is kept verbatim: prompt formats (`<start_of_turn>user`) live
    // in code blocks and must not be taken for HTML.
    final kept = <String>[];
    s = s.replaceAllMapped(_code, (m) {
      kept.add(m.group(0)!);
      return '\u0000${kept.length - 1}\u0000';
    });
    s = s.replaceAll(_dropWhole, '');
    String? attr(String tag, String name) {
      for (final m in _attr.allMatches(tag)) {
        if (m.group(1)!.toLowerCase() == name) return m.group(3) ?? m.group(4);
      }
      return null;
    }

    s = s.replaceAllMapped(_img, (m) {
      final src = attr(m.group(0)!, 'src');
      if (src == null || src.isEmpty) return '';
      final alt = attr(m.group(0)!, 'alt');
      return '[image: ${alt == null || alt.isEmpty ? 'picture' : alt}]($src)';
    });
    s = s.replaceAllMapped(_markdownImage, (m) {
      final alt = m.group(1)!.isEmpty ? 'picture' : m.group(1)!;
      return '[image: $alt](${m.group(2)})';
    });
    s = s.replaceAllMapped(_anchor, (m) {
      final href = m.group(2) ?? m.group(3) ?? '';
      final text = m.group(4)!.replaceAll(_anyTag, '').trim();
      return '[${text.isEmpty ? href : text}]($href)';
    });
    s = s.replaceAll(_lineBreak, '\n').replaceAll(_anyTag, '');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
    // Indentation left behind by removed HTML would read as a code block;
    // nested list items keep theirs.
    s = s.replaceAllMapped(
      RegExp(r'^[ \t]{4,}(?![-*+] |\d+[.)] )', multiLine: true),
      (_) => '',
    );
    s = s.replaceAll(RegExp(r'\n[ \t]*(\n[ \t]*){2,}'), '\n\n').trim();
    return s.replaceAllMapped(
      RegExp('\u0000(\\d+)\u0000'),
      (m) => kept[int.parse(m.group(1)!)],
    );
  }

  static final RegExp _code = RegExp(r'```[\s\S]*?(```|$)|`[^`\n]+`');
}
